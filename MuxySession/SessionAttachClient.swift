import Darwin
import MachO
import MuxySessionProtocol

enum SessionAttachClient {
    static let connectAttempts = 150
    static let connectRetryMicroseconds: useconds_t = 20000
    static let inputBacklogLimit = 4 * 1024 * 1024

    struct Configuration {
        let identifier: SessionIdentifier
        let socketPath: String
        let command: String
        let shell: String
        let resourcesDirectory: String
        let workingDirectory: String
        let metadata: [SessionEnvironmentEntry]
    }

    static func run(configuration: Configuration) -> Int32 {
        signal(SIGPIPE, SIG_IGN)

        guard let socket = connect(socketPath: configuration.socketPath) else {
            SessionLog.write("muxy-session: could not reach the session daemon")
            return 1
        }
        SessionIO.setNonBlocking(socket)

        guard let signalPipe = SessionSignalPipe(signals: [SIGWINCH]) else {
            SessionIO.close(socket)
            return 1
        }

        let originalTerminal = enterRawMode()
        defer {
            if var originalTerminal {
                tcsetattr(STDIN_FILENO, TCSANOW, &originalTerminal)
            }
        }

        let connection = SessionConnection(descriptor: socket)
        connection.enqueue(SessionFrame(kind: .attach, payload: makeRequest(configuration).encoded()))

        return loop(connection: connection, signalPipe: signalPipe)
    }

    private static func loop(connection: SessionConnection, signalPipe: SessionSignalPipe) -> Int32 {
        while true {
            guard connection.flush() else { return 1 }

            var descriptors = [
                pollfd(fd: signalPipe.readDescriptor, events: Int16(POLLIN), revents: 0),
                pollfd(
                    fd: connection.descriptor,
                    events: Int16(connection.hasPendingOutput ? Int32(POLLIN) | Int32(POLLOUT) : Int32(POLLIN)),
                    revents: 0
                ),
            ]
            if connection.pendingByteCount < inputBacklogLimit {
                descriptors.append(pollfd(fd: STDIN_FILENO, events: Int16(POLLIN), revents: 0))
            }

            let ready = poll(&descriptors, nfds_t(descriptors.count), -1)
            if ready < 0 {
                guard errno == EINTR else { return 1 }
                continue
            }

            for entry in descriptors where entry.revents != 0 {
                if entry.fd == signalPipe.readDescriptor {
                    signalPipe.drain()
                    sendResize(connection)
                } else if entry.fd == STDIN_FILENO {
                    guard forwardInput(connection) else { return 0 }
                } else if let status = receive(connection, revents: entry.revents) {
                    _ = connection.flush()
                    return status
                }
            }
        }
    }

    private static func forwardInput(_ connection: SessionConnection) -> Bool {
        switch SessionIO.read(STDIN_FILENO) {
        case let .bytes(bytes):
            connection.enqueue(SessionFrame(kind: .input, payload: bytes))
            return true
        case .wouldBlock:
            return true
        case .endOfFile,
             .failed:
            return false
        }
    }

    private static func receive(_ connection: SessionConnection, revents: Int16) -> Int32? {
        if revents & Int16(POLLOUT) != 0, !connection.flush() {
            return 1
        }
        guard revents & Int16(POLLIN) != 0 || revents & Int16(POLLHUP) != 0 else { return nil }

        var reachedEnd = false
        readLoop: while true {
            switch SessionIO.read(connection.descriptor) {
            case let .bytes(bytes):
                connection.decoder.push(bytes)
            case .wouldBlock:
                break readLoop
            case .endOfFile,
                 .failed:
                reachedEnd = true
                break readLoop
            }
        }

        while true {
            let frame: SessionFrame?
            do {
                frame = try connection.decoder.next()
            } catch {
                return 1
            }
            guard let frame else { break }
            switch frame.kind {
            case .output:
                guard SessionIO.writeAll(STDOUT_FILENO, frame.payload) else { return 1 }
            case .exited:
                return (try? SessionExitPayload.decode(frame.payload)) ?? 0
            case .failure:
                let message = (try? SessionTextPayload.decode(frame.payload)) ?? "session failed"
                SessionLog.write("muxy-session: " + message)
                return 1
            case .attached,
                 .attach,
                 .input,
                 .resize,
                 .list,
                 .info,
                 .kill,
                 .killAll,
                 .sessions,
                 .acknowledged:
                break
            }
        }

        return reachedEnd ? 1 : nil
    }

    private static func sendResize(_ connection: SessionConnection) {
        guard let size = SessionPTY.windowSize(descriptor: STDIN_FILENO) else { return }
        connection.enqueue(SessionFrame(
            kind: .resize,
            payload: SessionResizePayload.encode(columns: size.columns, rows: size.rows)
        ))
    }

    private static func makeRequest(_ configuration: Configuration) -> SessionAttachRequest {
        let size = SessionPTY.windowSize(descriptor: STDIN_FILENO) ?? (columns: 80, rows: 24)
        let environment = SessionProcessEnvironment.current()
            .filter { !$0.key.hasPrefix("MUXY_SESSION_") }
            .map { SessionEnvironmentEntry(key: $0.key, value: $0.value) }
        return SessionAttachRequest(
            identifier: configuration.identifier,
            columns: size.columns,
            rows: size.rows,
            workingDirectory: configuration.workingDirectory,
            command: configuration.command,
            shell: configuration.shell,
            resourcesDirectory: configuration.resourcesDirectory,
            environment: environment,
            metadata: configuration.metadata
        )
    }

    private static func enterRawMode() -> termios? {
        var original = termios()
        guard tcgetattr(STDIN_FILENO, &original) == 0 else { return nil }
        var raw = original
        cfmakeraw(&raw)
        guard tcsetattr(STDIN_FILENO, TCSANOW, &raw) == 0 else { return nil }
        return original
    }

    private static func connect(socketPath: String) -> Int32? {
        if let descriptor = SessionSocket.connect(path: socketPath) {
            return descriptor
        }
        launchDaemon(socketPath: socketPath)
        for _ in 0 ..< connectAttempts {
            usleep(connectRetryMicroseconds)
            if let descriptor = SessionSocket.connect(path: socketPath) {
                return descriptor
            }
        }
        return nil
    }

    private static func launchDaemon(socketPath: String) {
        guard let binaryPath = executablePath() else {
            SessionLog.write("muxy-session: unable to locate the session daemon binary")
            return
        }
        let arguments = SessionCStringArray([binaryPath, "daemon", "--socket", socketPath])

        var fileActions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&fileActions)
        defer { posix_spawn_file_actions_destroy(&fileActions) }
        posix_spawn_file_actions_addopen(&fileActions, STDIN_FILENO, "/dev/null", O_RDWR, 0)
        posix_spawn_file_actions_addopen(&fileActions, STDOUT_FILENO, "/dev/null", O_RDWR, 0)
        posix_spawn_file_actions_addopen(
            &fileActions,
            STDERR_FILENO,
            socketPath + ".log",
            O_WRONLY | O_CREAT | O_TRUNC,
            0o600
        )

        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETSID))

        var processID: pid_t = 0
        let result = posix_spawn(&processID, binaryPath, &fileActions, &attributes, arguments.pointer, environ)
        guard result != 0 else { return }
        SessionLog.write("muxy-session: could not start the session daemon (\(result))")
    }

    static func executablePath() -> String? {
        if let provided = SessionProcessEnvironment.value("MUXY_SESSION_BINARY") {
            return provided
        }
        var size = UInt32(PATH_MAX)
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        guard _NSGetExecutablePath(&buffer, &size) == 0 else { return nil }
        return buffer.withUnsafeBufferPointer { pointer in
            guard let base = pointer.baseAddress else { return nil }
            return String(cString: base)
        }
    }
}
