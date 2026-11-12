import Foundation
import Darwin
import Security

public struct BasicProcess: Equatable {
    public let pid: Int32
    public let ppid: Int32
    public let birth: UInt64
    public let path: String
}

public enum ProcessReader {
    public static func basic(_ pid: Int32) -> BasicProcess? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size, info.pbi_uid == getuid() else { return nil }
        var path = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        guard proc_pidpath(pid, &path, UInt32(path.count)) > 0 else { return nil }
        return .init(pid: pid, ppid: Int32(info.pbi_ppid), birth: info.pbi_start_tvsec * 1_000_000 + info.pbi_start_tvusec, path: String(cString: path))
    }
    public static func all() -> [BasicProcess] {
        var pids = [Int32](repeating: 0, count: max(4096, Int(proc_listallpids(nil, 0)) + 1024))
        let count = pids.withUnsafeMutableBytes { proc_listallpids($0.baseAddress, Int32($0.count)) }
        guard count > 0 else { return [] }
        return pids.prefix(min(Int(count), pids.count)).compactMap(basic)
    }
}

public enum SignatureReader {
    // Validate the running code, not a process name or a guessed application directory.
    public static func identity(_ process: BasicProcess) -> ProcessIdentity? {
        var code: SecCode?
        guard SecCodeCopyGuestWithAttributes(nil, [kSecGuestAttributePid as String: process.pid] as CFDictionary, [], &code) == errSecSuccess,
              let code else { return nil }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return nil }
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
              let info = information as? [String: Any],
              let team = info[kSecCodeInfoTeamIdentifier as String] as? String,
              let identifier = info[kSecCodeInfoIdentifier as String] as? String,
              let client = IdentityPolicy.classify(team: team, identifier: identifier, valid: true) else { return nil }
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString("anchor apple generic" as CFString, [], &requirement) == errSecSuccess,
              SecCodeCheckValidity(code, [], requirement) == errSecSuccess,
              ProcessReader.basic(process.pid) == process else { return nil }
        return .init(pid: process.pid, birth: process.birth, path: process.path, team: team, signingID: identifier, client: client)
    }
}

public struct CommandResult { public let output: String; public let error: String; public let status: Int32 }
public enum SystemCommand {
    public static func run(_ path: String, _ arguments: [String], timeout: TimeInterval = 8) throws -> CommandResult {
        let process = Process(); process.executableURL = URL(fileURLWithPath: path); process.arguments = arguments
        // Use private temporary files to avoid pipe backpressure deadlocks, including error paths.
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ai-tide-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        let stdout = directory.appendingPathComponent("out"), stderr = directory.appendingPathComponent("err")
        FileManager.default.createFile(atPath: stdout.path, contents: nil, attributes: [.posixPermissions: 0o600])
        FileManager.default.createFile(atPath: stderr.path, contents: nil, attributes: [.posixPermissions: 0o600])
        let outHandle = try FileHandle(forWritingTo: stdout), errHandle = try FileHandle(forWritingTo: stderr)
        defer { try? outHandle.close(); try? errHandle.close() }
        process.standardOutput = outHandle; process.standardError = errHandle
        process.environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "LC_ALL": "C", "LANG": "C"]
        let done = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in done.signal() }
        try process.run()
        if done.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            if done.wait(timeout: .now() + 1) == .timedOut { kill(process.processIdentifier, SIGKILL); process.waitUntilExit() }
            throw CollectionError.invalidOutput("系统采集超时；未生成流量读数")
        }
        return .init(output: String(decoding: try Data(contentsOf: stdout), as: UTF8.self), error: String(decoding: try Data(contentsOf: stderr), as: UTF8.self), status: process.terminationStatus)
    }
}

public struct ProcessReading: Codable {
    public let identity: ProcessIdentity
    public let parentPID: Int32
    public let origin: String
    public let receivedCounter: UInt64?
    public let sentCounter: UInt64?
    public let receivedPerSecond: Double?
    public let sentPerSecond: Double?
    public let receivedDelta: UInt64?
    public let sentDelta: UInt64?
    public let state: String
}
public struct SystemSample: Codable {
    public let date: Date
    public let source: String
    public let readings: [ProcessReading]
    public let error: String?
    public let duration: Double
}

public final class SystemCollector {
    private var accumulator = TrafficAccumulator()
    private struct ExecutableKey: Hashable {
        let pid: Int32
        let birth: UInt64
        let path: String
        init(_ process: BasicProcess) { pid = process.pid; birth = process.birth; path = process.path }
    }
    private var rejected: [ExecutableKey: TimeInterval] = [:]
    public init() {}
    public func reset() { accumulator = TrafficAccumulator() }

    public func sample() -> SystemSample {
        let start = ProcessInfo.processInfo.systemUptime
        let basics = ProcessReader.all()
        // Installers may name the real executable with a version number (e.g. Claude Code).
        // Enumerate signatures rather than assuming an executable name or installation location.
        let keys = Set(basics.map(ExecutableKey.init))
        rejected = rejected.filter { keys.contains($0.key) && start - $0.value < 15 }
        let identities = basics.compactMap { process -> ProcessIdentity? in
            let key = ExecutableKey(process)
            guard rejected[key] == nil else { return nil }
            let identity = SignatureReader.identity(process)
            if identity == nil { rejected[key] = start }
            return identity
        }
        var readings: [ProcessReading] = []
        do {
            guard !identities.isEmpty else {
                accumulator.retain([])
                return .init(date: Date(), source: "macOS nettop · TCP/UDP · 同一用户", readings: [], error: nil, duration: ProcessInfo.processInfo.systemUptime - start)
            }
            var args = ["-P", "-L", "1", "-x", "-n", "-J", "bytes_in,bytes_out"]
            for identity in identities { args += ["-p", String(identity.pid)] }
            let result = try SystemCommand.run("/usr/bin/nettop", args)
            guard result.status == 0 else { throw CollectionError.invalidOutput("nettop 退出码 \(result.status)：\(result.error.prefix(160))") }
            let counters = Dictionary(uniqueKeysWithValues: try NettopParser.parse(result.output).map { ($0.pid, $0) })
            let now = ProcessInfo.processInfo.systemUptime
            var observed = Set<ProcessIdentity>()
            let index = Dictionary(uniqueKeysWithValues: basics.map { ($0.pid, $0) })
            let signed = Dictionary(uniqueKeysWithValues: identities.map { ($0.pid, $0) })
            for identity in identities {
                guard let before = index[identity.pid], ProcessReader.basic(identity.pid) == before,
                      SignatureReader.identity(before) == identity else { continue }
                let count = counters[identity.pid]
                let delta = count.flatMap { accumulator.observe($0, identity: identity, at: now) }
                if count != nil { observed.insert(identity) }
                let origin = Self.origin(identity: identity, basics: index, signed: signed)
                readings.append(.init(identity: identity, parentPID: before.ppid, origin: origin,
                                      receivedCounter: count?.received, sentCounter: count?.sent,
                                      receivedPerSecond: delta.map { Double($0.received) / $0.elapsed },
                                      sentPerSecond: delta.map { Double($0.sent) / $0.elapsed },
                                      receivedDelta: delta?.received, sentDelta: delta?.sent,
                                      state: count == nil ? "无可见 socket" : delta == nil ? "建立基线" : "已观测"))
            }
            accumulator.retain(observed)
            return .init(date: Date(), source: "macOS nettop · TCP/UDP · 同一用户", readings: readings.sorted { $0.identity.pid < $1.identity.pid }, error: nil, duration: now - start)
        } catch {
            accumulator.retain([])
            return .init(date: Date(), source: "macOS nettop", readings: [], error: String(describing: error), duration: ProcessInfo.processInfo.systemUptime - start)
        }
    }
    private static func origin(identity: ProcessIdentity, basics: [Int32: BasicProcess], signed: [Int32: ProcessIdentity]) -> String {
        if identity.client != .codex { return identity.client == .claudeCode ? "Claude Code 原生进程" : "ChatGPT 应用进程" }
        if identity.signingID != "codex" { return identity.signingID == "com.openai.codex" ? "Codex App 主进程" : "Codex App 网络辅助进程" }
        var pid = identity.pid; var visited = Set<Int32>()
        while let process = basics[pid], visited.insert(pid).inserted, visited.count < 64 {
            if let parent = signed[process.ppid], parent.signingID == "com.openai.codex" { return "Codex CLI · 当前祖先为 App" }
            pid = process.ppid
        }
        return "Codex CLI / TUI · 入口未确认"
    }
}
