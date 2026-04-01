#!/usr/bin/env python3
"""
FastAPI control server for Asterisk PBX inside Alpine Linux VM.
Listens on 0.0.0.0:7080 — SLIRP hostfwd delivers connections from Android host.

Token is injected by the Android app via QEMU -append api_token=<TOKEN>.
Guest reads it from /proc/cmdline.
"""

import json
import logging
import os
import socket
import subprocess
import time
import uuid
from typing import Optional

from fastapi import Depends, FastAPI, HTTPException, Header
from fastapi.responses import PlainTextResponse
from pydantic import BaseModel

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI(title="Stardial Asterisk API", version="1.0.0")

PJSIP_CONF      = "/etc/asterisk/pjsip.conf"
ASTERISK_LOG    = "/var/log/asterisk/messages"
CERT_FILE       = "/etc/asterisk/keys/asterisk.pem"
KEY_FILE        = "/etc/asterisk/keys/asterisk.key"
MESSAGES_FILE   = "/var/lib/asterisk/messages.json"
EXTENSIONS_FILE = "/var/lib/asterisk/extensions.json"

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
    # Kernel cmdline: QEMU injects api_token=<TOKEN> via -append
    try:
        with open("/proc/cmdline") as f:
            for part in f.read().split():
                if part.startswith("api_token="):
                    t = part[len("api_token="):].strip()
                    if t:
                        logger.info("Token loaded from /proc/cmdline")
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
            s.sendall((
                f"Action: MessageSend\r\nTo: pjsip:{to_ext}\r\n"
                f"From: pjsip:{from_ext}\r\nBody: {safe_body}\r\n\r\n"
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
# Extension storage (JSON-based)
# ---------------------------------------------------------------------------


def _read_user_extensions() -> list:
    try:
        with open(EXTENSIONS_FILE) as f:
            return json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        return []


def _write_user_extensions(exts: list) -> None:
    os.makedirs(os.path.dirname(EXTENSIONS_FILE), exist_ok=True)
    with open(EXTENSIONS_FILE, "w") as f:
        json.dump(exts, f, indent=2)


# ---------------------------------------------------------------------------
# pjsip.conf generation (string-based, not configparser)
# ---------------------------------------------------------------------------


def _generate_pjsip_conf(user_exts: list) -> str:
    """Generate complete pjsip.conf from scratch in proper Asterisk format."""
    out = []

    def section(name, **kv):
        out.append(f"[{name}]")
        for k, v in kv.items():
            out.append(f"{k}={v}")
        out.append("")

    section("global",
        type="global",
        user_agent="Stardial PBX 1.0",
        endpoint_identifier_order="username,ip,anonymous",
    )
    section("transport-udp", type="transport", protocol="udp", bind="0.0.0.0:5060")
    section("transport-tcp", type="transport", protocol="tcp", bind="0.0.0.0:5060")
    section("transport-ws",  type="transport", protocol="ws",  bind="0.0.0.0:8088")
    section("transport-wss",
        type="transport", protocol="wss", bind="0.0.0.0:8089",
        cert_file=CERT_FILE, priv_key_file=KEY_FILE,
    )

    # App's own extension 1000 (always present)
    section("1000",
        type="endpoint",
        context="from-internal",
        message_context="from-internal-msg",
        disallow="all",
        allow="opus,ulaw,alaw,g722",
        auth="auth1000",
        aors="aor_1000",
        force_rport="yes",
        direct_media="no",
        dtls_verify="fingerprint",
        dtls_cert_file=CERT_FILE,
        dtls_ca_file=CERT_FILE,
        dtls_setup="actpass",
        ice_support="yes",
        media_encryption="dtls",
        rtcp_mux="yes",
    )
    section("auth1000",
        type="auth", auth_type="userpass", username="1000", password="zyvr_local_pass",
    )
    section("aor_1000",
        type="aor", max_contacts="5", remove_existing="yes",
    )

    # User-created extensions
    for ext in user_exts:
        name = ext["name"]
        ep = dict(
            type="endpoint",
            context=ext.get("context", "from-internal"),
            message_context="from-internal-msg",
            disallow="all",
            allow="opus,ulaw,alaw,g722",
            auth=f"auth{name}",
            aors=f"aor_{name}",
            force_rport="yes",
            direct_media="no",
        )
        if ext.get("webrtc", True):
            ep.update(
                dtls_verify="fingerprint",
                dtls_cert_file=CERT_FILE,
                dtls_ca_file=CERT_FILE,
                dtls_setup="actpass",
                ice_support="yes",
                media_encryption="dtls",
                rtcp_mux="yes",
            )
        section(name, **ep)
        section(f"auth{name}",
            type="auth", auth_type="userpass",
            username=name, password=ext["password"],
        )
        section(f"aor_{name}",
            type="aor",
            max_contacts=str(ext.get("max_contacts", 5)),
            remove_existing="yes",
        )

    return "\n".join(out)


def _rebuild_pjsip() -> None:
    """Write pjsip.conf from scratch and reload pjsip module."""
    user_exts = _read_user_extensions()
    os.makedirs(os.path.dirname(PJSIP_CONF), exist_ok=True)
    with open(PJSIP_CONF, "w") as f:
        f.write(_generate_pjsip_conf(user_exts))
    try:
        out = _asterisk("module reload res_pjsip.so", timeout=15)
        logger.info("pjsip reload: %s", out or "(ok)")
    except Exception as e:
        logger.warning("pjsip reload failed: %s", e)


# ---------------------------------------------------------------------------
# Startup: rebuild pjsip.conf to ensure it's always correct
# ---------------------------------------------------------------------------


ASTERISK_CONF_FILE  = "/etc/asterisk/asterisk.conf"
SORCERY_CONF_FILE   = "/etc/asterisk/sorcery.conf"
SORCERY_CONF_CONTENT = """\
[res_pjsip]
endpoint=config,pjsip.conf,criteria=type=endpoint
auth=config,pjsip.conf,criteria=type=auth
aor=config,pjsip.conf,criteria=type=aor
transport=config,pjsip.conf,criteria=type=transport
global=config,pjsip.conf,criteria=type=global
domain_alias=config,pjsip.conf,criteria=type=domain_alias
registration=config,pjsip.conf,criteria=type=registration
identify=config,pjsip.conf,criteria=type=identify
"""
ASTERISK_CONF_CONTENT = """\
[directories]
astetcdir => /etc/asterisk
astmoddir => /usr/lib/asterisk/modules
astvarlibdir => /var/lib/asterisk
astdbdir => /var/lib/asterisk
astkeydir => /var/lib/asterisk
astdatadir => /var/lib/asterisk
astagidir => /var/lib/asterisk/agi-bin
astspooldir => /var/spool/asterisk
astrundir => /var/run/asterisk
astlogdir => /var/log/asterisk
astsbindir => /usr/sbin

[options]
verbose=3
"""


@app.on_event("startup")
async def on_startup():
    # Write sorcery.conf if missing — maps pjsip objects to pjsip.conf
    if not os.path.exists(SORCERY_CONF_FILE):
        try:
            os.makedirs("/etc/asterisk", exist_ok=True)
            with open(SORCERY_CONF_FILE, "w") as f:
                f.write(SORCERY_CONF_CONTENT)
            logger.info("Created %s", SORCERY_CONF_FILE)
        except Exception as e:
            logger.warning("sorcery.conf creation failed: %s", e)

    # Write asterisk.conf if missing — without it Asterisk ignores /etc/asterisk/
    if not os.path.exists(ASTERISK_CONF_FILE):
        try:
            os.makedirs("/etc/asterisk", exist_ok=True)
            with open(ASTERISK_CONF_FILE, "w") as f:
                f.write(ASTERISK_CONF_CONTENT)
            logger.info("Created %s — restarting Asterisk", ASTERISK_CONF_FILE)
            subprocess.run(["rc-service", "asterisk", "restart"], timeout=30)
            time.sleep(10)  # wait for Asterisk to finish restarting
            logger.info("Asterisk restarted with asterisk.conf")
        except Exception as e:
            logger.warning("asterisk.conf setup failed: %s", e)
    try:
        _rebuild_pjsip()
        logger.info("pjsip.conf rebuilt on startup")
    except Exception as e:
        logger.warning("pjsip startup rebuild failed: %s", e)


# ---------------------------------------------------------------------------
# Models
# ---------------------------------------------------------------------------


class ExtensionCreate(BaseModel):
    name: str
    password: str
    context: str = "from-internal"
    max_contacts: int = 5
    webrtc: bool = True


class HangupRequest(BaseModel):
    channel: str


class ExecRequest(BaseModel):
    cmd: str


class MessageSend(BaseModel):
    from_ext: str
    to_ext: str
    body: str


# ---------------------------------------------------------------------------
# Health
# ---------------------------------------------------------------------------


@app.get("/health")
def health():
    try:
        pidof = subprocess.run(["pidof", "asterisk"], capture_output=True, timeout=5)
        running = pidof.returncode == 0
        if not running:
            try:
                with open("/var/run/asterisk/asterisk.pid") as _pf:
                    _pid = int(_pf.read().strip())
                import os as _os
                _os.kill(_pid, 0)
                running = True
            except Exception:
                pass
        
        version = ""
        if running:
            try:
                out = subprocess.run(["asterisk", "-rx", "core show version"], capture_output=True, text=True, timeout=2)
                if out.returncode == 0:
                    version = out.stdout.strip()
            except subprocess.TimeoutExpired:
                pass
                
        return {
            "status":  "running" if running else "stopped",
            "version": version or "unknown",
            "wss":     "wss://127.0.0.1:8089/asterisk/sip",
            "ws":      "ws://127.0.0.1:8088/asterisk/sip",
        }
    except Exception as e:
        return {"status": "error", "detail": str(e)}


# ---------------------------------------------------------------------------
# TLS cert fingerprint
# ---------------------------------------------------------------------------


@app.get("/cert/fingerprint", dependencies=[Depends(require_auth)])
def cert_fingerprint():
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
# Extensions
# ---------------------------------------------------------------------------


@app.get("/extensions", dependencies=[Depends(require_auth)])
def list_extensions():
    return [
        {
            "name":    e["name"],
            "context": e.get("context", "from-internal"),
            "has_auth": True,
            "webrtc":  e.get("webrtc", True),
        }
        for e in _read_user_extensions()
    ]


@app.post("/extensions", dependencies=[Depends(require_auth)])
def create_extension(req: ExtensionCreate):
    exts = _read_user_extensions()
    if any(e["name"] == req.name for e in exts):
        raise HTTPException(409, f"Extension {req.name} already exists")
    exts.append({
        "name":         req.name,
        "password":     req.password,
        "context":      req.context,
        "max_contacts": req.max_contacts,
        "webrtc":       req.webrtc,
    })
    _write_user_extensions(exts)
    _rebuild_pjsip()
    return {"name": req.name, "webrtc": req.webrtc, "created": True}


@app.delete("/extensions/{name}", dependencies=[Depends(require_auth)])
def delete_extension(name: str):
    exts = _read_user_extensions()
    new_exts = [e for e in exts if e["name"] != name]
    if len(new_exts) == len(exts):
        raise HTTPException(404, f"Extension {name} not found")
    _write_user_extensions(new_exts)
    _rebuild_pjsip()
    return {"name": name, "removed_sections": [name, f"auth{name}", f"aor_{name}"]}


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
