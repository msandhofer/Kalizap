#!/bin/bash
set -euo pipefail

# Build whisper.cpp v1.8.4 static library with CoreML + Metal support
# Output: libwhisper.a (merged whisper + coreml bridge)

WHISPER_VERSION="v1.8.4"
BUILD_DIR="/tmp/whisper-build-$$"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
OUTPUT_DIR="$PROJECT_DIR/Sources/CWhisper/lib"

echo "=== Building whisper.cpp $WHISPER_VERSION with CoreML + Metal ==="
echo "Build dir: $BUILD_DIR"
echo "Output:    $OUTPUT_DIR/libwhisper.a"
echo ""

# 1. Clone
if [ -d "$BUILD_DIR" ]; then
    echo "Cleaning previous build..."
    rm -rf "$BUILD_DIR"
fi

echo "Cloning whisper.cpp $WHISPER_VERSION..."
git clone --branch "$WHISPER_VERSION" --depth 1 https://github.com/ggml-org/whisper.cpp.git "$BUILD_DIR"

# 2. Configure
echo ""
echo "Configuring cmake..."
cmake -B "$BUILD_DIR/build" -S "$BUILD_DIR" \
    -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=15.0 \
    -DWHISPER_COREML=ON \
    -DWHISPER_COREML_ALLOW_FALLBACK=ON \
    -DGGML_METAL=ON \
    -DGGML_METAL_EMBED_LIBRARY=ON \
    -DBUILD_SHARED_LIBS=OFF \
    -DCMAKE_BUILD_TYPE=Release

# 3. Build
echo ""
echo "Building..."
cmake --build "$BUILD_DIR/build" --config Release -j

# 4. Merge static libraries
echo ""
echo "Merging static libraries..."

# Collect all static libraries that need to be merged
LIBS_TO_MERGE=()
for lib in \
    "$BUILD_DIR/build/src/libwhisper.a" \
    "$BUILD_DIR/build/src/libwhisper.coreml.a" \
    "$BUILD_DIR/build/ggml/src/libggml.a" \
    "$BUILD_DIR/build/ggml/src/libggml-base.a" \
    "$BUILD_DIR/build/ggml/src/libggml-cpu.a" \
    "$BUILD_DIR/build/ggml/src/ggml-metal/libggml-metal.a" \
    "$BUILD_DIR/build/ggml/src/ggml-blas/libggml-blas.a"; do
    if [ -f "$lib" ]; then
        echo "  Found: $(basename "$lib") ($(du -h "$lib" | cut -f1))"
        LIBS_TO_MERGE+=("$lib")
    else
        echo "  Not found (skipping): $lib"
    fi
done

if [ ${#LIBS_TO_MERGE[@]} -lt 3 ]; then
    echo "ERROR: Too few libraries found. Expected at least whisper + coreml + ggml."
    exit 1
fi

MERGED_LIB="$BUILD_DIR/libwhisper-merged.a"
libtool -static -o "$MERGED_LIB" "${LIBS_TO_MERGE[@]}"

# 5. Verify CoreML symbols
echo ""
echo "Verifying CoreML symbols..."
if nm "$MERGED_LIB" | grep -q "whisper_coreml_init"; then
    echo "  CoreML symbols found."
else
    echo "  WARNING: No CoreML symbols found in merged library!"
fi

# 6. Copy to project
echo ""
echo "Copying to $OUTPUT_DIR..."
cp "$MERGED_LIB" "$OUTPUT_DIR/libwhisper.a"

# 7. Show size
SIZE=$(du -h "$OUTPUT_DIR/libwhisper.a" | cut -f1)
echo ""
echo "=== Done ==="
echo "  libwhisper.a size: $SIZE"
echo "  Location: $OUTPUT_DIR/libwhisper.a"

# 8. Cleanup
echo ""
echo "Cleaning up build directory..."
rm -rf "$BUILD_DIR"

echo "Build complete."
