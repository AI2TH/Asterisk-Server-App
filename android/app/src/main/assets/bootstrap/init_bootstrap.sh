#!/bin/sh
# init_bootstrap.sh — first-boot setup for Stardial Alpine VM
# Runs once (guarded by /bootstrap/.bootstrapped marker).
# Subsequent boots: OpenRC starts asterisk and stardial-api services directly.

set -e

MARKER="/bootstrap/.bootstrapped"
BOOTSTRAP_DIR="/bootstrap"
ASTERISK_CONF="/etc/asterisk"
KEYS_DIR="/etc/asterisk/keys"

if [ -f "$MARKER" ]; then
    echo "[stardial] Already bootstrapped, skipping."
    rc-service asterisk start 2>/dev/null || true
    rc-service stardial-api start 2>/dev/null || true
    exit 0
fi

echo "[stardial] === First boot bootstrap starting ==="

# ---------------------------------------------------------------------------
# 1. Install Asterisk, Python, and TLS tooling
# ---------------------------------------------------------------------------
echo "[stardial] Installing packages..."
apk update
apk add --no-cache \
    asterisk \
    asterisk-pjsip \
    asterisk-codec-g722 \
    asterisk-sounds-en \
    asterisk-srtp \
    openssl \
    python3 \
    py3-pip \
    py3-setuptools

# ---------------------------------------------------------------------------
# 2. Generate self-signed TLS certificate for WSS
# ---------------------------------------------------------------------------
echo "[stardial] Generating TLS certificate..."
mkdir -p "$KEYS_DIR"
openssl req -x509 -newkey rsa:2048 \
    -keyout "$KEYS_DIR/asterisk.key" \
    -out    "$KEYS_DIR/asterisk.pem" \
    -days   3650 \
    -nodes \
    -subj "/CN=stardial-pbx/O=Stardial/C=US" \
    -addext "subjectAltName=IP:127.0.0.1"
# Asterisk wants combined PEM for some configs
cat "$KEYS_DIR/asterisk.pem" "$KEYS_DIR/asterisk.key" > "$KEYS_DIR/asterisk-combined.pem"
chmod 600 "$KEYS_DIR/asterisk.key" "$KEYS_DIR/asterisk-combined.pem"
echo "[stardial] TLS certificate generated at $KEYS_DIR"

# ---------------------------------------------------------------------------
# 3. Install Python deps for API server
# ---------------------------------------------------------------------------
echo "[stardial] Installing Python packages..."
pip3 install --no-cache-dir -r "$BOOTSTRAP_DIR/requirements.txt"

# ---------------------------------------------------------------------------
# 4. Write Asterisk config files
# ---------------------------------------------------------------------------
echo "[stardial] Writing Asterisk configuration..."

# pjsip.conf — 4 transports: UDP, TCP, WS, WSS
cat > "$ASTERISK_CONF/pjsip.conf" << 'EOF'
[global]
type=global
user_agent=Stardial PBX 1.0
endpoint_identifier_order=username,ip,anonymous

[transport-udp]
type=transport
protocol=udp
bind=0.0.0.0:5060

[transport-tcp]
type=transport
protocol=tcp
bind=0.0.0.0:5060

[transport-ws]
type=transport
protocol=ws
bind=0.0.0.0:8088

[transport-wss]
type=transport
protocol=wss
bind=0.0.0.0:8089
cert_file=/etc/asterisk/keys/asterisk.pem
priv_key_file=/etc/asterisk/keys/asterisk.key
EOF

# extensions.conf
cat > "$ASTERISK_CONF/extensions.conf" << 'EOF'
[general]
static=yes
writeprotect=no

[from-internal]
exten => _X.,1,NoOp(Stardial: Dial ${EXTEN})
 same => n,Dial(PJSIP/${EXTEN},30)
 same => n,VoiceMail(${EXTEN}@default,u)
 same => n,Hangup()

exten => *97,1,VoicemailMain()
 same => n,Hangup()

exten => 9999,1,Answer()
 same => n,Echo()
 same => n,Hangup()

exten => 9998,1,Answer()
 same => n,Playback(demo-congrats)
 same => n,Hangup()
EOF

# rtp.conf — matches SLIRP hostfwd UDP range 10000-10019
cat > "$ASTERISK_CONF/rtp.conf" << 'EOF'
[general]
rtpstart=10000
rtpend=10019
EOF

# manager.conf — AMI (127.0.0.1 only; forwarded via SLIRP tcp::5038-:5038)
cat > "$ASTERISK_CONF/manager.conf" << 'EOF'
[general]
enabled=yes
port=5038
bindaddr=127.0.0.1
timestampevents=yes

[stardial]
secret=stardial_ami_secret
read=all
write=all
EOF

# http.conf — ARI (8088) + WSS (8089)
cat > "$ASTERISK_CONF/http.conf" << 'EOF'
[general]
enabled=yes
bindaddr=0.0.0.0
bindport=8088
prefix=asterisk
tlsenable=yes
tlsbindaddr=0.0.0.0:8089
tlscertfile=/etc/asterisk/keys/asterisk.pem
tlsprivkeyfile=/etc/asterisk/keys/asterisk.key
EOF

# ari.conf
cat > "$ASTERISK_CONF/ari.conf" << 'EOF'
[general]
enabled=yes
pretty=yes

[stardial]
type=user
password=stardial_ari_pass
password_format=plain
EOF

# modules.conf — autoload handles pjsip/srtp; no explicit load needed
# (explicit "load =>" for modules not installed causes Asterisk to abort)

# logger.conf
cat > "$ASTERISK_CONF/logger.conf" << 'EOF'
[general]
dateformat=%F %T

[logfiles]
messages => notice,warning,error,verbose
console  => notice,warning,error
EOF

# ---------------------------------------------------------------------------
# 5. Install API server
# ---------------------------------------------------------------------------
cp "$BOOTSTRAP_DIR/api_server.py" /usr/local/bin/stardial_api.py
chmod +x /usr/local/bin/stardial_api.py

# ---------------------------------------------------------------------------
# 6. OpenRC: asterisk service
# ---------------------------------------------------------------------------
cat > /etc/init.d/asterisk << 'INITEOF'
#!/sbin/openrc-run
name="asterisk"
description="Asterisk PBX"
command="/usr/sbin/asterisk"
command_args="-f"
command_background=true
pidfile="/var/run/asterisk/asterisk.pid"
output_log="/var/log/asterisk/startup.log"
error_log="/var/log/asterisk/startup.log"
start_pre() {
    mkdir -p /var/run/asterisk /var/log/asterisk /var/spool/asterisk
}
depend() {
    need net
    after localmount
}
INITEOF
chmod +x /etc/init.d/asterisk
rc-update add asterisk default

# ---------------------------------------------------------------------------
# 7. OpenRC: stardial-api service
# ---------------------------------------------------------------------------
cat > /etc/init.d/stardial-api << 'INITEOF'
#!/sbin/openrc-run
name="stardial-api"
description="Stardial FastAPI control server"
command="/usr/bin/python3"
command_args="/usr/local/bin/stardial_api.py"
command_background=true
pidfile="/var/run/stardial-api.pid"
stdout_log="/var/log/stardial-api.log"
stderr_log="/var/log/stardial-api.log"
depend() {
    need net asterisk
}
INITEOF
chmod +x /etc/init.d/stardial-api
rc-update add stardial-api default

# ---------------------------------------------------------------------------
# 8. Start services
# ---------------------------------------------------------------------------
echo "[stardial] Starting Asterisk..."
rc-service asterisk start

# Give process a moment to settle or crash
sleep 3
if pidof asterisk >/dev/null 2>&1; then
    echo "[stardial] Asterisk process running (pid: $(pidof asterisk))"
else
    echo "[stardial] WARNING: Asterisk not running after start. Startup log:"
    tail -30 /var/log/asterisk/startup.log 2>/dev/null || echo "(no startup log)"
fi

echo "[stardial] Waiting for Asterisk CLI to be ready..."
for i in $(seq 1 30); do
    if asterisk -rx "core show version" >/dev/null 2>&1; then
        echo "[stardial] Asterisk CLI is ready."
        break
    fi
    sleep 2
done

echo "[stardial] Starting Stardial API server..."
rc-service stardial-api start

# ---------------------------------------------------------------------------
# 9. Mark bootstrap complete
# ---------------------------------------------------------------------------
touch "$MARKER"
echo "[stardial] === Bootstrap complete ==="
echo "[stardial] WSS endpoint: wss://127.0.0.1:8089/asterisk/sip"
echo "[stardial] WS  endpoint: ws://127.0.0.1:8088/asterisk/sip"
