#!/bin/bash
# build_alpine_base.sh — Build Alpine 3.19 aarch64 rootfs for the Stardial VM.
# Uses a native linux/arm64 Alpine container with "apk --root" (no chroot, no binfmt_misc).
# Asterisk + Python are installed at runtime by init_bootstrap.sh (first boot).
#
# Output: android/app/src/main/assets/vm/base.qcow2.gz
#
# Requirements: Docker (Colima or Docker Desktop) with arm64 container support.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ASSETS_VM_DIR="${PROJECT_ROOT}/android/app/src/main/assets/vm"
GUEST_DIR="${PROJECT_ROOT}/guest"

mkdir -p "${ASSETS_VM_DIR}"

echo "=== Building Alpine 3.19 aarch64 base image for Stardial ==="
echo "Output: ${ASSETS_VM_DIR}/base.qcow2.gz"
echo ""

docker run --rm \
    --platform linux/arm64 \
    --privileged \
    -v "${ASSETS_VM_DIR}:/out" \
    -v "${GUEST_DIR}:/bootstrap_src:ro" \
    -v "${SCRIPT_DIR}/alpine_build_inner.sh:/build.sh:ro" \
    alpine:3.19 \
    sh /build.sh 2>&1

echo ""
echo "=== Build complete ==="
ls -lh "${ASSETS_VM_DIR}/base.qcow2.gz"
echo ""
echo "SHA-256:"
shasum -a 256 "${ASSETS_VM_DIR}/base.qcow2.gz"
