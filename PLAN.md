# n-doc-monitor Development Plan

Build a macOS menu bar app in SwiftUI that monitors native n-doc builds by walking the process tree (make → latexmk → lualatex), identifying which documents are being typeset, and counting lualatex runs per document.

## Acceptance criteria

- Menu bar icon appears when the app is running.
- When no n-doc build is active: shows "idle" or similar.
- When an n-doc build is active: shows document names and run counts, e.g. "ADV_TDS: Run 2, ASE: Run 3".
- Auto-detects n-doc builds by checking whether a running `make` process's working directory contains `common/latexmkrc`.
- Polling-based (1–2 second interval), no excessive CPU usage.
- macOS 26 target. Pure SwiftUI, no AppKit unless unavoidable.
- No run-total estimation — just count completed/active runs.

## Constraints

- **No Docker support** — native processes only.
- **No wrapper scripts** — auto-detect n-doc builds from process tree.
- **No external dependencies** — pure Swift, standard macOS frameworks.
- **Standalone repo** at `/Users/akr/develop/n-doc-monitor-app`.

## Scope

- **In scope**: Xcode project, SwiftUI menu bar app, process monitoring, display logic.
- **Out of scope**: iOS/iPadOS, Docker monitoring, run-total prediction, notification system, logging to file.

---

## Development steps

Each step is incremental and introduces specific SwiftUI / macOS concepts.

### Step 1: Create the Xcode project skeleton ✅

**What we build**: A minimal SwiftUI app that shows an icon in the macOS menu bar. Clicking it opens a popover/panel with static placeholder text ("No build active").

**SwiftUI concepts introduced**:
- `@main` App struct and app lifecycle.
- `MenuBarExtra` — the SwiftUI view that lives in the menu bar.
- `Scene` protocol and how macOS menu bar apps differ from windowed apps (no `WindowGroup`, no Dock icon).

**Files created**:
- `Sources/NDocMonitor/NDocMonitorApp.swift` — app entry point with `MenuBarExtra`.
- `Sources/NDocMonitor/MonitorView.swift` — the panel that appears when clicking the menu bar icon.
- `Package.swift` — SPM package definition.

**Tests**: Smoke test in `NDocMonitorTests` target — verify the app struct exists and the content view renders without errors.

**Milestone**: App launches, shows a menu bar icon (e.g., `doc.text.magnifyingglass` SF Symbol), click opens a panel saying "No build active". Test target runs green.

---

### Step 2: Process scanner — enumerate running processes ✅

**What we build**: A Swift class `ProcessScanner` that uses macOS `libproc` C APIs to list running processes, get their names, PIDs, parent PIDs, and working directories.

**SwiftUI concepts introduced**:
- Bridging C APIs (`libproc.h`) into Swift using `Darwin` module imports.
- `ObservableObject` and `@Published` — preparing a model that the UI can observe.

**Key functions**:
- `listAllPIDs() -> [pid_t]`
- `getProcessInfo(pid:) -> ProcessInfo?` (name, pid, ppid, cwd)
- `buildProcessTree() -> [pid_t: [pid_t]]` (parent → children mapping)

**Milestone**: We can call `ProcessScanner` from a test/debug view and print all running processes with their parent-child relationships.

---

### Step 3: n-doc build detection ✅

**What we build**: Logic to find the root `make` process of an n-doc build. The scanner looks for `make` processes whose working directory contains `common/latexmkrc` (checked via `FileManager`).

**SwiftUI concepts introduced**:
- `Timer.publish` / `onReceive` — periodic polling from the UI.
- Connecting the `ProcessScanner` to the app's `@StateObject`.

**Key logic**:
- Every ~2 seconds, scan for `make` processes.
- For each, check if `<cwd>/common/latexmkrc` exists.
- If found, this is the n-doc root process. Store its PID.

**Milestone**: The menu bar panel shows "n-doc build detected (PID: XXXX)" when you run `make` in an n-doc repo, and "No build active" otherwise.

---

### Step 4: Walk the process tree — find latexmk and lualatex

**What we build**: From the root `make` PID, walk the child process tree to find:
1. **latexmk processes** — each represents one document being typeset.
2. **lualatex processes** — children of latexmk, represent individual typesetting runs.

For each latexmk process, derive the document name from its working directory (e.g., cwd ending in `/adv_tds` → "ADV_TDS").

**SwiftUI concepts introduced**:
- `@Observable` model class (or `ObservableObject`) with structured data.
- Data modelling with Swift structs for `DocumentBuild` (name, run count, status).

**Key data model**:
```swift
struct DocumentBuild: Identifiable {
    let id: pid_t          // latexmk PID
    let name: String       // e.g. "ADV_TDS"
    var runCount: Int      // number of lualatex invocations seen
    var isActive: Bool     // lualatex currently running?
}
```

**Milestone**: The app detects which documents are being built and shows their names.

---

### Step 5: Count lualatex runs per document

**What we build**: Track how many times lualatex has been spawned for each latexmk process. Since lualatex runs sequentially (one finishes before the next starts), we need to detect new lualatex PIDs appearing over successive polling cycles.

**Logic**:
- On each poll, for each latexmk PID, check for lualatex child processes.
- If a new lualatex PID appears (different from the last seen), increment the run counter.
- If no lualatex child is present, the document is between runs or finished.

**SwiftUI concepts introduced**:
- State diffing — comparing snapshots across polling cycles.
- `@State` vs `@StateObject` vs `@ObservedObject` — understanding ownership.

**Milestone**: Display updates live: "ADV_TDS: Run 1" → "ADV_TDS: Run 2" as lualatex invocations proceed.

---

### Step 6: Polish the UI

**What we build**: A clean, informative panel UI.

**UI elements**:
- Menu bar icon changes appearance when a build is active (e.g., filled vs outline symbol, or badge).
- Panel shows a list of documents with run counts.
- "Idle" state when no build is running.
- Timestamp of when the build started (optional).

**SwiftUI concepts introduced**:
- `List` / `ForEach` for dynamic content.
- Conditional views (`if`/`else` in view builders).
- SF Symbols and how to use them.
- `VStack`, `HStack`, `Spacer`, `.padding()`, `.font()` — layout basics.

**Milestone**: Visually polished menu bar app showing live build progress.

---

### Step 7: Handle edge cases and robustness

**What we build**: Handle real-world scenarios:

- **Parallel builds**: `make -j4` runs multiple latexmk processes simultaneously — ensure all are tracked.
- **Build finishes**: Detect when the root make process exits; reset state to idle.
- **Multiple n-doc repos**: If two builds run simultaneously (unlikely but possible), show both.
- **Process dies unexpectedly**: Clean up stale entries.
- **Permissions**: Handle cases where `libproc` can't read a process (different user).

**Milestone**: App handles all normal and edge-case build scenarios without crashes or stale data.

---

### Step 8: App lifecycle and distribution

**What we build**: Final touches for a proper macOS app.

- **Launch at login** (optional, user-configurable via `SMAppService`).
- **About panel** with version info.
- **Quit menu item**.
- **App icon**.
- **Code signing** for local development (no distribution outside App Store planned initially).

**SwiftUI concepts introduced**:
- `Settings` scene for preferences.
- `SMAppService` for login items.
- App sandboxing considerations (may need to be disabled for `libproc` access).

**Milestone**: Complete, distributable macOS menu bar app.

---

### Step 9: UI Improvements

**What we build**: Let the user tear the main panel off from the menu bar icon so that is a floating window.

**SwiftUI concepts introduced**:
- Tear off menu bar items to create floating windows.

**Milestone**: Visually polished menu bar app with better user experience.

---

### Step 10: Configure n-doc directories

**What we build**: Add a directory picker to the menu bar app in which the user can select their n-doc directories. This can be used to filter the processes to only show those that are running in the selected directories. We would not need the marker file approach anymore. The selected directories will be stored in `UserDefaults`.

**SwiftUI concepts introduced**:
- Final polish and testing.

**Milestone**: The app gains the ability to filter processes by directory. Preferences are saved between launches.

---

## Technical notes

### Process monitoring approach

macOS provides `libproc` via the `Darwin` module in Swift:
- `proc_listallpids()` — list all PIDs.
- `proc_pidinfo()` with `PROC_PIDTBSDINFO` — get process name, ppid.
- `proc_pidinfo()` with `PROC_PIDVNODEPATHINFO` — get working directory.
- `proc_pidpath()` — get executable path.

These work for processes owned by the same user without elevated privileges.

### Why not `NSWorkspace` / `NSRunningApplication`?

These only track GUI apps, not command-line tools like make/latexmk/lualatex. We need the lower-level `libproc` APIs.

### Sandboxing

A sandboxed app cannot use `libproc` to inspect other processes. The app will need to run **without App Sandbox** (or with a temporary entitlement). This is fine for a developer tool not distributed via the App Store.
