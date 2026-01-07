#!/bin/bash
#
# build.sh
# Build script for Soju
#

set -e

echo "Building Soju..."

# Clean build folder
xcodebuild clean -project Soju.xcodeproj -scheme Soju

# Build the project
xcodebuild build \
    -project Soju.xcodeproj \
    -scheme Soju \
    -configuration Release \
    -derivedDataPath build

echo "Build complete!"
echo "App location: build/Build/Products/Release/Soju.app"
