import Foundation
import TideCore

let arguments = CommandLine.arguments
func option(_ name: String) -> String? {
    guard let index = arguments.firstIndex(of: name), index + 1 < arguments.count else { return nil }
    return arguments[index + 1]
}
if arguments.contains("--help") {
    print("""
    tide-probe [--seconds 15] [--interval 1]
      Read signed AI process identities and macOS nettop counters as JSON Lines.
      No prompts, credentials, or payloads are read. Paths are local executable paths.
    tide-probe --transport-pid PID [--seconds 10]
      Diagnostic raw counter mode for a controlled transfer; NOT AI attribution.
    """)
    exit(0)
}
let seconds = min(600, max(1, Double(option("--seconds") ?? "10") ?? 10))
let interval = min(10, max(0.3, Double(option("--interval") ?? "1") ?? 1))
let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; encoder.outputFormatting = [.sortedKeys]
let collector = SystemCollector()
let start = ProcessInfo.processInfo.systemUptime
repeat {
    if let pidString = option("--transport-pid"), let pid = Int32(pidString) {
        do {
            let result = try SystemCommand.run("/usr/bin/nettop", ["-P", "-L", "1", "-x", "-n", "-J", "bytes_in,bytes_out", "-p", String(pid)])
            guard result.status == 0 else { throw CollectionError.invalidOutput(result.error) }
            let rows = try NettopParser.parse(result.output)
            let object: [String: Any] = ["source": "nettop transport diagnostic — not AI attribution", "time": ProcessInfo.processInfo.systemUptime,
                "pid": pid, "received": rows.first?.received as Any? ?? NSNull(), "sent": rows.first?.sent as Any? ?? NSNull()]
            let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
            FileHandle.standardOutput.write(data + Data("\n".utf8))
        } catch { fputs("\(error)\n", stderr); exit(1) }
    } else {
        let sample = collector.sample()
        if let data = try? encoder.encode(sample) { FileHandle.standardOutput.write(data + Data("\n".utf8)) }
    }
    Thread.sleep(forTimeInterval: interval)
} while ProcessInfo.processInfo.systemUptime - start < seconds
