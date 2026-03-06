#!/bin/sh
# alpine_build_inner.sh — Runs INSIDE the Alpine build container to pre-install
# Asterisk and the FastAPI control server into the base disk image.
# Called by build_alpine_base.sh.

set -e

GUEST_DIR="/guest"
OUT_DIR="/out"

echo "[inner] Installing Asterisk packages..."
apk update
apk add --no-cache \
    asterisk \
    asterisk-pjsip \
    asterisk-codec-g722 \
    asterisk-sounds-en \
    python3 \
    py3-pip \
    py3-setuptools \
    openrc \
    util-linux \
    e2fsprogs

echo "[inner] Installing Python packages..."
pip3 install --no-cache-dir \
    fastapi==0.111.0 \
    uvicorn==0.30.1

echo "[inner] Copying guest files..."
mkdir -p /bootstrap
cp "$GUEST_DIR/api_server.py"      /usr/local/bin/stardial_api.py
cp "$GUEST_DIR/init_bootstrap.sh"  /bootstrap/init_bootstrap.sh
cp "$GUEST_DIR/requirements.txt"   /bootstrap/requirements.txt
chmod +x /usr/local/bin/stardial_api.py /bootstrap/init_bootstrap.sh

# Pre-write Asterisk config templates
mkdir -p /etc/asterisk
for conf in pjsip.conf extensions.conf rtp.conf manager.conf http.conf ari.conf; do
    if [ -f "$GUEST_DIR/asterisk_config/$conf" ]; then
        cp "$GUEST_DIR/asterisk_config/$conf" "/etc/asterisk/$conf"
    fi
done

echo "[inner] Setting up OpenRC for Asterisk..."
# Create minimal inittab entry for openrc
cat > /etc/inittab << 'EOF'
::sysinit:/sbin/openrc sysinit
::sysinit:/sbin/openrc boot
::wait:/sbin/openrc default
::ctrlaltdel:/sbin/reboot
::shutdown:/sbin/openrc shutdown
EOF

# Create asterisk OpenRC service
cat > /etc/init.d/asterisk << 'INITEOF'
#!/sbin/openrc-run
name="asterisk"
description="Asterisk PBX"
command="/usr/sbin/asterisk"
command_args="-f"
command_background=true
pidfile="/var/run/asterisk/asterisk.pid"
start_pre() { mkdir -p /var/run/asterisk /var/log/asterisk /var/spool/asterisk; }
depend() { need net; after localmount; }
INITEOF
chmod +x /etc/init.d/asterisk
rc-update add asterisk default 2>/dev/null || true

# Create stardial-api OpenRC service
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
depend() { need net asterisk; }
INITEOF
chmod +x /etc/init.d/stardial-api
rc-update add stardial-api default 2>/dev/null || true

# Set init_bootstrap.sh to run on first boot via /etc/local.d
mkdir -p /etc/local.d
ln -sf /bootstrap/init_bootstrap.sh /etc/local.d/00-stardial-bootstrap.start
rc-update add local default 2>/dev/null || true

echo "[inner] Alpine base image build complete."
