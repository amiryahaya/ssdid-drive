#!/bin/bash
#
# Build the macOS File Provider extension
#
# Usage:
#   ./scripts/build-extension.sh [debug|release]
#
# Environment variables:
#   CODE_SIGN_IDENTITY  - Code signing identity (for production builds)
#   DEVELOPMENT_TEAM    - Apple Developer Team ID
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
EXTENSION_DIR="${PROJECT_DIR}/macos-extension"

# Configuration
CONFIGURATION="${1:-Release}"
if [ "$CONFIGURATION" = "debug" ]; then
    CONFIGURATION="Debug"
elif [ "$CONFIGURATION" = "release" ]; then
    CONFIGURATION="Release"
fi

echo "Building File Provider extension (${CONFIGURATION})..."

# Check if we're on macOS
if [ "$(uname)" != "Darwin" ]; then
    echo "Error: File Provider extension can only be built on macOS"
    exit 1
fi

# Check if Xcode is installed
if ! command -v xcodebuild &> /dev/null; then
    echo "Error: Xcode command line tools not found"
    echo "Please install Xcode from the App Store"
    exit 1
fi

# Check if the extension project exists
if [ ! -d "${EXTENSION_DIR}" ]; then
    echo "Error: Extension directory not found at ${EXTENSION_DIR}"
    exit 1
fi

cd "${EXTENSION_DIR}"

# Create build directory
mkdir -p build

# Build arguments
BUILD_ARGS=(
    -configuration "${CONFIGURATION}"
    -derivedDataPath build/DerivedData
    -destination "generic/platform=macOS"
)

# Add code signing if identity is provided
if [ -n "$CODE_SIGN_IDENTITY" ]; then
    BUILD_ARGS+=(
        CODE_SIGN_IDENTITY="${CODE_SIGN_IDENTITY}"
    )
fi

if [ -n "$DEVELOPMENT_TEAM" ]; then
    BUILD_ARGS+=(
        DEVELOPMENT_TEAM="${DEVELOPMENT_TEAM}"
    )
fi

# Check if xcodeproj exists, if not create it
if [ ! -d "SecureSharingFileProvider.xcodeproj" ]; then
    echo "Creating Xcode project..."

    # Create a Package.swift for the extension
    cat > Package.swift << 'EOF'
// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SecureSharingFileProvider",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "SecureSharingFileProvider",
            targets: ["SecureSharingFileProvider"]
        ),
    ],
    targets: [
        .target(
            name: "SecureSharingFileProvider",
            path: "SecureSharingFileProvider"
        ),
    ]
)
EOF

    echo "Note: Xcode project needs to be created manually."
    echo "Please open Xcode and create a new File Provider extension target."
    echo ""
    echo "Steps:"
    echo "1. Open Xcode"
    echo "2. Create a new macOS App Extension project"
    echo "3. Select 'File Provider Extension' template"
    echo "4. Copy the Swift files from SecureSharingFileProvider/ into the project"
    echo "5. Configure entitlements and Info.plist"
    echo ""
    exit 0
fi

# Build the extension
echo "Building extension..."
xcodebuild \
    -project SecureSharingFileProvider.xcodeproj \
    -scheme SecureSharingFileProvider \
    "${BUILD_ARGS[@]}" \
    build

# Find the built appex
APPEX_PATH=$(find build/DerivedData -name "*.appex" -type d | head -1)

if [ -z "$APPEX_PATH" ]; then
    echo "Error: Built extension not found"
    exit 1
fi

# Copy to output directory
OUTPUT_DIR="${PROJECT_DIR}/macos-extension/build"
mkdir -p "${OUTPUT_DIR}"
cp -R "${APPEX_PATH}" "${OUTPUT_DIR}/"

APPEX_NAME=$(basename "${APPEX_PATH}")
echo ""
echo "Build complete!"
echo "Extension: ${OUTPUT_DIR}/${APPEX_NAME}"
echo ""
echo "To include in Tauri build, add this to tauri.conf.json:"
echo '  "bundle": {'
echo '    "macOS": {'
echo '      "resources": ["../macos-extension/build/'${APPEX_NAME}'"]'
echo '    }'
echo '  }'
