import Darwin
import MuxySessionProtocol

struct SessionProcess {
    let masterDescriptor: Int32
    let processID: pid_t
    let ttyDevice: UInt64
}

enum SessionPTY {
    private static let resetSignals: [Int32] = [SIGPIPE, SIGCHLD, SIGHUP, SIGINT, SIGQUIT, SIGTERM, SIGTSTP, SIGTTIN, SIGTTOU]

    static func spawn(
        invocation: SessionShellInvocation,
        workingDirectory: String,
        columns: UInt16,
        rows: UInt16
    ) -> SessionProcess? {
        let argumentList = SessionCStringArray(invocation.arguments)
        let environmentList = SessionCStringArray(invocation.environment.map { "\($0.key)=\($0.value)" })
        guard let executable = strdup(invocation.executable) else { return nil }
        let directory = strdup(workingDirectory)
        defer {
            free(executable)
            free(directory)
        }

        var size = winsize(
            ws_row: rows == 0 ? 24 : rows,
            ws_col: columns == 0 ? 80 : columns,
            ws_xpixel: 0,
            ws_ypixel: 0
        )
        var master: Int32 = -1
        var name = [CChar](repeating: 0, count: Int(PATH_MAX))

        let processID = forkpty(&master, &name, nil, &size)
        if processID < 0 {
            SessionLog.write("forkpty failed: \(String(cString: strerror(errno)))")
            return nil
        }

        if processID == 0 {
            var empty = sigset_t()
            sigemptyset(&empty)
            sigprocmask(SIG_SETMASK, &empty, nil)
            for number in resetSignals {
                signal(number, SIG_DFL)
            }
            if let directory, chdir(directory) != 0 {
                if let home = getenv("HOME") {
                    _ = chdir(home)
                } else {
                    _ = chdir("/")
                }
            }
            execve(executable, argumentList.pointer, environmentList.pointer)
            _exit(127)
        }

        SessionIO.setNonBlocking(master)
        SessionIO.setCloseOnExec(master)

        var status = stat()
        let device: UInt64 = stat(&name, &status) == 0
            ? UInt64(UInt32(bitPattern: status.st_rdev))
            : 0

        return SessionProcess(masterDescriptor: master, processID: processID, ttyDevice: device)
    }

    static func resize(masterDescriptor: Int32, columns: UInt16, rows: UInt16) {
        var size = winsize(
            ws_row: rows == 0 ? 24 : rows,
            ws_col: columns == 0 ? 80 : columns,
            ws_xpixel: 0,
            ws_ypixel: 0
        )
        _ = ioctl(masterDescriptor, TIOCSWINSZ, &size)
    }

    static func windowSize(descriptor: Int32) -> (columns: UInt16, rows: UInt16)? {
        var size = winsize()
        guard ioctl(descriptor, TIOCGWINSZ, &size) == 0 else { return nil }
        return (size.ws_col, size.ws_row)
    }

    static func foregroundProcessGroup(masterDescriptor: Int32) -> pid_t? {
        let group = tcgetpgrp(masterDescriptor)
        return group > 0 ? group : nil
    }

    static func requestRedraw(masterDescriptor: Int32, fallbackProcessID: pid_t) {
        let group = foregroundProcessGroup(masterDescriptor: masterDescriptor) ?? fallbackProcessID
        guard group > 0 else { return }
        _ = killpg(group, SIGWINCH)
    }

    static func terminate(processID: pid_t) {
        guard processID > 0 else { return }
        if killpg(processID, SIGHUP) != 0 {
            _ = kill(processID, SIGHUP)
        }
        _ = killpg(processID, SIGCONT)
    }
}
