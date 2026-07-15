import AppKit
import ApplicationServices
import CoreGraphics
import SwiftUI
import TransomKit

struct ContentView: View {
    @StateObject private var probe = ProbeModel()
    @StateObject private var geometry = GeometryModel()

    @State private var displays: [DisplayInfo] = []
    @State private var apps: [TargetApp] = []
    @State private var selectedAppPID: pid_t = 0
    @State private var selectedDisplayID: CGDirectDisplayID = 0

    // Permissions, refreshed on a slow timer so the UI is live.
    @State private var screenRecording = false
    @State private var accessibility = false
    private let identity = CodeIdentity.current()
    private let permTimer = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                permissionsSection
                Divider()
                displaysSection
                Divider()
                liveProbeSection
                Divider()
                geometrySection
            }
            .padding(20)
        }
        .onAppear(perform: refreshAll)
        .onReceive(permTimer) { _ in refreshPermissions() }
    }

    // MARK: - 1. Permissions

    private var permissionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Permissions").font(.title2).bold()
            HStack(spacing: 24) {
                statusPill("Screen Recording", screenRecording)
                statusPill("Accessibility", accessibility)
            }
            HStack {
                Button("Open Screen Recording settings") {
                    open("x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
                }
                Button("Open Accessibility settings") {
                    open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
                }
                Button("Refresh", action: refreshPermissions)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("This app's TCC identity (which identity holds the grant):")
                    .font(.caption).foregroundStyle(.secondary)
                Text("bundle id:  \(identity.identifier ?? "—")")
                    .font(.system(.caption, design: .monospaced))
                Text("cdhash:     \(identity.cdhash ?? "—")\(identity.isAdHoc ? "  (AD-HOC — TCC will re-prompt every build)" : "")")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(identity.isAdHoc ? Color.orange : Color.secondary)
            }
            .padding(8)
            .background(Color.secondary.opacity(0.08))
            .cornerRadius(6)
        }
    }

    private func statusPill(_ label: String, _ ok: Bool) -> some View {
        HStack(spacing: 6) {
            Circle().fill(ok ? Color.green : Color.red).frame(width: 10, height: 10)
            Text(label)
            Text(ok ? "granted" : "NOT granted").foregroundStyle(.secondary)
        }
    }

    // MARK: - 2. Displays

    private var displaysSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Displays").font(.title2).bold()
                Button("Refresh", action: refreshAll)
            }
            ForEach(displays, id: \.id) { d in
                Text(
                    "id \(d.id)\(d.isMain ? "  [main]" : "")   "
                        + "\(d.pixelWidth)x\(d.pixelHeight) px   "
                        + "\(Int(d.sizePoints.width))x\(Int(d.sizePoints.height)) pt   "
                        + "scale \(String(format: "%.2f", d.scale))x"
                )
                .font(.system(.body, design: .monospaced))
            }
        }
    }

    // MARK: - 3. Live probe (the important one)

    private var liveProbeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Live probe  ·  OQ-1").font(.title2).bold()
            Text("Pick an app + display, Start, then open the app's menus. Watch whether the menu appears in the capture and whether AX draws a rect (orange) around it.")
                .font(.caption).foregroundStyle(.secondary)

            HStack {
                Picker("App", selection: $selectedAppPID) {
                    Text("—").tag(pid_t(0))
                    ForEach(apps, id: \.pid) { Text($0.name).tag($0.pid) }
                }.frame(width: 260)
                Picker("Display", selection: $selectedDisplayID) {
                    Text("—").tag(CGDirectDisplayID(0))
                    ForEach(displays, id: \.id) {
                        Text("\($0.id)\($0.isMain ? " (main)" : "")").tag($0.id)
                    }
                }.frame(width: 160)
                Button("Reload apps") { apps = AppResolver.runningApps() }
                if probe.running {
                    Button("Stop") { probe.stop() }
                } else {
                    Button("Start", action: startProbe)
                        .disabled(selectedAppPID == 0 || selectedDisplayID == 0)
                }
            }

            if let err = probe.lastError {
                Text(err).foregroundStyle(.red).font(.caption)
            }
            Text(probe.statsLine).font(.system(.caption, design: .monospaced))

            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Rectangle().fill(Color.black.opacity(0.85))
                    if let img = probe.frameImage {
                        Image(nsImage: img).resizable().scaledToFit()
                    } else {
                        Text(probe.running ? "waiting for frames…" : "not running")
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
                .frame(height: 360)
                .frame(maxWidth: .infinity)
                .cornerRadius(6)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Event log").font(.headline)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 1) {
                            ForEach(probe.events) { e in
                                Text(String(format: "%7.2f  %@  %@", e.t, e.kind, e.detail))
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(color(for: e.kind))
                            }
                        }
                    }
                }
                .frame(width: 320, height: 360)
            }
        }
    }

    private func color(for kind: String) -> Color {
        switch kind {
        case "menu-opened": return .orange
        case "window-created": return .green
        case "destroyed", "menu-closed": return .secondary
        case "error": return .red
        default: return .primary
        }
    }

    // MARK: - 4. Geometry test

    private var geometrySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Geometry test  ·  OQ-2").font(.title2).bold()
            Text("Set a window's position/size via AX, read it back, and compare. The delta is the answer (I-4).")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Picker("Window", selection: $geometry.windowIndex) {
                    ForEach(geometry.windows, id: \.index) {
                        Text("[\($0.index)] \($0.title.isEmpty ? $0.role : $0.title)").tag($0.index)
                    }
                }.frame(width: 320)
                Button("Reload windows") { geometry.reload(pid: selectedAppPID) }
            }
            HStack {
                field("x", $geometry.x)
                field("y", $geometry.y)
                field("w", $geometry.w)
                field("h", $geometry.h)
                Button("Apply") { geometry.apply(pid: selectedAppPID) }
                    .disabled(selectedAppPID == 0 || geometry.windows.isEmpty)
            }
            if let r = geometry.result {
                Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 2) {
                    GridRow {
                        Text("").font(.caption)
                        Text("requested").font(.caption).bold()
                        Text("actual").font(.caption).bold()
                        Text("delta").font(.caption).bold()
                    }
                    GridRow {
                        Text("pos").font(.system(.caption, design: .monospaced))
                        Text("(\(i(r.requestedPosition.x)),\(i(r.requestedPosition.y)))")
                            .font(.system(.caption, design: .monospaced))
                        Text(r.actualPosition.map { "(\(i($0.x)),\(i($0.y)))" } ?? "—")
                            .font(.system(.caption, design: .monospaced))
                        Text(r.positionDelta.map { "(\(i($0.x)),\(i($0.y)))" } ?? "—")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(deltaColor(r.positionDelta.map { $0 == .zero } ?? false))
                    }
                    GridRow {
                        Text("size").font(.system(.caption, design: .monospaced))
                        Text("\(i(r.requestedSize.width))x\(i(r.requestedSize.height))")
                            .font(.system(.caption, design: .monospaced))
                        Text(r.actualSize.map { "\(i($0.width))x\(i($0.height))" } ?? "—")
                            .font(.system(.caption, design: .monospaced))
                        Text(r.sizeDelta.map { "\(i($0.width))x\(i($0.height))" } ?? "—")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(deltaColor(r.sizeDelta.map { $0 == .zero } ?? false))
                    }
                }
                Text("OQ-2: honored exactly? \(r.exact ? "YES" : "NO — clamped/rounded")")
                    .font(.caption).bold()
                    .foregroundStyle(r.exact ? Color.green : Color.orange)
            }
        }
    }

    private func field(_ label: String, _ binding: Binding<String>) -> some View {
        HStack(spacing: 4) {
            Text(label)
            TextField(label, text: binding).frame(width: 70)
        }
    }

    private func deltaColor(_ exact: Bool) -> Color { exact ? .green : .orange }
    private func i(_ v: CGFloat) -> Int { Int(v.rounded()) }

    // MARK: - actions

    private func refreshAll() {
        displays = Displays.all()
        apps = AppResolver.runningApps()
        if selectedDisplayID == 0 {
            selectedDisplayID = displays.first(where: { $0.isMain })?.id ?? displays.first?.id ?? 0
        }
        refreshPermissions()
    }

    private func refreshPermissions() {
        screenRecording = CGPreflightScreenCaptureAccess()
        accessibility = AXIsProcessTrusted()
    }

    private func startProbe() {
        guard let app = apps.first(where: { $0.pid == selectedAppPID }),
            let disp = displays.first(where: { $0.id == selectedDisplayID })
        else { return }
        geometry.reload(pid: app.pid)
        probe.start(app: app, display: disp)
    }

    private func open(_ urlString: String) {
        if let url = URL(string: urlString) { NSWorkspace.shared.open(url) }
    }
}

/// Backing model for the geometry test. Kept tiny: resolve windows, apply a
/// placement, publish the read-back result.
@MainActor
final class GeometryModel: ObservableObject {
    @Published var windows: [AXWindowInfo] = []
    @Published var windowIndex: Int = 0
    @Published var x = "100"
    @Published var y = "100"
    @Published var w = "1280"
    @Published var h = "800"
    @Published var result: PlacementResult?

    func reload(pid: pid_t) {
        guard pid != 0 else { windows = []; return }
        windows = AXWindow.windows(pid: pid).map { $0.info() }
        if !windows.contains(where: { $0.index == windowIndex }) {
            windowIndex = windows.first?.index ?? 0
        }
    }

    func apply(pid: pid_t) {
        let all = AXWindow.windows(pid: pid)
        guard windowIndex >= 0, windowIndex < all.count else { return }
        let pos = CGPoint(x: Double(x) ?? 0, y: Double(y) ?? 0)
        let size = CGSize(width: Double(w) ?? 0, height: Double(h) ?? 0)
        result = all[windowIndex].place(position: pos, size: size)
    }
}
