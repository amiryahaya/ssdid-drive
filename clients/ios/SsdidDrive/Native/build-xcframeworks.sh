#!/bin/bash
#
# Build ML-KEM and ML-DSA xcframeworks for iOS using liboqs
#
# Prerequisites:
# - Xcode with command line tools
# - CMake (brew install cmake)
# - Ninja (brew install ninja) - optional but faster
#
# Usage: ./build-xcframeworks.sh
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/build"
LIBOQS_VERSION="0.10.1"
LIBOQS_DIR="$BUILD_DIR/liboqs"

# Output directories
MLKEM_FRAMEWORK_DIR="$SCRIPT_DIR/../Frameworks/MlKemNative.xcframework"
MLDSA_FRAMEWORK_DIR="$SCRIPT_DIR/../Frameworks/MlDsaNative.xcframework"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# ============================================================================
# Download and build liboqs
# ============================================================================

download_liboqs() {
    log_info "Downloading liboqs v${LIBOQS_VERSION}..."

    mkdir -p "$BUILD_DIR"
    cd "$BUILD_DIR"

    if [ -d "$LIBOQS_DIR" ]; then
        log_info "liboqs already downloaded"
        return
    fi

    git clone --depth 1 --branch ${LIBOQS_VERSION} https://github.com/open-quantum-safe/liboqs.git
    log_info "liboqs downloaded successfully"
}

# Build liboqs for a specific platform
build_liboqs_for_platform() {
    local PLATFORM=$1      # e.g., "iphoneos", "iphonesimulator", "macosx"
    local ARCH=$2          # e.g., "arm64", "x86_64"
    local SDK=$3           # SDK name
    local MIN_VERSION=$4   # Minimum deployment version
    local BUILD_NAME="${PLATFORM}-${ARCH}"
    local BUILD_PATH="$BUILD_DIR/liboqs-build-${BUILD_NAME}"
    local INSTALL_PATH="$BUILD_DIR/liboqs-install-${BUILD_NAME}"

    log_info "Building liboqs for ${BUILD_NAME}..."

    if [ -d "$INSTALL_PATH" ] && [ -f "$INSTALL_PATH/lib/liboqs.a" ]; then
        log_info "liboqs for ${BUILD_NAME} already built"
        return
    fi

    rm -rf "$BUILD_PATH" "$INSTALL_PATH"
    mkdir -p "$BUILD_PATH" "$INSTALL_PATH"

    cd "$BUILD_PATH"

    # Get SDK path
    local SDK_PATH=$(xcrun --sdk $SDK --show-sdk-path)

    # Set deployment target based on platform
    local DEPLOYMENT_FLAG=""
    case $PLATFORM in
        iphoneos)
            DEPLOYMENT_FLAG="-mios-version-min=${MIN_VERSION}"
            ;;
        iphonesimulator)
            DEPLOYMENT_FLAG="-mios-simulator-version-min=${MIN_VERSION}"
            ;;
        macosx)
            DEPLOYMENT_FLAG="-mmacosx-version-min=${MIN_VERSION}"
            ;;
        maccatalyst)
            DEPLOYMENT_FLAG="-target ${ARCH}-apple-ios${MIN_VERSION}-macabi"
            ;;
    esac

    # Configure with CMake
    cmake "$LIBOQS_DIR" \
        -DCMAKE_INSTALL_PREFIX="$INSTALL_PATH" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_OSX_SYSROOT="$SDK_PATH" \
        -DCMAKE_OSX_ARCHITECTURES="$ARCH" \
        -DCMAKE_C_FLAGS="${DEPLOYMENT_FLAG}" \
        -DBUILD_SHARED_LIBS=OFF \
        -DOQS_BUILD_ONLY_LIB=ON \
        -DOQS_USE_OPENSSL=OFF \
        -DOQS_MINIMAL_BUILD="KEM_ml_kem_768;SIG_ml_dsa_65" \
        -DOQS_DIST_BUILD=OFF \
        -DOQS_ENABLE_KEM_ml_kem_768=ON \
        -DOQS_ENABLE_SIG_ml_dsa_65=ON

    # Build and install
    cmake --build . --parallel
    cmake --install .

    log_info "liboqs for ${BUILD_NAME} built successfully"
}

# ============================================================================
# Build wrapper libraries
# ============================================================================

build_wrapper_library() {
    local LIB_NAME=$1         # MlKemNative or MlDsaNative
    local SOURCE_DIR=$2       # Path to source files
    local PLATFORM=$3
    local ARCH=$4
    local SDK=$5
    local MIN_VERSION=$6
    local BUILD_NAME="${PLATFORM}-${ARCH}"
    local LIBOQS_INSTALL="$BUILD_DIR/liboqs-install-${BUILD_NAME}"
    local OUTPUT_DIR="$BUILD_DIR/${LIB_NAME}-${BUILD_NAME}"

    log_info "Building ${LIB_NAME} for ${BUILD_NAME}..."

    rm -rf "$OUTPUT_DIR"
    mkdir -p "$OUTPUT_DIR"

    local SDK_PATH=$(xcrun --sdk $SDK --show-sdk-path)
    local CC=$(xcrun --sdk $SDK --find clang)

    # Set deployment target flags
    local DEPLOYMENT_FLAG=""
    case $PLATFORM in
        iphoneos)
            DEPLOYMENT_FLAG="-mios-version-min=${MIN_VERSION}"
            ;;
        iphonesimulator)
            DEPLOYMENT_FLAG="-mios-simulator-version-min=${MIN_VERSION}"
            ;;
        macosx)
            DEPLOYMENT_FLAG="-mmacosx-version-min=${MIN_VERSION}"
            ;;
        maccatalyst)
            DEPLOYMENT_FLAG="-target ${ARCH}-apple-ios${MIN_VERSION}-macabi"
            ;;
    esac

    # Compile the wrapper
    local SRC_FILE=""
    if [ "$LIB_NAME" = "MlKemNative" ]; then
        SRC_FILE="$SOURCE_DIR/src/mlkem.c"
    else
        SRC_FILE="$SOURCE_DIR/src/mldsa.c"
    fi

    $CC -c "$SRC_FILE" \
        -o "$OUTPUT_DIR/wrapper.o" \
        -arch $ARCH \
        -isysroot "$SDK_PATH" \
        $DEPLOYMENT_FLAG \
        -I"$SOURCE_DIR/include" \
        -I"$LIBOQS_INSTALL/include" \
        -DUSE_LIBOQS \
        -O2 \
        -fPIC

    # Create static library with liboqs
    libtool -static -o "$OUTPUT_DIR/lib${LIB_NAME}.a" \
        "$OUTPUT_DIR/wrapper.o" \
        "$LIBOQS_INSTALL/lib/liboqs.a"

    log_info "${LIB_NAME} for ${BUILD_NAME} built successfully"
}

# ============================================================================
# Create xcframework
# ============================================================================

create_xcframework() {
    local LIB_NAME=$1
    local SOURCE_DIR=$2
    local OUTPUT_FRAMEWORK=$3

    log_info "Creating ${LIB_NAME}.xcframework..."

    rm -rf "$OUTPUT_FRAMEWORK"

    # Prepare header directory
    local HEADER_DIR="$BUILD_DIR/${LIB_NAME}-headers"
    rm -rf "$HEADER_DIR"
    mkdir -p "$HEADER_DIR"
    cp "$SOURCE_DIR/include/"*.h "$HEADER_DIR/"
    cp "$SOURCE_DIR/include/module.modulemap" "$HEADER_DIR/"

    # Build xcframework command
    local XCFRAMEWORK_ARGS=()

    # iOS device (arm64)
    if [ -d "$BUILD_DIR/${LIB_NAME}-iphoneos-arm64" ]; then
        XCFRAMEWORK_ARGS+=(-library "$BUILD_DIR/${LIB_NAME}-iphoneos-arm64/lib${LIB_NAME}.a" -headers "$HEADER_DIR")
    fi

    # iOS Simulator (arm64 + x86_64)
    local SIM_ARM64="$BUILD_DIR/${LIB_NAME}-iphonesimulator-arm64"
    local SIM_X64="$BUILD_DIR/${LIB_NAME}-iphonesimulator-x86_64"
    if [ -d "$SIM_ARM64" ] && [ -d "$SIM_X64" ]; then
        # Create fat library for simulator
        local SIM_FAT="$BUILD_DIR/${LIB_NAME}-iphonesimulator-fat"
        rm -rf "$SIM_FAT"
        mkdir -p "$SIM_FAT"
        lipo -create \
            "$SIM_ARM64/lib${LIB_NAME}.a" \
            "$SIM_X64/lib${LIB_NAME}.a" \
            -output "$SIM_FAT/lib${LIB_NAME}.a"
        XCFRAMEWORK_ARGS+=(-library "$SIM_FAT/lib${LIB_NAME}.a" -headers "$HEADER_DIR")
    fi

    # macOS (arm64 + x86_64)
    local MAC_ARM64="$BUILD_DIR/${LIB_NAME}-macosx-arm64"
    local MAC_X64="$BUILD_DIR/${LIB_NAME}-macosx-x86_64"
    if [ -d "$MAC_ARM64" ] && [ -d "$MAC_X64" ]; then
        # Create fat library for macOS
        local MAC_FAT="$BUILD_DIR/${LIB_NAME}-macosx-fat"
        rm -rf "$MAC_FAT"
        mkdir -p "$MAC_FAT"
        lipo -create \
            "$MAC_ARM64/lib${LIB_NAME}.a" \
            "$MAC_X64/lib${LIB_NAME}.a" \
            -output "$MAC_FAT/lib${LIB_NAME}.a"
        XCFRAMEWORK_ARGS+=(-library "$MAC_FAT/lib${LIB_NAME}.a" -headers "$HEADER_DIR")
    fi

    # Mac Catalyst (arm64 + x86_64)
    local CAT_ARM64="$BUILD_DIR/${LIB_NAME}-maccatalyst-arm64"
    local CAT_X64="$BUILD_DIR/${LIB_NAME}-maccatalyst-x86_64"
    if [ -d "$CAT_ARM64" ] && [ -d "$CAT_X64" ]; then
        # Create fat library for Mac Catalyst
        local CAT_FAT="$BUILD_DIR/${LIB_NAME}-maccatalyst-fat"
        rm -rf "$CAT_FAT"
        mkdir -p "$CAT_FAT"
        lipo -create \
            "$CAT_ARM64/lib${LIB_NAME}.a" \
            "$CAT_X64/lib${LIB_NAME}.a" \
            -output "$CAT_FAT/lib${LIB_NAME}.a"
        XCFRAMEWORK_ARGS+=(-library "$CAT_FAT/lib${LIB_NAME}.a" -headers "$HEADER_DIR")
    fi

    # Create the xcframework
    xcodebuild -create-xcframework \
        "${XCFRAMEWORK_ARGS[@]}" \
        -output "$OUTPUT_FRAMEWORK"

    log_info "${LIB_NAME}.xcframework created successfully"
}

# ============================================================================
# Main build process
# ============================================================================

main() {
    log_info "=== Building ML-KEM and ML-DSA xcframeworks ==="
    log_info "Script directory: $SCRIPT_DIR"

    # Check prerequisites
    command -v cmake >/dev/null 2>&1 || log_error "cmake is required. Install with: brew install cmake"
    command -v xcodebuild >/dev/null 2>&1 || log_error "Xcode command line tools required"

    # Download liboqs
    download_liboqs

    # Build liboqs for all platforms
    log_info "=== Building liboqs for all platforms ==="

    # iOS device
    build_liboqs_for_platform "iphoneos" "arm64" "iphoneos" "15.0"

    # iOS Simulator
    build_liboqs_for_platform "iphonesimulator" "arm64" "iphonesimulator" "15.0"
    build_liboqs_for_platform "iphonesimulator" "x86_64" "iphonesimulator" "15.0"

    # macOS
    build_liboqs_for_platform "macosx" "arm64" "macosx" "12.0"
    build_liboqs_for_platform "macosx" "x86_64" "macosx" "12.0"

    # Mac Catalyst
    build_liboqs_for_platform "maccatalyst" "arm64" "macosx" "15.0"
    build_liboqs_for_platform "maccatalyst" "x86_64" "macosx" "15.0"

    # Build wrapper libraries
    log_info "=== Building wrapper libraries ==="

    MLKEM_SOURCE="$SCRIPT_DIR/MlKemNative"
    MLDSA_SOURCE="$SCRIPT_DIR/MlDsaNative"

    # ML-KEM
    build_wrapper_library "MlKemNative" "$MLKEM_SOURCE" "iphoneos" "arm64" "iphoneos" "15.0"
    build_wrapper_library "MlKemNative" "$MLKEM_SOURCE" "iphonesimulator" "arm64" "iphonesimulator" "15.0"
    build_wrapper_library "MlKemNative" "$MLKEM_SOURCE" "iphonesimulator" "x86_64" "iphonesimulator" "15.0"
    build_wrapper_library "MlKemNative" "$MLKEM_SOURCE" "macosx" "arm64" "macosx" "12.0"
    build_wrapper_library "MlKemNative" "$MLKEM_SOURCE" "macosx" "x86_64" "macosx" "12.0"
    build_wrapper_library "MlKemNative" "$MLKEM_SOURCE" "maccatalyst" "arm64" "macosx" "15.0"
    build_wrapper_library "MlKemNative" "$MLKEM_SOURCE" "maccatalyst" "x86_64" "macosx" "15.0"

    # ML-DSA
    build_wrapper_library "MlDsaNative" "$MLDSA_SOURCE" "iphoneos" "arm64" "iphoneos" "15.0"
    build_wrapper_library "MlDsaNative" "$MLDSA_SOURCE" "iphonesimulator" "arm64" "iphonesimulator" "15.0"
    build_wrapper_library "MlDsaNative" "$MLDSA_SOURCE" "iphonesimulator" "x86_64" "iphonesimulator" "15.0"
    build_wrapper_library "MlDsaNative" "$MLDSA_SOURCE" "macosx" "arm64" "macosx" "12.0"
    build_wrapper_library "MlDsaNative" "$MLDSA_SOURCE" "macosx" "x86_64" "macosx" "12.0"
    build_wrapper_library "MlDsaNative" "$MLDSA_SOURCE" "maccatalyst" "arm64" "macosx" "15.0"
    build_wrapper_library "MlDsaNative" "$MLDSA_SOURCE" "maccatalyst" "x86_64" "macosx" "15.0"

    # Create xcframeworks
    log_info "=== Creating xcframeworks ==="

    create_xcframework "MlKemNative" "$MLKEM_SOURCE" "$MLKEM_FRAMEWORK_DIR"
    create_xcframework "MlDsaNative" "$MLDSA_SOURCE" "$MLDSA_FRAMEWORK_DIR"

    log_info "=== Build complete! ==="
    log_info "Frameworks created at:"
    log_info "  - $MLKEM_FRAMEWORK_DIR"
    log_info "  - $MLDSA_FRAMEWORK_DIR"
}

main "$@"
