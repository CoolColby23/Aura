import Darwin
import Foundation

enum DiscordError: LocalizedError, Equatable {
    case missingApplicationID, unavailable, connectFailed, writeFailed
    var errorDescription: String? {
        switch self {
        case .missingApplicationID: "Enter a Discord application ID."
        case .unavailable: "Discord Desktop is not running."
        case .connectFailed: "Could not connect to Discord."
        case .writeFailed: "Discord disconnected while updating presence."
        }
    }
}

actor DiscordPresenceClient: PresencePublishing {
    private var applicationID: String
    private var socketFD: Int32 = -1
    private var lastPresence: DiscordPresence?
    private(set) var socketPath: String?
    private let runtimeRoots: [String]?

    init(
        applicationID: String = ReleaseConfiguration.discordApplicationID,
        runtimeRoots: [String]? = nil
    ) {
        self.applicationID = applicationID.isEmpty ? ReleaseConfiguration.discordApplicationID : applicationID
        self.runtimeRoots = runtimeRoots
    }
    deinit { if socketFD >= 0 { Darwin.close(socketFD) } }

    func publish(_ presence: DiscordPresence) async throws {
        try await connectIfNeeded()
        if let lastPresence, !Self.shouldPublish(presence, after: lastPresence) { return }
        let activity = Self.activityPayload(for: presence)
        try send(
            opcode: 1,
            payload: [
                "cmd": "SET_ACTIVITY", "args": ["pid": ProcessInfo.processInfo.processIdentifier, "activity": activity],
                "nonce": UUID().uuidString,
            ])
        lastPresence = presence
    }

    /// Discord advances its progress bar locally. Small timestamp differences
    /// between polls should not create another RPC update; seeks still do.
    nonisolated static func shouldPublish(_ presence: DiscordPresence, after previous: DiscordPresence) -> Bool {
        var currentPayload = activityPayload(for: presence)
        var previousPayload = activityPayload(for: previous)
        currentPayload.removeValue(forKey: "timestamps")
        previousPayload.removeValue(forKey: "timestamps")
        guard NSDictionary(dictionary: currentPayload).isEqual(to: previousPayload) else { return true }
        func equivalent(_ lhs: Date?, _ rhs: Date?) -> Bool {
            switch (lhs, rhs) {
            case (nil, nil): true
            case let (lhs?, rhs?): abs(lhs.timeIntervalSince(rhs)) < 2
            default: false
            }
        }
        return !equivalent(presence.startedAt, previous.startedAt) || !equivalent(presence.endsAt, previous.endsAt)
    }

    nonisolated static func activityPayload(for presence: DiscordPresence) -> [String: Any] {
        let largeImage =
            switch presence.largeImage {
            case .artwork:
                DiscordMediaURL.externalImage(
                    presence.artworkURL,
                    fallback: ReleaseConfiguration.discordApplicationIconURL
                )
            case .playbackPlatform:
                presence.platform.discordSmallImageURL
            case .aura:
                ReleaseConfiguration.discordApplicationIconURL
            }
        let details = bounded(presence.title, fallback: "Listening on \(presence.platform.rawValue)")
        let state = bounded(presence.state, fallback: presence.platform.rawValue)
        var assets = ["large_image": largeImage]
        let largeText = presence.largeImageText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !largeText.isEmpty { assets["large_text"] = bounded(largeText, fallback: presence.platform.rawValue) }
        switch presence.smallImage {
        case .aura:
            assets["small_image"] = ReleaseConfiguration.discordApplicationIconURL
            assets["small_text"] = bounded(presence.smallImageText, fallback: "Shared with Aura")
        case .playbackPlatform:
            assets["small_image"] = presence.platform.discordSmallImageURL
            assets["small_text"] = bounded(presence.smallImageText, fallback: "Playing on \(presence.platform.rawValue)")
        case .none: break
        }
        var activity: [String: Any] = [
            "type": presence.activityType.payloadValue,
            "name": bounded(presence.activityName, fallback: "Aura"),
            "details": details, "state": state,
            "assets": assets,
        ]
        var timestamps: [String: Int] = [:]
        if let startedAt = presence.startedAt {
            timestamps["start"] = Int(startedAt.timeIntervalSince1970 * 1_000)
        }
        if let endsAt = presence.endsAt {
            if let startedAt = presence.startedAt {
                if endsAt > startedAt { timestamps["end"] = Int(endsAt.timeIntervalSince1970 * 1_000) }
            } else {
                timestamps["end"] = Int(endsAt.timeIntervalSince1970 * 1_000)
            }
        }
        if !timestamps.isEmpty {
            activity["timestamps"] = timestamps
        }
        if let url = presence.appleMusicURL {
            let label = presence.buttonLabel.trimmingCharacters(in: .whitespacesAndNewlines)
            activity["buttons"] = [
                ["label": String((label.isEmpty ? "Listen on \(presence.platform.rawValue)" : label).prefix(32)), "url": url.absoluteString]
            ]
        }
        return activity
    }

    nonisolated private static func bounded(_ value: String, fallback: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return String((trimmed.isEmpty ? fallback : trimmed).prefix(128))
    }

    func clear() async {
        guard socketFD >= 0 else { return }
        try? send(
            opcode: 1,
            payload: [
                "cmd": "SET_ACTIVITY", "args": ["pid": ProcessInfo.processInfo.processIdentifier, "activity": NSNull()],
                "nonce": UUID().uuidString,
            ])
        lastPresence = nil
    }

    func disconnect() {
        if socketFD >= 0 { Darwin.close(socketFD) }
        socketFD = -1
        socketPath = nil
        lastPresence = nil
    }

    func setApplicationID(_ value: String) {
        applicationID = value.isEmpty ? ReleaseConfiguration.discordApplicationID : value
        disconnect()
    }

    /// A socket file can survive after Discord exits. Only report availability
    /// after a live IPC connection succeeds. Preserve healthy connections so
    /// idle checks do not clear the last published activity.
    func probeAvailability() async -> Bool {
        do {
            try await connectIfNeeded()
            return true
        } catch {
            disconnect()
            return false
        }
    }

    private func connectIfNeeded() async throws {
        if socketFD >= 0, !isSocketLive {
            disconnect()
        }
        guard socketFD < 0 else { return }
        guard !applicationID.isEmpty else {
            throw DiscordError.missingApplicationID
        }
        for path in candidatePaths() where FileManager.default.fileExists(atPath: path) {
            let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
            guard fd >= 0 else { throw DiscordError.connectFailed }
            var noSignal: Int32 = 1
            _ = Darwin.setsockopt(
                fd, SOL_SOCKET, SO_NOSIGPIPE,
                &noSignal, socklen_t(MemoryLayout<Int32>.size)
            )
            var sendTimeout = timeval(tv_sec: 2, tv_usec: 0)
            _ = Darwin.setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &sendTimeout, socklen_t(MemoryLayout<timeval>.size))
            var address = sockaddr_un()
            address.sun_family = sa_family_t(AF_UNIX)
            let pathCapacity = MemoryLayout.size(ofValue: address.sun_path)
            guard path.utf8CString.count <= pathCapacity else { Darwin.close(fd); continue }
            withUnsafeMutablePointer(to: &address.sun_path.0) { destination in
                path.withCString { source in _ = Darwin.strncpy(destination, source, pathCapacity) }
            }
            let result = withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
                }
            }
            // Stale socket files are common after Discord exits. Try every slot.
            guard result == 0 else { Darwin.close(fd); continue }
            socketFD = fd
            socketPath = path
            do {
                try send(opcode: 0, payload: ["v": 1, "client_id": applicationID])
                return
            } catch {
                disconnect()
            }
        }
        throw DiscordError.unavailable
    }

    private var isSocketLive: Bool {
        guard socketFD >= 0 else { return false }
        var descriptor = pollfd(
            fd: socketFD,
            events: Int16(POLLHUP | POLLERR | POLLNVAL),
            revents: 0
        )
        let result = Darwin.poll(&descriptor, 1, 0)
        guard result >= 0 else { return false }
        return result == 0 || descriptor.revents & Int16(POLLHUP | POLLERR | POLLNVAL) == 0
    }

    private func send(opcode: UInt32, payload: [String: Any]) throws {
        let body = try JSONSerialization.data(withJSONObject: payload)
        var op = opcode.littleEndian
        var length = UInt32(body.count).littleEndian
        var frame = Data(bytes: &op, count: 4)
        frame.append(Data(bytes: &length, count: 4)); frame.append(body)
        var offset = 0
        while offset < frame.count {
            let written = frame.withUnsafeBytes { bytes in
                Darwin.write(socketFD, bytes.baseAddress!.advanced(by: offset), frame.count - offset)
            }
            if written < 0, errno == EINTR { continue }
            guard written > 0 else { disconnect(); throw DiscordError.writeFailed }
            offset += written
        }
    }

    private func candidatePaths() -> [String] {
        let roots: [String]
        if let runtimeRoots {
            roots = runtimeRoots
        } else {
            let environment = ProcessInfo.processInfo.environment
            roots = [environment["XDG_RUNTIME_DIR"], environment["TMPDIR"], environment["TMP"], environment["TEMP"], "/tmp"].compactMap { $0 }
        }
        var seen = Set<String>()
        return roots.filter { seen.insert($0).inserted }.flatMap { root in (0...9).map { URL(fileURLWithPath: root).appendingPathComponent("discord-ipc-\($0)").path } }
    }
}
