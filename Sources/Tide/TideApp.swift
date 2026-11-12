import SwiftUI
import AppKit
import TideCore

@main struct TideApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var model = TideModel()
    init() {
        if CommandLine.arguments.contains("--check-resources") {
            let checks = ["jade", "copper", "app-icon"].map { name -> [String: Any] in
                let image = MaterialBundle.image(name)
                return ["asset": name, "loaded": image != nil, "width": image?.size.width ?? 0, "height": image?.size.height ?? 0]
            }
            if let data = try? JSONSerialization.data(withJSONObject: checks, options: [.sortedKeys]), let text = String(data: data, encoding: .utf8) { print(text) }
            exit(checks.allSatisfy { $0["loaded"] as? Bool == true } ? 0 : 1)
        }
    }
    var body: some Scene {
        WindowGroup("潮汐 · AI 网络活动", id: "tide") {
            TideView().environmentObject(model).preferredColorScheme(.dark).tint(Theme.jade)
        }
        .defaultSize(width: 1120, height: 810)
        .windowStyle(.hiddenTitleBar)
        .commands { CommandGroup(replacing: .newItem) {} }
        MenuBarExtra {
            MiniView().environmentObject(model).preferredColorScheme(.dark).tint(Theme.jade)
        } label: { Image(systemName: "water.waves") }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if let icon = MaterialBundle.image("app-icon") { NSApp.applicationIconImage = icon }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}

enum Theme {
    static let background = Color(red: 0.075, green: 0.084, blue: 0.085)
    static let text = Color(red: 0.94, green: 0.93, blue: 0.90)
    static let muted = Color(red: 0.66, green: 0.69, blue: 0.68)
    static let jade = Color(red: 0.62, green: 0.85, blue: 0.72)
    static let copper = Color(red: 0.94, green: 0.67, blue: 0.49)
    static func color(_ client: Client) -> Color { client == .claudeCode ? copper : jade }
    static func name(_ client: Client) -> String {
        switch client { case .chatGPT: return "ChatGPT"; case .codex: return "Codex"; case .claudeCode: return "Claude Code" }
    }
    static func rate(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "—" }
        if value < 1024 { return String(format: "%.0f B/s", value) }
        if value < 1024 * 1024 { return String(format: "%.1f KiB/s", value / 1024) }
        return String(format: "%.2f MiB/s", value / (1024 * 1024))
    }
}

enum MaterialBundle {
    static let directory: URL = {
        #if DEBUG
        return Bundle.module.bundleURL
        #else
        // Release assets resolve inside the application, never from a developer's build directory.
        return Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/AITide_Tide.bundle")
        #endif
    }()
    static let jade = NSImage(contentsOf: directory.appendingPathComponent("jade.png"))
    static let copper = NSImage(contentsOf: directory.appendingPathComponent("copper.png"))
    static let icon = NSImage(contentsOf: directory.appendingPathComponent("app-icon.png"))
    static func image(_ name: String) -> NSImage? {
        switch name { case "jade": return jade; case "copper": return copper; case "app-icon": return icon; default: return nil }
    }
}

struct TideButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 12, weight: .medium))
            .foregroundStyle(Theme.text).padding(.horizontal, 14).padding(.vertical, 8)
            .background(.white.opacity(configuration.isPressed ? 0.15 : 0.07), in: RoundedRectangle(cornerRadius: 7))
            .overlay { RoundedRectangle(cornerRadius: 7).strokeBorder(.white.opacity(0.12), lineWidth: 0.7) }
    }
}

struct HistoryPoint: Identifiable {
    let id = UUID()
    let date: Date
    let received: Double?
    let sent: Double?
}
struct ClientSummary {
    let readings: [ProcessReading]
    let received: Double?
    let sent: Double?
    let status: String
}

@MainActor final class TideModel: ObservableObject {
    @Published var sample: SystemSample?
    @Published var paused = false
    @Published var openAI: Client = .codex
    @Published var histories: [Client: [HistoryPoint]] = [:]
    @Published var showSources = false
    @Published var stale = false
    private let collector = SystemCollector()
    private var task: Task<Void, Never>?
    private var watchdog: Task<Void, Never>?
    private var sessionStart = Date()
    init() {
        start()
        watchdog = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, !Task.isCancelled else { break }
                self.stale = !self.paused && self.sample.map { Date().timeIntervalSince($0.date) > 6 } == true
            }
        }
    }
    deinit { task?.cancel(); watchdog?.cancel() }
    func start() {
        task?.cancel()
        let collector = self.collector
        task = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { break }
                if !self.paused {
                    let value = await Task.detached(priority: .utility) { collector.sample() }.value
                    guard !Task.isCancelled else { break }
                    if !self.paused { self.accept(value) }
                }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }
    private func accept(_ value: SystemSample) {
        sample = value
        stale = false
        for client in Client.allCases {
            let summary = summary(client)
            let point = HistoryPoint(date: value.date, received: summary.received, sent: summary.sent)
            histories[client, default: []].append(point)
            histories[client]?.removeAll { value.date.timeIntervalSince($0.date) > 60 }
        }
        if openAI == .codex, !value.readings.contains(where: { $0.identity.client == .codex }), value.readings.contains(where: { $0.identity.client == .chatGPT }) { openAI = .chatGPT }
    }
    func summary(_ client: Client) -> ClientSummary {
        let rows = sample?.readings.filter { $0.identity.client == client } ?? []
        guard !paused else { return .init(readings: rows, received: nil, sent: nil, status: "采集已暂停") }
        guard !stale else { return .init(readings: rows, received: nil, sent: nil, status: "采样已过期 · 等待刷新") }
        guard let sample else { return .init(readings: [], received: nil, sent: nil, status: "正在读取系统") }
        guard sample.error == nil else { return .init(readings: rows, received: nil, sent: nil, status: "采集不可用 · 查看来源") }
        guard !rows.isEmpty else { return .init(readings: [], received: nil, sent: nil, status: "未发现已核验进程") }
        let measured = rows.filter { $0.receivedPerSecond != nil && $0.sentPerSecond != nil }
        guard !measured.isEmpty else { return .init(readings: rows, received: nil, sent: nil, status: rows.contains { $0.receivedCounter != nil } ? "正在建立采样基线" : "进程已核验 · 无可见连接") }
        let partial = rows.contains { $0.receivedCounter != nil && $0.receivedPerSecond == nil }
        return .init(readings: rows, received: measured.compactMap(\.receivedPerSecond).reduce(0, +), sent: measured.compactMap(\.sentPerSecond).reduce(0, +), status: partial ? "部分进程建立基线" : "\(rows.count) 个已核验进程 · \(measured.count) 个有读数")
    }
    func togglePause() {
        paused.toggle()
        // Restart only after the prior worker exits, so the collector is never accessed concurrently.
        if paused { task?.cancel() }
        else {
            let oldTask = task
            task = Task { [weak self] in
                await oldTask?.value
                guard let self, !Task.isCancelled else { return }
                self.collector.reset()
                self.start()
            }
        }
    }
    func clearHistory() { histories = [:]; sessionStart = Date() }
    func export() {
        guard let sample else { return }
        let panel = NSSavePanel(); panel.nameFieldStringValue = "tide-diagnostics.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(sample)
            // Export on explicit action only. Replace the current home prefix before sharing.
            let text = String(decoding: data, as: UTF8.self).replacingOccurrences(of: NSHomeDirectory().replacingOccurrences(of: "/", with: "\\/"), with: "~").replacingOccurrences(of: NSHomeDirectory(), with: "~")
            try text.write(to: url, atomically: true, encoding: .utf8)
        } catch { NSAlert(error: error).runModal() }
    }
}

struct TideView: View {
    @EnvironmentObject var model: TideModel
    @State private var timeline = false
    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(.white.opacity(0.09)).frame(height: 1)
            if timeline {
                VStack(alignment: .leading, spacing: 26) {
                    Text("每一阵波动，都有真实读数。 ").font(.system(size: 25, weight: .medium))
                    Text("接收为实线，发送为虚线。空白表示没有可用采样，不代表零流量。").foregroundStyle(Theme.muted)
                    TrafficChart(client: model.openAI, height: 170)
                    TrafficChart(client: .claudeCode, height: 170)
                    Spacer(minLength: 0)
                }.padding(32).frame(maxHeight: .infinity)
            } else {
                HStack(spacing: 0) {
                    OrbPanel(client: model.openAI)
                    OrbPanel(client: .claudeCode)
                }.padding(.horizontal, 20).padding(.top, 12).frame(maxHeight: .infinity)
                HStack(spacing: 10) {
                    Image(systemName: "waveform.path").foregroundStyle(Theme.muted)
                    Text("流光随观测字节量变化").font(.system(size: 12)).foregroundStyle(Theme.muted)
                }.padding(.bottom, 24)
                VStack(spacing: 16) {
                    HStack {
                        Text("最近 60 秒").font(.system(size: 14, weight: .medium))
                        Spacer()
                        Label("接收", systemImage: "arrow.down").font(.system(size: 11)).foregroundStyle(Theme.muted)
                        Label("发送 · 虚线", systemImage: "arrow.up").font(.system(size: 11)).foregroundStyle(Theme.muted)
                        Button { model.clearHistory() } label: { Image(systemName: "arrow.counterclockwise") }.buttonStyle(.plain).help("清空本地曲线")
                    }
                    TrafficChart(client: model.openAI, height: 45)
                    TrafficChart(client: .claudeCode, height: 45)
                    HStack {
                        Text("60 秒前"); Spacer(); Text("40"); Spacer(); Text("20"); Spacer(); Text("现在")
                    }.font(.system(size: 10, design: .monospaced)).foregroundStyle(Theme.muted)
                }.padding(24).background(.black.opacity(0.12)).overlay(alignment: .top) { Rectangle().fill(.white.opacity(0.09)).frame(height: 1) }
            }
            footer
        }
        .foregroundStyle(Theme.text).background(Theme.background)
        .frame(minWidth: 980, minHeight: 750)
        .sheet(isPresented: $model.showSources) { SourcesView().environmentObject(model) }
    }
    private var header: some View {
        HStack(spacing: 12) {
            Text("潮汐").font(.system(size: 19, weight: .semibold))
            Text("TIDE").font(.system(size: 11, weight: .medium)).tracking(3).foregroundStyle(Theme.muted)
            Spacer()
            HStack(spacing: 3) {
                viewButton("潮汐", selected: !timeline) { timeline = false }
                viewButton("时间线", selected: timeline) { timeline = true }
            }.padding(3).background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 9))
                .overlay { RoundedRectangle(cornerRadius: 9).strokeBorder(.white.opacity(0.08), lineWidth: 0.7) }
            Spacer()
            Circle().fill(model.paused || model.stale ? Theme.muted : model.sample?.error != nil ? Theme.copper : Theme.jade).frame(width: 5, height: 5)
            Text(model.paused ? "已暂停" : model.stale ? "等待刷新" : model.sample == nil ? "连接系统中" : model.sample?.error != nil ? "采集异常" : "系统实测")
                .font(.system(size: 11)).foregroundStyle(Theme.muted)
            Button { model.togglePause() } label: { Image(systemName: model.paused ? "play.fill" : "pause.fill") }
                .buttonStyle(.plain).frame(width: 24).help(model.paused ? "恢复采集" : "暂停采集").accessibilityLabel(model.paused ? "恢复采集" : "暂停采集")
            Button { model.showSources = true } label: { Image(systemName: "slider.horizontal.3") }
                .buttonStyle(.plain).frame(width: 24).help("数据来源与进程身份").accessibilityLabel("数据来源与进程身份")
        }.padding(.leading, 82).padding(.trailing, 24).frame(height: 58)
    }
    private func viewButton(_ label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label).font(.system(size: 12, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? Theme.text : Theme.muted).frame(width: 73, height: 28)
                .background(.white.opacity(selected ? 0.10 : 0), in: RoundedRectangle(cornerRadius: 6))
        }.buttonStyle(.plain)
    }
    private var footer: some View {
        HStack(spacing: 8) {
            Text("macOS nettop").fontWeight(.medium)
            Text("·  TCP / UDP  ·  含本地连接  ·  非 token 统计")
            Spacer()
            Button("查看真实来源") { model.showSources = true }.buttonStyle(.plain).foregroundStyle(Theme.text)
        }.font(.system(size: 10)).foregroundStyle(Theme.muted).padding(.horizontal, 26).frame(height: 36)
        .overlay(alignment: .top) { Rectangle().fill(.white.opacity(0.08)).frame(height: 1) }
    }
}

struct OrbPanel: View {
    @EnvironmentObject var model: TideModel
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    let client: Client
    private var summary: ClientSummary { model.summary(client) }
    var body: some View {
        VStack(spacing: 9) {
            GeometryReader { geometry in
                let diameter = min(geometry.size.height - 12, geometry.size.width * 0.69)
                let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
                ZStack {
                    if let artwork = MaterialBundle.image(client == .claudeCode ? "copper" : "jade") {
                    Image(nsImage: artwork)
                        .resizable().interpolation(.high).scaledToFit().frame(width: diameter, height: diameter)
                        .saturation(summary.received == nil ? 0.55 : 0.9)
                        .opacity(summary.received == nil ? 0.48 : 0.9)
                        .position(center)
                    } else {
                        Label("素材未加载 · 请重新安装完整应用", systemImage: "exclamationmark.triangle")
                            .font(.system(size: 12)).foregroundStyle(Theme.copper).position(center)
                    }
                    TimelineView(.animation(minimumInterval: 1 / 24, paused: reduceMotion || model.paused || ((summary.received ?? 0) + (summary.sent ?? 0) == 0))) { timeline in
                        Canvas { context, size in
                            let time = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
                            drawStream(&context, center: center, radius: diameter * 0.47, size: size, rate: summary.received ?? 0, incoming: true, time: time)
                            drawStream(&context, center: center, radius: diameter * 0.47, size: size, rate: summary.sent ?? 0, incoming: false, time: time)
                        }
                    }.accessibilityHidden(true)
                }
            }.frame(minHeight: 230, maxHeight: 350).clipped()
            HStack(spacing: 7) {
                Text(Theme.name(client)).font(.system(size: 27, weight: .medium))
                if client != .claudeCode {
                    Menu { Button("Codex · App / CLI") { model.openAI = .codex }; Button("ChatGPT") { model.openAI = .chatGPT } } label: { Image(systemName: "chevron.down").font(.system(size: 11)) }.menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 20)
                }
            }
            HStack(spacing: 20) {
                metric("arrow.down", summary.received)
                Rectangle().fill(.white.opacity(0.15)).frame(width: 1, height: 15)
                metric("arrow.up", summary.sent)
            }.padding(.top, 6)
            Text(summary.status).font(.system(size: 11)).foregroundStyle(Theme.muted).padding(.top, 5)
            if client == .codex {
                Text("App / CLI 按 PID 计量，入口关系见来源").font(.system(size: 10)).foregroundStyle(Theme.muted)
            } else {
                Text(client == .claudeCode ? "仅计入已核验的原生客户端" : "独立 ChatGPT 客户端").font(.system(size: 10)).foregroundStyle(Theme.muted)
            }
        }.padding(.bottom, 20).frame(maxWidth: .infinity)
    }
    private func metric(_ icon: String, _ value: Double?) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon).foregroundStyle(Theme.color(client))
            Text(Theme.rate(value)).monospacedDigit().foregroundStyle(Theme.text)
        }.font(.system(size: 17, weight: .regular, design: .monospaced))
    }
    private func drawStream(_ context: inout GraphicsContext, center: CGPoint, radius: Double, size: CGSize, rate: Double, incoming: Bool, time: Double) {
        guard rate > 0 else { return }
        let intensity = min(1, log1p(rate) / log1p(256 * 1024))
        let count = max(2, Int(24 * intensity))
        let travel = min(90, center.x - radius - 8)
        guard travel > 0 else { return }
        for i in 0..<count {
            let phase = (time * (0.35 + intensity * 0.6) + Double(i) / Double(count)).truncatingRemainder(dividingBy: 1)
            let progress = incoming ? 1 - phase : phase
            let x = incoming ? center.x - radius - progress * travel : center.x + radius + progress * travel
            let lane = sin(Double(i) * 8.17) * (8 + progress * 17)
            let y = center.y + lane + sin(progress * .pi) * 8
            let alpha = (1 - progress) * (0.4 + intensity * 0.5)
            let path = Path(ellipseIn: CGRect(x: x, y: y, width: 1.2 + intensity, height: 1.2 + intensity))
            context.fill(path, with: .color(Theme.color(client).opacity(alpha)))
        }
        for i in 0..<3 {
            let phase = (time * 0.32 + Double(i) / 3).truncatingRemainder(dividingBy: 1)
            let width = radius * (1.4 + phase * 1.1)
            let rect = CGRect(x: center.x - width / 2, y: center.y + radius * 0.91 - width * 0.055, width: width, height: width * 0.11)
            context.stroke(Path(ellipseIn: rect), with: .color(Theme.color(client).opacity((1 - phase) * intensity * 0.18)), lineWidth: 0.7)
        }
    }
}

struct TrafficChart: View {
    @EnvironmentObject var model: TideModel
    let client: Client
    let height: CGFloat
    var body: some View {
        let points = model.histories[client] ?? []
        let maxValue = max(1024, points.flatMap { [$0.received ?? 0, $0.sent ?? 0] }.max() ?? 0)
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle().fill(Theme.color(client)).frame(width: 5, height: 5)
                Text(Theme.name(client)).foregroundStyle(Theme.muted)
                Spacer()
                Text("纵轴上限 " + Theme.rate(maxValue)).foregroundStyle(Theme.muted)
            }.font(.system(size: 10))
            Canvas { context, size in
                let end = model.paused ? (points.last?.date ?? Date()) : Date()
                for column in 0...6 {
                    let x = size.width * CGFloat(column) / 6
                    var line = Path(); line.move(to: .init(x: x, y: 0)); line.addLine(to: .init(x: x, y: size.height))
                    context.stroke(line, with: .color(.white.opacity(0.045)), style: StrokeStyle(lineWidth: 1, dash: [2, 4]))
                }
                var baseline = Path(); baseline.move(to: .init(x: 0, y: size.height - 1)); baseline.addLine(to: .init(x: size.width, y: size.height - 1))
                context.stroke(baseline, with: .color(.white.opacity(0.12)), lineWidth: 0.7)
                for incoming in [true, false] {
                    var path = Path(); var connected = false; var lastDate: Date?
                    for point in points {
                        let x = size.width * (1 - end.timeIntervalSince(point.date) / 60)
                        guard let value = incoming ? point.received : point.sent, x >= 0 else { connected = false; lastDate = nil; continue }
                        let p = CGPoint(x: x, y: size.height - 2 - (size.height - 5) * min(1, value / maxValue))
                        if connected, let lastDate, point.date.timeIntervalSince(lastDate) < 4 { path.addLine(to: p) }
                        else { path.move(to: p) }
                        connected = true; lastDate = point.date
                    }
                    context.stroke(path, with: .color(Theme.color(client).opacity(incoming ? 0.95 : 0.55)), style: StrokeStyle(lineWidth: incoming ? 1.4 : 1, lineCap: .round, dash: incoming ? [] : [3, 3]))
                }
            }.frame(height: height).accessibilityLabel("\(Theme.name(client)) 最近一分钟实际收发速率曲线")
        }
    }
}

struct SourcesView: View {
    @EnvironmentObject var model: TideModel
    @Environment(\.dismiss) var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("真实来源").font(.system(size: 24, weight: .semibold))
                    Text("系统字节计数 + 运行中进程签名；不按域名猜测客户端。").foregroundStyle(Theme.muted)
                }
                Spacer(); Button("完成") { dismiss() }.buttonStyle(TideButtonStyle()).keyboardShortcut(.defaultAction)
            }
            if let error = model.sample?.error {
                Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(Theme.copper).textSelection(.enabled)
            }
            HStack {
                Text("PID").frame(width: 64, alignment: .leading)
                Text("客户端 / 已核验标识").frame(width: 240, alignment: .leading)
                Text("当前来源关系").frame(maxWidth: .infinity, alignment: .leading)
                Text("收 / 发").frame(width: 175, alignment: .trailing)
            }.font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.muted)
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(model.sample?.readings ?? [], id: \.identity.pid) { row in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(alignment: .top) {
                                Text(String(row.identity.pid)).monospaced().frame(width: 64, alignment: .leading)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(Theme.name(row.identity.client)).foregroundStyle(Theme.color(row.identity.client))
                                    Text(row.identity.signingID).font(.system(size: 10, design: .monospaced)).foregroundStyle(Theme.muted)
                                }.frame(width: 240, alignment: .leading)
                                Text(row.origin).font(.system(size: 11)).frame(maxWidth: .infinity, alignment: .leading)
                                VStack(alignment: .trailing, spacing: 3) {
                                    Text(Theme.rate(model.paused || model.stale ? nil : row.receivedPerSecond) + " / " + Theme.rate(model.paused || model.stale ? nil : row.sentPerSecond)).font(.system(size: 10, design: .monospaced))
                                    Text(row.state).font(.system(size: 10)).foregroundStyle(Theme.muted)
                                }.frame(width: 175, alignment: .trailing)
                            }
                            Text(row.identity.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                                .font(.system(size: 9, design: .monospaced)).foregroundStyle(Theme.muted).lineLimit(2).textSelection(.enabled)
                        }
                    }
                    if model.sample?.readings.isEmpty != false {
                        Text("尚无可展示的已核验客户端。请启动 Codex、Claude Code 或独立 ChatGPT 客户端。若已启动，可能是当前版本的签名标识未被支持。").foregroundStyle(Theme.muted).padding(.vertical, 30)
                    }
                }
            }
            Divider()
            Text("范围：同一用户的已核验 TCP/UDP 进程，包含本地与后台流量。首样本仅建立基线；短命进程或采样间结束的连接可能漏计；计数器回退会重新建立基线。代理后端的流量不反向归给 AI 客户端。网络字节不代表模型请求、token、费用或思考状态。")
                .font(.system(size: 11)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
            HStack {
                Text("\(model.sample?.source ?? "等待系统采样") · 采集耗时 \(String(format: "%.0f", (model.sample?.duration ?? 0) * 1000)) ms").font(.system(size: 10)).foregroundStyle(Theme.muted)
                Spacer(); Button("导出诊断…") { model.export() }.buttonStyle(TideButtonStyle()).disabled(model.sample == nil)
            }
        }.padding(28).frame(width: 900, height: 650).foregroundStyle(Theme.text).background(Theme.background)
    }
}

struct MiniView: View {
    @EnvironmentObject var model: TideModel
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack { Text("潮汐").font(.system(size: 16, weight: .semibold)); Spacer(); Text(model.paused ? "已暂停" : model.stale ? "等待刷新" : model.sample == nil ? "连接系统中" : model.sample?.error != nil ? "采集异常" : "系统实测").font(.system(size: 10)).foregroundStyle(model.sample?.error != nil ? Theme.copper : Theme.muted) }
            ForEach([model.openAI, .claudeCode], id: \.rawValue) { client in
                HStack {
                    Circle().fill(Theme.color(client)).frame(width: 6, height: 6)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(Theme.name(client))
                        Text(model.summary(client).status).font(.system(size: 9)).foregroundStyle(Theme.muted)
                    }; Spacer()
                    VStack(alignment: .trailing, spacing: 3) {
                        Text("↓ " + Theme.rate(model.summary(client).received))
                        Text("↑ " + Theme.rate(model.summary(client).sent)).foregroundStyle(Theme.muted)
                    }.font(.system(size: 11, design: .monospaced))
                }
            }
            Text("macOS nettop · 含本地连接 · 非 token 统计").font(.system(size: 9)).foregroundStyle(Theme.muted)
            Divider()
            HStack {
                Button("打开潮汐") { openWindow(id: "tide"); NSApp.activate(ignoringOtherApps: true) }
                Spacer(); Button(model.paused ? "继续" : "暂停") { model.togglePause() }
                Button("退出") { NSApp.terminate(nil) }
            }.font(.system(size: 11)).buttonStyle(TideButtonStyle())
        }.padding(20).frame(width: 330).background(Theme.background).foregroundStyle(Theme.text)
    }
}
