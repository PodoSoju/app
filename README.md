# PodoSoju

A Wine-based Windows application launcher for macOS.

## Overview

PodoSoju is a native macOS application that enables running Windows applications and games on Apple Silicon Macs. Built with Swift and SwiftUI, it provides a modern and intuitive interface for managing Windows applications.

## Features

- **Workspace Management**: Organize Windows applications in isolated workspaces
- **Native macOS Experience**: Built with SwiftUI for seamless Mac integration
- **Apple Silicon Optimized**: Designed specifically for M-series processors
- **Powered by Soju**: Uses the Soju Wine distribution for Windows compatibility

## Architecture

- **PodoSoju**: Main application (macOS app)
- **PodoSojuKit**: Core framework providing Wine integration and workspace management
- **Soju**: Wine distribution (downloaded separately)

## Requirements

- macOS 14.0 (Sonoma) or later
- Apple Silicon (M1/M2/M3/M4)

## Installation

Download from [Releases](https://github.com/PodoSoju/app/releases)

## Development

### Building

```bash
# Sync Xcode project
python3 Scripts/sync-project.py

# Build
xcodebuild -scheme PodoSoju -configuration Debug build
```

Or open `PodoSoju.xcodeproj` in Xcode and build (Cmd+R).

### Project Structure

```
PodoSoju/           # macOS app source
PodoSojuKit/        # Core framework
Scripts/            # Build automation
```

## References

- [Soju](https://github.com/PodoSoju/soju) - Wine distribution for PodoSoju
- [Whisky](https://github.com/Whisky-App/Whisky) - Wine wrapper for macOS

## License

MIT
