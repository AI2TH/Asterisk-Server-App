#!/usr/bin/env python3
"""
FastAPI control server for Asterisk PBX inside Alpine Linux VM.
Listens on 0.0.0.0:7080 — SLIRP hostfwd delivers connections from Android host.

Token is injected by the Android app via QEMU fw_cfg:
  -fw_cfg name=opt/api_token,string=<TOKEN>
Guest reads it from: /sys/firmware/qemu_fw_cfg/by_name/opt/api_token/raw
"""

import configparser
import json
import logging
import os
import re
import socket
import subprocess
import time
import uuid
from typing import Optional

from fastapi import Depends, FastAPI, HTTPException, Header, Path
from fastapi.responses import PlainTextResponse
from pydantic import BaseModel, field_validator

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI(title="Stardial Asterisk API", version="1.0.0")

PJSIP_CONF    = "/etc/asterisk/pjsip.conf"
ASTERISK_LOG  = "/var/log/asterisk/messages"
CERT_FILE     = "/etc/asterisk/keys/asterisk.pem"
MESSAGES_FILE = "/var/lib/asterisk/messages.json"

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
# Messages storage helpers
# ---------------------------------------------------------------------------


def _read_messages() -> list:
    try:
        with open(MESSAGES_FILE) as f:
            return json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        return []


def _write_messages(messages: list) -> None:
    os.makedirs(os.path.dirname(MESSAGES_FILE), exist_ok=True)
    with open(MESSAGES_FILE, "w") as f:
        json.dump(messages, f)


def _ami_send_message(from_ext: str, to_ext: str, body: str) -> bool:
    """Send SIP MESSAGE via AMI MessageSend action to 127.0.0.1:5038."""
    try:
        s = socket.create_connection(("127.0.0.1", 5038), timeout=5)
        with s:
            def _recv_response() -> str:
                data = b""
                while b"\r\n\r\n" not in data:
                    chunk = s.recv(4096)
                    if not chunk:
                        break
                    data += chunk
                return data.decode("utf-8", errors="replace")

            _recv_response()  # banner
            s.sendall(
                b"Action: Login\r\nUsername: stardial\r\n"
                b"Secret: stardial_ami_secret\r\nEvents: off\r\n\r\n"
            )
            _recv_response()  # login response
            safe_body = body.replace("\r\n", " ").replace("\n", " ")
            safe_to = to_ext.replace("\r\n", " ").replace("\n", " ").replace("\r", " ")
            safe_from = from_ext.replace("\r\n", " ").replace("\n", " ").replace("\r", " ")
            s.sendall((
                f"Action: MessageSend\r\nTo: pjsip:{safe_to}\r\n"
                f"From: pjsip:{safe_from}\r\nBody: {safe_body}\r\n\r\n"
            ).encode())
            resp = _recv_response()
            try:
                s.sendall(b"Action: Logoff\r\n\r\n")
            except Exception:
                pass
        return "Response: Success" in resp
    except Exception as e:
        logger.error("AMI send failed: %s", e)
        return False


# ---------------------------------------------------------------------------
# Models
# ---------------------------------------------------------------------------


class ExtensionCreate(BaseModel):
    name: str           # e.g. "1001"
    password: str       # SIP password
    context: str = "from-internal"
    max_contacts: int = 5
    webrtc: bool = True  # enable DTLS/SRTP for SIP.js / WebRTC

    @field_validator("name")
    @classmethod
    def validate_name(cls, v):
        if not re.fullmatch(r"[a-zA-Z0-9_-]+", v):
            raise ValueError("Invalid extension name")
        return v


class HangupRequest(BaseModel):
    channel: str

    @field_validator("channel")
    @classmethod
    def validate_channel(cls, v):
        if not re.fullmatch(r"[a-zA-Z0-9/._\-@;:]+", v):
            raise ValueError("Invalid channel name")
        return v


class ExecRequest(BaseModel):
    cmd: str


class MessageSend(BaseModel):
    from_ext: str
    to_ext: str
    body: str

    @field_validator("from_ext", "to_ext")
    @classmethod
    def validate_extensions(cls, v):
        if not re.fullmatch(r"[a-zA-Z0-9_-]+", v):
            raise ValueError("Invalid extension name")
        return v


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
        fp = result.stdout.strip().replace("SHA256 Fingerprint=", "").replace(":", "").lower()
        return {"fingerprint": fp, "raw": result.stdout.strip()}
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
        "type":            "endpoint",
        "context":         req.context,
        "message_context": "from-internal-msg",
        "disallow":        "all",
        "allow":           "opus,ulaw,alaw,g722",
        "auth":            auth_name,
        "aors":            aor_name,
        "force_rport":     "yes",
        "direct_media":    "no",
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
def delete_extension(name: str = Path(..., regex=r"^[a-zA-Z0-9_-]+$")):
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
# Messages
# ---------------------------------------------------------------------------


@app.get("/messages", dependencies=[Depends(require_auth)])
def list_messages():
    return _read_messages()


@app.post("/messages/send", dependencies=[Depends(require_auth)])
def send_message(req: MessageSend):
    safe_body = req.body.replace("\r\n", " ").replace("\n", " ")
    delivered = _ami_send_message(req.from_ext, req.to_ext, safe_body)
    msg = {
        "id":        str(uuid.uuid4()),
        "from":      req.from_ext,
        "to":        req.to_ext,
        "body":      req.body,
        "timestamp": time.time(),
        "direction": "sent",
        "delivered": delivered,
    }
    messages = _read_messages()
    messages.append(msg)
    _write_messages(messages)
    return msg


@app.delete("/messages/{msg_id}", dependencies=[Depends(require_auth)])
def delete_message(msg_id: str):
    messages = _read_messages()
    before = len(messages)
    messages = [m for m in messages if m.get("id") != msg_id]
    if len(messages) == before:
        raise HTTPException(404, "Message not found")
    _write_messages(messages)
    return {"deleted": True}


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=7080, log_level="info")
