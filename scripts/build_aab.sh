#!/usr/bin/env bash
# build_aab.sh — Build the Zyvr AAB inside a Docker container.
# Usage: ./scripts/build_aab.sh [release|debug]
#
# Uses the same Ubuntu+Android SDK+Flutter builder image as Pockr.
# Must use --platform linux/amd64 on Apple Silicon Macs.

set -euo pipefail

MODE="${1:-release}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$PROJECT_ROOT/dist"
BUILDER_IMAGE="zyvr-builder"
DOCKERFILE="$PROJECT_ROOT/docker/Dockerfile.build"

mkdir -p "$BUILD_DIR"

echo "[zyvr] Building AAB (mode: $MODE)..."

# Build the builder image if it doesn't exist or Dockerfile has changed
if ! docker image inspect "$BUILDER_IMAGE" &>/dev/null; then
    echo "[zyvr] Building Docker builder image..."
    docker build \
        --platform linux/amd64 \
        -t "$BUILDER_IMAGE" \
        -f "$DOCKERFILE" \
        "$PROJECT_ROOT"
fi

# Run the Flutter build inside the container
JNILIBS_SRC="$(cd "$PROJECT_ROOT/../pockr/android/app/src/main/jniLibs/arm64-v8a" 2>/dev/null && pwd || true)"
JNILIBS_DST="/workspace/android/app/src/main/jniLibs/arm64-v8a"

if [ -z "$JNILIBS_SRC" ]; then
    echo "[zyvr] ERROR: pockr jniLibs not found at ../pockr/android/app/src/main/jniLibs/arm64-v8a"
    exit 1
fi

docker run --rm \
    --platform linux/amd64 \
    -v "$PROJECT_ROOT:/workspace" \
    -v "$JNILIBS_SRC:$JNILIBS_DST:ro" \
    -w /workspace \
    "$BUILDER_IMAGE" \
    bash -c "
        flutter clean && \
        flutter pub get && \
        dart run flutter_launcher_icons && \
        flutter build appbundle --$MODE --target-platform android-arm64
    "

# Copy AAB out after the container exits
cp "$PROJECT_ROOT/build/app/outputs/bundle/${MODE}/app-${MODE}.aab" "$BUILD_DIR/zyvr-$MODE.aab"
echo "[zyvr] AAB ready: $BUILD_DIR/zyvr-$MODE.aab"
