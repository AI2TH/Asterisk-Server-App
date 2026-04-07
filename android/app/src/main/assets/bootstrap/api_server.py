#!/usr/bin/env python3
"""
FastAPI control server for Asterisk PBX inside Alpine Linux VM.
Listens on 0.0.0.0:7080 — SLIRP hostfwd delivers connections from Android host.

Token is injected by the Android app via QEMU fw_cfg:
  -fw_cfg name=opt/api_token,string=<TOKEN>
Guest reads it from: /sys/firmware/qemu_fw_cfg/by_name/opt/api_token/raw
"""

import configparser
import logging
import os
import subprocess
from typing import Optional

from fastapi import Depends, FastAPI, HTTPException, Header
from fastapi.responses import PlainTextResponse
from pydantic import BaseModel

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI(title="Stardial Asterisk API", version="1.0.0")

PJSIP_CONF   = "/etc/asterisk/pjsip.conf"
ASTERISK_LOG = "/var/log/asterisk/messages"
CERT_FILE    = "/etc/asterisk/keys/asterisk.pem"

# ---------------------------------------------------------------------------
# Token loading
# ---------------------------------------------------------------------------

FW_CFG_PATH = "/sys/firmware/qemu_fw_cfg/by_name/opt/api_token/raw"
TOKEN_FILE  = "/bootstrap/token"


def _load_token() -> str:
    for path in (FW_CFG_PATH, TOKEN_FILE):
        try:
            with open(path) as f:
                t = f.read().strip()
                if t:
                    logger.info("Token loaded from %s", path)
                    return t
        except OSError:
            pass
    t = os.environ.get("API_TOKEN", "").strip()
    if t:
        logger.info("Token loaded from environment")
        return t
    logger.warning("No API token found — all authenticated requests will be rejected")
    return ""


API_TOKEN = _load_token()

# ---------------------------------------------------------------------------
# Auth
# ---------------------------------------------------------------------------


def require_auth(authorization: Optional[str] = Header(None)) -> None:
    if not API_TOKEN:
        raise HTTPException(503, "Server not ready: token not configured")
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(401, "Missing Authorization header")
    if authorization[len("Bearer "):] != API_TOKEN:
        raise HTTPException(401, "Invalid token")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _asterisk(cmd: str, timeout: int = 10) -> str:
    """Run `asterisk -rx <cmd>` and return stdout."""
    result = subprocess.run(
        ["asterisk", "-rx", cmd],
        capture_output=True, text=True, timeout=timeout
    )
    return result.stdout.strip()


def _sh(cmd: str, timeout: int = 30) -> dict:
    result = subprocess.run(
        ["sh", "-c", cmd],
        capture_output=True, text=True, timeout=timeout
    )
    return {
        "stdout":   result.stdout,
        "stderr":   result.stderr,
        "exitCode": result.returncode,
    }


# ---------------------------------------------------------------------------
# Models
# ---------------------------------------------------------------------------


class ExtensionCreate(BaseModel):
    name: str           # e.g. "1001"
    password: str       # SIP password
    context: str = "from-internal"
    max_contacts: int = 5
    webrtc: bool = True  # enable DTLS/SRTP for SIP.js / WebRTC


class HangupRequest(BaseModel):
    channel: str


class ExecRequest(BaseModel):
    cmd: str


# ---------------------------------------------------------------------------
# Health
# ---------------------------------------------------------------------------


@app.get("/health")
def health():
    try:
        # Check if Asterisk process is running via pidof.
        # Also check the pidfile as a fallback (covers renamed processes).
        pidof = subprocess.run(["pidof", "asterisk"], capture_output=True, timeout=5)
        running = pidof.returncode == 0
        if not running:
            # Fallback: check OpenRC pidfile
            try:
                with open("/var/run/asterisk/asterisk.pid") as _pf:
                    _pid = int(_pf.read().strip())
                import os as _os
                _os.kill(_pid, 0)
                running = True
            except Exception:
                pass
        version = _asterisk("core show version", timeout=5) if running else ""
        return {
            "status":  "running" if running else "stopped",
            "version": version or "unknown",
            "wss":     "wss://127.0.0.1:8089/asterisk/sip",
            "ws":      "ws://127.0.0.1:8088/asterisk/sip",
        }
    except Exception as e:
        return {"status": "error", "detail": str(e)}


# ---------------------------------------------------------------------------
# TLS cert fingerprint (needed by SIP.js for DTLS setup)
# ---------------------------------------------------------------------------


@app.get("/cert/fingerprint", dependencies=[Depends(require_auth)])
def cert_fingerprint():
    """Return SHA-256 fingerprint of the Asterisk TLS cert for SIP.js DTLS config."""
    try:
        result = subprocess.run(
            ["openssl", "x509", "-noout", "-fingerprint", "-sha256", "-in", CERT_FILE],
            capture_output=True, text=True, timeout=5
        )
        raw = result.stdout.strip()
        fp = raw.replace("SHA256 Fingerprint=", "").replace(":", "").lower()
        logger.info("Cert fingerprint: %s", fp)
        return {"fingerprint": fp}
    except Exception as e:
        raise HTTPException(500, str(e))


# ---------------------------------------------------------------------------
# Extensions (PJSIP config management)
# ---------------------------------------------------------------------------


def _read_pjsip() -> configparser.RawConfigParser:
    cfg = configparser.RawConfigParser()
    cfg.optionxform = str  # preserve case
    cfg.read(PJSIP_CONF)
    return cfg


def _write_pjsip(cfg: configparser.RawConfigParser) -> None:
    with open(PJSIP_CONF, "w") as f:
        cfg.write(f)
    try:
        _asterisk("module reload res_pjsip.so", timeout=10)
    except Exception:
        pass


def _list_endpoints(cfg: configparser.RawConfigParser) -> list[str]:
    return [
        s for s in cfg.sections()
        if cfg.get(s, "type", fallback=None) == "endpoint"
    ]


@app.get("/extensions", dependencies=[Depends(require_auth)])
def list_extensions():
    cfg = _read_pjsip()
    result = []
    for section in _list_endpoints(cfg):
        result.append({
            "name":         section,
            "context":      cfg.get(section, "context", fallback="from-internal"),
            "max_contacts": cfg.get(f"aor_{section}", "max_contacts", fallback="5"),
            "webrtc":       cfg.get(section, "dtls_enable", fallback="no") == "yes",
            "has_auth":     cfg.has_section(f"auth{section}"),
        })
    return result


@app.post("/extensions", dependencies=[Depends(require_auth)])
def create_extension(req: ExtensionCreate):
    cfg = _read_pjsip()
    name      = req.name
    auth_name = f"auth{name}"
    aor_name  = f"aor_{name}"

    if cfg.has_section(name):
        raise HTTPException(409, f"Extension {name} already exists")

    # Endpoint stanza
    endpoint: dict = {
        "type":       "endpoint",
        "context":    req.context,
        "disallow":   "all",
        "allow":      "opus,ulaw,alaw,g722",
        "auth":       auth_name,
        "aors":       aor_name,
        "force_rport": "yes",
        "direct_media": "no",
    }

    if req.webrtc:
        # DTLS/SRTP settings required by SIP.js / WebRTC (per sipjs.com/guides/server-configuration/asterisk/)
        endpoint.update({
            "dtls_enable":    "yes",
            "dtls_verify":    "fingerprint",
            "dtls_cert_file": CERT_FILE,
            "dtls_ca_file":   CERT_FILE,
            "dtls_setup":     "actpass",
            "ice_support":    "yes",
            "media_encryption": "dtls",
            "rtcp_mux":       "yes",
        })

    cfg[name]      = endpoint
    cfg[auth_name] = {
        "type":       "auth",
        "auth_type":  "userpass",
        "username":   name,
        "password":   req.password,
    }
    cfg[aor_name]  = {
        "type":          "aor",
        "max_contacts":  str(req.max_contacts),
        "remove_existing": "yes",
    }

    _write_pjsip(cfg)
    return {"name": name, "webrtc": req.webrtc, "created": True}


@app.delete("/extensions/{name}", dependencies=[Depends(require_auth)])
def delete_extension(name: str):
    cfg = _read_pjsip()
    removed = []
    for section in (name, f"auth{name}", f"aor_{name}"):
        if cfg.has_section(section):
            cfg.remove_section(section)
            removed.append(section)
    if not removed:
        raise HTTPException(404, f"Extension {name} not found")
    _write_pjsip(cfg)
    return {"name": name, "removed_sections": removed}


# ---------------------------------------------------------------------------
# Asterisk reload
# ---------------------------------------------------------------------------


@app.post("/asterisk/reload", dependencies=[Depends(require_auth)])
def reload_asterisk():
    try:
        output = _asterisk("module reload", timeout=15)
        return {"reloaded": True, "output": output}
    except subprocess.TimeoutExpired:
        raise HTTPException(504, "Reload timed out")
    except Exception as e:
        raise HTTPException(500, str(e))


# ---------------------------------------------------------------------------
# Calls / channels
# ---------------------------------------------------------------------------


@app.get("/calls", dependencies=[Depends(require_auth)])
def list_calls():
    try:
        output = _asterisk("core show channels concise", timeout=5)
        channels = []
        for line in output.splitlines():
            parts = line.split("!")
            if len(parts) >= 3:
                channels.append({
                    "channel":  parts[0],
                    "context":  parts[1],
                    "exten":    parts[2],
                    "state":    parts[4] if len(parts) > 4 else "",
                    "duration": parts[9] if len(parts) > 9 else "",
                })
        return channels
    except Exception as e:
        raise HTTPException(500, str(e))


@app.post("/calls/hangup", dependencies=[Depends(require_auth)])
def hangup_call(req: HangupRequest):
    try:
        output = _asterisk(f"channel request hangup {req.channel}", timeout=10)
        return {"channel": req.channel, "output": output}
    except Exception as e:
        raise HTTPException(500, str(e))


# ---------------------------------------------------------------------------
# Logs
# ---------------------------------------------------------------------------


@app.get("/logs", dependencies=[Depends(require_auth)])
def get_logs(tail: int = 200):
    try:
        result = subprocess.run(
            ["tail", f"-{tail}", ASTERISK_LOG],
            capture_output=True, text=True, timeout=5
        )
        return PlainTextResponse(result.stdout)
    except FileNotFoundError:
        return PlainTextResponse("Log file not found yet")
    except Exception as e:
        raise HTTPException(500, str(e))


# ---------------------------------------------------------------------------
# VM shell (Terminal screen)
# ---------------------------------------------------------------------------


@app.post("/vm/exec", dependencies=[Depends(require_auth)])
def vm_exec(req: ExecRequest):
    try:
        return _sh(req.cmd, timeout=30)
    except subprocess.TimeoutExpired:
        raise HTTPException(504, "Command timed out")
    except Exception as e:
        raise HTTPException(500, str(e))


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=7080, log_level="info")
