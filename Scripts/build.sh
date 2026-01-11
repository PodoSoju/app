#!/bin/bash
#
# build.sh
# PodoSoju build script with versioning support
#
# Usage:
#   ./Scripts/build.sh                    # Release build
#   ./Scripts/build.sh --debug            # Debug build
#   ./Scripts/build.sh --patch            # Bump patch version, then build
#   ./Scripts/build.sh --minor            # Bump minor version, then build
#   ./Scripts/build.sh --major            # Bump major version, then build
#   ./Scripts/build.sh --clean            # Clean before build
#   ./Scripts/build.sh --show-version     # Show current version and exit
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
BUMP_SCRIPT="$SCRIPT_DIR/bump-version.sh"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Defaults
CONFIGURATION="Release"
CLEAN_BUILD=false
BUMP_TYPE=""

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --debug|-d)
            CONFIGURATION="Debug"
            shift
            ;;
        --release|-r)
            CONFIGURATION="Release"
            shift
            ;;
        --clean|-c)
            CLEAN_BUILD=true
            shift
            ;;
        --patch)
            BUMP_TYPE="patch"
            shift
            ;;
        --minor)
            BUMP_TYPE="minor"
            shift
            ;;
        --major)
            BUMP_TYPE="major"
            shift
            ;;
        --show-version|-v)
            "$BUMP_SCRIPT" --show
            exit 0
            ;;
        --help|-h)
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  --debug, -d        Debug build (default: Release)"
            echo "  --release, -r      Release build"
            echo "  --clean, -c        Clean before build"
            echo "  --patch            Bump patch version before build"
            echo "  --minor            Bump minor version before build"
            echo "  --major            Bump major version before build"
            echo "  --show-version, -v Show current version and exit"
            echo "  --help, -h         Show this help"
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            exit 1
            ;;
    esac
done

cd "$PROJECT_ROOT"

# Bump version if requested
if [ -n "$BUMP_TYPE" ]; then
    echo -e "${YELLOW}Bumping version ($BUMP_TYPE)...${NC}"
    "$BUMP_SCRIPT" "$BUMP_TYPE"
    echo ""
fi

# Show current version
VERSION=$("$BUMP_SCRIPT" --show 2>/dev/null | grep "PodoSoju:" | sed 's/.*PodoSoju:[[:space:]]*//' | cut -d' ' -f1)
echo -e "${BLUE}Building PodoSoju v$VERSION ($CONFIGURATION)${NC}"
echo ""

# Clean if requested
if [ "$CLEAN_BUILD" = true ]; then
    echo -e "${YELLOW}Cleaning...${NC}"
    xcodebuild clean \
        -project PodoSoju.xcodeproj \
        -scheme PodoSoju \
        -quiet
fi

# Build
echo -e "${YELLOW}Building...${NC}"
xcodebuild build \
    -project PodoSoju.xcodeproj \
    -scheme PodoSoju \
    -configuration "$CONFIGURATION" \
    -derivedDataPath build \
    -quiet

echo ""
echo -e "${GREEN}Build complete!${NC}"
echo -e "App location: ${BLUE}build/Build/Products/$CONFIGURATION/PodoSoju.app${NC}"
echo -e "Version: ${BLUE}$VERSION${NC}"
