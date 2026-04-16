#!/usr/bin/env swift

import Foundation
import Darwin

if CommandLine.arguments.contains("--demo") {
    print("""
    \u{001B}[48;5;235m                                  \u{001B}[0m
    \u{001B}[48;5;235m  🦅 GitWing TUI  \u{001B}[0m  native git for terminal
    \u{001B}[48;5;235m                                  \u{001B}[0m
    ┌────────────────────────────────────────────────────────────────────────┐
    │  STAGED (3)                       UNSTAGED (2)             │
    ├────────────────────────────────┴───────────────────────────┤
    │▸ src/main.swift                     README.md               │
    │  src/App.swift                     LICENSE                 │
    │  Package.swift                                            │
    └────────────────────────────────────────────────────────────┘

    [Tab] Switch [Space] Stage [Enter] Commit [q] Quit
    """)
    exit(0)
}

var app = App()
app.run()

class App {
    private var running = true
    private var view: View = .files
    private var idx = 0
    private var repo = ""
    private var staged: [String] = []
    private var unstaged: [String] = []
    private var msg = ""
    private var status = "Welcome to GitWing"

    enum View { case files, diff, commits, commands }

    func run() {
        setup()
        repo = findGitRepo()
        if !repo.isEmpty { refresh() }
        draw()
        inputLoop()
    }

    private func findGitRepo() -> String {
        let paths = UserDefaults.standard.stringArray(forKey: "repositories") ?? []
        if let p = paths.first, isGit(p) { return p }
        var path = FileManager.default.currentDirectoryPath
        while !isGit(path) {
            if let parent = (path as NSString).deletingLastPathComponent as String? {
                if parent == path { break }
                path = parent
            } else { break }
        }
        return path
    }

    private func isGit(_ p: String) -> Bool {
        FileManager.default.fileExists(atPath: (p as NSString).appendingPathComponent(".git"))
    }

    private func setup() {
        var t = termios()
        tcgetattr(0, &t)
        t.c_lflag = t.c_lflag & ~UInt(ICANON) & ~UInt(ECHO)
        tcsetattr(0, TCSAFLUSH, &t)
    }

    private func refresh() {
        guard isGit(repo) else { return }
        staged = git(["diff", "--cached", "--name-only"])
        unstaged = git(["diff", "--name-only"])
    }

    private func git(_ a: [String]) -> [String] {
        let p = Process()
        let pipe = Pipe()
        p.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/git")
        p.arguments = a
        p.currentDirectoryURL = URL(fileURLWithPath: repo)
        p.standardOutput = pipe
        p.standardError = pipe
        try? p.run()
        p.waitUntilExit()
        let d = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: d, encoding: .utf8)?.split(separator: "\n").map(String.init) ?? []
    }

    private func inputLoop() {
        while running {
            if let key = readKey() {
                handle(key)
                if running { draw() }
            }
        }
    }

    private func readKey() -> Character? {
        var b = [CChar](repeating: 0, count: 8)
        let n = read(0, &b, 8)
        return n > 0 ? Character(UnicodeScalar(UInt8(b[0]))) : nil
    }

    private func handle(_ k: Character) {
        switch k {
        case "q": running = false
        case "\t": cycle()
        case "\r": doAction()
        case " ": stage()
        case "j": idx = min(idx + 1, maxItems - 1)
        case "k": idx = max(idx - 1, 0)
        case "g": idx = 0
        case "G": idx = maxItems - 1
        default: break
        }
    }

    private func doAction() {
        if view == .files && !staged.isEmpty {
            _ = git(["commit", "-m", msg])
            msg = ""
            refresh()
            status = "Committed!"
        }
    }

    private func stage() {
        guard !unstaged.isEmpty else { return }
        _ = git(["add", unstaged[idx]])
        refresh()
        status = "Staged"
    }

    private func cycle() {
        switch view {
        case .files: view = .diff
        case .diff: view = .commits
        case .commits: view = .commands
        case .commands: view = .files
        }
        idx = 0
    }

    private var maxItems: Int { max(staged.count, unstaged.count, 8) }

    private func draw() {
        print("\u{001B}[2J\u{001B}[H", terminator: "")
        header()
        switch view {
        case .files: files()
        case .diff: diffs()
        case .commits: commits()
        case .commands: commands()
        }
        footer()
    }

    private func header() {
        let w = tw()
        let name = URL(fileURLWithPath: repo).lastPathComponent
        print("\u{001B}[48;5;235m 🦅 GitWing \u{001B}[0m" + s(w-14-name.count) + "\u{001B}[48;5;235m \(name) \u{001B}[0m\n")
    }

    private func files() {
        let w = tw()/2-1
        print("┌"+d(w)+"┬"+d(w)+"┐")
        print("│\u{001B}[32m STAGED (\(staged.count)) \u{001B}[0m"+s(w-15)+"│\u{001B}[33m UNSTAGED (\(unstaged.count)) \u{001B}[0m"+s(w-16)+"│")
        print("├"+d(w)+"┴"+d(w)+"┤")
        for i in 0..<6 {
            let sf = i < staged.count ? staged[i] : ""
            let uf = i < unstaged.count ? unstaged[i] : ""
            let sel = idx == i
            let ps = sel ? "▸ " : "  "
            let pu = sel ? "▸ " : "  "
            print("│\(ps)\u{001B}[32m\(sf.t(w-4))\u{001B}[0m"+s(max(0,w-sf.t(w-4).count-ps.count-2))+"│\(pu)\u{001B}[33m\(uf.t(w-4))\u{001B}[0m"+s(max(0,w-uf.t(w-4).count-pu.count-2))+"│")
        }
        let cw = tw()-2
        print("├"+d(cw)+"┤")
        print("│ Commit: \(msg.t(cw-10))\u{001B}[0m│")
        print("└"+d(cw)+"┘")
    }

    private func diffs() {
        let w = tw()-2
        print("┌"+d(w)+"┐")
        print("│ DIFF VIEWER                                                │")
        print("├"+d(w)+"┤")
        let diff = git(["diff"])
        for l in diff.prefix(16) {
            var ln = l.t(w-2)
            if ln.hasPrefix("+") { ln = "\u{001B}[32m\(ln)\u{001B}[0m" }
            else if ln.hasPrefix("-") { ln = "\u{001B}[31m\(ln)\u{001B}[0m" }
            else if ln.hasPrefix("@@") { ln = "\u{001B}[36m\(ln)\u{001B}[0m" }
            print("│ \(ln)")
        }
        print("└"+d(w)+"┘")
    }

    private func commits() {
        let w = tw()-2
        print("┌"+d(w)+"┐")
        print("│ CREATE COMMIT                                             │")
        print("├"+d(w)+"┤")
        print("│ \(staged.count) files staged")
        print("│ Message: \(msg.t(w-12))")
        print("├"+d(w)+"┤")
        let log = git(["log", "--oneline", "-5"])
        for l in log { print("│ \(l.t(w-2))") }
        print("└"+d(w)+"┘")
    }

    private func commands() {
        let w = tw()-2
        let cmds = [("status","Show status"),("log -10","Last 10"),("branch -a","Branches"),("stash list","Stashes"),("fetch --all","Fetch all"),("pull","Pull"),("push","Push"),("reflog","Ref log")]
        print("┌"+d(w)+"┐")
        print("│ QUICK COMMANDS                                            │")
        print("├"+d(w)+"┤")
        for (i,c) in cmds.enumerated() {
            let sel = i == idx
            let m = sel ? "▸ " : "  "
            let col = sel ? "\u{001B}[33m" : ""
            let r = "\u{001B}[0m"
            print("│\(col)\(m)\(c.0)\(r)"+c.0.p(w)+"│ "+c.1.t(w-18))
        }
        print("└"+d(w)+"┘")
    }

    private func footer() {
        let w = tw()
        print("\u{001B}[48;5;236m \(status) ".p(w)+"\u{001B}[0m")
        print(" [Tab] View  [Space] Stage  [Enter] Commit  [q] Quit")
    }

    private func tw() -> Int {
        var ws = winsize()
        _ = ioctl(STDOUT_FILENO, TIOCGWINSZ, &ws)
        return max(Int(ws.ws_col), 60)
    }

    private func s(_ n: Int) -> String { n > 0 ? String(repeating: " ", count: n) : "" }
    private func d(_ n: Int) -> String { String(repeating: "─", count: n) }
}

extension String {
    func t(_ n: Int) -> String { count <= n ? self : String(prefix(n-2)) + " " }
    func p(_ n: Int) -> String { count >= n ? String(prefix(n)) : self + s(n-count) }
    private func s(_ n: Int) -> String { n > 0 ? String(repeating: " ", count: n) : "" }
}