#!/bin/sh
# alpine_build_inner.sh — runs INSIDE an arm64 Alpine container (--privileged)
# Builds a minimal Alpine 3.19 aarch64 rootfs with Asterisk + Python pre-installed.
# Packages are baked in at build time so the app works fully offline on first boot.
# Called by build_alpine_base.sh via Docker.

set -e

ALPINE_VERSION=3.19.1

echo "=== Installing host build tools ==="
apk add --no-cache e2fsprogs qemu-img wget

echo "=== Downloading Alpine ${ALPINE_VERSION} aarch64 minirootfs ==="
MINIROOTFS_URL="https://dl-cdn.alpinelinux.org/alpine/v3.19/releases/aarch64/alpine-minirootfs-${ALPINE_VERSION}-aarch64.tar.gz"
wget -q -O /tmp/minirootfs.tar.gz "$MINIROOTFS_URL"
echo "Downloaded: $(du -sh /tmp/minirootfs.tar.gz | cut -f1)"

echo "=== Creating 2GB ext4 raw disk ==="
dd if=/dev/zero of=/tmp/alpine.raw bs=1M count=2048 status=none
mkfs.ext4 -F -L "alpine-root" -m 0 -q /tmp/alpine.raw

mkdir -p /mnt/alpine
mount -o loop /tmp/alpine.raw /mnt/alpine

echo "=== Extracting minirootfs ==="
tar xzf /tmp/minirootfs.tar.gz -C /mnt/alpine

# APK repositories
cat > /mnt/alpine/etc/apk/repositories << 'REPOS'
https://dl-cdn.alpinelinux.org/alpine/v3.19/main
https://dl-cdn.alpinelinux.org/alpine/v3.19/community
REPOS

echo "=== Installing alpine-base + openrc via apk --root ==="
apk --root /mnt/alpine \
    --arch aarch64 \
    --repositories-file /mnt/alpine/etc/apk/repositories \
    add --no-cache \
    alpine-base openrc 2>&1 | tail -15

# System config
echo "stardial-pbx" > /mnt/alpine/etc/hostname

cat > /mnt/alpine/etc/hosts << 'HOSTS'
127.0.0.1 localhost stardial-pbx
::1       localhost
HOSTS

# QEMU SLIRP networking — static IP (no udhcpc / AF_PACKET needed)
mkdir -p /mnt/alpine/etc/network
cat > /mnt/alpine/etc/network/interfaces << 'NET'
auto lo
iface lo inet loopback
auto eth0
iface eth0 inet static
  address 10.0.2.15
  netmask 255.255.255.0
  gateway 10.0.2.2
NET

# DNS — use-vc forces TCP (SLIRP UDP proxy is unreliable on some Android builds)
cat > /mnt/alpine/etc/resolv.conf << 'DNS'
nameserver 10.0.2.3
nameserver 8.8.8.8
nameserver 8.8.4.4
options timeout:2 attempts:2 use-vc
DNS

# Load qemu_fw_cfg at boot so api_token is readable from /sys/firmware/qemu_fw_cfg/
echo "qemu_fw_cfg" >> /mnt/alpine/etc/modules

# fstab
cat > /mnt/alpine/etc/fstab << 'FSTAB'
/dev/vda / ext4 rw,relatime 0 1
proc /proc proc defaults 0 0
sysfs /sys sysfs defaults 0 0
devtmpfs /dev devtmpfs defaults 0 0
devpts /dev/pts devpts gid=5,mode=620 0 0
shm /dev/shm tmpfs defaults 0 0
tmp /tmp tmpfs nosuid,nodev 0 0
FSTAB

# ---------------------------------------------------------------------------
# Pre-install Asterisk + Python + pip packages via chroot (build-time, offline)
# ---------------------------------------------------------------------------
echo "=== Pre-installing Asterisk + Python + pip packages (offline bake) ==="
mount -t proc  proc     /mnt/alpine/proc
mount -t sysfs sysfs    /mnt/alpine/sys
mount -o bind  /dev     /mnt/alpine/dev
mount -t devpts devpts  /mnt/alpine/dev/pts

chroot /mnt/alpine /bin/sh << 'CHROOT'
set -e
apk update
apk add --no-cache \
    asterisk \
    asterisk-sounds-en \
    asterisk-srtp \
    openssl \
    python3 \
    py3-pip \
    py3-setuptools
pip3 install --no-cache-dir --break-system-packages \
    "fastapi==0.111.0" \
    "uvicorn[standard]==0.30.1"
# Clean pip cache to save space
rm -rf /root/.cache/pip
CHROOT

umount /mnt/alpine/dev/pts
umount /mnt/alpine/dev
umount /mnt/alpine/sys
umount /mnt/alpine/proc

echo "Rootfs size after pre-install: $(du -sh /mnt/alpine | cut -f1)"

# Bootstrap scripts — cert/config/service setup only (packages already installed)
echo "=== Copying bootstrap scripts ==="
mkdir -p /mnt/alpine/bootstrap
cp /bootstrap_src/api_server.py     /mnt/alpine/bootstrap/
cp /bootstrap_src/requirements.txt  /mnt/alpine/bootstrap/
cp /bootstrap_src/init_bootstrap.sh /mnt/alpine/bootstrap/
cp /bootstrap_src/store_msg.py      /mnt/alpine/bootstrap/
chmod +x /mnt/alpine/bootstrap/init_bootstrap.sh

# OpenRC service — runs init_bootstrap.sh on first boot
cat > /mnt/alpine/etc/init.d/stardial-bootstrap << 'RC'
#!/sbin/openrc-run
name="stardial-bootstrap"
description="Install Asterisk and start API server on first boot"

depend() {
    need networking
    after networking
}

start() {
    [ -f /bootstrap/.bootstrapped ] && return 0
    ebegin "Running Stardial bootstrap (first boot only)"
    /bootstrap/init_bootstrap.sh
    local ret=$?
    eend $ret
}
RC
chmod +x /mnt/alpine/etc/init.d/stardial-bootstrap

# OpenRC runlevel symlinks (manual — no rc-update without chroot)
echo "=== Configuring OpenRC runlevels ==="
mkdir -p /mnt/alpine/etc/runlevels/sysinit \
         /mnt/alpine/etc/runlevels/boot \
         /mnt/alpine/etc/runlevels/default \
         /mnt/alpine/etc/runlevels/shutdown

for svc in devfs dmesg; do
    ln -sf /etc/init.d/$svc /mnt/alpine/etc/runlevels/sysinit/$svc
done

for svc in modules sysctl hostname bootmisc syslog; do
    ln -sf /etc/init.d/$svc /mnt/alpine/etc/runlevels/boot/$svc
done

for svc in networking stardial-bootstrap; do
    ln -sf /etc/init.d/$svc /mnt/alpine/etc/runlevels/default/$svc
done

for svc in killprocs mount-ro savecache; do
    [ -f /mnt/alpine/etc/init.d/$svc ] && \
        ln -sf /etc/init.d/$svc /mnt/alpine/etc/runlevels/shutdown/$svc || true
done

echo "Final rootfs size: $(du -sh /mnt/alpine | cut -f1)"
df -h /mnt/alpine | tail -1

umount /mnt/alpine

echo "=== Converting raw → QCOW2 ==="
qemu-img convert -f raw -O qcow2 -c /tmp/alpine.raw /tmp/base.qcow2

echo "=== Compressing ==="
gzip -9 -c /tmp/base.qcow2 > /out/base.qcow2.gz

echo "=== Done ==="
ls -lh /out/base.qcow2.gz
qemu-img info /tmp/base.qcow2
