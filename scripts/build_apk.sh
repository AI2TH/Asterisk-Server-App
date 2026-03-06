#!/usr/bin/env bash
# build_apk.sh — Build the Stardial APK inside a Docker container.
# Usage: ./scripts/build_apk.sh [release|debug]
#
# Uses the same Ubuntu+Android SDK+Flutter builder image as Pockr.
# Must use --platform linux/amd64 on Apple Silicon Macs.

set -euo pipefail

MODE="${1:-debug}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$PROJECT_ROOT/build"
BUILDER_IMAGE="stardial-builder"
DOCKERFILE="$PROJECT_ROOT/docker/Dockerfile.build"

mkdir -p "$BUILD_DIR"

echo "[stardial] Building APK (mode: $MODE)..."

# Build the builder image if it doesn't exist or Dockerfile has changed
if ! docker image inspect "$BUILDER_IMAGE" &>/dev/null; then
    echo "[stardial] Building Docker builder image..."
    docker build \
        --platform linux/amd64 \
        -t "$BUILDER_IMAGE" \
        -f "$DOCKERFILE" \
        "$PROJECT_ROOT"
fi

# Run the Flutter build inside the container
docker run --rm \
    --platform linux/amd64 \
    -v "$PROJECT_ROOT:/workspace" \
    -v "$BUILD_DIR:/build-output" \
    -w /workspace \
    "$BUILDER_IMAGE" \
    bash -c "
        flutter pub get && \
        flutter build apk --$MODE --target-platform android-arm64 && \
        cp build/app/outputs/flutter-apk/app-$MODE.apk /build-output/stardial-$MODE.apk
    "

echo "[stardial] APK ready: $BUILD_DIR/stardial-$MODE.apk"
