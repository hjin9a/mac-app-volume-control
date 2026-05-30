import AppKit
import CoreAudio
import Foundation
import SwiftUI

@main
@MainActor
struct AppVolumeGlassMain {
    private static let delegate = AppDelegate()

    static func main() {
        guard #available(macOS 14.2, *) else {
            fatalError("AppVolumeGlass requires macOS 14.2 or newer.")
        }

        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.delegate = delegate
        app.run()
    }
}

@MainActor
@available(macOS 14.2, *)
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private let model = AudioMixerModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        model.onMenuBarIconChange = { [weak self] choice in
            self?.statusItem.button?.image = makeMenuBarIcon(choice)
        }

        if let button = statusItem.button {
            button.image = makeMenuBarIcon(model.selectedMenuBarIcon)
            button.imagePosition = .imageOnly
            button.title = ""
            button.action = #selector(togglePopover)
            button.target = self
        }

        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        popover.contentSize = NSSize(width: 340, height: 430)
        let appAppearance = NSAppearance(named: .aqua)
        popover.appearance = appAppearance
        let hostingController = NSHostingController(rootView: MixerPopoverView(model: model))
        hostingController.view.wantsLayer = true
        hostingController.view.layer?.backgroundColor = NSColor.clear.cgColor
        hostingController.view.appearance = appAppearance
        popover.contentViewController = hostingController

        model.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.stopAll()
    }

    @objc @MainActor private func togglePopover() {
        guard let button = statusItem.button else {
            return
        }

        if popover.isShown {
            popover.performClose(nil)
        } else {
            model.refresh()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

enum MenuBarIconChoice: String, CaseIterable, Identifiable {
    case hachiware
    case chiikawa
    case usagi

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .hachiware:
            return "hachiware"
        case .chiikawa:
            return "chiikawa"
        case .usagi:
            return "usagi"
        }
    }

    var resourceName: String {
        switch self {
        case .hachiware:
            return "MenuBarIcon"
        case .chiikawa:
            return "MenuBarIconChiikawa"
        case .usagi:
            return "MenuBarIconUsagi"
        }
    }

    var footerIconSize: CGSize {
        switch self {
        case .hachiware:
            return CGSize(width: 15.5, height: 14)
        case .chiikawa:
            return CGSize(width: 16.5, height: 13.9)
        case .usagi:
            return CGSize(width: 15.2, height: 14.2)
        }
    }

    var footerIconYOffset: CGFloat {
        switch self {
        case .hachiware:
            return 0
        case .chiikawa:
            return 0.2
        case .usagi:
            return -0.2
        }
    }
}

func makeMenuBarIcon(_ choice: MenuBarIconChoice) -> NSImage {
    let data = menuBarIconURL(for: choice)
        .flatMap { try? Data(contentsOf: $0) }
    let image = data.flatMap(NSImage.init(data:)) ?? NSImage(size: NSSize(width: 18, height: 16))
    image.size = NSSize(width: 18, height: 16)
    image.isTemplate = true
    image.accessibilityDescription = "AppVolumeGlass"
    return image
}

func menuBarIconURL(for choice: MenuBarIconChoice) -> URL? {
    let fileName = "\(choice.resourceName).svg"
    let bundleName = "AppVolumeGlass_AppVolumeGlass.bundle"
    let candidates: [URL?] = [
        Bundle.main.resourceURL?
            .appendingPathComponent(bundleName)
            .appendingPathComponent(fileName),
        Bundle.main.executableURL?
            .deletingLastPathComponent()
            .appendingPathComponent(bundleName)
            .appendingPathComponent(fileName),
        Bundle.main.executableURL?
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(bundleName)
            .appendingPathComponent(fileName),
    ]

    return candidates.compactMap { $0 }.first { FileManager.default.fileExists(atPath: $0.path) }
}

struct AppAudioProcess: Identifiable, Comparable, Hashable {
    let objectID: AudioObjectID
    let pid: pid_t
    let bundleID: String
    let name: String
    let isRunningOutput: Bool

    var id: String {
        "\(objectID)-\(pid)-\(bundleID)"
    }

    var displayName: String {
        identity.displayName
    }

    var detailName: String {
        identity.detailName
    }

    var iconBundleID: String {
        identity.bundleID
    }

    var identity: AppIdentity {
        AppIdentity(processName: name, bundleID: bundleID, pid: pid)
    }

    static func < (lhs: AppAudioProcess, rhs: AppAudioProcess) -> Bool {
        if lhs.isRunningOutput != rhs.isRunningOutput {
            return lhs.isRunningOutput && !rhs.isRunningOutput
        }
        return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
    }
}

struct AudioOutputDevice: Identifiable, Comparable, Hashable {
    let objectID: AudioObjectID
    let uid: String
    let name: String
    let isDefault: Bool

    var id: String {
        uid
    }

    var displayName: String {
        isDefault ? "\(name) (Default)" : name
    }

    static func < (lhs: AudioOutputDevice, rhs: AudioOutputDevice) -> Bool {
        if lhs.isDefault != rhs.isDefault {
            return lhs.isDefault && !rhs.isDefault
        }
        return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }
}

struct AppIdentity: Hashable {
    let displayName: String
    let bundleID: String
    let detailName: String

    init(processName: String, bundleID: String, pid: pid_t) {
        let rawName = processName.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackName = rawName.isEmpty ? (bundleID.isEmpty ? "pid \(pid)" : bundleID) : rawName
        let lowerName = fallbackName.lowercased()

        if bundleID.hasPrefix("com.google.Chrome") || lowerName.contains("chrome") {
            self.displayName = "Chrome"
            self.bundleID = "com.google.Chrome"
        } else if bundleID == "com.apple.Safari" || lowerName.contains("safari") {
            self.displayName = "Safari"
            self.bundleID = "com.apple.Safari"
        } else if bundleID.hasPrefix("com.hnc.Discord") || lowerName.contains("discord") {
            self.displayName = "Discord"
            self.bundleID = "com.hnc.Discord"
        } else if bundleID.hasPrefix("com.spotify.client") || lowerName.contains("spotify") {
            self.displayName = "Spotify"
            self.bundleID = "com.spotify.client"
        } else if bundleID.hasPrefix("com.valvesoftware.steam") || lowerName.contains("steam") {
            self.displayName = "Steam"
            self.bundleID = "com.valvesoftware.steam"
        } else if bundleID.hasPrefix("notion.id") || lowerName.contains("notion") {
            self.displayName = "Notion"
            self.bundleID = "notion.id"
        } else if bundleID.hasPrefix("com.figma.Desktop") || lowerName.contains("figma") {
            self.displayName = "Figma"
            self.bundleID = "com.figma.Desktop"
        } else if bundleID.hasPrefix("com.kakao.KakaoTalkMac") || lowerName.contains("kakao") || lowerName.contains("카카오") {
            self.displayName = "KakaoTalk"
            self.bundleID = "com.kakao.KakaoTalkMac"
        } else {
            self.displayName = fallbackName
            self.bundleID = bundleID
        }

        if bundleID.isEmpty {
            self.detailName = "pid \(pid)"
        } else if bundleID == self.bundleID {
            self.detailName = bundleID
        } else {
            self.detailName = "\(bundleID) · pid \(pid)"
        }
    }
}

@available(macOS 14.2, *)
@MainActor
final class AudioMixerModel: ObservableObject {
    @Published private(set) var processes: [AppAudioProcess] = []
    @Published private(set) var outputDevices: [AudioOutputDevice] = []
    @Published private(set) var selectedOutputDeviceID = ""
    @Published private(set) var selectedMenuBarIcon: MenuBarIconChoice
    @Published private(set) var statusText = "Ready"
    @Published var showIdleApps = false

    var onMenuBarIconChange: ((MenuBarIconChoice) -> Void)?

    private var volumes: [String: Double] = [:]
    private var controllers: [String: DuckedTap] = [:]
    private var timer: Timer?
    private let menuBarIconDefaultsKey = "selectedMenuBarIcon"

    init() {
        let savedIcon = UserDefaults.standard.string(forKey: menuBarIconDefaultsKey)
        selectedMenuBarIcon = savedIcon.flatMap(MenuBarIconChoice.init(rawValue:)) ?? .hachiware
    }

    var visibleProcesses: [AppAudioProcess] {
        let filtered = showIdleApps ? processes : processes.filter(\.isRunningOutput)
        return filtered.filter { !$0.bundleID.contains("AppVolumeGlass") }
    }

    func start() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    func refresh() {
        do {
            let devices = try audioOutputDevices()
            outputDevices = devices
            reconcileSelectedOutputDevice(with: devices)

            processes = try audioProcesses()
            statusText = "\(visibleProcesses.count) apps visible"
            stopControllersForMissingProcesses()
        } catch {
            statusText = shortError(error)
        }
    }

    func volume(for process: AppAudioProcess) -> Double {
        volumes[process.id] ?? 1
    }

    func setVolume(_ value: Double, for process: AppAudioProcess) {
        let clamped = min(max(value, 0), 1)
        volumes[process.id] = clamped

        do {
            if clamped >= 0.995 {
                controllers[process.id]?.stop()
                controllers[process.id] = nil
                statusText = "\(process.displayName) back to 100%"
                return
            }

            if let controller = controllers[process.id] {
                controller.gain = Float(clamped)
            } else {
                let controller = try makeController(for: process, gain: Float(clamped))
                try controller.start()
                controllers[process.id] = controller
                validateCapture(for: process, controller: controller)
            }

            statusText = "\(process.displayName) \(Int(clamped * 100))%"
        } catch {
            volumes[process.id] = 1
            controllers[process.id]?.stop()
            controllers[process.id] = nil
            statusText = shortError(error)
        }
    }

    func reset(_ process: AppAudioProcess) {
        setVolume(1, for: process)
    }

    func selectOutputDevice(_ id: String) {
        guard selectedOutputDeviceID != id else {
            return
        }

        guard let device = outputDevices.first(where: { $0.id == id }) else {
            statusText = "Output device not found"
            return
        }

        do {
            try setDefaultOutputDevice(device.objectID)
            selectedOutputDeviceID = id
            outputDevices = try audioOutputDevices()
            restartActiveControllers()
            statusText = "Output: \(device.name)"
        } catch {
            statusText = shortError(error)
            refresh()
        }
    }

    func selectMenuBarIcon(_ choice: MenuBarIconChoice) {
        guard selectedMenuBarIcon != choice else {
            return
        }

        selectedMenuBarIcon = choice
        UserDefaults.standard.set(choice.rawValue, forKey: menuBarIconDefaultsKey)
        onMenuBarIconChange?(choice)
    }

    func stopAll() {
        for controller in controllers.values {
            controller.stop()
        }
        controllers.removeAll()
        volumes.removeAll()
        statusText = "All apps reset"
    }

    func quit() {
        stopAll()
        NSApp.terminate(nil)
    }

    private var selectedOutputDevice: AudioOutputDevice? {
        outputDevices.first { $0.id == selectedOutputDeviceID } ?? outputDevices.first
    }

    private func reconcileSelectedOutputDevice(with devices: [AudioOutputDevice]) {
        if devices.contains(where: { $0.id == selectedOutputDeviceID }) {
            return
        }

        selectedOutputDeviceID = devices.first(where: \.isDefault)?.id ?? devices.first?.id ?? ""
    }

    private func makeController(for process: AppAudioProcess, gain: Float) throws -> DuckedTap {
        guard let outputDevice = selectedOutputDevice else {
            throw NSError(
                domain: "AppVolumeGlass",
                code: 4,
                userInfo: [NSLocalizedDescriptionKey: "No output device is available."]
            )
        }

        return try DuckedTap(process: process, gain: gain, outputDevice: outputDevice)
    }

    private func restartActiveControllers() {
        for controller in controllers.values {
            controller.stop()
        }
        controllers.removeAll()

        for process in processes {
            let currentVolume = volume(for: process)
            guard currentVolume < 0.995 else {
                continue
            }

            do {
                let controller = try makeController(for: process, gain: Float(currentVolume))
                try controller.start()
                controllers[process.id] = controller
                validateCapture(for: process, controller: controller)
            } catch {
                volumes[process.id] = 1
                statusText = shortError(error)
            }
        }
    }

    private func stopControllersForMissingProcesses() {
        let currentIDs = Set(processes.map(\.id))
        for id in controllers.keys where !currentIDs.contains(id) {
            controllers[id]?.stop()
            controllers[id] = nil
            volumes[id] = nil
        }
    }

    private func validateCapture(for process: AppAudioProcess, controller: DuckedTap) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self, weak controller] in
            guard let self, let controller else {
                return
            }

            guard self.controllers[process.id] === controller else {
                return
            }

            if !controller.hasObservedAudio {
                controller.stop()
                self.controllers[process.id] = nil
                self.volumes[process.id] = 1
                self.statusText = "No captured audio. Grant Screen & System Audio Recording, then relaunch."
            }
        }
    }
}

struct MixerPopoverView: View {
    @ObservedObject var model: AudioMixerModel
    @State private var isShowingResetConfirmation = false

    var body: some View {
        ZStack {
            Color.clear

            VStack(spacing: 12) {
                header
                    .padding(.horizontal, 6)

                appList

                footer
                    .padding(.horizontal, 6)
            }
            .padding(14)
        }
        .frame(width: 340, height: 430)
        .alert("Reset all volumes?", isPresented: $isShowingResetConfirmation) {
            Button("Reset", role: .destructive) {
                model.stopAll()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Every app volume will return to 100%.")
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Sound")
                    .font(.system(size: 14, weight: .semibold))
                    .adaptiveGlassText()
                Text(model.statusText)
                    .font(.caption)
                    .adaptiveGlassText(opacity: 0.72)
                    .lineLimit(1)
            }

            Spacer()

            HStack(spacing: 8) {
                OutputDeviceMenu(model: model)
            }
        }
    }

    private var appList: some View {
        AppListView(model: model)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "speaker.slash")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(.secondary)
            Text("No active audio apps")
                .font(.headline)
            Text("Start audio in Chrome, Discord, or another app, then refresh.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 58)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Toggle(
                isOn: Binding(
                    get: { model.showIdleApps },
                    set: { model.showIdleApps = $0 }
                )
            ) {
                Text("All apps")
                    .adaptiveGlassText(opacity: 0.72)
            }
            .toggleStyle(.switch)
            .font(.caption)
            .help("Show apps even when they are not currently playing audio")

            Spacer(minLength: 8)

            HStack(spacing: 14) {
                MenuBarIconMenu(model: model)

                FooterIconButton(systemName: "arrow.counterclockwise", help: "Reset all app volumes") {
                    isShowingResetConfirmation = true
                }

                FooterIconButton(systemName: "power", help: "Quit AppVolumeGlass") {
                    model.quit()
                }
            }
        }
        .frame(height: 32)
    }
}

struct MenuBarIconMenu: View {
    @ObservedObject var model: AudioMixerModel

    var body: some View {
        Menu {
            Button {
                model.selectMenuBarIcon(.hachiware)
            } label: {
                if model.selectedMenuBarIcon == .hachiware {
                    Label("hachiware", systemImage: "checkmark")
                } else {
                    Text("hachiware")
                }
            }

            Button {
                model.selectMenuBarIcon(.chiikawa)
            } label: {
                if model.selectedMenuBarIcon == .chiikawa {
                    Label("chiikawa", systemImage: "checkmark")
                } else {
                    Text("chiikawa")
                }
            }

            Button {
                model.selectMenuBarIcon(.usagi)
            } label: {
                if model.selectedMenuBarIcon == .usagi {
                    Label("usagi", systemImage: "checkmark")
                } else {
                    Text("usagi")
                }
            }
        } label: {
            let iconChoice = model.selectedMenuBarIcon
            Image(nsImage: makeMenuBarIcon(model.selectedMenuBarIcon))
                .resizable()
                .scaledToFit()
                .frame(width: iconChoice.footerIconSize.width, height: iconChoice.footerIconSize.height)
                .offset(y: iconChoice.footerIconYOffset)
                .frame(width: 28, height: 28)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassCircleSurface()
        .adaptiveGlassText(opacity: 0.88)
        .help("Choose menu bar icon")
    }
}

struct OutputDeviceMenu: View {
    @ObservedObject var model: AudioMixerModel

    var body: some View {
        Menu {
            if model.outputDevices.isEmpty {
                Text("No outputs")
            } else {
                ForEach(model.outputDevices) { device in
                    Button {
                        model.selectOutputDevice(device.id)
                    } label: {
                        if device.id == model.selectedOutputDeviceID {
                            Label(device.displayName, systemImage: "checkmark")
                        } else {
                            Text(device.displayName)
                        }
                    }
                }
            }
        } label: {
            Image(systemName: "speaker.wave.2.fill")
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 28, height: 28)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassCircleSurface()
        .adaptiveGlassText(opacity: 0.88)
        .help("Choose output device")
    }
}

struct AppListView: View {
    @ObservedObject var model: AudioMixerModel
    @State private var showScrollToTop = false

    var body: some View {
        ScrollViewReader { proxy in
            ZStack(alignment: .bottom) {
                ScrollView {
                    Color.clear
                        .frame(height: 0)
                        .id("app-list-top")

                    LazyVStack(spacing: 10) {
                        if model.visibleProcesses.isEmpty {
                            emptyState
                        } else {
                            ForEach(model.visibleProcesses) { process in
                                ProcessVolumeRow(
                                    process: process,
                                    value: Binding(
                                        get: { model.volume(for: process) },
                                        set: { model.setVolume($0, for: process) }
                                    )
                                )
                                .onAppear {
                                    updateScrollToTopButton(for: process, isVisible: true)
                                }
                                .onDisappear {
                                    updateScrollToTopButton(for: process, isVisible: false)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
                .scrollIndicators(.never)

                if showScrollToTop {
                    GlassCircleButton(systemName: "chevron.up", help: "Scroll to top") {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo("app-list-top", anchor: .top)
                        }
                    }
                    .padding(.bottom, 4)
                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "speaker.slash")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(.secondary)
            Text("No active audio apps")
                .font(.headline)
            Text("Start audio in Chrome, Discord, or another app, then refresh.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 58)
    }

    private func updateScrollToTopButton(for process: AppAudioProcess, isVisible: Bool) {
        guard process.id == model.visibleProcesses.first?.id else {
            return
        }

        withAnimation(.easeOut(duration: 0.14)) {
            showScrollToTop = !isVisible && model.visibleProcesses.count > 4
        }
    }
}

struct GlassCircleButton: View {
    let systemName: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .bold))
                .frame(width: 30, height: 30)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassCircleSurface()
        .adaptiveGlassText(opacity: 0.88)
        .help(help)
    }
}

struct FooterIconButton: View {
    let systemName: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 28, height: 28)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassCircleSurface()
        .adaptiveGlassText(opacity: 0.88)
        .help(help)
    }
}

struct ProcessVolumeRow: View {
    let process: AppAudioProcess
    @Binding var value: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(process.displayName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)

            HStack(spacing: 10) {
                AppIcon(process: process)
                    .frame(width: 20, height: 20)

                Slider(value: $value, in: 0...1)
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(.white.opacity(0.18), lineWidth: 0.6)
        }
    }
}

struct AppIcon: View {
    let process: AppAudioProcess

    var body: some View {
        Image(nsImage: icon())
            .resizable()
            .scaledToFit()
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
    }

    private func icon() -> NSImage {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: process.iconBundleID) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }

        if let app = NSRunningApplication(processIdentifier: process.pid),
           let url = app.bundleURL {
            return NSWorkspace.shared.icon(forFile: url.path)
        }

        return NSImage(systemSymbolName: "app.dashed", accessibilityDescription: nil) ?? NSImage()
    }
}

struct GlassSurface<Content: View>: View {
    var cornerRadius: CGFloat = 24
    var interactive = false
    @ViewBuilder let content: Content

    var body: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: 12) {
                let glass = interactive ? Glass.regular.interactive() : Glass.regular
                content
                    .glassEffect(glass, in: .rect(cornerRadius: cornerRadius))
            }
        } else {
            content
                .background(.thickMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(.white.opacity(0.16), lineWidth: 1)
                }
        }
    }
}

struct GlassIconButton: View {
    let systemName: String
    let help: String
    let action: () -> Void

    var body: some View {
        if #available(macOS 26.0, *) {
            Button(action: action) {
                Image(systemName: systemName)
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.glass)
            .controlSize(.small)
            .help(help)
        } else {
            Button(action: action) {
                Image(systemName: systemName)
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.borderless)
            .background(.thinMaterial, in: Circle())
            .help(help)
        }
    }
}

extension View {
    func adaptiveGlassText(opacity: Double = 1) -> some View {
        self
            .foregroundStyle(Color.primary.opacity(opacity))
    }

    @ViewBuilder
    func glassCircleSurface() -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular.interactive(), in: Circle())
        } else {
            self
                .background(.regularMaterial, in: Circle())
                .overlay {
                    Circle()
                        .stroke(.white.opacity(0.18), lineWidth: 0.6)
                }
        }
    }

    @ViewBuilder
    func buttonStyleGlassWhenAvailable() -> some View {
        if #available(macOS 26.0, *) {
            self.buttonStyle(.glass)
        } else {
            self.buttonStyle(.bordered)
        }
    }
}

struct CoreAudioFailure: Error, CustomStringConvertible {
    let operation: String
    let status: OSStatus

    var description: String {
        "\(operation) failed: \(status) \(fourCC(status))"
    }
}

func shortError(_ error: Error) -> String {
    if let failure = error as? CoreAudioFailure {
        return failure.description
    }
    return error.localizedDescription
}

func fourCC(_ status: OSStatus) -> String {
    let bigEndian = UInt32(bitPattern: status).bigEndian
    let bytes = [
        UInt8((bigEndian >> 24) & 0xff),
        UInt8((bigEndian >> 16) & 0xff),
        UInt8((bigEndian >> 8) & 0xff),
        UInt8(bigEndian & 0xff),
    ]

    guard bytes.allSatisfy({ $0 >= 32 && $0 <= 126 }) else {
        return ""
    }

    return "'\(String(bytes: bytes, encoding: .ascii) ?? "")'"
}

func check(_ status: OSStatus, _ operation: String) throws {
    guard status == noErr else {
        throw CoreAudioFailure(operation: operation, status: status)
    }
}

func address(
    _ selector: AudioObjectPropertySelector,
    scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(
        mSelector: selector,
        mScope: scope,
        mElement: kAudioObjectPropertyElementMain
    )
}

func objectIDList(
    objectID: AudioObjectID,
    selector: AudioObjectPropertySelector,
    scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
) throws -> [AudioObjectID] {
    var propertyAddress = address(selector, scope: scope)
    var byteCount: UInt32 = 0
    try check(
        AudioObjectGetPropertyDataSize(objectID, &propertyAddress, 0, nil, &byteCount),
        "AudioObjectGetPropertyDataSize(\(selector))"
    )

    guard byteCount > 0 else {
        return []
    }

    let count = Int(byteCount) / MemoryLayout<AudioObjectID>.stride
    var values = [AudioObjectID](repeating: 0, count: count)
    try check(
        AudioObjectGetPropertyData(objectID, &propertyAddress, 0, nil, &byteCount, &values),
        "AudioObjectGetPropertyData(\(selector))"
    )
    return values.filter { $0 != kAudioObjectUnknown }
}

func uint32Property(
    objectID: AudioObjectID,
    selector: AudioObjectPropertySelector,
    scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
) throws -> UInt32 {
    var propertyAddress = address(selector, scope: scope)
    var byteCount = UInt32(MemoryLayout<UInt32>.stride)
    var value: UInt32 = 0
    try check(
        AudioObjectGetPropertyData(objectID, &propertyAddress, 0, nil, &byteCount, &value),
        "AudioObjectGetPropertyData(\(selector))"
    )
    return value
}

func audioObjectIDProperty(
    objectID: AudioObjectID,
    selector: AudioObjectPropertySelector,
    scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
) throws -> AudioObjectID {
    var propertyAddress = address(selector, scope: scope)
    var byteCount = UInt32(MemoryLayout<AudioObjectID>.stride)
    var value = AudioObjectID(kAudioObjectUnknown)
    try check(
        AudioObjectGetPropertyData(objectID, &propertyAddress, 0, nil, &byteCount, &value),
        "AudioObjectGetPropertyData(\(selector))"
    )
    return value
}

func setAudioObjectIDProperty(
    objectID: AudioObjectID,
    selector: AudioObjectPropertySelector,
    value: AudioObjectID,
    scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
) throws {
    var propertyAddress = address(selector, scope: scope)
    var mutableValue = value
    let byteCount = UInt32(MemoryLayout<AudioObjectID>.stride)
    try check(
        AudioObjectSetPropertyData(objectID, &propertyAddress, 0, nil, byteCount, &mutableValue),
        "AudioObjectSetPropertyData(\(selector))"
    )
}

func pidProperty(objectID: AudioObjectID) throws -> pid_t {
    var propertyAddress = address(kAudioProcessPropertyPID)
    var byteCount = UInt32(MemoryLayout<pid_t>.stride)
    var value: pid_t = 0
    try check(
        AudioObjectGetPropertyData(objectID, &propertyAddress, 0, nil, &byteCount, &value),
        "AudioObjectGetPropertyData(kAudioProcessPropertyPID)"
    )
    return value
}

func stringProperty(objectID: AudioObjectID, selector: AudioObjectPropertySelector) -> String? {
    var propertyAddress = address(selector)
    var byteCount = UInt32(MemoryLayout<CFString?>.stride)
    var value: CFString?

    let status = withUnsafeMutablePointer(to: &value) { pointer in
        AudioObjectGetPropertyData(objectID, &propertyAddress, 0, nil, &byteCount, pointer)
    }

    guard status == noErr else {
        return nil
    }

    return value as String?
}

func runningName(pid: pid_t, bundleID: String) -> String {
    guard let app = NSRunningApplication(processIdentifier: pid) else {
        return bundleID.isEmpty ? "pid \(pid)" : bundleID
    }

    if let name = app.localizedName, !name.isEmpty {
        return name
    }

    return app.bundleURL?.deletingPathExtension().lastPathComponent
        ?? (bundleID.isEmpty ? "pid \(pid)" : bundleID)
}

func audioProcesses() throws -> [AppAudioProcess] {
    let ids = try objectIDList(
        objectID: AudioObjectID(kAudioObjectSystemObject),
        selector: kAudioHardwarePropertyProcessObjectList
    )

    return ids.compactMap { objectID in
        do {
            let pid = try pidProperty(objectID: objectID)
            let bundleID = stringProperty(objectID: objectID, selector: kAudioProcessPropertyBundleID) ?? ""
            let runningOutput = try uint32Property(
                objectID: objectID,
                selector: kAudioProcessPropertyIsRunningOutput
            ) != 0

            return AppAudioProcess(
                objectID: objectID,
                pid: pid,
                bundleID: bundleID,
                name: runningName(pid: pid, bundleID: bundleID),
                isRunningOutput: runningOutput
            )
        } catch {
            return nil
        }
    }
    .sorted()
}

func audioOutputDevices() throws -> [AudioOutputDevice] {
    let defaultOutputID = try? audioObjectIDProperty(
        objectID: AudioObjectID(kAudioObjectSystemObject),
        selector: kAudioHardwarePropertyDefaultOutputDevice
    )
    let deviceIDs = try objectIDList(
        objectID: AudioObjectID(kAudioObjectSystemObject),
        selector: kAudioHardwarePropertyDevices
    )

    return deviceIDs.compactMap { objectID in
        guard hasOutputChannels(objectID: objectID),
              let uid = stringProperty(objectID: objectID, selector: kAudioDevicePropertyDeviceUID) else {
            return nil
        }

        let name = stringProperty(objectID: objectID, selector: kAudioObjectPropertyName) ?? uid
        return AudioOutputDevice(
            objectID: objectID,
            uid: uid,
            name: name,
            isDefault: objectID == defaultOutputID
        )
    }
    .sorted()
}

func setDefaultOutputDevice(_ objectID: AudioObjectID) throws {
    try setAudioObjectIDProperty(
        objectID: AudioObjectID(kAudioObjectSystemObject),
        selector: kAudioHardwarePropertyDefaultOutputDevice,
        value: objectID
    )

    try? setAudioObjectIDProperty(
        objectID: AudioObjectID(kAudioObjectSystemObject),
        selector: kAudioHardwarePropertyDefaultSystemOutputDevice,
        value: objectID
    )
}

func hasOutputChannels(objectID: AudioObjectID) -> Bool {
    var propertyAddress = address(
        kAudioDevicePropertyStreamConfiguration,
        scope: kAudioDevicePropertyScopeOutput
    )
    var byteCount: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(objectID, &propertyAddress, 0, nil, &byteCount) == noErr,
          byteCount > 0 else {
        return false
    }

    let data = UnsafeMutableRawPointer.allocate(byteCount: Int(byteCount), alignment: MemoryLayout<AudioBufferList>.alignment)
    defer {
        data.deallocate()
    }

    guard AudioObjectGetPropertyData(objectID, &propertyAddress, 0, nil, &byteCount, data) == noErr else {
        return false
    }

    let bufferList = data.assumingMemoryBound(to: AudioBufferList.self)
    return UnsafeMutableAudioBufferListPointer(bufferList).contains { buffer in
        buffer.mNumberChannels > 0
    }
}

final class GainBox {
    var value: Float
    var callbackCount: UInt64 = 0
    var nonSilentSampleCount: UInt64 = 0

    init(_ value: Float) {
        self.value = value
    }
}

@available(macOS 14.2, *)
final class DuckedTap {
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?
    private let gainBox: GainBox
    private let process: AppAudioProcess

    var gain: Float {
        get { gainBox.value }
        set { gainBox.value = max(0, min(newValue, 1)) }
    }

    var hasObservedAudio: Bool {
        gainBox.nonSilentSampleCount > 0
    }

    init(process: AppAudioProcess, gain: Float, outputDevice: AudioOutputDevice) throws {
        self.process = process
        self.gainBox = GainBox(max(0, min(gain, 1)))

        let description = CATapDescription(stereoMixdownOfProcesses: [process.objectID])
        description.name = "AppVolumeGlass \(process.displayName)"
        description.uuid = UUID()
        description.isPrivate = true
        description.muteBehavior = .mutedWhenTapped

        var newTapID = AudioObjectID(kAudioObjectUnknown)
        try check(
            AudioHardwareCreateProcessTap(description, &newTapID),
            "AudioHardwareCreateProcessTap"
        )
        tapID = newTapID

        let tapUID = description.uuid.uuidString
        let outputUID = outputDevice.uid

        let aggregateDescription: [String: Any] = [
            kAudioAggregateDeviceNameKey: "AppVolumeGlass \(outputDevice.name)",
            kAudioAggregateDeviceUIDKey: "dev.codex.AppVolumeGlass.\(UUID().uuidString)",
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: true,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [
                [
                    kAudioSubDeviceUIDKey: outputUID,
                    kAudioSubDeviceDriftCompensationKey: false,
                ],
            ],
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceClockDeviceKey: outputUID,
            kAudioAggregateDeviceTapListKey: [
                [
                    kAudioSubTapUIDKey: tapUID,
                    kAudioSubTapDriftCompensationKey: true,
                ],
            ],
        ]

        var newAggregateID = AudioObjectID(kAudioObjectUnknown)
        try check(
            AudioHardwareCreateAggregateDevice(aggregateDescription as CFDictionary, &newAggregateID),
            "AudioHardwareCreateAggregateDevice"
        )
        aggregateID = newAggregateID

        var newIOProcID: AudioDeviceIOProcID?
        let gainBox = self.gainBox
        try check(
            AudioDeviceCreateIOProcIDWithBlock(&newIOProcID, newAggregateID, nil) {
                _, inputData, _, outputData, _ in
                mapAndCopyAudio(inputData: inputData, outputData: outputData, gainBox: gainBox)
            },
            "AudioDeviceCreateIOProcIDWithBlock"
        )
        ioProcID = newIOProcID
    }

    deinit {
        stop()
    }

    func start() throws {
        guard let ioProcID else {
            return
        }
        try check(AudioDeviceStart(aggregateID, ioProcID), "AudioDeviceStart")
    }

    func stop() {
        if let ioProcID, aggregateID != kAudioObjectUnknown {
            _ = AudioDeviceStop(aggregateID, ioProcID)
            _ = AudioDeviceDestroyIOProcID(aggregateID, ioProcID)
            self.ioProcID = nil
        }

        if aggregateID != kAudioObjectUnknown {
            _ = AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = AudioObjectID(kAudioObjectUnknown)
        }

        if tapID != kAudioObjectUnknown {
            _ = AudioHardwareDestroyProcessTap(tapID)
            tapID = AudioObjectID(kAudioObjectUnknown)
        }
    }
}

@available(macOS 14.2, *)
func tapUIDString(tapID: AudioObjectID) throws -> String {
    guard let tapUID = stringProperty(objectID: tapID, selector: kAudioTapPropertyUID) else {
        throw NSError(
            domain: "AppVolumeGlass",
            code: 4,
            userInfo: [NSLocalizedDescriptionKey: "Could not read tap UID."]
        )
    }
    return tapUID
}

func mapAndCopyAudio(
    inputData: UnsafePointer<AudioBufferList>?,
    outputData: UnsafeMutablePointer<AudioBufferList>?,
    gainBox: GainBox
) {
    guard let inputData, let outputData else {
        return
    }

    gainBox.callbackCount &+= 1
    let gain = gainBox.value
    let inputBuffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inputData))
    let outputBuffers = UnsafeMutableAudioBufferListPointer(outputData)
    let inputBufferCount = inputBuffers.count
    let outputBufferCount = outputBuffers.count

    for outputIndex in 0..<outputBufferCount {
        let outputBuffer = outputBuffers[outputIndex]
        guard let outputPointer = outputBuffer.mData else {
            continue
        }

        let inputIndex: Int
        if inputBufferCount > outputBufferCount {
            inputIndex = inputBufferCount - outputBufferCount + outputIndex
        } else {
            inputIndex = outputIndex
        }

        guard inputIndex < inputBufferCount else {
            memset(outputPointer, 0, Int(outputBuffer.mDataByteSize))
            continue
        }

        let inputBuffer = inputBuffers[inputIndex]

        guard let inputPointer = inputBuffer.mData,
              outputBuffer.mDataByteSize > 0 else {
            memset(outputPointer, 0, Int(outputBuffer.mDataByteSize))
            continue
        }

        let inputSamples = inputPointer.assumingMemoryBound(to: Float.self)
        let outputSamples = outputPointer.assumingMemoryBound(to: Float.self)
        let inputChannels = max(1, Int(inputBuffer.mNumberChannels))
        let outputChannels = max(1, Int(outputBuffer.mNumberChannels))
        let inputSampleCount = Int(inputBuffer.mDataByteSize) / MemoryLayout<Float>.size
        let outputSampleCount = Int(outputBuffer.mDataByteSize) / MemoryLayout<Float>.size
        let inputFrameCount = inputSampleCount / inputChannels
        let outputFrameCount = outputSampleCount / outputChannels
        let frameCount = min(inputFrameCount, outputFrameCount)

        guard frameCount > 0 else {
            memset(outputPointer, 0, Int(outputBuffer.mDataByteSize))
            continue
        }

        if inputChannels == outputChannels {
            let sampleCount = frameCount * inputChannels
            for sampleIndex in 0..<sampleCount {
                let sample = inputSamples[sampleIndex]
                if sample != 0 {
                    gainBox.nonSilentSampleCount &+= 1
                }
                outputSamples[sampleIndex] = sample * gain
            }
            if sampleCount < outputSampleCount {
                memset(outputSamples.advanced(by: sampleCount), 0, (outputSampleCount - sampleCount) * MemoryLayout<Float>.size)
            }
        } else if inputChannels == 2 && outputChannels > 2 {
            for frame in 0..<frameCount {
                let inBase = frame * 2
                let outBase = frame * outputChannels
                let left = inputSamples[inBase]
                let right = inputSamples[inBase + 1]
                if left != 0 || right != 0 {
                    gainBox.nonSilentSampleCount &+= 1
                }
                for channel in 0..<outputChannels {
                    outputSamples[outBase + channel] = 0
                }
                outputSamples[outBase] = left * gain
                outputSamples[outBase + 1] = right * gain
            }
            let writtenSamples = frameCount * outputChannels
            if writtenSamples < outputSampleCount {
                memset(outputSamples.advanced(by: writtenSamples), 0, (outputSampleCount - writtenSamples) * MemoryLayout<Float>.size)
            }
        } else if inputChannels == 1 && outputChannels > 1 {
            for frame in 0..<frameCount {
                let outBase = frame * outputChannels
                for channel in 0..<outputChannels {
                    outputSamples[outBase + channel] = 0
                }
                let source = inputSamples[frame]
                if source != 0 {
                    gainBox.nonSilentSampleCount &+= 1
                }
                let sample = source * gain
                outputSamples[outBase] = sample
                outputSamples[outBase + 1] = sample
            }
            let writtenSamples = frameCount * outputChannels
            if writtenSamples < outputSampleCount {
                memset(outputSamples.advanced(by: writtenSamples), 0, (outputSampleCount - writtenSamples) * MemoryLayout<Float>.size)
            }
        } else {
            for frame in 0..<frameCount {
                let inBase = frame * inputChannels
                let outBase = frame * outputChannels
                let copiedChannels = min(inputChannels, outputChannels)
                for channel in 0..<copiedChannels {
                    let sample = inputSamples[inBase + channel]
                    if sample != 0 {
                        gainBox.nonSilentSampleCount &+= 1
                    }
                    outputSamples[outBase + channel] = sample * gain
                }
                if copiedChannels < outputChannels {
                    for channel in copiedChannels..<outputChannels {
                        outputSamples[outBase + channel] = 0
                    }
                }
            }
            let writtenSamples = frameCount * outputChannels
            if writtenSamples < outputSampleCount {
                memset(outputSamples.advanced(by: writtenSamples), 0, (outputSampleCount - writtenSamples) * MemoryLayout<Float>.size)
            }
        }
    }
}
