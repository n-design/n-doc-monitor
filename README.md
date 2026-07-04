# n-doc monitor

A lightweight macOS menu bar app that monitors [n-doc](https://github.com/n-design/n-doc) LaTeX builds in real time.

![macOS](https://img.shields.io/badge/macOS-15%2B-blue)
![Swift](https://img.shields.io/badge/Swift-6.2-orange)
![License](https://img.shields.io/badge/License-MIT-green)

## What it does

When you run `make` in an n-doc repository, **n-doc monitor** automatically detects the build and shows:

- Which documents are currently being typeset
- How many `lualatex` runs have completed per document
- Elapsed build time
- A summary when the build finishes

The app lives entirely in the menu bar — no Dock icon, no main window. Click the menu bar icon to open a floating status panel that stays visible while you work.

## Features

- **Live build tracking** — detects `make` → `latexmk` → `lualatex` process trees
- **Floating panel** — stays on top, draggable, persists across focus changes
- **Configurable accent color** — pick your preferred highlight color in Settings
- **Launch at login** — optional, configurable in Settings
- **Parallel build support** — tracks multiple documents built simultaneously
- **Lightweight** — polls every 2 seconds using `libproc`, no daemons or file watchers

## Requirements

- macOS 15.0 or later
- n-doc builds running natively (not in Docker)

## Installation

### From DMG (to be done)

### Build from source

```bash
# Run directly
swift run

# Build a distributable .app bundle
./Scripts/build_app.sh

# Build .app + DMG for distribution
./Scripts/build_app.sh --dmg
```

The `.app` bundle and `.dmg` are created in the `build/` directory.

## Usage

1. Launch the app — a magnifying glass icon appears in the menu bar
2. Start a build in your n-doc repository (`make`, `make all`, etc.)
3. The icon changes to a hammer while the build is active
4. Click the icon to see build progress

### Toolbar buttons

| Icon | Action |
|------|--------|
| ↩ | Reset panel position (snap back under menu bar icon) |
| ℹ | About n-doc monitor |
| ⚙ | Settings (accent color, launch at login) |
| ✕ | Quit |

## How it works

n-doc monitor scans the process table every 2 seconds looking for `make` processes in directories containing a `common/latexmkrc` marker file (the n-doc convention). When it finds one, it walks the process tree to discover `latexmk` and `lualatex` child processes, grouping them by document name.

## Project structure

```
Sources/NDocMonitor/
├── NDocMonitorApp.swift       # App entry point, AppDelegate
├── MonitorView.swift          # Main status panel UI
├── DocumentBuildRow.swift     # Single document row in the panel
├── BuildMonitor.swift         # Polling loop and state management
├── BuildDetector.swift        # Process tree analysis
├── DocumentBuild.swift        # Document build model
├── CompletedBuild.swift       # Completed build summary model
├── ProcessScanner.swift       # libproc wrapper for process listing
├── ProcessInfo.swift          # Process metadata model
├── FloatingPanel.swift        # NSPanel subclass for floating window
├── StatusItemController.swift # NSStatusItem + panel management
├── SettingsView.swift         # Preferences window
└── AccentColor.swift          # Color persistence helpers

Scripts/
├── build_app.sh               # Build .app bundle and optional DMG
├── debug_build.swift          # Debug helper
└── demo_scanner.swift         # Process scanner demo

Resources/
└── Info.plist                 # App bundle metadata
```

## Tech stack

- **SwiftUI** — all views
- **AppKit** — `NSStatusItem`, `NSPanel`, window management
- **libproc** — native process scanning (no shell commands)
- **Swift Package Manager** — build system

## License

[MIT](LICENSE)
