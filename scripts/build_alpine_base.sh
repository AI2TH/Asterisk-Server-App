#!/usr/bin/env bash
# build_alpine_base.sh — Build Alpine Linux base image with Asterisk pre-installed.
# Output: android/app/src/main/assets/vm/base.qcow2.gz
#
# Prerequisites: Docker Desktop running, qemu-img available (or runs inside Docker)
# Platform: must run on aarch64 or use --platform linux/arm64

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ASSETS_VM_DIR="$PROJECT_ROOT/android/app/src/main/assets/vm"
GUEST_DIR="$PROJECT_ROOT/guest"
OUTPUT_GZ="$ASSETS_VM_DIR/base.qcow2.gz"

CONTAINER_NAME="stardial-alpine-builder-$$"
IMAGE_NAME="arm64v8/alpine:3.19"
DISK_SIZE="4G"
BASE_QCOW2="$ASSETS_VM_DIR/base.qcow2"

echo "[stardial] Building Alpine base image with Asterisk..."
echo "[stardial] Guest dir: $GUEST_DIR"
echo "[stardial] Output:    $OUTPUT_GZ"

mkdir -p "$ASSETS_VM_DIR"

# ---------------------------------------------------------------------------
# 1. Create an ext4 disk image via qemu-img inside a Docker container
# ---------------------------------------------------------------------------
echo "[stardial] Creating blank disk..."
docker run --rm \
  --platform linux/arm64 \
  -v "$ASSETS_VM_DIR:/out" \
  "$IMAGE_NAME" \
  sh -c "apk add --no-cache qemu-img 2>/dev/null || true; \
    dd if=/dev/zero of=/out/base.raw bs=1M count=4096 && \
    mkfs.ext4 /out/base.raw"

# ---------------------------------------------------------------------------
# 2. Run Alpine in QEMU (via Docker QEMU emulation) to install Asterisk
#    This step uses the alpine_build_inner.sh script
# ---------------------------------------------------------------------------
echo "[stardial] Installing Asterisk into disk image..."
docker run --rm \
  --platform linux/arm64 \
  --privileged \
  -v "$ASSETS_VM_DIR:/out" \
  -v "$GUEST_DIR:/guest:ro" \
  "$IMAGE_NAME" \
  sh /guest/alpine_build_inner.sh

# ---------------------------------------------------------------------------
# 3. Convert raw → qcow2 → gzip
# ---------------------------------------------------------------------------
echo "[stardial] Converting and compressing disk image..."
docker run --rm \
  --platform linux/arm64 \
  -v "$ASSETS_VM_DIR:/out" \
  "$IMAGE_NAME" \
  sh -c "apk add --no-cache qemu-img && \
    qemu-img convert -f raw -O qcow2 /out/base.raw /out/base.qcow2 && \
    rm /out/base.raw && \
    gzip -9 /out/base.qcow2"

echo "[stardial] Done. Output: $OUTPUT_GZ"
echo "[stardial] Remember to bump ASSETS_VERSION in VmManager.kt if base image changed."
