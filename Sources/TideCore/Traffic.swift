import Foundation

public enum Client: String, Codable, CaseIterable { case chatGPT, codex, claudeCode }
public struct ProcessCounters: Equatable {
    public let pid: Int32
    public let received: UInt64
    public let sent: UInt64
    public init(pid: Int32, received: UInt64, sent: UInt64) { self.pid = pid; self.received = received; self.sent = sent }
}
public enum CollectionError: Error { case invalidOutput(String) }
public enum NettopParser {
    public static func parse(_ text: String) throws -> [ProcessCounters] {
        let lines = text.split(whereSeparator: \.isNewline).map(String.init)
        guard let first = lines.first else { throw CollectionError.invalidOutput("nettop 未返回表头") }
        let header = try csv(first)
        guard let rx = header.firstIndex(of: "bytes_in"), let tx = header.firstIndex(of: "bytes_out") else {
            throw CollectionError.invalidOutput("nettop 缺少收发字节列")
        }
        var seen = Set<Int32>()
        return try lines.dropFirst().map { line in
            let fields = try csv(line)
            guard fields.count > max(rx, tx), let name = fields.first,
                  let dot = name.lastIndex(of: "."), let pid = Int32(name[name.index(after: dot)...]), pid > 0,
                  let received = UInt64(fields[rx]), let sent = UInt64(fields[tx]), seen.insert(pid).inserted else {
                throw CollectionError.invalidOutput("nettop 数据格式变化或字节计数无效")
            }
            return .init(pid: pid, received: received, sent: sent)
        }
    }
    private static func csv(_ line: String) throws -> [String] {
        var result: [String] = []; var field = ""; var quoted = false
        var cursor = line.startIndex
        while cursor < line.endIndex {
            let char = line[cursor]
            let next = line.index(after: cursor)
            if char == "\"" {
                if quoted && next < line.endIndex && line[next] == "\"" { field.append("\""); cursor = line.index(after: next); continue }
                quoted.toggle()
            } else if char == "," && !quoted { result.append(field); field = "" }
            else { field.append(char) }
            cursor = next
        }
        guard !quoted else { throw CollectionError.invalidOutput("未闭合 CSV 字段") }
        result.append(field)
        return result
    }
}
public enum IdentityPolicy {
    public static func classify(team: String, identifier: String, valid: Bool) -> Client? {
        guard valid else { return nil }
        if team == "Q6L2SF6YDW", identifier == "com.anthropic.claude-code" { return .claudeCode }
        guard team == "2DC432GLL2" else { return nil }
        if ["com.openai.chat", "com.openai.chat.helper", "com.openai.chat.helper.GPU", "com.openai.chat.helper.Renderer"].contains(identifier) { return .chatGPT }
        if ["codex", "com.openai.codex", "com.openai.codex.helper", "com.openai.codex.helper.GPU", "com.openai.codex.helper.Renderer"].contains(identifier) { return .codex }
        return nil
    }
}
public struct ProcessIdentity: Hashable, Codable {
    public let pid: Int32
    public let birth: UInt64
    public let path: String
    public let team: String
    public let signingID: String
    public let client: Client
    public init(pid: Int32, birth: UInt64, path: String, team: String, signingID: String, client: Client) {
        self.pid = pid; self.birth = birth; self.path = path; self.team = team; self.signingID = signingID; self.client = client
    }
}
public struct TrafficDelta: Equatable {
    public let received: UInt64
    public let sent: UInt64
    public let elapsed: TimeInterval
    public init(received: UInt64, sent: UInt64, elapsed: TimeInterval) { self.received = received; self.sent = sent; self.elapsed = elapsed }
}
public struct TrafficAccumulator {
    private var previous: [ProcessIdentity: (ProcessCounters, TimeInterval)] = [:]
    public init() {}
    public mutating func observe(_ counters: ProcessCounters, identity: ProcessIdentity, at time: TimeInterval) -> TrafficDelta? {
        guard counters.pid == identity.pid else { return nil }
        let last = previous[identity]
        previous[identity] = (counters, time)
        guard let (old, oldTime) = last, time > oldTime,
              counters.received >= old.received, counters.sent >= old.sent else { return nil }
        return .init(received: counters.received - old.received, sent: counters.sent - old.sent, elapsed: time - oldTime)
    }
    public mutating func retain(_ identities: Set<ProcessIdentity>) {
        previous = previous.filter { identities.contains($0.key) }
    }
}
