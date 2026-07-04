#!/usr/bin/env swift

// Standalone demo of ProcessScanner — run with:
//   swift Scripts/demo_scanner.swift
//
// Since this is a standalone script, we inline the minimal libproc
// calls rather than importing the module.

import Darwin

// --- Helpers (same logic as ProcessScanner) ---

struct ProcInfo {
    let pid: pid_t
    let ppid: pid_t
    let name: String
    let execPath: String?
    let cwd: String?
}

func getAllPIDs() -> [pid_t] {
    let count = proc_listallpids(nil, 0)
    guard count > 0 else { return [] }
    var pids = [pid_t](repeating: 0, count: Int(count) + 20)
    let bufSize = Int32(pids.count) * Int32(MemoryLayout<pid_t>.size)
    let actual = pids.withUnsafeMutableBufferPointer { buf in
        proc_listallpids(buf.baseAddress, bufSize)
    }
    guard actual > 0 else { return [] }
    return Array(pids.prefix(Int(actual)))
}

func getInfo(_ pid: pid_t) -> ProcInfo? {
    var bsd = proc_bsdinfo()
    let bsdSize = Int32(MemoryLayout<proc_bsdinfo>.size)
    let r = withUnsafeMutablePointer(to: &bsd) { ptr in
        proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, ptr, bsdSize)
    }
    guard r == bsdSize else { return nil }

    let name = withUnsafeBytes(of: bsd.pbi_name) { buf in
        guard let base = buf.baseAddress else { return "" }
        return String(cString: base.assumingMemoryBound(to: CChar.self))
    }

    var pathBuf = [CChar](repeating: 0, count: Int(MAXPATHLEN))
    let pathLen = proc_pidpath(pid, &pathBuf, UInt32(MAXPATHLEN))
    let execPath = pathLen > 0
        ? String(decoding: pathBuf.prefix(while: { $0 != 0 }).map { UInt8($0) }, as: UTF8.self)
        : nil

    var vnode = proc_vnodepathinfo()
    let vSize = Int32(MemoryLayout<proc_vnodepathinfo>.size)
    let vr = withUnsafeMutablePointer(to: &vnode) { ptr in
        proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, ptr, vSize)
    }
    var cwd: String? = nil
    if vr == vSize {
        cwd = withUnsafeBytes(of: vnode.pvi_cdir.vip_path) { buf in
            guard let base = buf.baseAddress else { return "" }
            return String(cString: base.assumingMemoryBound(to: CChar.self))
        }
        if cwd?.isEmpty == true { cwd = nil }
    }

    return ProcInfo(pid: pid, ppid: pid_t(bsd.pbi_ppid), name: name,
                    execPath: execPath, cwd: cwd)
}

// --- Demo output ---

let myPID = getpid()
print("╔══════════════════════════════════════════╗")
print("║       ProcessScanner Live Demo           ║")
print("╚══════════════════════════════════════════╝")

print("\n── Our own process ──")
if let me = getInfo(myPID) {
    print("  PID:   \(me.pid)")
    print("  PPID:  \(me.ppid)")
    print("  Name:  \(me.name)")
    print("  Exec:  \(me.execPath ?? "n/a")")
    print("  CWD:   \(me.cwd ?? "n/a")")
}

let allPIDs = getAllPIDs()
let allProcs = allPIDs.compactMap { getInfo($0) }

print("\n── Summary ──")
print("  Total visible processes: \(allProcs.count)")

// Group by name and show the most common ones
var nameCounts: [String: Int] = [:]
for p in allProcs { nameCounts[p.name, default: 0] += 1 }
let top10 = nameCounts.sorted { $0.value > $1.value }.prefix(10)
print("\n── Top 10 process names ──")
for (name, count) in top10 {
    print("  \(name): \(count)")
}

// Show any make or latexmk processes
let interesting = allProcs.filter { ["make", "latexmk", "lualatex", "perl"].contains($0.name) }
if interesting.isEmpty {
    print("\n── No make/latexmk/lualatex processes found (no build running) ──")
} else {
    print("\n── Build-related processes ──")
    for p in interesting {
        print("  [\(p.pid)] \(p.name)  cwd: \(p.cwd ?? "?")")
    }
}

// Show a small slice of the process tree from launchd
print("\n── Process tree from launchd (PID 1), depth 2 ──")
var tree: [pid_t: [pid_t]] = [:]
for p in allProcs { tree[p.ppid, default: []].append(p.pid) }

let topChildren = (tree[1] ?? []).prefix(10)
for child in topChildren {
    if let info = getInfo(child) {
        print("  └─ [\(info.pid)] \(info.name)")
        let grandchildren = (tree[child] ?? []).prefix(4)
        for gc in grandchildren {
            if let gcInfo = getInfo(gc) {
                print("      └─ [\(gcInfo.pid)] \(gcInfo.name)")
            }
        }
        if (tree[child] ?? []).count > 4 {
            print("      ... and \((tree[child] ?? []).count - 4) more")
        }
    }
}
if (tree[1] ?? []).count > 10 {
    print("  ... and \((tree[1] ?? []).count - 10) more top-level processes")
}
