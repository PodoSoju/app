#!/bin/bash
#
# bump-version.sh
# PodoSoju/PodoJuice version bump script
#
# Usage:
#   ./Scripts/bump-version.sh patch          # 1.0.0 -> 1.0.1
#   ./Scripts/bump-version.sh minor          # 1.0.0 -> 1.1.0
#   ./Scripts/bump-version.sh major          # 1.0.0 -> 2.0.0
#   ./Scripts/bump-version.sh podojuice patch  # PodoJuice patch
#   ./Scripts/bump-version.sh podojuice minor  # PodoJuice minor
#   ./Scripts/bump-version.sh podojuice major  # PodoJuice major
#   ./Scripts/bump-version.sh --show         # Show current versions
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
INFO_PLIST="$PROJECT_ROOT/PodoSoju/Info.plist"
PODOJUICE_VERSION="$PROJECT_ROOT/../PodoJuice/Sources/PodoJuice/Version.swift"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Get current PodoSoju version from Info.plist
get_podosoju_version() {
    /usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$INFO_PLIST"
}

# Get current build number
get_build_number() {
    /usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$INFO_PLIST"
}

# Get current PodoJuice version
get_podojuice_version() {
    if [ -f "$PODOJUICE_VERSION" ]; then
        major=$(grep "static let major" "$PODOJUICE_VERSION" | sed 's/.*= //' | tr -d ' ')
        minor=$(grep "static let minor" "$PODOJUICE_VERSION" | sed 's/.*= //' | tr -d ' ')
        patch=$(grep "static let patch" "$PODOJUICE_VERSION" | sed 's/.*= //' | tr -d ' ')
        echo "$major.$minor.$patch"
    else
        echo "0.0.0"
    fi
}

# Bump PodoSoju version
bump_podosoju_version() {
    local bump_type=$1
    local current=$(get_podosoju_version)

    # Parse version
    IFS='.' read -r major minor patch <<< "$current"

    case $bump_type in
        major)
            major=$((major + 1))
            minor=0
            patch=0
            ;;
        minor)
            minor=$((minor + 1))
            patch=0
            ;;
        patch)
            patch=$((patch + 1))
            ;;
        *)
            echo -e "${RED}Error: Unknown bump type: $bump_type${NC}"
            exit 1
            ;;
    esac

    local new_version="$major.$minor.$patch"

    # Update Info.plist
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $new_version" "$INFO_PLIST"

    # Increment build number
    local build=$(get_build_number)
    local new_build=$((build + 1))
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $new_build" "$INFO_PLIST"

    echo -e "${GREEN}PodoSoju: $current -> $new_version (build $new_build)${NC}"
}

# Bump PodoJuice version
bump_podojuice_version() {
    local bump_type=$1

    if [ ! -f "$PODOJUICE_VERSION" ]; then
        echo -e "${RED}Error: PodoJuice Version.swift not found${NC}"
        exit 1
    fi

    # Get current values
    local current_major=$(grep "static let major" "$PODOJUICE_VERSION" | sed 's/.*= //' | tr -d ' ')
    local current_minor=$(grep "static let minor" "$PODOJUICE_VERSION" | sed 's/.*= //' | tr -d ' ')
    local current_patch=$(grep "static let patch" "$PODOJUICE_VERSION" | sed 's/.*= //' | tr -d ' ')
    local current_build=$(grep "static let build" "$PODOJUICE_VERSION" | sed 's/.*= //' | tr -d ' ')
    local current="$current_major.$current_minor.$current_patch"

    local new_major=$current_major
    local new_minor=$current_minor
    local new_patch=$current_patch

    case $bump_type in
        major)
            new_major=$((current_major + 1))
            new_minor=0
            new_patch=0
            ;;
        minor)
            new_minor=$((current_minor + 1))
            new_patch=0
            ;;
        patch)
            new_patch=$((current_patch + 1))
            ;;
        *)
            echo -e "${RED}Error: Unknown bump type: $bump_type${NC}"
            exit 1
            ;;
    esac

    local new_build=$((current_build + 1))
    local new_version="$new_major.$new_minor.$new_patch"

    # Update Version.swift
    cat > "$PODOJUICE_VERSION" << EOF
import Foundation

struct PodoJuiceVersion {
    static let major = $new_major
    static let minor = $new_minor
    static let patch = $new_patch
    static let build = $new_build

    static var string: String {
        "\(major).\(minor).\(patch)"
    }

    static var full: String {
        "\(major).\(minor).\(patch) (build \(build))"
    }
}
EOF

    echo -e "${GREEN}PodoJuice: $current -> $new_version (build $new_build)${NC}"
}

# Show current versions
show_versions() {
    echo -e "${YELLOW}Current versions:${NC}"
    echo -e "  PodoSoju:   $(get_podosoju_version) (build $(get_build_number))"
    echo -e "  PodoJuice:  $(get_podojuice_version)"
}

# Main
case "${1:-}" in
    --show|-s)
        show_versions
        ;;
    podojuice)
        if [ -z "${2:-}" ]; then
            echo "Usage: $0 podojuice [patch|minor|major]"
            exit 1
        fi
        bump_podojuice_version "$2"
        ;;
    patch|minor|major)
        bump_podosoju_version "$1"
        ;;
    *)
        echo "Usage: $0 [patch|minor|major|podojuice [patch|minor|major]|--show]"
        echo ""
        echo "Commands:"
        echo "  patch              Bump PodoSoju patch version (1.0.0 -> 1.0.1)"
        echo "  minor              Bump PodoSoju minor version (1.0.0 -> 1.1.0)"
        echo "  major              Bump PodoSoju major version (1.0.0 -> 2.0.0)"
        echo "  podojuice patch    Bump PodoJuice patch version"
        echo "  podojuice minor    Bump PodoJuice minor version"
        echo "  podojuice major    Bump PodoJuice major version"
        echo "  --show, -s         Show current versions"
        exit 1
        ;;
esac
