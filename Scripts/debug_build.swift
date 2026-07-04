#!/usr/bin/env swift

// Debug script: show what ProcessScanner sees for build-related processes.

import Darwin
import Foundation

func getInfo(_ pid: pid_t) -> (pid: pid_t, ppid: pid_t, name: String, exec: String?, cwd: String?)? {
    var bsd = proc_bsdinfo()
    let s = Int32(MemoryLayout<proc_bsdinfo>.size)
    let r = withUnsafeMutablePointer(to: &bsd) { ptr in
        proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, ptr, s)
    }
    guard r == s else { return nil }

    let name = withUnsafeBytes(of: bsd.pbi_name) { buf in
        String(cString: buf.baseAddress!.assumingMemoryBound(to: CChar.self))
    }

    var pb = [CChar](repeating: 0, count: Int(MAXPATHLEN))
    let pl = proc_pidpath(pid, &pb, UInt32(MAXPATHLEN))
    let exec = pl > 0 ? String(decoding: pb.prefix(while: { $0 != 0 }).map { UInt8($0) }, as: UTF8.self) : nil

    var vn = proc_vnodepathinfo()
    let vs = Int32(MemoryLayout<proc_vnodepathinfo>.size)
    let vr = withUnsafeMutablePointer(to: &vn) { ptr in
        proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, ptr, vs)
    }
    var cwd: String? = nil
    if vr == vs {
        cwd = withUnsafeBytes(of: vn.pvi_cdir.vip_path) { buf in
            String(cString: buf.baseAddress!.assumingMemoryBound(to: CChar.self))
        }
    }

    return (pid, pid_t(bsd.pbi_ppid), name, exec, cwd)
}

// Get all PIDs
let count = proc_listallpids(nil, 0)
guard count > 0 else { print("No processes"); exit(0) }
var pids = [pid_t](repeating: 0, count: Int(count) + 20)
let bufSize = Int32(pids.count) * Int32(MemoryLayout<pid_t>.size)
let actual = pids.withUnsafeMutableBufferPointer { buf in
    proc_listallpids(buf.baseAddress, bufSize)
}
pids = Array(pids.prefix(Int(actual)))

// Find all build-related processes
print("=== All build-related processes ===")
print("PID\tPPID\tNAME\tEXEC\tCWD")
print(String(repeating: "-", count: 100))

for pid in pids {
    guard let p = getInfo(pid) else { continue }
    let interesting = ["make", "perl", "latexmk", "lualatex", "luahbtex"].contains(p.name)
    if interesting {
        let execShort = p.exec ?? "nil"
        print("\(p.pid)\t\(p.ppid)\t\(p.name)\t\(execShort)\t\(p.cwd ?? "nil")")
    }
}

// Build parent→child tree
print("\n=== Process tree for make processes ===")
var tree: [pid_t: [pid_t]] = [:]
var infoMap: [pid_t: (pid: pid_t, ppid: pid_t, name: String, exec: String?, cwd: String?)] = [:]
for pid in pids {
    if let p = getInfo(pid) {
        tree[p.ppid, default: []].append(p.pid)
        infoMap[pid] = p
    }
}

// Find root make processes
let makeProcs = infoMap.values.filter { $0.name == "make" || $0.name == "gmake" }
for m in makeProcs {
    // Check if parent is also make — skip sub-makes
    if let parent = infoMap[m.ppid], parent.name == "make" || parent.name == "gmake" {
        continue
    }
    print("\nRoot make PID \(m.pid) cwd=\(m.cwd ?? "nil")")
    func printDescendants(_ pid: pid_t, depth: Int) {
        for child in tree[pid] ?? [] {
            guard let info = infoMap[child] else { continue }
            let indent = String(repeating: "  ", count: depth)
            let execShort = info.exec.map { e in
                if e.count > 40 { return "..." + String(e.suffix(37)) }
                return e
            } ?? "nil"
            print("\(indent)└─ [\(info.pid)] \(info.name) exec=\(execShort) cwd=\(info.cwd ?? "nil")")
            printDescendants(child, depth: depth + 1)
        }
    }
    printDescendants(m.pid, depth: 1)
}
