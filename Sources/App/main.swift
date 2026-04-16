import Foundation
import Darwin

struct GitWingTUI {
    static func main() {
        var app = TUIApp()
        app.run()
    }
}

class TUIApp {
    private var running = true
    private var view: ViewType = .files
    private var selectedIndex = 0
    private var repoPath = ""
    private var staged: [String] = []
    private var unstaged: [String] = []
    private var commitMsg = ""
    private var output = ""
    private var cmdInput = ""
    private var status = "Welcome to GitWing"
    private var cmdPalette = false

    enum ViewType { case files, diff, commits, commands }

    func run() {
        setupTerminal()
        loadRepo()
        refresh()
        draw()

        while running {
            if let key = readKey() { handle(key) }
            draw()
        }
        restoreTerminal()
    }

    private func setupTerminal() {
        var t = termios()
        tcgetattr(STDIN_FILENO, &t)
        t.c_lflag &= ~(ICANON | ECHO)
        tcsetattr(STDIN_FILENO, TCSAFLUSH, &t)
    }

    private func restoreTerminal() {
        var t = termios()
        tcgetattr(STDIN_FILENO, &t)
        t.c_lflag |= ICANON | ECHO
        tcsetattr(STDIN_FILENO, TCSAFLUSH, &t)
    }

    private func loadRepo() {
        let paths = UserDefaults.standard.stringArray(forKey: "repositories") ?? []
        repoPath = paths.first ?? FileManager.default.currentDirectoryPath
    }

    private func refresh() {
        guard !repoPath.isEmpty else { return }
        staged = git(["diff", "--cached", "--name-only"])
        unstaged = git(["diff", "--name-only"])
    }

    private func git(_ args: [String]) -> [String] {
        let p = Process()
        let pipe = Pipe()
        p.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/git")
        p.arguments = args
        p.currentDirectoryURL = URL(fileURLWithPath: repoPath)
        p.standardOutput = pipe
        p.standardError = pipe

        do {
            try p.run()
            p.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)?
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map(String.init) ?? []
        } catch {
            return []
        }
    }

    private func readKey() -> Character? {
        var buf = [CChar](repeating: 0, count: 8)
        let n = read(STDIN_FILENO, &buf, 8)
        return n > 0 ? Character(UnicodeScalar(UInt8(buf[0]))) : nil
    }

    private func handle(_ key: Character) {
        switch key {
        case "q": running = false
        case "\t": cycleView()
        case "\r": execAction()
        case " ": toggleStage()
        case "j", "↓": moveDown()
        case "k", "↑": moveUp()
        case "g": selectedIndex = 0
        case "G": selectedIndex = maxItems - 1
        case "\u{1B}": if cmdPalette { cmdPalette = false }
        default: break
        }
    }

    private func cycleView() {
        switch view {
        case .files: view = .diff
        case .diff: view = .commits
        case .commits: view = .commands
        case .commands: view = .files
        }
        selectedIndex = 0
    }

    private var maxItems: Int {
        switch view {
        case .files: return max(staged.count, unstaged.count, 1)
        case .diff: return 20
        case .commits: return 15
        case .commands: return 12
        }
    }

    private func moveDown() { selectedIndex = min(selectedIndex + 1, maxItems - 1) }
    private func moveUp() { selectedIndex = max(selectedIndex - 1, 0) }

    private func toggleStage() {
        guard !unstaged.isEmpty else { return }
        let file = unstaged[selectedIndex]
        _ = git(["add", file])
        refresh()
        status = "Staged: \(file)"
    }

    private func execAction() {
        switch view {
        case .files:
            guard !staged.isEmpty else { return }
            _ = git(["commit", "-m", commitMsg])
            commitMsg = ""
            refresh()
            status = "Committed!"
        case .commands:
            runCmd()
        default: break
        }
    }

    private func runCmd() {
        let cmds: [(String, [String])] = [
            ("status", ["status"]),
            ("log -10", ["log", "--oneline", "-10"]),
            ("branch", ["branch", "-a"]),
            ("stash", ["stash", "list"]),
            ("fetch", ["fetch", "--all"]),
        ]
        guard selectedIndex < cmds.count else { return }
        output = git(cmds[selectedIndex].1).joined(separator: "\n")
        status = "Ran: git \(cmds[selectedIndex].0)"
    }

    private func draw() {
        clear()
        header()
        content()
        footer()
    }

    private func clear() { print("\u{001B}[2J\u{001B}[H", terminator: "") }

    private func header() {
        let w = width()
        let repo = URL(fileURLWithPath: repoPath).lastPathComponent
        let title = " 🦅 GitWing "
        print("\u{001B}[48;5;235m\(title)\u{001B}[0m", terminator: "")
        print(String(repeating: " ", count: w - title.count - repo.count - 3))
        print("\u{001B}[48;5;235m \(repo) \u{001B}[0m")
        print("")
    }

    private func content() {
        switch view {
        case .files: filesView()
        case .diff: diffView()
        case .commits: commitView()
        case .commands: commandsView()
        }
    }

    private func filesView() {
        let w = width() / 2 - 1

        print("┌" + String(repeating: "─", count: w) + "┬" + String(repeating: "─", count: w) + "┐")

        let s = " STAGED (\(staged.count)) "
        let u = " UNSTAGED (\(unstaged.count)) "
        print("│\u{001B}[32m\(s)\u{001B}[0m" + String(repeating: " ", count: w - s.count) + "│\u{001B}[33m\(u)\u{001B}[0m" + String(repeating: " ", count: w - u.count) + "│")
        print("├" + String(repeating: "─", count: w) + "┴" + String(repeating: "─", count: w) + "┤")

        for i in 0..<8 {
            let sf = i < staged.count ? staged[i] : ""
            let uf = i < unstaged.count ? unstaged[i] : ""
            let ps = i == selectedIndex ? "▸ " : "  "
            let pu = i == selectedIndex ? "▸ " : "  "

            if !sf.isEmpty {
                print("│\(ps)\u{001B}[32m\(sf.trunc(w-4))\u{001B}[0m")
            } else {
                print("│" + String(repeating: " ", count: w))
            }

            if view == .files && !uf.isEmpty {
                print("│\(pu)\u{001B}[33m\(uf.trunc(w-4))\u{001B}[0m")
            } else {
                print("│" + String(repeating: " ", count: w))
            }
        }

        let cw = width() - 2
        print("├" + String(repeating: "─", count: cw) + "┤")
        print("│ Commit: \(String(commitMsg.prefix(cw-10)).padding(cw-10))\u{001B}[0m│")
        print("└" + String(repeating: "─", count: cw) + "┘")
    }

    private func diffView() {
        let w = width() - 2
        print("┌" + String(repeating: "─", count: w) + "┐")
        print("│ DIFF VIEWER                              │")
        print("├" + String(repeating: "─", count: w) + "┤")

        let diff = git(["diff"])
        for line in diff.prefix(18) {
            var line = line.trunc(w - 2)
            if line.hasPrefix("+") { line = "\u{001B}[32m\(line)\u{001B}[0m" }
            else if line.hasPrefix("-") { line = "\u{001B}[31m\(line)\u{001B}[0m" }
            else if line.hasPrefix("@@") { line = "\u{001B}[36m\(line)\u{001B}[0m" }
            print("│ \(line)")
        }
        print("└" + String(repeating: "─", count: w) + "┘")
    }

    private func commitView() {
        let w = width() - 2
        print("┌" + String(repeating: "─", count: w) + "┐")
        print("│ CREATE COMMIT                           │")
        print("├" + String(repeating: "─", count: w) + "┤")
        print("│ \(staged.count) files staged")
        print("│")
        print("│ Commit message:")
        print("│ \(String(commitMsg.prefix(w-4)))")
        print("├" + String(repeating: "─", count: w) + "┤")
        let log = git(["log", "--oneline", "-5"])
        for line in log {
            print("│ \(line.trunc(w-2))")
        }
        print("└" + String(repeating: "─", count: w) + "┘")
    }

    private func commandsView() {
        let w = width() - 2
        let cmds: [(String, String)] = [
            ("status", "Show working tree status"),
            ("log -10", "Last 10 commits"),
            ("branch -a", "List all branches"),
            ("stash list", "List stashes"),
            ("fetch --all", "Fetch all remotes"),
            ("pull", "Pull current branch"),
            ("push", "Push current branch"),
            ("reflog", "Reference log"),
        ]

        print("┌" + String(repeating: "─", count: w) + "┐")
        print("│ QUICK COMMANDS                          │")
        print("├" + String(repeating: "─", count: w) + "┤")

        for (i, cmd) in cmds.enumerated() {
            let sel = i == selectedIndex
            let mark = sel ? "▸ " : "  "
            let col = sel ? "\u{001B}[33m" : ""
            let rst = "\u{001B}[0m"
            print("│\(col)\(mark)\(cmd.0)\(rst)".padding(w) + "│ " + cmd.1.trunc(w - 20))
        }
        print("└" + String(repeating: "─", count: w) + "┘")
    }

    private func footer() {
        let w = width()
        print("\u{001B}[48;5;236m \(status) ".padding(w-1) + "\u{001B}[0m")
        let hints = "[Tab] View  [Space] Stage  [Enter] Commit  [q] Quit"
        print(" \(hints)")
    }

    private func width() -> Int {
        var ws = winsize()
        _ = ioctl(STDOUT_FILENO, TIOCGWINSZ, &ws)
        return max(Int(ws.ws_col), 60)
    }

    private var maxItems: Int {
        switch view {
        case .files: return max(staged.count, unstaged.count, 8)
        case .diff: return 20
        case .commits: return 15
        case .commands: return 8
        }
    }
}

extension String {
    func trunc(_ n: Int) -> String {
        count <= n ? self : String(prefix(n - 2)) + " "
    }
    func padding(_ n: Int) -> String {
        count >= n ? String(prefix(n)) : self + String(repeating: " ", count: n - count)
    }
}

GitWingTUI.main()