import SwiftUI
import WebKit
import AppKit
import UserNotifications
import UniformTypeIdentifiers
import Carbon
import CryptoKit
import JavaScriptCore

private enum AppKeys {
    static let welcomeShown = "mcv.v1.welcome.shown"
    static let hintLaunchCount = "mcv.v1.hintLaunchCount"
    static let hintsForcedEnabled = "mcv.v1.hintsForcedEnabled"
    static let bookmarks = "mcv.v1.bookmarks"
    static let history = "mcv.v1.history"
    static let downloads = "mcv.v1.downloads"
    static let savedFolders = "mcv.v1.savedFolders"
    static let savedLinks = "mcv.v1.savedLinks"
    static let chromeTheme = "mcv.v1.chromeTheme"
    static let settings = "mcv.v1.settings"
    static let tabSession = "mcv.v1.tabSession"
    static let ollamaModel = "mcv.v1.ollamaModel"
    static let ctrlESuggestionsEnabled = "mcv.v1.ctrlE.suggestionsEnabled"
    static let ctrlEScrollFactor = "mcv.v1.ctrlE.scrollFactor"
    static let ctrlECornerRadius = "mcv.v1.ctrlE.cornerRadius"
    static let securityMode = "mcv.v1.securityMode"
    static let clearOnExitHosts = "mcv.v1.clearOnExitHosts"
    static let secureJavaScriptRules = "mcv.v1.secureJavaScriptRules"
    static let chromeBarGradientEnabled = "mcv.v1.chromeBarGradientEnabled"
    static let chromeBarGradientAnimationEnabled = "mcv.v1.chromeBarGradientAnimationEnabled"
    static let commandAliases = "mcv.v1.commandAliases"
    static let webExtensions = "mcv.v1.webExtensions"
    static let webExtensionPermissionOverrides = "mcv.v1.webExtensionPermissionOverrides"
}

private enum HintLifecycle {
    static let maxLaunchesWithHints = 3
    private static var didRegisterForCurrentProcess = false

    @discardableResult
    static func registerLaunchIfNeeded() -> Int {
        let defaults = UserDefaults.standard
        if !didRegisterForCurrentProcess {
            let current = defaults.integer(forKey: AppKeys.hintLaunchCount)
            defaults.set(current + 1, forKey: AppKeys.hintLaunchCount)
            didRegisterForCurrentProcess = true
        }
        return defaults.integer(forKey: AppKeys.hintLaunchCount)
    }

    static var launchCount: Int {
        UserDefaults.standard.integer(forKey: AppKeys.hintLaunchCount)
    }

    static func shouldShowHints(forceEnabled: Bool) -> Bool {
        forceEnabled || launchCount <= maxLaunchesWithHints
    }

    static var shouldShowHints: Bool {
        shouldShowHints(forceEnabled: UserDefaults.standard.bool(forKey: AppKeys.hintsForcedEnabled))
    }
}

private enum AppSceneIDs {
    static let mainWindow = "main-window"
    static let musicWindow = "music-window"
    static let performanceWindow = "performance-window"
}

private enum BrowserWindowMode {
    case standard
    case music
}

private extension Notification.Name {
    static let mcvChromeThemeDidChange = Notification.Name("mcv.chromeThemeDidChange")
    static let mcvSettingsDidChange = Notification.Name("mcv.settingsDidChange")
    static let mcvSecurityModeDidChange = Notification.Name("mcv.securityModeDidChange")
    static let mcvRequestMusicAction = Notification.Name("mcv.requestMusicAction")
    static let mcvMusicCommand = Notification.Name("mcv.musicCommand")
}

private enum MusicWheelAction: String, CaseIterable, Identifiable {
    case next
    case playlist
    case favorite
    case playPause
    case search
    case focus
    case previous
    case volume

    static let ringOrder: [MusicWheelAction] = [
        .next, .playlist, .favorite, .playPause, .search, .focus, .previous, .volume
    ]

    var id: String { rawValue }

    var title: String {
        switch self {
        case .next: return "Next"
        case .playlist: return "Playlist"
        case .favorite: return "Favorite"
        case .playPause: return "Play / Pause"
        case .search: return "Find"
        case .focus: return "Focus"
        case .previous: return "Previous"
        case .volume: return "Volume"
        }
    }

    var symbolName: String {
        switch self {
        case .next: return "forward.end.fill"
        case .playlist: return "radio"
        case .favorite: return "heart.fill"
        case .playPause: return "playpause.fill"
        case .search: return "magnifyingglass"
        case .focus: return "headphones"
        case .previous: return "backward.end.fill"
        case .volume: return "speaker.wave.2.fill"
        }
    }

    var unitVector: CGVector {
        switch self {
        case .next: return CGVector(dx: 0, dy: -1)
        case .playlist: return CGVector(dx: 0.707, dy: -0.707)
        case .favorite: return CGVector(dx: 1, dy: 0)
        case .playPause: return CGVector(dx: 0.707, dy: 0.707)
        case .search: return CGVector(dx: 0, dy: 1)
        case .focus: return CGVector(dx: -0.707, dy: 0.707)
        case .previous: return CGVector(dx: -1, dy: 0)
        case .volume: return CGVector(dx: -0.707, dy: -0.707)
        }
    }
}

private enum MusicWheelMood: String, CaseIterable {
    case coding
    case trading
    case night
    case resonance

    var title: String {
        switch self {
        case .coding: return "Coding"
        case .trading: return "Trading"
        case .night: return "Night"
        case .resonance: return "Resonance"
        }
    }

    var next: MusicWheelMood {
        switch self {
        case .coding: return .trading
        case .trading: return .night
        case .night: return .resonance
        case .resonance: return .coding
        }
    }
}

private struct MusicWheelNowPlaying {
    var title: String
    var subtitle: String
    var progress: Double
    var artworkURL: String?
    var sourceURL: String?

    static let placeholder = MusicWheelNowPlaying(
        title: "No track",
        subtitle: "Music Wheel",
        progress: 0,
        artworkURL: nil,
        sourceURL: nil
    )
}

private struct ChromeTheme: Codable, Equatable {
    var red: Double
    var green: Double
    var blue: Double
    var intensity: Double

    static let `default` = ChromeTheme(red: 0.18, green: 0.45, blue: 0.90, intensity: 0.55)

    var color: Color {
        Color(red: red, green: green, blue: blue)
    }

    var clamped: ChromeTheme {
        ChromeTheme(
            red: min(max(red, 0.0), 1.0),
            green: min(max(green, 0.0), 1.0),
            blue: min(max(blue, 0.0), 1.0),
            intensity: min(max(intensity, 0.0), 1.5)
        )
    }
}

private enum SearchEngineOption: String, CaseIterable, Codable, Identifiable {
    case duckduckgo
    case google
    case bing
    case yahoo

    var id: String { rawValue }
    var title: String {
        switch self {
        case .duckduckgo: return "DuckDuckGo"
        case .google: return "Google"
        case .bing: return "Bing"
        case .yahoo: return "Yahoo"
        }
    }
}

private enum NewTabStartOption: String, CaseIterable, Codable, Identifiable {
    case startPage
    case blankPage
    case customPage

    var id: String { rawValue }
    var title: String {
        switch self {
        case .startPage: return "Start Page"
        case .blankPage: return "Blank Page"
        case .customPage: return "Selected Page"
        }
    }
}

private enum BrowserLanguageOption: String, CaseIterable, Codable, Identifiable {
    case system
    case english
    case ukrainian
    case russian

    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: return "System"
        case .english: return "English"
        case .ukrainian: return "Ukrainian"
        case .russian: return "Russian"
        }
    }
}

private enum AppearanceThemeOption: String, CaseIterable, Codable, Identifiable {
    case system
    case dark
    case light

    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: return "System"
        case .dark: return "Dark"
        case .light: return "Light"
        }
    }
}

private enum TabStyleOption: String, CaseIterable, Codable, Identifiable {
    case system
    case compact
    case rounded

    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: return "System"
        case .compact: return "Compact"
        case .rounded: return "Rounded"
        }
    }
}

private enum NewTabPositionOption: String, CaseIterable, Codable, Identifiable {
    case end
    case nextToCurrent

    var id: String { rawValue }
    var title: String {
        switch self {
        case .end: return "At End"
        case .nextToCurrent: return "Next to Current"
        }
    }
}

private enum CommandPriorityOption: String, CaseIterable, Codable, Identifiable {
    case commandsFirst
    case searchFirst

    var id: String { rawValue }
    var title: String {
        switch self {
        case .commandsFirst: return "Commands First"
        case .searchFirst: return "Search First"
        }
    }
}

private enum NetworkProfileOption: String, CaseIterable, Codable, Identifiable {
    case system
    case strict
    case relaxed

    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: return "System Default"
        case .strict: return "Strict"
        case .relaxed: return "Relaxed"
        }
    }
}

private enum SecurityModeOption: String, CaseIterable, Codable, Identifiable {
    case classic
    case safe
    case secure

    var id: String { rawValue }

    var title: String {
        switch self {
        case .classic: return "Classic"
        case .safe: return "Safe"
        case .secure: return "Secure"
        }
    }

    var summary: String {
        switch self {
        case .classic:
            return "Default profile with normal storage and no extra request filtering."
        case .safe:
            return "Separate persistent profile with download confirmation and clear-on-exit host list."
        case .secure:
            return "Isolated non-persistent profile with strict network and script restrictions."
        }
    }
}

private enum SecurityModeStore {
    static func current() -> SecurityModeOption {
        let raw = UserDefaults.standard.string(forKey: AppKeys.securityMode)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
        return SecurityModeOption(rawValue: raw) ?? .classic
    }

    @discardableResult
    static func set(_ mode: SecurityModeOption) -> Bool {
        let previous = current()
        guard previous != mode else { return false }
        UserDefaults.standard.set(mode.rawValue, forKey: AppKeys.securityMode)
        NotificationCenter.default.post(
            name: .mcvSecurityModeDidChange,
            object: mode,
            userInfo: [
                "previous": previous.rawValue,
                "current": mode.rawValue
            ]
        )
        return true
    }
}

private enum ClearOnExitStore {
    static func hosts() -> [String] {
        let values = UserDefaults.standard.stringArray(forKey: AppKeys.clearOnExitHosts) ?? []
        return values
            .map { normalizeHost($0) }
            .filter { !$0.isEmpty }
            .sorted()
    }

    static func add(_ rawHost: String) -> String? {
        let host = normalizeHost(rawHost)
        guard !host.isEmpty else { return nil }
        var values = Set(hosts())
        values.insert(host)
        UserDefaults.standard.set(values.sorted(), forKey: AppKeys.clearOnExitHosts)
        return host
    }

    static func remove(_ rawHost: String) -> String? {
        let host = normalizeHost(rawHost)
        guard !host.isEmpty else { return nil }
        var values = Set(hosts())
        guard values.contains(host) else { return nil }
        values.remove(host)
        UserDefaults.standard.set(values.sorted(), forKey: AppKeys.clearOnExitHosts)
        return host
    }

    private static func normalizeHost(_ raw: String) -> String {
        let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !cleaned.isEmpty else { return "" }
        let candidate = cleaned.contains("://") ? cleaned : "https://\(cleaned)"
        if let url = URL(string: candidate), let host = url.host?.trimmingCharacters(in: .whitespacesAndNewlines) {
            return host.lowercased()
        }
        let noPath = cleaned.split(separator: "/").first.map(String.init) ?? cleaned
        return noPath.split(separator: ":").first.map { String($0).lowercased() } ?? ""
    }
}

private enum SecureJavaScriptPolicyStore {
    static func isEnabled(forHost rawHost: String) -> Bool {
        let host = normalizeHost(rawHost)
        guard !host.isEmpty else { return true }
        let rules = UserDefaults.standard.dictionary(forKey: AppKeys.secureJavaScriptRules) as? [String: Bool] ?? [:]
        return rules[host] ?? true
    }

    static func set(enabled: Bool, forHost rawHost: String) -> String? {
        let host = normalizeHost(rawHost)
        guard !host.isEmpty else { return nil }
        var rules = UserDefaults.standard.dictionary(forKey: AppKeys.secureJavaScriptRules) as? [String: Bool] ?? [:]
        if enabled {
            rules.removeValue(forKey: host)
        } else {
            rules[host] = false
        }
        UserDefaults.standard.set(rules, forKey: AppKeys.secureJavaScriptRules)
        return host
    }

    private static func normalizeHost(_ raw: String) -> String {
        let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !cleaned.isEmpty else { return "" }
        let candidate = cleaned.contains("://") ? cleaned : "https://\(cleaned)"
        if let url = URL(string: candidate), let host = url.host?.trimmingCharacters(in: .whitespacesAndNewlines) {
            return host.lowercased()
        }
        let noPath = cleaned.split(separator: "/").first.map(String.init) ?? cleaned
        return noPath.split(separator: ":").first.map { String($0).lowercased() } ?? ""
    }
}

private enum SecurityProfileRuntime {
    private static let safeProfileIdentifier = UUID(uuidString: "8F87F56B-A999-41E3-BD30-6553A2F1E5A5") ?? UUID()
    private static let classicProcessPool = WKProcessPool()
    private static let safeProcessPool = WKProcessPool()
    private static let secureProcessPool = WKProcessPool()

    static let secureDataStore = WKWebsiteDataStore.nonPersistent()

    static func websiteDataStore(for mode: SecurityModeOption) -> WKWebsiteDataStore {
        switch mode {
        case .classic:
            return .default()
        case .safe:
            if #available(macOS 14.0, *) {
                return WKWebsiteDataStore(forIdentifier: safeProfileIdentifier)
            }
            return .default()
        case .secure:
            return secureDataStore
        }
    }

    static func processPool(for mode: SecurityModeOption) -> WKProcessPool {
        switch mode {
        case .classic:
            return classicProcessPool
        case .safe:
            return safeProcessPool
        case .secure:
            return secureProcessPool
        }
    }

    static func clearAllWebsiteData() {
        let dataTypes = WKWebsiteDataStore.allWebsiteDataTypes()
        let stores: [WKWebsiteDataStore] = [
            WKWebsiteDataStore.default(),
            websiteDataStore(for: .safe),
            secureDataStore
        ]
        var visited: Set<ObjectIdentifier> = []
        for store in stores {
            let id = ObjectIdentifier(store)
            if visited.contains(id) {
                continue
            }
            visited.insert(id)
            store.fetchDataRecords(ofTypes: dataTypes) { records in
                store.removeData(ofTypes: dataTypes, for: records, completionHandler: {})
            }
        }
    }

    static func clearCookies(forHosts hosts: [String], mode: SecurityModeOption) {
        let cleanedHosts = hosts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
        guard !cleanedHosts.isEmpty else { return }

        let store = websiteDataStore(for: mode)
        let types: Set<String> = [WKWebsiteDataTypeCookies]
        store.fetchDataRecords(ofTypes: types) { records in
            let matches = records.filter { record in
                let name = record.displayName.lowercased()
                return cleanedHosts.contains { host in
                    name == host || name.hasSuffix(".\(host)") || host.hasSuffix(".\(name)")
                }
            }
            guard !matches.isEmpty else { return }
            store.removeData(ofTypes: types, for: matches, completionHandler: {})
        }
    }
}

private struct MCVBrowserSettings: Codable, Equatable {
    var defaultSearchEngine: SearchEngineOption
    var newTabStart: NewTabStartOption
    var newTabCustomURL: String
    var restoreTabsOnLaunch: Bool
    var browserLanguage: BrowserLanguageOption
    var downloadsFolderPath: String

    var appearanceTheme: AppearanceThemeOption
    var interfaceTintHex: String
    var interfaceOpacity: Double
    var interfaceBlur: Double
    var tabStyle: TabStyleOption
    var interfaceScale: Double

    var openLinksInNewTab: Bool
    var newTabPosition: NewTabPositionOption
    var closeTabOnDoubleClick: Bool
    var tabWheelEnabled: Bool
    var tabLimit: Int

    var blockTrackers: Bool
    var disableWebRTC: Bool
    var clearDataOnClose: Bool
    var doNotTrack: Bool

    var smartSearchEnabled: Bool
    var commandPriority: CommandPriorityOption
    var ddgBangsEnabled: Bool
    var localLLMEnabled: Bool

    var processLimit: Int
    var unloadInactiveTabs: Bool
    var unloadAfterSeconds: Int
    var energySaver: Bool

    var customCommandsText: String

    var customUserAgent: String
    var developerMode: Bool
    var experimentalFeatures: Bool
    var networkProfile: NetworkProfileOption

    static var `default`: MCVBrowserSettings {
        MCVBrowserSettings(
            defaultSearchEngine: .duckduckgo,
            newTabStart: .startPage,
            newTabCustomURL: "https://duckduckgo.com/",
            restoreTabsOnLaunch: true,
            browserLanguage: .system,
            downloadsFolderPath: (NSSearchPathForDirectoriesInDomains(.downloadsDirectory, .userDomainMask, true).first ?? (NSHomeDirectory() + "/Downloads")),
            appearanceTheme: .system,
            interfaceTintHex: "#2E73E6",
            interfaceOpacity: 1.0,
            interfaceBlur: 0.6,
            tabStyle: .system,
            interfaceScale: 1.0,
            openLinksInNewTab: true,
            newTabPosition: .end,
            closeTabOnDoubleClick: false,
            tabWheelEnabled: true,
            tabLimit: 80,
            blockTrackers: false,
            disableWebRTC: false,
            clearDataOnClose: false,
            doNotTrack: true,
            smartSearchEnabled: true,
            commandPriority: .commandsFirst,
            ddgBangsEnabled: true,
            localLLMEnabled: false,
            processLimit: 8,
            unloadInactiveTabs: true,
            unloadAfterSeconds: 180,
            energySaver: false,
            customCommandsText: "",
            customUserAgent: "",
            developerMode: false,
            experimentalFeatures: true,
            networkProfile: .system
        )
    }
}

private final class MCVSettingsStore: ObservableObject {
    static let shared = MCVSettingsStore()

    @Published private(set) var settings: MCVBrowserSettings = .default
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private init() {
        load()
    }

    func update(_ mutate: (inout MCVBrowserSettings) -> Void) {
        var next = settings
        mutate(&next)
        if next == settings {
            return
        }
        settings = next
        save()
        NotificationCenter.default.post(name: .mcvSettingsDidChange, object: settings)
    }

    func resetToDefaults() {
        settings = .default
        save()
        NotificationCenter.default.post(name: .mcvSettingsDidChange, object: settings)
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: AppKeys.settings),
              let decoded = try? decoder.decode(MCVBrowserSettings.self, from: data) else {
            settings = .default
            return
        }
        settings = decoded
    }

    private func save() {
        guard let data = try? encoder.encode(settings) else { return }
        UserDefaults.standard.set(data, forKey: AppKeys.settings)
    }
}

private enum WebExtensionCompatibilityTier: String, Codable, CaseIterable {
    case a = "A"
    case b = "B"
    case c = "C"

    var title: String { rawValue }
}

private struct WebExtensionInstallRecord: Codable, Identifiable {
    var id: String
    var rootPath: String
    var enabled: Bool
    var installedAt: TimeInterval
    var manifestHash: String
    var customName: String?
}

private struct WebExtensionManifest: Decodable {
    struct ContentScript: Decodable {
        let matches: [String]
        let js: [String]?
        let runAt: String?
        let allFrames: Bool?

        enum CodingKeys: String, CodingKey {
            case matches
            case js
            case runAt = "run_at"
            case allFrames = "all_frames"
        }
    }

    struct Background: Decodable {
        let scripts: [String]?
        let serviceWorker: String?

        enum CodingKeys: String, CodingKey {
            case scripts
            case serviceWorker = "service_worker"
        }
    }

    struct Action: Decodable {
        let defaultPopup: String?

        enum CodingKeys: String, CodingKey {
            case defaultPopup = "default_popup"
        }
    }

    struct OptionsUI: Decodable {
        let page: String?
    }

    let manifestVersion: Int
    let name: String
    let version: String?
    let description: String?
    let permissions: [String]?
    let hostPermissions: [String]?
    let contentScripts: [ContentScript]?
    let background: Background?
    let action: Action?
    let browserAction: Action?
    let optionsPage: String?
    let optionsUI: OptionsUI?

    enum CodingKeys: String, CodingKey {
        case manifestVersion = "manifest_version"
        case name
        case version
        case description
        case permissions
        case hostPermissions = "host_permissions"
        case contentScripts = "content_scripts"
        case background
        case action
        case browserAction = "browser_action"
        case optionsPage = "options_page"
        case optionsUI = "options_ui"
    }
}

private struct WebExtensionContentScriptPlan {
    let scriptKey: String
    let matches: [String]
    let source: String
    let injectionTime: WKUserScriptInjectionTime
    let forMainFrameOnly: Bool
}

private struct WebExtensionBundle: Identifiable {
    let id: String
    let name: String
    let version: String
    let description: String
    let rootURL: URL
    let enabled: Bool
    let tier: WebExtensionCompatibilityTier
    let permissions: Set<String>
    let hostPermissions: [String]
    let popupPath: String?
    let optionsPath: String?
    let backgroundScriptURLs: [URL]
    let contentScripts: [WebExtensionContentScriptPlan]

    var summaryLine: String {
        "\(id) \(enabled ? "on" : "off") tier \(tier.title) \(name) v\(version)"
    }
}

private enum WebExtensionError: LocalizedError {
    case sourceNotFound
    case sourceMustBeFolder
    case manifestMissing
    case manifestInvalid
    case invalidIdentifier
    case invalidDisplayName
    case extensionNotFound
    case copyFailed
    case scriptFileMissing(String)

    var errorDescription: String? {
        switch self {
        case .sourceNotFound:
            return "Path does not exist"
        case .sourceMustBeFolder:
            return "Expected unpacked extension folder"
        case .manifestMissing:
            return "manifest.json not found"
        case .manifestInvalid:
            return "manifest.json is invalid"
        case .invalidIdentifier:
            return "Invalid extension identifier"
        case .invalidDisplayName:
            return "Invalid extension name"
        case .extensionNotFound:
            return "Extension not found"
        case .copyFailed:
            return "Failed to copy extension files"
        case let .scriptFileMissing(name):
            return "Script file missing: \(name)"
        }
    }
}

private func mcvJSONString(from object: Any) -> String? {
    guard JSONSerialization.isValidJSONObject(object),
          let data = try? JSONSerialization.data(withJSONObject: object, options: []) else {
        return nil
    }
    return String(data: data, encoding: .utf8)
}

private func mcvJSONPropertyListSafe(_ value: Any) -> Any? {
    if value is NSNull { return NSNull() }
    if let str = value as? String { return str }
    if let num = value as? NSNumber { return num }
    if let bool = value as? Bool { return bool as NSNumber }
    if let dict = value as? [String: Any] {
        var next: [String: Any] = [:]
        for (key, item) in dict {
            if let safe = mcvJSONPropertyListSafe(item) {
                next[key] = safe
            }
        }
        return next
    }
    if let arr = value as? [Any] {
        return arr.compactMap(mcvJSONPropertyListSafe)
    }
    return nil
}

private final class WebExtensionPermissionGate {
    static let shared = WebExtensionPermissionGate()

    private let defaults = UserDefaults.standard
    private var blockedByExtension: [String: Set<String>] = [:]

    private init() {
        load()
    }

    func load() {
        if let raw = defaults.dictionary(forKey: AppKeys.webExtensionPermissionOverrides) as? [String: [String]] {
            blockedByExtension = raw.mapValues { Set($0.map { $0.lowercased() }) }
        } else {
            blockedByExtension = [:]
        }
    }

    private func save() {
        let encoded = blockedByExtension.mapValues { Array($0).sorted() }
        defaults.set(encoded, forKey: AppKeys.webExtensionPermissionOverrides)
    }

    func grant(permission: String, extensionID: String) {
        let key = permission.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !key.isEmpty else { return }
        var blocked = blockedByExtension[extensionID] ?? []
        blocked.remove(key)
        if blocked.isEmpty {
            blockedByExtension.removeValue(forKey: extensionID)
        } else {
            blockedByExtension[extensionID] = blocked
        }
        save()
    }

    func revoke(permission: String, extensionID: String) {
        let key = permission.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !key.isEmpty else { return }
        var blocked = blockedByExtension[extensionID] ?? []
        blocked.insert(key)
        blockedByExtension[extensionID] = blocked
        save()
    }

    func isOperationAllowed(
        _ op: String,
        bundle: WebExtensionBundle,
        currentURL: URL?
    ) -> Bool {
        let required = requiredPermission(for: op)
        if let required {
            let requiredKey = required.lowercased()
            if blockedByExtension[bundle.id]?.contains(requiredKey) == true {
                return false
            }
            if !bundle.permissions.contains(requiredKey) {
                return false
            }
        }

        if op == "scripting.executeScript" {
            guard let currentURL else { return false }
            return isHostAllowed(url: currentURL, hostPatterns: bundle.hostPermissions)
        }
        return true
    }

    private func requiredPermission(for op: String) -> String? {
        switch op {
        case "tabs.query", "tabs.create":
            return "tabs"
        case "scripting.executeScript":
            return "scripting"
        case "contextMenus.create":
            return "contextmenus"
        case "commands.getAll":
            return "commands"
        case "notifications.create":
            return "notifications"
        default:
            return nil
        }
    }

    private func isHostAllowed(url: URL, hostPatterns: [String]) -> Bool {
        guard let scheme = url.scheme?.lowercased(),
              let host = url.host?.lowercased() else {
            return false
        }
        let path = url.path.isEmpty ? "/" : url.path

        if hostPatterns.isEmpty {
            return scheme == "https" || scheme == "http"
        }

        for pattern in hostPatterns {
            let trimmed = pattern.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if trimmed == "<all_urls>" {
                return true
            }
            guard let schemeSplit = trimmed.split(separator: ":", maxSplits: 1).first else { continue }
            let patternScheme = String(schemeSplit)
            if patternScheme != "*" && patternScheme != scheme {
                continue
            }
            guard let slashesRange = trimmed.range(of: "://") else { continue }
            let afterScheme = trimmed[slashesRange.upperBound...]
            let hostAndPath = afterScheme.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
            guard let patternHostPart = hostAndPath.first else { continue }
            let patternHost = String(patternHostPart)
            let patternPath = hostAndPath.count > 1 ? "/" + hostAndPath[1] : "/*"
            if !matchWildcard(patternHost, value: host) {
                continue
            }
            if matchWildcard(patternPath, value: path) {
                return true
            }
        }
        return false
    }

    private func matchWildcard(_ pattern: String, value: String) -> Bool {
        if pattern == "*" { return true }
        if pattern.hasPrefix("*.") {
            let suffix = String(pattern.dropFirst(2))
            return value == suffix || value.hasSuffix("." + suffix)
        }
        if pattern.contains("*") {
            let escaped = NSRegularExpression.escapedPattern(for: pattern).replacingOccurrences(of: "\\*", with: ".*")
            let regex = "^\(escaped)$"
            return value.range(of: regex, options: .regularExpression) != nil
        }
        return value == pattern
    }
}

private final class WebExtensionStorageStore {
    static let shared = WebExtensionStorageStore()
    private let defaults = UserDefaults.standard

    private init() {}

    private func key(for extensionID: String) -> String {
        "mcv.v1.webext.storage.\(extensionID)"
    }

    private func readStore(extensionID: String) -> [String: Any] {
        defaults.dictionary(forKey: key(for: extensionID)) ?? [:]
    }

    private func writeStore(_ value: [String: Any], extensionID: String) {
        defaults.set(value, forKey: key(for: extensionID))
    }

    func get(extensionID: String, keysPayload: Any?) -> [String: Any] {
        let source = readStore(extensionID: extensionID)
        if keysPayload == nil || keysPayload is NSNull {
            return source
        }
        if let key = keysPayload as? String {
            return [key: source[key] ?? NSNull()]
        }
        if let keys = keysPayload as? [String] {
            var out: [String: Any] = [:]
            for key in keys {
                out[key] = source[key] ?? NSNull()
            }
            return out
        }
        if let defaultsObject = keysPayload as? [String: Any] {
            var out = defaultsObject
            for (key, value) in source {
                out[key] = value
            }
            return out
        }
        return source
    }

    func set(extensionID: String, items: [String: Any]) {
        var source = readStore(extensionID: extensionID)
        for (key, value) in items {
            source[key] = value
        }
        writeStore(source, extensionID: extensionID)
    }

    func remove(extensionID: String, keys: [String]) {
        var source = readStore(extensionID: extensionID)
        for key in keys {
            source.removeValue(forKey: key)
        }
        writeStore(source, extensionID: extensionID)
    }

    func clear(extensionID: String) {
        defaults.removeObject(forKey: key(for: extensionID))
    }
}

private enum WebExtensionBridge {
    static let messageName = "mcvExtBridge"
    static let responseFunction = "__mcvExtNativeResponse"

    static let runtimeShimSource = """
    (() => {
      if (window.__mcvExtShimInstalled) return;
      window.__mcvExtShimInstalled = true;
      const bridgeName = "mcvExtBridge";
      const hasBridge = !!(window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers[bridgeName]);
      const pending = new Map();
      let seq = 0;

      const toError = (value) => value instanceof Error ? value : new Error(String(value || "extension bridge error"));

      const nativeCall = (op, extensionId, payload) => {
        if (!hasBridge) return Promise.reject(new Error("bridge unavailable"));
        const requestId = `mcv-ext-${Date.now()}-${++seq}`;
        return new Promise((resolve, reject) => {
          pending.set(requestId, { resolve, reject, createdAt: Date.now() });
          try {
            window.webkit.messageHandlers[bridgeName].postMessage({
              requestId,
              op,
              extensionId,
              payload: payload ?? null,
              href: String(location.href || "")
            });
          } catch (error) {
            pending.delete(requestId);
            reject(toError(error));
            return;
          }
          setTimeout(() => {
            const item = pending.get(requestId);
            if (!item) return;
            pending.delete(requestId);
            reject(new Error(`bridge timeout for ${op}`));
          }, 10000);
        });
      };

      window.__mcvExtNativeResponse = (packet) => {
        if (!packet || typeof packet !== "object") return;
        const requestId = packet.requestId;
        if (!requestId) return;
        const item = pending.get(requestId);
        if (!item) return;
        pending.delete(requestId);
        if (packet.ok) {
          item.resolve(packet.result);
        } else {
          item.reject(toError(packet.error || "extension bridge failed"));
        }
      };

      const makePatternRegex = (pattern) => {
        const parts = String(pattern || "")
          .split("*")
          .map((part) => part.replace(/[|\\\\{}()[\\]^$+?.]/g, "\\\\$&"));
        return new RegExp(`^${parts.join(".*")}$`);
      };

      window.__mcvMatchExtensionPattern = (pattern, href) => {
        const raw = String(pattern || "").trim();
        if (!raw) return false;
        if (raw === "<all_urls>") return true;
        let parsed;
        try { parsed = new URL(String(href || location.href || "")); } catch (_) { return false; }
        const split = raw.split("://");
        if (split.length !== 2) return false;
        const patternScheme = split[0];
        const right = split[1];
        const slash = right.indexOf("/");
        const patternHost = slash >= 0 ? right.slice(0, slash) : right;
        const patternPath = slash >= 0 ? right.slice(slash) : "/*";
        if (patternScheme !== "*" && parsed.protocol.replace(":", "") !== patternScheme) return false;
        const hostRegex = makePatternRegex(patternHost);
        const pathRegex = makePatternRegex(patternPath);
        return hostRegex.test(parsed.host) && pathRegex.test(parsed.pathname || "/");
      };

      const extensionApiCache = new Map();
      window.__mcvGetChromeForExtension = (extensionId) => {
        const id = String(extensionId || "").trim();
        if (!id) return null;
        if (extensionApiCache.has(id)) return extensionApiCache.get(id);

        const runtimeOnMessageListeners = [];
        const runtimeApi = {
          id,
          getURL(path = "") {
            return `mcv-extension://${id}/${String(path || "").replace(/^\\//, "")}`;
          },
          sendMessage(message, callback) {
            const promise = nativeCall("runtime.sendMessage", id, { message });
            if (typeof callback === "function") {
              promise.then((value) => callback(value)).catch(() => callback(undefined));
              return;
            }
            return promise;
          },
          onMessage: {
            addListener(fn) {
              if (typeof fn === "function") runtimeOnMessageListeners.push(fn);
            },
            removeListener(fn) {
              const index = runtimeOnMessageListeners.indexOf(fn);
              if (index >= 0) runtimeOnMessageListeners.splice(index, 1);
            },
            hasListener(fn) {
              return runtimeOnMessageListeners.includes(fn);
            }
          }
        };

        const storageApi = {
          local: {
            get(keys, callback) {
              const promise = nativeCall("storage.get", id, { keys });
              if (typeof callback === "function") {
                promise.then((value) => callback(value || {})).catch(() => callback({}));
                return;
              }
              return promise;
            },
            set(items, callback) {
              const payload = items && typeof items === "object" ? items : {};
              const promise = nativeCall("storage.set", id, { items: payload }).then(() => undefined);
              if (typeof callback === "function") {
                promise.then(() => callback()).catch(() => callback());
                return;
              }
              return promise;
            },
            remove(keys, callback) {
              const payload = Array.isArray(keys) ? keys : [keys];
              const promise = nativeCall("storage.remove", id, { keys: payload }).then(() => undefined);
              if (typeof callback === "function") {
                promise.then(() => callback()).catch(() => callback());
                return;
              }
              return promise;
            },
            clear(callback) {
              const promise = nativeCall("storage.clear", id, {}).then(() => undefined);
              if (typeof callback === "function") {
                promise.then(() => callback()).catch(() => callback());
                return;
              }
              return promise;
            }
          }
        };

        const tabsApi = {
          query(queryInfo, callback) {
            const promise = nativeCall("tabs.query", id, { queryInfo: queryInfo || {} });
            if (typeof callback === "function") {
              promise.then((value) => callback(Array.isArray(value) ? value : [])).catch(() => callback([]));
              return;
            }
            return promise;
          },
          create(createProperties, callback) {
            const promise = nativeCall("tabs.create", id, { createProperties: createProperties || {} });
            if (typeof callback === "function") {
              promise.then((value) => callback(value || null)).catch(() => callback(null));
              return;
            }
            return promise;
          }
        };

        const scriptingApi = {
          executeScript(details, callback) {
            const promise = nativeCall("scripting.executeScript", id, { details: details || {} });
            if (typeof callback === "function") {
              promise.then((value) => callback(value || [])).catch(() => callback([]));
              return;
            }
            return promise;
          }
        };

        const contextMenusApi = {
          create(createProperties, callback) {
            const promise = nativeCall("contextMenus.create", id, { createProperties: createProperties || {} });
            if (typeof callback === "function") {
              promise.then((value) => callback(value)).catch(() => callback(undefined));
              return;
            }
            return promise;
          }
        };

        const commandsApi = {
          getAll(callback) {
            const promise = nativeCall("commands.getAll", id, {});
            if (typeof callback === "function") {
              promise.then((value) => callback(Array.isArray(value) ? value : [])).catch(() => callback([]));
              return;
            }
            return promise;
          }
        };

        const notificationsApi = {
          create(notificationId, options, callback) {
            const payload = {
              notificationId: typeof notificationId === "string" ? notificationId : "",
              options: options && typeof options === "object" ? options : {}
            };
            const promise = nativeCall("notifications.create", id, payload);
            if (typeof callback === "function") {
              promise.then((value) => callback(value)).catch(() => callback(undefined));
              return;
            }
            return promise;
          }
        };

        const api = {
          runtime: runtimeApi,
          storage: storageApi,
          tabs: tabsApi,
          scripting: scriptingApi,
          contextMenus: contextMenusApi,
          commands: commandsApi,
          notifications: notificationsApi
        };
        extensionApiCache.set(id, api);
        return api;
      };
    })();
    """

    static func wrappedContentScriptSource(
        extensionID: String,
        scriptKey: String,
        matches: [String],
        code: String
    ) -> String {
        let matchesJSON = mcvJSONString(from: matches) ?? "[]"
        let extJSON = mcvJSONString(from: [extensionID]) ?? "[\"unknown\"]"
        let keyJSON = mcvJSONString(from: [scriptKey]) ?? "[\"unknown\"]"
        let extensionLiteral = extJSON.dropFirst().dropLast()
        let keyLiteral = keyJSON.dropFirst().dropLast()

        return """
        (() => {
          try {
            if (typeof window.__mcvGetChromeForExtension !== "function") return;
            if (typeof window.__mcvMatchExtensionPattern !== "function") return;
            const __mcvURL = String(location.href || "");
            const __mcvPatterns = \(matchesJSON);
            const __mcvAllowed = __mcvPatterns.length === 0 || __mcvPatterns.some((pattern) => window.__mcvMatchExtensionPattern(pattern, __mcvURL));
            if (!__mcvAllowed) return;
            if (!window.__mcvInjectedScripts) window.__mcvInjectedScripts = new Set();
            const __mcvKey = \(keyLiteral);
            if (window.__mcvInjectedScripts.has(__mcvKey)) return;
            window.__mcvInjectedScripts.add(__mcvKey);
            const chrome = window.__mcvGetChromeForExtension(\(extensionLiteral));
            const browser = chrome;
            if (!chrome) return;
            \(code)
          } catch (error) {
            console.warn("mcv extension script error", error);
          }
        })();
        """
    }
}

private final class WebExtensionBackgroundRuntime {
    static let shared = WebExtensionBackgroundRuntime()

    private let queue = DispatchQueue(label: "mcv.webext.background", qos: .utility)
    private var contexts: [String: JSContext] = [:]

    private init() {}

    func sync(with bundles: [WebExtensionBundle]) {
        let enabled = bundles.filter { $0.enabled && !$0.backgroundScriptURLs.isEmpty }
        queue.async { [weak self] in
            guard let self else { return }
            let activeIDs = Set(enabled.map(\.id))
            let staleIDs = Set(self.contexts.keys).subtracting(activeIDs)
            for id in staleIDs {
                self.contexts.removeValue(forKey: id)
            }

            for bundle in enabled {
                if self.contexts[bundle.id] != nil {
                    continue
                }
                guard let context = JSContext() else { continue }
                context.name = "mcv.ext.bg.\(bundle.id)"
                context.exceptionHandler = { _, exception in
                    if let message = exception?.toString() {
                        NSLog("webext background exception \(bundle.id): %@", message)
                    }
                }
                let bootstrap = """
                const chrome = {
                  runtime: {
                    id: "\(bundle.id)",
                    sendMessage: (message) => Promise.resolve({ ok: true, message }),
                    onInstalled: { addListener: () => {}, removeListener: () => {} }
                  },
                  storage: {
                    local: {
                      get: () => Promise.resolve({}),
                      set: () => Promise.resolve(),
                      remove: () => Promise.resolve(),
                      clear: () => Promise.resolve()
                    }
                  }
                };
                const browser = chrome;
                """
                context.evaluateScript(bootstrap)

                for scriptURL in bundle.backgroundScriptURLs {
                    guard let code = try? String(contentsOf: scriptURL, encoding: .utf8) else { continue }
                    context.evaluateScript(code)
                }
                self.contexts[bundle.id] = context
            }
        }
    }
}

private final class WebExtensionManager {
    static let shared = WebExtensionManager()

    private let defaults = UserDefaults.standard
    private let fileManager = FileManager.default
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let queue = DispatchQueue(label: "mcv.webext.manager", qos: .userInitiated)

    private var records: [WebExtensionInstallRecord] = []
    private var bundlesByID: [String: WebExtensionBundle] = [:]
    private var orderedIDs: [String] = []

    private init() {
        reload()
    }

    func reload() {
        queue.sync {
            loadRecordsLocked()
            rebuildBundlesLocked()
        }
    }

    func listBundles() -> [WebExtensionBundle] {
        queue.sync {
            orderedIDs.compactMap { bundlesByID[$0] }
        }
    }

    func bundle(id: String) -> WebExtensionBundle? {
        queue.sync { bundlesByID[id] }
    }

    func enabledBundles() -> [WebExtensionBundle] {
        listBundles().filter(\.enabled)
    }

    func listSummary() -> String {
        let bundles = listBundles()
        if bundles.isEmpty {
            return "No extensions installed. Use: ext install <folder|webstore_url|extension_id>"
        }
        let lines = bundles.prefix(8).map(\.summaryLine)
        let suffix = bundles.count > lines.count ? " …" : ""
        return "Extensions \(bundles.count): " + lines.joined(separator: " | ") + suffix
    }

    @discardableResult
    func installUnpackedExtension(from path: String, preferredID: String? = nil) throws -> WebExtensionBundle {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        let expanded = NSString(string: trimmed).expandingTildeInPath
        let sourceURL = URL(fileURLWithPath: expanded, isDirectory: true).standardizedFileURL

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: sourceURL.path, isDirectory: &isDirectory) else {
            throw WebExtensionError.sourceNotFound
        }
        guard isDirectory.boolValue else {
            throw WebExtensionError.sourceMustBeFolder
        }

        let manifestURL = sourceURL.appendingPathComponent("manifest.json")
        guard fileManager.fileExists(atPath: manifestURL.path) else {
            throw WebExtensionError.manifestMissing
        }
        guard let manifestData = try? Data(contentsOf: manifestURL),
              let manifest = try? decoder.decode(WebExtensionManifest.self, from: manifestData) else {
            throw WebExtensionError.manifestInvalid
        }

        let extensionID: String
        if let preferred = preferredID?.trimmingCharacters(in: .whitespacesAndNewlines),
           !preferred.isEmpty {
            guard let normalized = Self.normalizedExternalExtensionID(preferred) else {
                throw WebExtensionError.invalidIdentifier
            }
            extensionID = normalized
        } else {
            extensionID = stableExtensionID(name: manifest.name, sourcePath: sourceURL.path)
        }
        let targetURL = try installationRootURL().appendingPathComponent(extensionID, isDirectory: true)
        do {
            if fileManager.fileExists(atPath: targetURL.path) {
                try fileManager.removeItem(at: targetURL)
            }
            try fileManager.copyItem(at: sourceURL, to: targetURL)
        } catch {
            throw WebExtensionError.copyFailed
        }

        let manifestHash = Self.sha256Hex(of: manifestData)
        queue.sync {
            let existingCustomName = records.first(where: { $0.id == extensionID })?.customName
            let record = WebExtensionInstallRecord(
                id: extensionID,
                rootPath: targetURL.path,
                enabled: true,
                installedAt: Date().timeIntervalSince1970,
                manifestHash: manifestHash,
                customName: existingCustomName
            )
            if let existingIndex = records.firstIndex(where: { $0.id == extensionID }) {
                records[existingIndex] = record
            } else {
                records.append(record)
            }
            saveRecordsLocked()
            rebuildBundlesLocked()
        }
        guard let bundle = bundle(id: extensionID) else {
            throw WebExtensionError.extensionNotFound
        }
        return bundle
    }

    @discardableResult
    func setEnabled(_ enabled: Bool, extensionID: String) -> Bool {
        queue.sync {
            guard let index = records.firstIndex(where: { $0.id == extensionID }) else { return false }
            if records[index].enabled == enabled {
                return true
            }
            records[index].enabled = enabled
            saveRecordsLocked()
            rebuildBundlesLocked()
            return true
        }
    }

    @discardableResult
    func removeExtension(id: String) -> Bool {
        queue.sync {
            guard let index = records.firstIndex(where: { $0.id == id }) else { return false }
            let record = records.remove(at: index)
            try? fileManager.removeItem(at: URL(fileURLWithPath: record.rootPath))
            saveRecordsLocked()
            rebuildBundlesLocked()
            return true
        }
    }

    @discardableResult
    func renameExtension(id: String, customName: String?) throws -> Bool {
        try queue.sync {
            guard let index = records.firstIndex(where: { $0.id == id }) else { return false }
            let normalized = try Self.normalizedDisplayName(customName)
            if records[index].customName == normalized {
                return true
            }
            records[index].customName = normalized
            saveRecordsLocked()
            rebuildBundlesLocked()
            return true
        }
    }

    private func loadRecordsLocked() {
        guard let data = defaults.data(forKey: AppKeys.webExtensions),
              let decoded = try? decoder.decode([WebExtensionInstallRecord].self, from: data) else {
            records = []
            return
        }
        records = decoded
    }

    private func saveRecordsLocked() {
        guard let data = try? encoder.encode(records) else { return }
        defaults.set(data, forKey: AppKeys.webExtensions)
    }

    private func rebuildBundlesLocked() {
        var nextByID: [String: WebExtensionBundle] = [:]
        var nextOrder: [String] = []
        var cleanedRecords: [WebExtensionInstallRecord] = []

        for record in records {
            let rootURL = URL(fileURLWithPath: record.rootPath, isDirectory: true)
            let manifestURL = rootURL.appendingPathComponent("manifest.json")
            guard let data = try? Data(contentsOf: manifestURL),
                  let manifest = try? decoder.decode(WebExtensionManifest.self, from: data),
                  let bundle = try? makeBundle(record: record, manifest: manifest, rootURL: rootURL) else {
                continue
            }
            cleanedRecords.append(record)
            nextOrder.append(record.id)
            nextByID[record.id] = bundle
        }

        records = cleanedRecords
        saveRecordsLocked()
        orderedIDs = nextOrder
        bundlesByID = nextByID
        WebExtensionBackgroundRuntime.shared.sync(with: nextOrder.compactMap { nextByID[$0] })
    }

    private func makeBundle(
        record: WebExtensionInstallRecord,
        manifest: WebExtensionManifest,
        rootURL: URL
    ) throws -> WebExtensionBundle {
        let permissions = Set((manifest.permissions ?? []).map { $0.lowercased() })
        let hostPermissions = manifest.hostPermissions ?? []
        let tier = compatibilityTier(for: manifest)
        let popupPath = manifest.action?.defaultPopup ?? manifest.browserAction?.defaultPopup
        let optionsPath = manifest.optionsPage ?? manifest.optionsUI?.page
        let displayName = record.customName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? record.customName!
            : manifest.name

        let backgroundPaths = (manifest.background?.scripts ?? []) + (manifest.background?.serviceWorker.map { [$0] } ?? [])
        let backgroundURLs = backgroundPaths.map { rootURL.appendingPathComponent($0) }

        var plans: [WebExtensionContentScriptPlan] = []
        if let contentScripts = manifest.contentScripts {
            for (index, entry) in contentScripts.enumerated() {
                let scriptFiles = entry.js ?? []
                if scriptFiles.isEmpty {
                    continue
                }
                var joinedCode = ""
                for path in scriptFiles {
                    let scriptURL = rootURL.appendingPathComponent(path)
                    guard let part = try? String(contentsOf: scriptURL, encoding: .utf8) else {
                        throw WebExtensionError.scriptFileMissing(path)
                    }
                    joinedCode.append(part)
                    joinedCode.append("\n")
                }
                let key = "\(record.id).\(index)"
                let runAt = (entry.runAt ?? "").lowercased()
                let injectionTime: WKUserScriptInjectionTime = (runAt == "document_start") ? .atDocumentStart : .atDocumentEnd
                plans.append(
                    WebExtensionContentScriptPlan(
                        scriptKey: key,
                        matches: entry.matches,
                        source: joinedCode,
                        injectionTime: injectionTime,
                        forMainFrameOnly: !(entry.allFrames ?? false)
                    )
                )
            }
        }

        return WebExtensionBundle(
            id: record.id,
            name: displayName,
            version: manifest.version ?? "1.0",
            description: manifest.description ?? "",
            rootURL: rootURL,
            enabled: record.enabled,
            tier: tier,
            permissions: permissions,
            hostPermissions: hostPermissions,
            popupPath: popupPath,
            optionsPath: optionsPath,
            backgroundScriptURLs: backgroundURLs,
            contentScripts: plans
        )
    }

    private func compatibilityTier(for manifest: WebExtensionManifest) -> WebExtensionCompatibilityTier {
        let permissions = Set((manifest.permissions ?? []).map { $0.lowercased() })
        if permissions.contains("webrequestblocking") || permissions.contains("debugger") || permissions.contains("nativeMessaging".lowercased()) {
            return .c
        }
        if manifest.background != nil || manifest.action != nil || manifest.browserAction != nil {
            return .b
        }
        return .a
    }

    private func installationRootURL() throws -> URL {
        let appSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let root = appSupport.appendingPathComponent("MCV").appendingPathComponent("WebExtensions", isDirectory: true)
        if !fileManager.fileExists(atPath: root.path) {
            try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        }
        return root
    }

    private func stableExtensionID(name: String, sourcePath: String) -> String {
        let seed = name.lowercased() + "::" + sourcePath.lowercased()
        let digest = SHA256.hash(data: Data(seed.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return "ext_" + String(hex.prefix(20))
    }

    private static func sha256Hex(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func normalizedExternalExtensionID(_ raw: String) -> String? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard value.range(of: #"^[a-z0-9_-]{6,64}$"#, options: .regularExpression) != nil else {
            return nil
        }
        return value
    }

    private static func normalizedDisplayName(_ raw: String?) throws -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return nil
        }
        if trimmed.count > 80 {
            throw WebExtensionError.invalidDisplayName
        }
        return trimmed
    }
}

private enum WebStoreInstallError: LocalizedError {
    case invalidExtensionID
    case invalidDownloadURL
    case downloadFailed(String)
    case invalidCRXHeader
    case unsupportedCRXVersion(UInt32)
    case malformedCRX
    case unzipFailed(String)
    case manifestMissing

    var errorDescription: String? {
        switch self {
        case .invalidExtensionID:
            return "Invalid Chrome Web Store extension id"
        case .invalidDownloadURL:
            return "Failed to build CRX download URL"
        case .downloadFailed(let message):
            return "CRX download failed: \(message)"
        case .invalidCRXHeader:
            return "Downloaded file is not a CRX package"
        case .unsupportedCRXVersion(let version):
            return "Unsupported CRX version: \(version)"
        case .malformedCRX:
            return "Malformed CRX package"
        case .unzipFailed(let message):
            return "Failed to unpack CRX: \(message)"
        case .manifestMissing:
            return "manifest.json not found after unpack"
        }
    }
}

private final class WebStoreCRXInstaller {
    static let shared = WebStoreCRXInstaller()

    private let fileManager = FileManager.default

    private init() {}

    static func extractExtensionID(from raw: String) -> String? {
        let input = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return nil }

        if let direct = normalizedExtensionID(input) {
            return direct
        }

        if let url = URL(string: input),
           let host = url.host?.lowercased(),
           host.contains("chromewebstore.google.com") || host.contains("chrome.google.com") {
            for component in url.pathComponents.reversed() {
                if let id = normalizedExtensionID(component) {
                    return id
                }
            }
            if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
               let queryItems = components.queryItems {
                for item in queryItems {
                    if item.name.lowercased() == "id",
                       let value = item.value,
                       let id = normalizedExtensionID(value) {
                        return id
                    }
                }
            }
        }

        let lower = input.lowercased()
        if let range = lower.range(of: #"[a-z]{32}"#, options: .regularExpression) {
            return String(lower[range])
        }
        return nil
    }

    func installFromWebStoreInput(_ raw: String) throws -> WebExtensionBundle {
        guard let extensionID = Self.extractExtensionID(from: raw) else {
            throw WebStoreInstallError.invalidExtensionID
        }

        let workspaceURL = fileManager.temporaryDirectory
            .appendingPathComponent("mcv-webstore-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: workspaceURL, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: workspaceURL) }

        let crxData = try downloadCRXData(extensionID: extensionID)
        let zipData = try extractZIPPayload(from: crxData)

        let zipURL = workspaceURL.appendingPathComponent("\(extensionID).zip")
        try zipData.write(to: zipURL, options: .atomic)

        let unpackedURL = workspaceURL.appendingPathComponent("unpacked", isDirectory: true)
        try unzip(zipURL: zipURL, destinationURL: unpackedURL)

        guard let extensionRoot = resolveExtensionRoot(in: unpackedURL) else {
            throw WebStoreInstallError.manifestMissing
        }

        return try WebExtensionManager.shared.installUnpackedExtension(
            from: extensionRoot.path,
            preferredID: extensionID
        )
    }

    private func downloadCRXData(extensionID: String) throws -> Data {
        var components = URLComponents(string: "https://clients2.google.com/service/update2/crx")
        components?.queryItems = [
            URLQueryItem(name: "response", value: "redirect"),
            URLQueryItem(name: "prodversion", value: "9999.0.0.0"),
            URLQueryItem(name: "acceptformat", value: "crx2,crx3"),
            URLQueryItem(name: "x", value: "id=\(extensionID)&installsource=ondemand&uc")
        ]
        guard let url = components?.url else {
            throw WebStoreInstallError.invalidDownloadURL
        }
        do {
            let data = try Data(contentsOf: url)
            guard !data.isEmpty else {
                throw WebStoreInstallError.downloadFailed("empty response from update service")
            }
            return data
        } catch {
            throw WebStoreInstallError.downloadFailed(error.localizedDescription)
        }
    }

    private func extractZIPPayload(from crxData: Data) throws -> Data {
        let bytes = [UInt8](crxData)
        guard bytes.count >= 12 else {
            throw WebStoreInstallError.malformedCRX
        }
        guard bytes[0] == 0x43, bytes[1] == 0x72, bytes[2] == 0x32, bytes[3] == 0x34 else {
            throw WebStoreInstallError.invalidCRXHeader
        }

        let version = try Self.readUInt32LE(bytes, at: 4)
        let payloadOffset: Int
        switch version {
        case 2:
            let pubLen = Int(try Self.readUInt32LE(bytes, at: 8))
            let sigLen = Int(try Self.readUInt32LE(bytes, at: 12))
            payloadOffset = 16 + pubLen + sigLen
        case 3:
            let headerLen = Int(try Self.readUInt32LE(bytes, at: 8))
            payloadOffset = 12 + headerLen
        default:
            throw WebStoreInstallError.unsupportedCRXVersion(version)
        }

        guard payloadOffset > 0, payloadOffset < bytes.count else {
            throw WebStoreInstallError.malformedCRX
        }
        return Data(bytes[payloadOffset...])
    }

    private func unzip(zipURL: URL, destinationURL: URL) throws {
        if fileManager.fileExists(atPath: destinationURL.path) {
            try? fileManager.removeItem(at: destinationURL)
        }
        try fileManager.createDirectory(at: destinationURL, withIntermediateDirectories: true)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", zipURL.path, destinationURL.path]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
        } catch {
            throw WebStoreInstallError.unzipFailed(error.localizedDescription)
        }

        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? "unknown unzip error"
            throw WebStoreInstallError.unzipFailed(output)
        }
    }

    private func resolveExtensionRoot(in unpackedRoot: URL) -> URL? {
        let directManifest = unpackedRoot.appendingPathComponent("manifest.json")
        if fileManager.fileExists(atPath: directManifest.path) {
            return unpackedRoot
        }

        if let children = try? fileManager.contentsOfDirectory(
            at: unpackedRoot,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) {
            for child in children {
                let manifest = child.appendingPathComponent("manifest.json")
                if fileManager.fileExists(atPath: manifest.path) {
                    return child
                }
            }
        }

        if let enumerator = fileManager.enumerator(
            at: unpackedRoot,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) {
            for case let fileURL as URL in enumerator {
                if fileURL.lastPathComponent.lowercased() == "manifest.json" {
                    return fileURL.deletingLastPathComponent()
                }
            }
        }

        return nil
    }

    private static func normalizedExtensionID(_ raw: String) -> String? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard value.range(of: #"^[a-z]{32}$"#, options: .regularExpression) != nil else {
            return nil
        }
        return value
    }

    private static func readUInt32LE(_ bytes: [UInt8], at offset: Int) throws -> UInt32 {
        guard offset >= 0, offset + 4 <= bytes.count else {
            throw WebStoreInstallError.malformedCRX
        }
        return UInt32(bytes[offset]) |
            (UInt32(bytes[offset + 1]) << 8) |
            (UInt32(bytes[offset + 2]) << 16) |
            (UInt32(bytes[offset + 3]) << 24)
    }
}

private final class AudioFocusCoordinator {
    static let shared = AudioFocusCoordinator()

    private weak var activeWebView: WKWebView?

    private init() {}

    func claim(_ webView: WKWebView) -> WKWebView? {
        if let activeWebView, activeWebView !== webView {
            self.activeWebView = webView
            return activeWebView
        }
        self.activeWebView = webView
        return nil
    }

    func releaseIfCurrent(_ webView: WKWebView) {
        if activeWebView === webView {
            activeWebView = nil
        }
    }
}

private final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?

    init(target: WKScriptMessageHandler) {
        self.target = target
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(userContentController, didReceive: message)
    }
}

private final class MusicWindowCloseDelegate: NSObject, NSWindowDelegate {
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }
}

private final class MusicWindowManager {
    static let shared = MusicWindowManager()

    private weak var musicWindow: NSWindow?
    private var closeDelegate: MusicWindowCloseDelegate?

    private init() {}

    var hasLiveWindow: Bool {
        musicWindow != nil
    }

    func register(_ window: NSWindow) {
        musicWindow = window
        window.isReleasedWhenClosed = false
        if closeDelegate == nil {
            closeDelegate = MusicWindowCloseDelegate()
        }
        if window.delegate !== closeDelegate {
            window.delegate = closeDelegate
        }
    }

    func present(using openWindow: (String) -> Void) {
        if let musicWindow {
            NSApp.activate(ignoringOtherApps: true)
            musicWindow.makeKeyAndOrderFront(nil)
            return
        }
        openWindow(AppSceneIDs.musicWindow)
    }
}

private final class ExtensionWindowCloseDelegate: NSObject, NSWindowDelegate {
    private let onClose: () -> Void

    init(onClose: @escaping () -> Void) {
        self.onClose = onClose
    }

    func windowWillClose(_ notification: Notification) {
        onClose()
    }
}

private final class ExtensionWindowManager {
    static let shared = ExtensionWindowManager()

    private var windows: [UUID: NSWindow] = [:]
    private var closeDelegates: [UUID: ExtensionWindowCloseDelegate] = [:]

    private init() {}

    func present(resourceURL: URL, readAccessURL: URL, title: String) {
        let configuration = WKWebViewConfiguration()
        let controller = WKUserContentController()
        let runtimeScript = WKUserScript(
            source: WebExtensionBridge.runtimeShimSource,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
        controller.addUserScript(runtimeScript)
        configuration.userContentController = controller

        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 980, height: 720), configuration: configuration)
        webView.allowsBackForwardNavigationGestures = true
        if #available(macOS 13.0, *) {
            webView.isInspectable = true
        }
        webView.loadFileURL(resourceURL, allowingReadAccessTo: readAccessURL)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 980, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        let token = UUID()
        let delegate = ExtensionWindowCloseDelegate { [weak self] in
            self?.windows.removeValue(forKey: token)
            self?.closeDelegates.removeValue(forKey: token)
        }

        window.title = title
        window.contentView = webView
        window.isReleasedWhenClosed = false
        window.delegate = delegate
        window.center()

        windows[token] = window
        closeDelegates[token] = delegate

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}

private final class MusicActionDispatchDeduper {
    static let shared = MusicActionDispatchDeduper()

    private var handledRequestIDs: [String: Date] = [:]

    private init() {}

    func claim(_ requestID: String) -> Bool {
        let now = Date()
        handledRequestIDs = handledRequestIDs.filter { now.timeIntervalSince($0.value) < 3.0 }
        if handledRequestIDs[requestID] != nil {
            return false
        }
        handledRequestIDs[requestID] = now
        return true
    }
}

private struct BridgeResponse: Decodable {
    let action: String
    let success: Bool?
    let title: String?
    let message: String?
    let url: String?
    let query: String?
    let index: Int?

    var isSuccess: Bool {
        success ?? true
    }
}

private struct OllamaStatusInfo {
    let isAvailable: Bool
    let binaryPath: String
    let statusText: String
    let installedModels: [String]
}

private struct OllamaGenerateOutput {
    let success: Bool
    let model: String
    let text: String
    let message: String
}

private struct OllamaPullOutput {
    let success: Bool
    let model: String
    let message: String
    let installedModels: [String]
}

private final class CommandHelperClient {
    static let shared = CommandHelperClient()

    private let helperName = "mcv_command_helper"

    private init() {}

    func execute(input: String) -> BridgeResponse? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        guard let helperURL = resolveHelperURL() else { return nil }
        let preparedInput = rewriteAICommandToConfiguredModel(text)

        let process = Process()
        process.executableURL = helperURL
        process.arguments = [preparedInput]

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        do {
            try process.run()
        } catch {
            return nil
        }

        process.waitUntilExit()
        let output = outPipe.fileHandleForReading.readDataToEndOfFile()
        guard !output.isEmpty else { return nil }

        return try? JSONDecoder().decode(BridgeResponse.self, from: output)
    }

    func predictSmartURL(for query: String) -> (url: URL, hits: Int)? {
        let clean = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return nil }
        guard let response = execute(input: "__mcv_smart_predict \(clean)"),
              response.action == "smart_prediction",
              let rawURL = response.url,
              let url = URL(string: rawURL) else {
            return nil
        }
        let hits = max(0, response.index ?? 0)
        return (url, hits)
    }

    func learnSmartMapping(query: String, url: String) {
        let cleanQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanQuery.isEmpty, !cleanURL.isEmpty else { return }
        _ = execute(input: "__mcv_smart_learn \(cleanQuery)\t\(cleanURL)")
    }

    func resolveMusicPlaylistURL(sourceURL: String?, title: String?) -> URL? {
        let safeURL = sanitizeHelperField(sourceURL ?? "")
        let safeTitle = sanitizeHelperField(title ?? "")
        guard let response = execute(input: "__mcv_music_playlist \(safeURL)\t\(safeTitle)"),
              response.action == "navigate",
              let value = response.url,
              let url = URL(string: value) else {
            return nil
        }
        return url
    }

    func resolveMusicFocusQuery(mood: String?) -> String? {
        let normalized = sanitizeHelperField((mood ?? "coding").trimmingCharacters(in: .whitespacesAndNewlines))
        guard let response = execute(input: "__mcv_music_focus \(normalized)"),
              response.action == "music_play" else {
            return nil
        }
        return response.query?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func resolveMusicFindQuery(sourceTitle: String?) -> String? {
        let cleaned = sanitizeHelperField(sourceTitle ?? "")
        guard let response = execute(input: "__mcv_music_find \(cleaned)"),
              response.action == "music_play" else {
            return nil
        }
        return response.query?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func fetchOllamaStatus() -> OllamaStatusInfo {
        guard let response = execute(input: "__mcv_ollama_status"),
              response.action == "ollama_status" else {
            return OllamaStatusInfo(
                isAvailable: false,
                binaryPath: "",
                statusText: "Ollama helper unavailable",
                installedModels: []
            )
        }

        return OllamaStatusInfo(
            isAvailable: response.isSuccess,
            binaryPath: response.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            statusText: response.message?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Ollama unavailable",
            installedModels: parseHelperList(response.query)
        )
    }

    func fetchInstalledOllamaModels() -> [String] {
        guard let response = execute(input: "__mcv_ollama_list"),
              response.action == "ollama_models_installed" else {
            return []
        }
        return parseHelperList(response.query)
    }

    func pullOllamaModel(_ model: String) -> OllamaPullOutput {
        let safeModel = sanitizeHelperField(model)
        guard !safeModel.isEmpty else {
            return OllamaPullOutput(success: false, model: "", message: "Model is required", installedModels: [])
        }

        guard let response = execute(input: "__mcv_ollama_pull \(safeModel)"),
              response.action == "ollama_pull" else {
            return OllamaPullOutput(
                success: false,
                model: safeModel,
                message: "Ollama helper unavailable",
                installedModels: []
            )
        }

        return OllamaPullOutput(
            success: response.isSuccess,
            model: {
                let value = response.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return value.isEmpty ? safeModel : value
            }(),
            message: response.message?.trimmingCharacters(in: .whitespacesAndNewlines) ?? (response.isSuccess ? "Done" : "Failed"),
            installedModels: parseHelperList(response.query)
        )
    }

    func generateLocalAI(prompt: String, model: String) -> OllamaGenerateOutput {
        let safePrompt = sanitizeHelperField(prompt)
        let safeModel = sanitizeHelperField(model)

        guard !safePrompt.isEmpty else {
            return OllamaGenerateOutput(success: false, model: safeModel, text: "", message: "Prompt is empty")
        }

        let response: BridgeResponse?
        if safeModel.isEmpty {
            response = execute(input: "ai \(safePrompt)")
        } else {
            response = execute(input: "__mcv_ollama_generate \(safeModel)\t\(safePrompt)")
        }

        guard let response,
              response.action == "ai_result" else {
            return OllamaGenerateOutput(success: false, model: safeModel, text: "", message: "Ollama helper unavailable")
        }

        let resolvedTitle = response.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let resolvedModel = resolvedTitle.isEmpty ? (safeModel.isEmpty ? "llama3.2:3b" : safeModel) : resolvedTitle
        let payload = response.message ?? ""
        return OllamaGenerateOutput(
            success: response.isSuccess,
            model: resolvedModel,
            text: response.isSuccess ? payload : "",
            message: response.isSuccess ? "ok" : payload
        )
    }

    func generateLocalAIChat(prompt: String, model: String, imagePath: String?) -> OllamaGenerateOutput {
        let safePrompt = sanitizeHelperField(prompt)
        let safeModel = sanitizeHelperField(model)
        let safeImagePath = sanitizeHelperField(imagePath ?? "")

        guard !safePrompt.isEmpty else {
            return OllamaGenerateOutput(success: false, model: safeModel, text: "", message: "Prompt is empty")
        }

        let response: BridgeResponse?
        if safeImagePath.isEmpty {
            if safeModel.isEmpty {
                response = execute(input: "ai \(safePrompt)")
            } else {
                response = execute(input: "__mcv_ollama_generate \(safeModel)\t\(safePrompt)")
            }
        } else {
            let resolvedModel = safeModel.isEmpty ? "llama3.2:3b" : safeModel
            response = execute(input: "__mcv_ollama_chat \(resolvedModel)\t\(safePrompt)\t\(safeImagePath)")
        }

        guard let response,
              response.action == "ai_result" else {
            return OllamaGenerateOutput(success: false, model: safeModel, text: "", message: "Ollama helper unavailable")
        }

        let resolvedTitle = response.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let resolvedModel = resolvedTitle.isEmpty ? (safeModel.isEmpty ? "llama3.2:3b" : safeModel) : resolvedTitle
        let payload = response.message ?? ""
        return OllamaGenerateOutput(
            success: response.isSuccess,
            model: resolvedModel,
            text: response.isSuccess ? payload : "",
            message: response.isSuccess ? "ok" : payload
        )
    }

    private func parseHelperList(_ raw: String?) -> [String] {
        guard let raw else { return [] }
        return raw
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func rewriteAICommandToConfiguredModel(_ input: String) -> String {
        let lower = input.lowercased()
        guard lower == "ai" || lower.hasPrefix("ai ") else {
            return input
        }

        let prompt = String(input.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else {
            return input
        }

        let configuredModel = UserDefaults.standard.string(forKey: AppKeys.ollamaModel)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !configuredModel.isEmpty else {
            return input
        }

        let safeModel = sanitizeHelperField(configuredModel)
        let safePrompt = sanitizeHelperField(prompt)
        return "__mcv_ollama_generate \(safeModel)\t\(safePrompt)"
    }

    private func sanitizeHelperField(_ value: String) -> String {
        value.replacingOccurrences(of: "\t", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func resolveHelperURL() -> URL? {
        let fm = FileManager.default

        if let bundleDir = Bundle.main.executableURL?.deletingLastPathComponent() {
            let bundled = bundleDir.appendingPathComponent(helperName)
            if fm.isExecutableFile(atPath: bundled.path) {
                return bundled
            }
        }

        let local = URL(fileURLWithPath: fm.currentDirectoryPath).appendingPathComponent(helperName)
        if fm.isExecutableFile(atPath: local.path) {
            return local
        }

        return nil
    }
}

private struct MiniQuickTranslateRequest {
    let source: String?
    let target: String
    let text: String
}

private struct MiniAIRequest {
    let prompt: String
}

private func translateLanguageAlias(_ raw: String) -> String? {
    let token = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !token.isEmpty else { return nil }

    let aliases: [String: String] = [
        "auto": "auto",

        "e": "en", "en": "en", "english": "en",
        "f": "fr", "fr": "fr", "french": "fr",
        "r": "ru", "ru": "ru", "russian": "ru",
        "u": "uk", "uk": "uk", "ukrainian": "uk",
        "s": "es", "es": "es", "spanish": "es",
        "c": "zh-CN", "zh": "zh-CN", "zh-cn": "zh-CN", "chinese": "zh-CN",
        "a": "ar", "ar": "ar", "arabic": "ar", "arabian": "ar",
        "i": "it", "it": "it", "italian": "it"
    ]

    return aliases[token]
}

private func parseTranslatePayload(from input: String) -> (source: String?, target: String, text: String)? {
    let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
    let lower = trimmed.lowercased()
    guard lower == "translate" || lower.hasPrefix("translate ") || lower == "tran" || lower.hasPrefix("tran ") || lower == "tr" || lower.hasPrefix("tr ") else {
        return nil
    }

    let words = trimmed.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
    guard words.count >= 2 else { return nil }

    if words.count >= 4,
       let src = translateLanguageAlias(words[1]),
       let dst = translateLanguageAlias(words[2]) {
        let text = words.dropFirst(3).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        return (source: src == "auto" ? nil : src, target: dst, text: text)
    }

    let text = words.dropFirst().joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return nil }
    let hasCyrillic = text.range(of: "\\p{Cyrillic}", options: .regularExpression) != nil
    return (source: nil, target: hasCyrillic ? "en" : "ru", text: text)
}

private func detectCalculatorExpression(from input: String) -> String? {
    let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }

    if trimmed.hasPrefix("=") {
        let expr = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
        return expr.isEmpty ? nil : expr
    }

    let lower = trimmed.lowercased()
    if lower == "calc" || lower.hasPrefix("calc ") {
        let expr = String(trimmed.dropFirst(4)).trimmingCharacters(in: .whitespacesAndNewlines)
        return expr.isEmpty ? nil : expr
    }

    let allowed = CharacterSet(charactersIn: "0123456789.,+-*/()% ")
    if trimmed.unicodeScalars.contains(where: { !allowed.contains($0) }) {
        return nil
    }

    let compact = trimmed.replacingOccurrences(of: " ", with: "")
    guard compact.unicodeScalars.contains(where: { CharacterSet.decimalDigits.contains($0) }) else {
        return nil
    }
    let operators = CharacterSet(charactersIn: "+-*/%")
    guard compact.unicodeScalars.contains(where: { operators.contains($0) }) else {
        return nil
    }

    return trimmed
}

private final class MiniMCVPanelModel: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate {
    @Published var input = ""
    @Published var title = "Mini MCV"
    @Published var resultText = "Type query and press Enter. For calc/translate/ai you'll get instant result."
    @Published var detail = "Examples: calc 12*7, tran r e привет, ai explain rsi divergence"
    @Published var isError = false
    @Published var isLoading = false
    @Published var showsWebPreview = false
    @Published var focusTicket = 0

    let webView: WKWebView
    private var translateTask: Task<Void, Never>?
    private var aiTask: Task<Void, Never>?
    private var predictionWorkItem: DispatchWorkItem?
    private var pendingLearnQuery: String?
    private var pendingLearnAt: Date?

    override init() {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        config.preferences.javaScriptCanOpenWindowsAutomatically = true
        config.mediaTypesRequiringUserActionForPlayback = []
        self.webView = WKWebView(frame: .zero, configuration: config)
        super.init()
        webView.navigationDelegate = self
        webView.uiDelegate = self
    }

    deinit {
        translateTask?.cancel()
        aiTask?.cancel()
        predictionWorkItem?.cancel()
    }

    func requestFocus() {
        focusTicket &+= 1
    }

    func clearInput() {
        predictionWorkItem?.cancel()
        translateTask?.cancel()
        aiTask?.cancel()
        clearPendingSmartLearning()
        input = ""
        isError = false
        isLoading = false
        showsWebPreview = false
        title = "Mini MCV"
        resultText = "Type query and press Enter. For calc/translate/ai you'll get instant result."
        detail = "Examples: calc 12*7, tran r e привет, ai explain rsi divergence"
    }

    func showCalculatorExpression(_ expression: String) {
        let clean = expression.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }

        predictionWorkItem?.cancel()
        translateTask?.cancel()
        aiTask?.cancel()
        clearPendingSmartLearning()

        input = clean
        showsWebPreview = false
        if let result = evaluateCalcExpression(clean) {
            isError = false
            isLoading = false
            title = "Calculator"
            resultText = result
            detail = clean
        } else {
            isError = true
            isLoading = false
            title = "Calculator"
            resultText = "Cannot evaluate expression"
            detail = clean
        }
    }

    func updateInlineHint(for raw: String) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            predictionWorkItem?.cancel()
            isError = false
            isLoading = false
            if !showsWebPreview {
                title = "Mini MCV"
                resultText = "Type query and press Enter. For calc/translate/ai you'll get instant result."
                detail = "Examples: calc 12*7, tran r e привет, ai explain rsi divergence"
            }
            return
        }

        if let expression = parseCalcExpression(from: text),
           let result = evaluateCalcExpression(expression) {
            predictionWorkItem?.cancel()
            isError = false
            isLoading = false
            showsWebPreview = false
            title = "Calculator"
            resultText = result
            detail = expression
            return
        }

        if let request = parseTranslateRequest(from: text) {
            predictionWorkItem?.cancel()
            isError = false
            isLoading = false
            showsWebPreview = false
            let src = request.source ?? "auto"
            title = "Translator"
            resultText = request.text
            detail = "Press Enter to translate (\(src) -> \(request.target))"
            return
        }

        if isAICommandPrefix(text) {
            predictionWorkItem?.cancel()
            isError = false
            isLoading = false
            showsWebPreview = false
            title = "Local AI"
            if let request = parseAIRequest(from: text) {
                resultText = request.prompt
                detail = "Press Enter to ask local model (\(selectedOllamaModel()))"
            } else {
                resultText = "Usage: ai <prompt>"
                detail = "Example: ai summarize this page in 3 bullets"
            }
            return
        }

        queueSmartPrediction(for: text)
        if !showsWebPreview {
            isError = false
            isLoading = false
            title = "Web Preview"
            resultText = text
            detail = "Press Enter to open mini web preview"
        }
    }

    func submit() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        if let expression = parseCalcExpression(from: text) {
            clearPendingSmartLearning()
            if let result = evaluateCalcExpression(expression) {
                isError = false
                isLoading = false
                showsWebPreview = false
                title = "Calculator"
                resultText = result
                detail = expression
            } else {
                isError = true
                isLoading = false
                showsWebPreview = false
                title = "Calculator"
                resultText = "Cannot evaluate expression"
                detail = expression
            }
            return
        }

        if let request = parseTranslateRequest(from: text) {
            clearPendingSmartLearning()
            runTranslate(request)
            return
        }

        if isAICommandPrefix(text) {
            clearPendingSmartLearning()
            guard let request = parseAIRequest(from: text) else {
                isError = true
                isLoading = false
                showsWebPreview = false
                title = "Local AI"
                resultText = "Usage: ai <prompt>"
                detail = "Example: ai explain trend following strategy"
                return
            }
            runLocalAI(request)
            return
        }

        openWebPreview(for: text)
    }

    private func runTranslate(_ request: MiniQuickTranslateRequest) {
        translateTask?.cancel()
        aiTask?.cancel()
        isLoading = true
        isError = false
        showsWebPreview = false
        title = "Translator"
        resultText = request.text
        detail = "Translating..."

        translateTask = Task {
            let source = request.source ?? "auto"
            let escaped = request.text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? request.text
            guard let url = URL(string: "https://translate.googleapis.com/translate_a/single?client=gtx&sl=\(source)&tl=\(request.target)&dt=t&q=\(escaped)") else {
                await MainActor.run {
                    self.isLoading = false
                    self.isError = true
                    self.title = "Translator"
                    self.resultText = "Invalid translation request"
                    self.detail = ""
                }
                return
            }

            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                if Task.isCancelled { return }
                guard let translated = parseTranslatedText(from: data) else {
                    await MainActor.run {
                        self.isLoading = false
                        self.isError = true
                        self.title = "Translator"
                        self.resultText = "Translation failed"
                        self.detail = "Try again"
                    }
                    return
                }

                await MainActor.run {
                    self.isLoading = false
                    self.isError = false
                    self.title = "Translation"
                    self.resultText = translated
                    self.detail = "\(source) -> \(request.target)"
                }
            } catch {
                if Task.isCancelled { return }
                await MainActor.run {
                    self.isLoading = false
                    self.isError = true
                    self.title = "Translator"
                    self.resultText = "Network error"
                    self.detail = error.localizedDescription
                }
            }
        }
    }

    private func openWebPreview(for input: String) {
        if let response = CommandHelperClient.shared.execute(input: input),
           response.action != "not_command" {
            switch response.action {
            case "navigate":
                if let value = response.url, let url = URL(string: value) {
                    clearPendingSmartLearning()
                    loadWebPreview(url)
                    return
                }
            case "search_web":
                let query = (response.query ?? input).trimmingCharacters(in: .whitespacesAndNewlines)
                if let ddg = ddgURL(for: query) {
                    beginPendingSmartLearning(for: query)
                    loadWebPreview(ddg)
                    return
                }
            case "show_message":
                isError = response.isSuccess == false
                isLoading = false
                showsWebPreview = false
                title = response.title ?? "Command"
                resultText = response.message ?? "Done"
                detail = "Run this command in the main browser for full action."
                return
            default:
                isError = false
                isLoading = false
                showsWebPreview = false
                title = response.title ?? "Command"
                resultText = response.message ?? "This command targets main browser windows."
                detail = "Use normal window for state-changing commands."
                return
            }
        }

        if let url = resolveDirectURL(from: input) {
            clearPendingSmartLearning()
            loadWebPreview(url)
            return
        }

        if let prediction = CommandHelperClient.shared.predictSmartURL(for: input) {
            clearPendingSmartLearning()
            loadWebPreview(prediction.url)
            title = "Smart match"
            detail = "Learned from your history (\(max(2, prediction.hits))x)"
            return
        }

        if let ddg = ddgURL(for: input) {
            beginPendingSmartLearning(for: input)
            loadWebPreview(ddg)
        }
    }

    private func loadWebPreview(_ url: URL) {
        translateTask?.cancel()
        aiTask?.cancel()
        isError = false
        isLoading = true
        showsWebPreview = true
        title = "Loading..."
        resultText = url.absoluteString
        detail = url.host ?? "Web preview"
        webView.load(URLRequest(url: url))
    }

    private func resolveDirectURL(from input: String) -> URL? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.contains("://") {
            return URL(string: trimmed)
        }
        if trimmed.contains(".") && !trimmed.contains(" ") {
            return URL(string: "https://\(trimmed)")
        }
        return nil
    }

    private func ddgURL(for query: String) -> URL? {
        let escaped = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        return URL(string: "https://duckduckgo.com/?q=\(escaped)")
    }

    private func shouldAttemptSmartPrediction(for query: String) -> Bool {
        let clean = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean.count >= 4 else { return false }
        guard clean.contains(" ") else { return false }
        guard resolveDirectURL(from: clean) == nil else { return false }

        let lower = clean.lowercased()
        if lower.hasPrefix("!") {
            return false
        }
        if lower == "yt" || lower.hasPrefix("yt ") || lower == "wiki" || lower.hasPrefix("wiki ") || lower == "gh" || lower.hasPrefix("gh ") {
            return false
        }
        return true
    }

    private func queueSmartPrediction(for text: String) {
        predictionWorkItem?.cancel()
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard shouldAttemptSmartPrediction(for: query) else { return }

        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let prediction = CommandHelperClient.shared.predictSmartURL(for: query)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                guard self.input.trimmingCharacters(in: .whitespacesAndNewlines) == query else { return }
                guard !self.showsWebPreview else { return }
                guard let prediction else { return }
                self.isError = false
                self.isLoading = false
                self.title = "Smart match"
                self.resultText = prediction.url.absoluteString
                self.detail = "Press Enter to open learned page (\(max(2, prediction.hits))x)"
            }
        }

        predictionWorkItem = work
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.16, execute: work)
    }

    private func beginPendingSmartLearning(for query: String) {
        let clean = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        pendingLearnQuery = clean
        pendingLearnAt = Date()
    }

    private func clearPendingSmartLearning() {
        pendingLearnQuery = nil
        pendingLearnAt = nil
    }

    private func isSearchHost(_ host: String) -> Bool {
        let normalized = host.lowercased()
        if normalized == "duckduckgo.com" || normalized == "www.duckduckgo.com" {
            return true
        }
        if normalized == "bing.com" || normalized == "www.bing.com" {
            return true
        }
        if normalized == "search.yahoo.com" || normalized == "yahoo.com" || normalized == "www.yahoo.com" {
            return true
        }
        if normalized == "google.com" || normalized == "www.google.com" || normalized.hasSuffix(".google.com") {
            return true
        }
        return false
    }

    private func maybeLearnFromCurrentURL(_ url: URL) {
        guard let query = pendingLearnQuery,
              let startedAt = pendingLearnAt else {
            return
        }

        if Date().timeIntervalSince(startedAt) > 300 {
            clearPendingSmartLearning()
            return
        }

        guard let host = url.host?.lowercased() else { return }
        if isSearchHost(host) {
            return
        }

        CommandHelperClient.shared.learnSmartMapping(query: query, url: url.absoluteString)
        clearPendingSmartLearning()
    }

    private func parseCalcExpression(from input: String) -> String? {
        detectCalculatorExpression(from: input)
    }

    private func evaluateCalcExpression(_ expression: String) -> String? {
        let sanitized = expression.replacingOccurrences(of: ",", with: ".")
        let allowed = CharacterSet(charactersIn: "0123456789.+-*/()% ")
        if sanitized.unicodeScalars.contains(where: { !allowed.contains($0) }) {
            return nil
        }

        let nsExpression = NSExpression(format: sanitized)
        guard let number = nsExpression.expressionValue(with: nil, context: nil) as? NSNumber else {
            return nil
        }

        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 8
        formatter.minimumFractionDigits = 0
        formatter.usesGroupingSeparator = true
        return formatter.string(from: number) ?? number.stringValue
    }

    private func parseTranslateRequest(from input: String) -> MiniQuickTranslateRequest? {
        guard let parsed = parseTranslatePayload(from: input) else { return nil }
        return MiniQuickTranslateRequest(source: parsed.source, target: parsed.target, text: parsed.text)
    }

    private func isAICommandPrefix(_ input: String) -> Bool {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        return lower == "ai" || lower.hasPrefix("ai ")
    }

    private func parseAIRequest(from input: String) -> MiniAIRequest? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        guard lower == "ai" || lower.hasPrefix("ai ") else { return nil }
        let prompt = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return nil }
        return MiniAIRequest(prompt: prompt)
    }

    private func selectedOllamaModel() -> String {
        let raw = UserDefaults.standard.string(forKey: AppKeys.ollamaModel)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return raw.isEmpty ? "llama3.2:3b" : raw
    }

    private func runLocalAI(_ request: MiniAIRequest) {
        translateTask?.cancel()
        aiTask?.cancel()

        let model = selectedOllamaModel()
        isError = false
        isLoading = true
        showsWebPreview = false
        title = "Local AI"
        resultText = request.prompt
        detail = "Thinking with \(model)..."

        aiTask = Task { [weak self, prompt = request.prompt, model] in
            let output = await Task.detached(priority: .userInitiated) {
                CommandHelperClient.shared.generateLocalAI(prompt: prompt, model: model)
            }.value

            await MainActor.run {
                guard let self, !Task.isCancelled else { return }
                self.isLoading = false
                self.showsWebPreview = false
                if output.success {
                    self.isError = false
                    self.title = "AI • \(output.model)"
                    self.resultText = output.text
                    self.detail = "Local response via Ollama"
                } else {
                    self.isError = true
                    self.title = "AI error"
                    self.resultText = output.message.isEmpty ? "Cannot run local model" : output.message
                    self.detail = "Open Settings > General > Configure Ollama"
                }
            }
        }
    }

    private func parseTranslatedText(from data: Data) -> String? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [Any],
              let segments = root.first as? [Any] else {
            return nil
        }

        var out = ""
        for segment in segments {
            if let row = segment as? [Any], let text = row.first as? String {
                out += text
            }
        }
        let trimmed = out.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        guard showsWebPreview else { return }
        isLoading = true
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard showsWebPreview else { return }
        isLoading = false
        isError = false
        let rawTitle = webView.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        title = rawTitle.isEmpty ? (webView.url?.host ?? "Web Preview") : rawTitle
        resultText = webView.url?.absoluteString ?? resultText
        detail = webView.url?.host ?? "Web preview"
        if let currentURL = webView.url {
            maybeLearnFromCurrentURL(currentURL)
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        guard showsWebPreview else { return }
        isLoading = false
        isError = true
        title = "Preview Error"
        resultText = "Cannot open preview"
        detail = error.localizedDescription
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        guard showsWebPreview else { return }
        isLoading = false
        isError = true
        title = "Preview Error"
        resultText = "Cannot open preview"
        detail = error.localizedDescription
    }

    // Keep popup flows inside Mini MCV instead of creating regular browser tabs/windows.
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        guard navigationAction.targetFrame == nil || navigationAction.targetFrame?.isMainFrame == false else {
            return nil
        }
        if let popupURL = navigationAction.request.url {
            clearPendingSmartLearning()
            loadWebPreview(popupURL)
            title = "Popup in Mini MCV"
            detail = popupURL.host ?? popupURL.absoluteString
        }
        return nil
    }
}

private struct MiniMCVPanelView: View {
    @ObservedObject var model: MiniMCVPanelModel
    let onClose: () -> Void

    @FocusState private var inputFocused: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.14), lineWidth: 0.8)
                )

            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(Color.white.opacity(0.72))

                    TextField("Mini MCV command or query", text: Binding(
                        get: { model.input },
                        set: { newValue in
                            model.input = newValue
                            model.updateInlineHint(for: newValue)
                        }
                    ))
                    .textFieldStyle(.plain)
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.96))
                    .focused($inputFocused)
                    .onSubmit { model.submit() }

                    if !model.input.isEmpty {
                        Button(action: { model.clearInput() }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(Color.white.opacity(0.56))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .frame(height: 62)
                .background(
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .fill(Color.white.opacity(0.10))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .stroke(Color.white.opacity(0.18), lineWidth: 1)
                )

                if model.showsWebPreview {
                    ZStack(alignment: .topTrailing) {
                        BrowserWebView(webView: model.webView)
                            .frame(height: 360)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(Color.white.opacity(0.14), lineWidth: 1)
                            )

                        if model.isLoading {
                            HStack(spacing: 6) {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Loading")
                                    .font(.system(size: 11, weight: .semibold))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(.ultraThinMaterial, in: Capsule(style: .continuous))
                            .padding(8)
                        }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(model.title)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(model.isError ? Color.red.opacity(0.90) : Color.cyan.opacity(0.90))
                        Text(model.resultText)
                            .font(.system(size: 21, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.white.opacity(0.95))
                            .lineLimit(3)
                            .textSelection(.enabled)
                        if !model.detail.isEmpty {
                            Text(model.detail)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Color.white.opacity(0.68))
                                .lineLimit(2)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 130, alignment: .topLeading)
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.white.opacity(0.06))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.white.opacity(0.10), lineWidth: 0.8)
                    )
                }
            }
            .padding(14)
        }
        .frame(width: 720)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
                inputFocused = true
            }
        }
        .onChange(of: model.focusTicket) { _, _ in
            DispatchQueue.main.async {
                inputFocused = true
            }
        }
        .onExitCommand(perform: onClose)
    }
}

private final class MiniMCVPanelController {
    static let shared = MiniMCVPanelController()

    private let model = MiniMCVPanelModel()
    private var panel: NSPanel?

    private init() {}

    func toggle() {
        if panel?.isVisible == true {
            hide()
        } else {
            show()
        }
    }

    func show() {
        if panel == nil {
            panel = buildPanel()
        }
        guard let panel else { return }
        NSApp.activate(ignoringOtherApps: true)
        if !panel.isVisible {
            panel.center()
        }
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        model.requestFocus()
    }

    func showCalculator(expression: String) {
        show()
        model.showCalculatorExpression(expression)
        model.requestFocus()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func buildPanel() -> NSPanel {
        let content = MiniMCVPanelView(model: model) { [weak self] in
            self?.hide()
        }
        let host = NSHostingController(rootView: content)
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 740, height: 510),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.contentViewController = host
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        // `canJoinAllSpaces` and `moveToActiveSpace` conflict on newer macOS and crash in `_validateCollectionBehavior`.
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = true
        return panel
    }
}

private let miniMCVHotKeySignature = OSType(0x4D43564D) // MCVM
private let miniMCVHotKeyID: UInt32 = 1

private let miniMCVCarbonHotKeyHandler: EventHandlerUPP = { _, event, _ in
    guard let event else { return noErr }
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    guard status == noErr else { return noErr }
    guard hotKeyID.signature == miniMCVHotKeySignature, hotKeyID.id == miniMCVHotKeyID else { return noErr }
    GlobalHotKeyManager.shared.handleHotKeyPress()
    return noErr
}

private final class GlobalHotKeyManager {
    static let shared = GlobalHotKeyManager()

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private var action: (() -> Void)?

    private init() {}

    func registerOptionSpace(action: @escaping () -> Void) {
        self.action = action
        guard hotKeyRef == nil else { return }

        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            miniMCVCarbonHotKeyHandler,
            1,
            &eventSpec,
            nil,
            &handlerRef
        )
        guard installStatus == noErr else { return }

        let hotKeyID = EventHotKeyID(signature: miniMCVHotKeySignature, id: miniMCVHotKeyID)
        let registerStatus = RegisterEventHotKey(
            UInt32(kVK_Space),
            UInt32(optionKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        if registerStatus != noErr {
            if let handlerRef {
                RemoveEventHandler(handlerRef)
                self.handlerRef = nil
            }
        }
    }

    fileprivate func handleHotKeyPress() {
        guard let action else { return }
        DispatchQueue.main.async {
            action()
        }
    }

    deinit {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        if let handlerRef {
            RemoveEventHandler(handlerRef)
        }
    }
}

private struct BookmarkItem: Codable, Identifiable {
    var id: UUID
    var title: String
    var url: String
    var addedAt: Date
    var shortcut: BookmarkShortcut?
}

private struct BookmarkShortcut: Codable, Equatable {
    let normalized: String

    private var normalizedKey: String? {
        let cleaned = normalized
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !cleaned.isEmpty else { return nil }

        if cleaned.count == 1,
           let scalar = cleaned.unicodeScalars.first,
           CharacterSet.alphanumerics.contains(scalar) {
            return cleaned
        }

        let separators = CharacterSet(charactersIn: "+ -_,;")
        let tokens = cleaned
            .components(separatedBy: separators)
            .filter { !$0.isEmpty }
        if tokens.count == 2,
           Self.isOptionAlias(tokens[0]),
           tokens[1].count == 1,
           let scalar = tokens[1].unicodeScalars.first,
           CharacterSet.alphanumerics.contains(scalar) {
            return tokens[1]
        }

        return nil
    }

    var matchKey: String? {
        normalizedKey
    }

    var inputValue: String {
        normalizedKey ?? ""
    }

    var displayLabel: String {
        guard let key = normalizedKey else { return "⌥+?" }
        return "⌥+\(key.uppercased())"
    }

    static func parse(_ rawValue: String) -> BookmarkShortcut? {
        let cleaned = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !cleaned.isEmpty else { return nil }

        var keyCandidate = cleaned
        if cleaned.contains("+") || cleaned.contains(" ") || cleaned.contains("-") || cleaned.contains("_") || cleaned.contains(",") || cleaned.contains(";") {
            let tokens = cleaned
                .components(separatedBy: CharacterSet(charactersIn: "+ -_,;"))
                .filter { !$0.isEmpty }
            guard !tokens.isEmpty else { return nil }
            if tokens.count == 2, isOptionAlias(tokens[0]) {
                keyCandidate = tokens[1]
            } else {
                return nil
            }
        }

        guard keyCandidate.count == 1,
              let scalar = keyCandidate.unicodeScalars.first,
              CharacterSet.alphanumerics.contains(scalar) else {
            return nil
        }

        return BookmarkShortcut(normalized: keyCandidate)
    }

    static func fromEvent(_ event: NSEvent) -> BookmarkShortcut? {
        guard event.type == .keyDown else { return nil }
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        guard flags == [.option] else { return nil }
        guard let keyToken = keyToken(from: event) else { return nil }
        return BookmarkShortcut(normalized: keyToken)
    }

    private static func keyToken(from event: NSEvent) -> String? {
        guard let chars = event.charactersIgnoringModifiers?.trimmingCharacters(in: .whitespacesAndNewlines),
              chars.count == 1,
              let scalar = chars.unicodeScalars.first else {
            return nil
        }

        guard CharacterSet.alphanumerics.contains(scalar) else { return nil }
        return String(chars.lowercased())
    }

    private static func isOptionAlias(_ raw: String) -> Bool {
        raw == "opt" || raw == "option" || raw == "alt" || raw == "⌥"
    }
}

private struct HistoryItem: Codable, Identifiable {
    let id: UUID
    let title: String
    let url: String
    let visitedAt: Date
}

private struct DownloadItem: Codable, Identifiable {
    let id: UUID
    let title: String
    let sourceURL: String
    let destinationPath: String
    let downloadedAt: Date
}

private struct SavedFolder: Codable, Identifiable {
    let id: UUID
    let name: String
    let parentID: UUID?
    let createdAt: Date
}

private struct SavedLink: Codable, Identifiable {
    let id: UUID
    let title: String
    let url: String
    let folderID: UUID?
    let addedAt: Date
}

private struct TabSessionState: Codable {
    let urls: [String]
    let selectedIndex: Int
}

private struct ClosedTabRecord {
    let url: URL?
    let title: String
}

private struct PageFindSuggestion: Identifiable {
    let id: Int
    let markIndex: Int
    let snippet: String
}

private struct SavedNavigatorEntry: Identifiable {
    enum Kind {
        case folder
        case link
    }

    let id: UUID
    let kind: Kind
    let title: String
    let subtitle: String
    let folderID: UUID?
    let folder: SavedFolder?
    let link: SavedLink?
}

private struct CommandSuggestion: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let subtitle: String
    let value: String
}

private struct OllamaSidebarMessage: Identifiable {
    enum Role {
        case user
        case assistant
        case system
    }

    let id = UUID()
    let role: Role
    let text: String
    let imageURL: URL?
    let timestamp = Date()
}

private struct AIPageActionItem: Identifiable {
    let id: String
    let kind: String
    let label: String
    let role: String
    let hint: String
    let context: String
    let selectorHint: String
}

private struct AIPageSemanticSnapshot {
    let title: String
    let url: String
    let visibleTextBlocks: [String]
    let actions: [AIPageActionItem]
}

private enum CommandOverlayMode {
    case mixed
    case commandsOnly
}

private enum UtilityPanelKind: String {
    case bookmarks
    case history
    case colors
    case extensions
    case ollamaChat
}

private final class BrowserTab: NSObject, ObservableObject, Identifiable {
    enum Kind: Equatable {
        case regular
        case bookmark(UUID)
        case help
    }

    let id = UUID()
    let webView: WKWebView
    let kind: Kind

    @Published var title: String = "New Tab"
    @Published var displayURL: String = ""
    @Published var canGoBack: Bool = false
    @Published var canGoForward: Bool = false
    @Published var isLoading: Bool = false
    @Published var loadingProgress: Double = 0.0
    @Published var hasAudio: Bool = false
    @Published var isSuspended: Bool = false
    @Published var showsNativeHelpContent: Bool = false
    @Published var helpContextLine: String = ""

    var isStartPage = true
    var lastActiveAt = Date()
    private var suspendedURL: URL?
    private var suspendedTitle: String?

    private var observers: [NSKeyValueObservation] = []

    var isBookmarkTab: Bool {
        if case .bookmark = kind {
            return true
        }
        return false
    }

    var bookmarkID: UUID? {
        if case let .bookmark(id) = kind {
            return id
        }
        return nil
    }

    var isHelpTab: Bool {
        if case .help = kind {
            return true
        }
        return false
    }

    init(kind: Kind = .regular, webViewConfiguration: WKWebViewConfiguration? = nil, startPageTheme: ChromeTheme = .default) {
        self.kind = kind
        let config = webViewConfiguration ?? WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        config.preferences.javaScriptCanOpenWindowsAutomatically = true
        if #available(macOS 12.3, *) {
            config.preferences.isElementFullscreenEnabled = true
        }
        config.mediaTypesRequiringUserActionForPlayback = []
        self.webView = WKWebView(frame: .zero, configuration: config)
        self.webView.allowsBackForwardNavigationGestures = true
        if #available(macOS 13.3, *) {
            self.webView.isInspectable = true
        }

        super.init()
        installObservers()
        if isHelpTab {
            showHelpDocument(context: nil)
        } else {
            loadNewTabPage(theme: startPageTheme)
        }
    }

    private func installObservers() {
        observers.append(
            webView.observe(\.title, options: [.new, .initial]) { [weak self] view, _ in
                guard let self else { return }
                if self.isSuspended {
                    return
                }
                if self.isHelpTab && self.showsNativeHelpContent {
                    return
                }
                if self.isStartPage {
                    self.title = "New Tab"
                    return
                }
                let raw = view.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if raw.isEmpty {
                    self.title = view.url?.host ?? "New Tab"
                } else {
                    self.title = raw
                }
            }
        )

        observers.append(
            webView.observe(\.url, options: [.new, .initial]) { [weak self] view, _ in
                guard let self else { return }
                if self.isSuspended {
                    self.displayURL = self.suspendedURL?.absoluteString ?? self.displayURL
                    return
                }
                if self.isHelpTab && self.showsNativeHelpContent {
                    self.displayURL = ""
                    return
                }
                if self.isStartPage {
                    self.displayURL = ""
                } else {
                    self.displayURL = view.url?.absoluteString ?? ""
                }
            }
        )

        observers.append(
            webView.observe(\.canGoBack, options: [.new, .initial]) { [weak self] view, _ in
                self?.canGoBack = view.canGoBack
            }
        )

        observers.append(
            webView.observe(\.canGoForward, options: [.new, .initial]) { [weak self] view, _ in
                self?.canGoForward = view.canGoForward
            }
        )

        observers.append(
            webView.observe(\.isLoading, options: [.new, .initial]) { [weak self] view, _ in
                guard let self else { return }
                self.isLoading = view.isLoading
                if !view.isLoading,
                   (self.isStartPage || (self.isHelpTab && self.showsNativeHelpContent)) {
                    self.loadingProgress = 0.0
                }
            }
        )

        observers.append(
            webView.observe(\.estimatedProgress, options: [.new, .initial]) { [weak self] view, _ in
                guard let self else { return }
                if self.isStartPage || (self.isHelpTab && self.showsNativeHelpContent) {
                    self.loadingProgress = 0.0
                    return
                }
                let value = min(max(view.estimatedProgress, 0.0), 1.0)
                let delta = abs(value - self.loadingProgress)
                if delta >= 0.015 || value <= 0.02 || value >= 0.99 {
                    self.loadingProgress = value
                }
            }
        )
    }

    func load(url: URL) {
        showsNativeHelpContent = false
        helpContextLine = ""
        isStartPage = false
        isSuspended = false
        hasAudio = false
        suspendedURL = nil
        suspendedTitle = nil
        lastActiveAt = Date()
        loadingProgress = 0.03
        webView.load(URLRequest(url: url))
    }

    func loadNewTabPage(theme _: ChromeTheme = .default) {
        showsNativeHelpContent = false
        helpContextLine = ""
        isStartPage = true
        isSuspended = false
        hasAudio = false
        suspendedURL = nil
        suspendedTitle = nil
        lastActiveAt = Date()
        title = "New Tab"
        displayURL = ""
        canGoBack = false
        canGoForward = false
        isLoading = false
        loadingProgress = 0.0
        webView.stopLoading()
    }

    func markActive() {
        lastActiveAt = Date()
        if isSuspended {
            resumeFromSuspension()
        }
    }

    @discardableResult
    func suspendIfNeeded(cutoff: Date) -> Bool {
        guard !isSuspended else { return false }
        guard !isStartPage else { return false }
        guard lastActiveAt < cutoff else { return false }
        guard let currentURL = webView.url,
              let scheme = currentURL.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return false
        }

        suspendedURL = currentURL
        suspendedTitle = title
        isSuspended = true
        hasAudio = false
        webView.stopLoading()
        webView.loadHTMLString(Self.suspendedTabHTML(title: title, url: currentURL.absoluteString), baseURL: nil)
        displayURL = currentURL.absoluteString
        return true
    }

    private func resumeFromSuspension() {
        guard isSuspended else { return }
        isSuspended = false
        if let target = suspendedURL {
            let restoreURL = target
            suspendedURL = nil
            suspendedTitle = nil
            load(url: restoreURL)
            return
        }

        suspendedTitle = nil
    }

    func showHelpDocument(context: String?) {
        isStartPage = true
        isSuspended = false
        hasAudio = false
        suspendedURL = nil
        suspendedTitle = nil
        showsNativeHelpContent = true
        title = "Help"
        displayURL = ""
        canGoBack = false
        canGoForward = false
        isLoading = false
        loadingProgress = 0.0
        let cleanContext = (context ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        helpContextLine = cleanContext
        webView.stopLoading()
    }

    private static func newTabHTML(theme: ChromeTheme) -> String {
        let c = theme.clamped
        let red = Int((c.red * 255.0).rounded())
        let green = Int((c.green * 255.0).rounded())
        let blue = Int((c.blue * 255.0).rounded())
        let tint = min(max(c.intensity, 0.0), 1.5)
        let luminance = (0.2126 * c.red) + (0.7152 * c.green) + (0.0722 * c.blue)
        let brightPenalty = max(0.0, luminance - 0.60)
        let alphaScale = max(0.58, 1.0 - brightPenalty * 0.62)

        let glowA = String(format: "%.3f", (0.16 + 0.26 * tint) * alphaScale)
        let glowB = String(format: "%.3f", (0.08 + 0.16 * tint) * alphaScale)
        let cardA = String(format: "%.3f", (0.08 + 0.12 * tint) * alphaScale)
        let cardB = String(format: "%.3f", (0.02 + 0.08 * tint) * alphaScale)
        let cardBorder = String(format: "%.3f", (0.20 + 0.22 * tint) * alphaScale)
        let tagBg = String(format: "%.3f", (0.16 + 0.22 * tint) * alphaScale)
        let tagBorder = String(format: "%.3f", (0.24 + 0.30 * tint) * alphaScale)
        let showHints = HintLifecycle.shouldShowHints
        let hintAccent = String(format: "%.3f", (0.42 + 0.30 * tint) * alphaScale)
        let hintStyle = showHints ? """
    .hint {
      margin-top:16px;
      color: rgba(\(red),\(green),\(blue),\(hintAccent));
      font-size:13px;
      font-weight: 600;
    }
""" : ""
        let hintMarkup = showHints ? "<div class=\"hint\">Try: yt lofi beats, wiki WebKit, gh apple</div>" : ""
        return """
<!doctype html>
<html>
<head>
  <meta charset=\"utf-8\" />
  <meta name=\"viewport\" content=\"width=device-width, initial-scale=1\" />
  <title>MC Browser</title>
  <style>
    html, body { margin:0; width:100%; height:100%; }
    body {
      display:grid;
      place-items:center;
      background: radial-gradient(1000px 520px at 50% -20%, rgba(\(red),\(green),\(blue),\(glowA)), transparent 60%),
                  radial-gradient(680px 360px at 110% 105%, rgba(\(red),\(green),\(blue),\(glowB)), transparent 60%),
                  linear-gradient(140deg, #0d1220, #141a2a 56%, #0e1018);
      font-family: -apple-system, BlinkMacSystemFont, \"SF Pro Text\", \"Segoe UI\", sans-serif;
      color: rgba(241,247,255,0.95);
      overflow:hidden;
    }
    .card {
      width:min(760px, calc(100vw - 56px));
      border-radius: 24px;
      padding: 32px;
      border:1px solid rgba(\(red),\(green),\(blue),\(cardBorder));
      background:
        linear-gradient(150deg, rgba(255,255,255,0.14), rgba(255,255,255,0.03)),
        linear-gradient(135deg, rgba(\(red),\(green),\(blue),\(cardA)), rgba(\(red),\(green),\(blue),\(cardB));
      backdrop-filter: blur(18px) saturate(135%);
      box-shadow: 0 30px 80px rgba(0,0,0,0.35);
    }
    .tag {
      display:inline-block;
      font-size:12px;
      letter-spacing:.08em;
      text-transform: uppercase;
      font-weight:700;
      padding:6px 10px;
      border-radius:999px;
      background: rgba(\(red),\(green),\(blue),\(tagBg));
      border: 1px solid rgba(\(red),\(green),\(blue),\(tagBorder));
    }
    h1 {
      margin:14px 0 10px;
      font-size: clamp(30px, 4vw, 48px);
      letter-spacing: -.02em;
      line-height: 1.04;
    }
    p {
      margin:0;
      font-size:16px;
      color: rgba(236,243,255,0.82);
      line-height: 1.52;
      max-width: 48ch;
    }
\(hintStyle)
  </style>
</head>
<body>
  <main class=\"card\">
    <div class=\"tag\">MC Browser V 1.0</div>
    <h1>New Tab</h1>
    <p>Clean outside, powerful inside. Use Smart Bar for search and address, press Cmd+E for command overlay.</p>
\(hintMarkup)
  </main>
</body>
</html>
"""
    }

    private static func suspendedTabHTML(title: String, url: String) -> String {
        return """
<!doctype html>
<html>
<head>
  <meta charset=\"utf-8\" />
  <meta name=\"viewport\" content=\"width=device-width, initial-scale=1\" />
  <title>Suspended Tab</title>
  <style>
    html, body { margin:0; width:100%; height:100%; }
    body {
      display:grid;
      place-items:center;
      background: radial-gradient(900px 460px at 50% -10%, rgba(82,170,255,0.24), transparent 58%),
                  linear-gradient(140deg, #0b101d, #131a2a);
      color: rgba(242,247,255,0.94);
      font-family: -apple-system, BlinkMacSystemFont, \"SF Pro Text\", \"Segoe UI\", sans-serif;
    }
    .card {
      width:min(680px, calc(100vw - 54px));
      border-radius: 22px;
      padding: 28px;
      border:1px solid rgba(255,255,255,0.2);
      background: linear-gradient(150deg, rgba(255,255,255,0.14), rgba(255,255,255,0.04));
      backdrop-filter: blur(14px) saturate(130%);
      box-shadow: 0 26px 80px rgba(0,0,0,0.35);
    }
    h1 {
      margin:0 0 10px;
      font-size: clamp(24px, 4vw, 38px);
      letter-spacing: -.02em;
    }
    p {
      margin:0;
      line-height:1.52;
      color: rgba(232,240,255,0.78);
      font-size:15px;
    }
    .meta {
      margin-top:14px;
      font-size:12px;
      color: rgba(188,213,255,0.72);
      word-break: break-all;
    }
  </style>
</head>
<body>
  <main class=\"card\">
    <h1>Tab suspended</h1>
    <p>This background tab was unloaded to reduce memory usage. Open this tab to restore content.</p>
    <div class=\"meta\">\(title) · \(url)</div>
  </main>
</body>
</html>
"""
    }
}

private final class BrowserStore: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler, WKDownloadDelegate {
    private enum AudioMonitor {
        static let messageName = "mcvAudio"
        static let scriptSource = """
        (() => {
          if (window.__mcvAudioHookInstalled) return;
          window.__mcvAudioHookInstalled = true;
          let lastState = { value: null };

          const isActive = () => {
            const media = Array.from(document.querySelectorAll('audio,video'));
            return media.some((m) => {
              try {
                return !m.paused && !m.ended && !m.muted && Number(m.volume || 0) > 0;
              } catch (_) {
                return false;
              }
            });
          };

          const post = (type) => {
            if (lastState.value === type) {
              return;
            }
            lastState.value = type;
            try {
              window.webkit.messageHandlers.mcvAudio.postMessage({ type, href: location.href });
            } catch (_) {}
          };

          const report = () => post(isActive() ? 'playing' : 'stopped');
          document.addEventListener('play', report, true);
          document.addEventListener('pause', report, true);
          document.addEventListener('ended', report, true);
          document.addEventListener('emptied', report, true);
          document.addEventListener('volumechange', report, true);
          document.addEventListener('visibilitychange', () => {
            if (document.visibilityState === 'visible') {
              report();
            } else {
              post('stopped');
            }
          }, true);
          window.addEventListener('pageshow', report, true);
          window.addEventListener('pagehide', () => post('stopped'), true);
          setInterval(() => {
            if (document.visibilityState === 'visible') {
              report();
            }
          }, 12000);
          report();
        })();
        """
    }

    private enum SecureShield {
        static let scriptSource = """
        (() => {
          if (window.__mcvSecureShieldInstalled) return;
          window.__mcvSecureShieldInstalled = true;

          const resolveURL = (raw) => {
            try { return new URL(raw, location.href); } catch (_) { return null; }
          };
          const isCrossOrigin = (url) => {
            const parsed = resolveURL(url);
            if (!parsed) return true;
            return parsed.origin !== location.origin;
          };
          const isInsecure = (url) => {
            const parsed = resolveURL(url);
            if (!parsed) return true;
            return parsed.protocol === "http:" || parsed.protocol === "ws:";
          };
          const shouldBlock = (url) => {
            if (!url) return false;
            return isInsecure(url) || isCrossOrigin(url);
          };
          const securityError = (kind, url) => {
            const value = String(url || "");
            return new DOMException(`secure mode blocked ${kind}: ${value}`, "SecurityError");
          };

          const originalFetch = window.fetch;
          if (typeof originalFetch === "function") {
            window.fetch = function(input, init) {
              const candidate = typeof input === "string" ? input : (input && input.url ? input.url : "");
              if (shouldBlock(candidate)) {
                return Promise.reject(securityError("fetch", candidate));
              }
              return originalFetch.call(this, input, init);
            };
          }

          const originalXHRopen = XMLHttpRequest.prototype.open;
          const originalXHRsend = XMLHttpRequest.prototype.send;
          XMLHttpRequest.prototype.open = function(method, url, async, user, password) {
            this.__mcvSecureBlocked = shouldBlock(url);
            this.__mcvSecureBlockedURL = String(url || "");
            return originalXHRopen.call(this, method, url, async, user, password);
          };
          XMLHttpRequest.prototype.send = function(body) {
            if (this.__mcvSecureBlocked) {
              throw securityError("xhr", this.__mcvSecureBlockedURL || "");
            }
            return originalXHRsend.call(this, body);
          };

          if (typeof navigator.sendBeacon === "function") {
            const originalSendBeacon = navigator.sendBeacon.bind(navigator);
            navigator.sendBeacon = function(url, data) {
              if (shouldBlock(url)) {
                return false;
              }
              return originalSendBeacon(url, data);
            };
          }

          if (typeof window.WebSocket === "function") {
            const OriginalWebSocket = window.WebSocket;
            const WrappedWebSocket = function(url, protocols) {
              if (shouldBlock(url)) {
                throw securityError("websocket", url);
              }
              return new OriginalWebSocket(url, protocols);
            };
            WrappedWebSocket.prototype = OriginalWebSocket.prototype;
            Object.defineProperty(window, "WebSocket", {
              configurable: true,
              writable: true,
              value: WrappedWebSocket
            });
          }

          const wrapWorkerConstructor = (key) => {
            const Original = window[key];
            if (typeof Original !== "function") return;
            const Wrapped = function(url, options) {
              if (shouldBlock(url)) {
                throw securityError("worker", url);
              }
              return new Original(url, options);
            };
            Wrapped.prototype = Original.prototype;
            Object.defineProperty(window, key, {
              configurable: true,
              writable: true,
              value: Wrapped
            });
          };
          wrapWorkerConstructor("Worker");
          wrapWorkerConstructor("SharedWorker");

          if (window.Notification && typeof window.Notification.requestPermission === "function") {
            window.Notification.requestPermission = () => Promise.resolve("denied");
          }

          if (navigator.serviceWorker && typeof navigator.serviceWorker.register === "function") {
            navigator.serviceWorker.register = () => Promise.reject(securityError("serviceWorker", "register"));
          }

          if (window.PushManager && window.PushManager.prototype && typeof window.PushManager.prototype.subscribe === "function") {
            window.PushManager.prototype.subscribe = function() {
              return Promise.reject(securityError("push", "subscribe"));
            };
          }

          const markBlockedScript = (node) => {
            if (!(node instanceof HTMLScriptElement)) return;
            const src = node.getAttribute("src") || "";
            if (!src) return;
            if (!shouldBlock(src)) return;
            node.type = "javascript/blocked";
            node.removeAttribute("src");
            node.text = "";
            node.setAttribute("data-mcv-secure-blocked", "1");
            if (node.parentNode) {
              node.parentNode.removeChild(node);
            }
          };

          const preloadedScripts = Array.from(document.querySelectorAll("script[src]"));
          for (const script of preloadedScripts) {
            markBlockedScript(script);
          }

          const observer = new MutationObserver((mutations) => {
            for (const mutation of mutations) {
              for (const node of mutation.addedNodes) {
                if (!(node instanceof Element)) continue;
                if (node instanceof HTMLScriptElement) {
                  markBlockedScript(node);
                }
                const nested = node.querySelectorAll ? node.querySelectorAll("script[src]") : [];
                for (const script of nested) {
                  markBlockedScript(script);
                }
              }
            }
          });
          observer.observe(document.documentElement || document, { childList: true, subtree: true });
        })();
        """
    }

    private static var didRestoreSessionForCurrentLaunch = false

    @Published private(set) var tabs: [BrowserTab] = []
    @Published var selectedTabID: UUID?

    @Published var smartInput: String = ""
    @Published var commandInput: String = ""
    @Published var isCommandOverlayVisible = false
    @Published var commandOverlayMode: CommandOverlayMode = .mixed
    @Published var commandSuggestions: [CommandSuggestion] = []
    @Published var selectedCommandSuggestionIndex: Int?
    @Published var smartBarCommandArmed = false
    @Published var overlayCommandArmed = false

    @Published var utilityPanel: UtilityPanelKind?
    @Published private(set) var bookmarks: [BookmarkItem] = []
    @Published private(set) var history: [HistoryItem] = []
    @Published private(set) var downloads: [DownloadItem] = []
    @Published private(set) var savedFolders: [SavedFolder] = []
    @Published private(set) var savedLinks: [SavedLink] = []
    @Published private(set) var chromeTheme: ChromeTheme = .default
    @Published var extensionInstallInProgress = false
    @Published var extensionInstallProgress: Double = 0.0
    @Published var extensionInstallStatus = ""

    @Published var transientMessage: String?

    let windowMode: BrowserWindowMode
    var isMusicWindow: Bool { windowMode == .music }

    private var tabMap: [ObjectIdentifier: BrowserTab] = [:]
    private var bookmarkTabsByID: [UUID: BrowserTab] = [:]
    private var tabMaintenanceTimer: Timer?
    private var themeObserver: NSObjectProtocol?
    private var settingsObserver: NSObjectProtocol?
    private var musicCommandObserver: NSObjectProtocol?
    private var lastMusicNextAt: Date = .distantPast
    private var lastMusicVolumeFeedbackAt: Date = .distantPast
    private var recentlyClosedTabs: [ClosedTabRecord] = []
    private var pendingSmartLearnQuery: String?
    private var pendingSmartLearnAt: Date?
    private var smartPredictionCache: [String: (url: URL, hits: Int)] = [:]
    private var smartPredictionMisses: Set<String> = []
    private var audioScriptInstalledControllers: Set<ObjectIdentifier> = []
    private var audioHandlerByWebViewID: [ObjectIdentifier: WeakScriptMessageHandler] = [:]
    private var extensionBridgeInstalledControllers: Set<ObjectIdentifier> = []
    private var extensionBridgeHandlerByControllerID: [ObjectIdentifier: WeakScriptMessageHandler] = [:]
    private var extensionDebugEvents: [String] = []
    private var lastSecurityBlockMessageAt: Date = .distantPast
    private var commandAliases: [String: String] = [:]
    private var activeDownloadSources: [ObjectIdentifier: URL?] = [:]
    private var activeDownloadDestinations: [ObjectIdentifier: URL] = [:]
    private var extensionInstallProgressTask: Task<Void, Never>?
    private var extensionInstallProgressToken = UUID()

    init(windowMode: BrowserWindowMode = .standard) {
        self.windowMode = windowMode
        super.init()
        loadBookmarks()
        loadHistory()
        loadDownloads()
        loadSavedLibrary()
        loadChromeTheme()
        loadCommandAliases()
        installThemeObserver()
        installSettingsObserver()
        installMusicCommandObserver()
        if !restoreTabsIfNeededOnLaunch() {
            openNewTab(select: true)
        }
        scheduleTabMaintenanceTimer()
    }

    deinit {
        tabMaintenanceTimer?.invalidate()
        extensionInstallProgressTask?.cancel()
        if let themeObserver {
            NotificationCenter.default.removeObserver(themeObserver)
        }
        if let settingsObserver {
            NotificationCenter.default.removeObserver(settingsObserver)
        }
        if let musicCommandObserver {
            NotificationCenter.default.removeObserver(musicCommandObserver)
        }
    }

    var selectedTab: BrowserTab? {
        guard let selectedTabID else { return tabs.first }
        return tabs.first(where: { $0.id == selectedTabID })
    }

    var canGoBack: Bool {
        selectedTab?.canGoBack ?? false
    }

    var canGoForward: Bool {
        selectedTab?.canGoForward ?? false
    }

    func openNewTab(
        select: Bool,
        url: URL? = nil,
        kind: BrowserTab.Kind = .regular,
        webViewConfiguration: WKWebViewConfiguration? = nil
    ) {
        let settings = MCVSettingsStore.shared.settings
        if isMusicWindow, let existingTab = tabs.first {
            if let url {
                existingTab.markActive()
                existingTab.load(url: url)
            } else {
                flashMessage("Music window supports one tab")
            }
            if select {
                selectedTabID = existingTab.id
                existingTab.markActive()
                syncSmartInputWithCurrentTab()
            }
            return
        }

        if kind == .regular {
            let tabLimit = max(1, settings.tabLimit)
            if tabs.filter({ !$0.isBookmarkTab }).count >= tabLimit {
                flashMessage("Tab limit reached (\(tabLimit))")
                return
            }
        }

        let activeSecurityMode = SecurityModeStore.current()
        let resolvedConfiguration = webViewConfiguration ?? makeConfiguration(for: activeSecurityMode)
        let tab = BrowserTab(kind: kind, webViewConfiguration: resolvedConfiguration, startPageTheme: chromeTheme)
        tab.webView.navigationDelegate = self
        tab.webView.uiDelegate = self
        if !tab.isHelpTab {
            setupAudioMonitoring(for: tab)
            setupWebExtensionBridge(for: tab)
        }
        if !settings.customUserAgent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            tab.webView.customUserAgent = settings.customUserAgent.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if let url {
            clearPendingSmartLearn()
            tab.load(url: url)
        } else {
            if kind == .regular {
                applyNewTabStartupBehavior(tab, using: settings)
            } else if kind == .help {
                tab.showHelpDocument(context: nil)
            }
        }

        if kind == .regular && settings.newTabPosition == .nextToCurrent,
           let selectedTabID,
           let selectedIndex = tabs.firstIndex(where: { $0.id == selectedTabID }) {
            tabs.insert(tab, at: min(selectedIndex + 1, tabs.count))
        } else {
            tabs.append(tab)
        }
        tabMap[ObjectIdentifier(tab.webView)] = tab

        if select || selectedTabID == nil {
            selectedTabID = tab.id
            tab.markActive()
            syncSmartInputWithCurrentTab()
        }
        saveTabSessionIfNeeded()
    }

    private func applyNewTabStartupBehavior(_ tab: BrowserTab, using settings: MCVBrowserSettings) {
        switch settings.newTabStart {
        case .startPage:
            break
        case .blankPage:
            tab.loadNewTabPage(theme: chromeTheme)
        case .customPage:
            let raw = settings.newTabCustomURL.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !raw.isEmpty else { return }
            let target = raw.contains("://") ? raw : "https://\(raw)"
            guard let customURL = URL(string: target) else { return }
            tab.load(url: customURL)
        }
    }

    private func restoreTabsIfNeededOnLaunch() -> Bool {
        guard windowMode == .standard else { return false }
        let settings = MCVSettingsStore.shared.settings
        guard settings.restoreTabsOnLaunch else {
            UserDefaults.standard.removeObject(forKey: AppKeys.tabSession)
            return false
        }
        guard !Self.didRestoreSessionForCurrentLaunch else { return false }
        Self.didRestoreSessionForCurrentLaunch = true

        guard let data = UserDefaults.standard.data(forKey: AppKeys.tabSession),
              let session = try? JSONDecoder().decode(TabSessionState.self, from: data),
              !session.urls.isEmpty else {
            return false
        }

        var restoredRegularIDs: [UUID] = []
        for rawURL in session.urls {
            guard let url = URL(string: rawURL),
                  let scheme = url.scheme?.lowercased(),
                  scheme == "http" || scheme == "https" else {
                continue
            }
            if let lastID = tabs.last?.id {
                selectedTabID = lastID
            }
            openNewTab(select: false, url: url, kind: .regular)
            if let id = tabs.last?.id {
                restoredRegularIDs.append(id)
            }
        }

        guard !restoredRegularIDs.isEmpty else {
            UserDefaults.standard.removeObject(forKey: AppKeys.tabSession)
            return false
        }

        let safeIndex = min(max(0, session.selectedIndex), restoredRegularIDs.count - 1)
        selectedTabID = restoredRegularIDs[safeIndex]
        selectedTab?.markActive()
        syncSmartInputWithCurrentTab()
        return true
    }

    private func saveTabSessionIfNeeded() {
        guard windowMode == .standard else { return }
        let settings = MCVSettingsStore.shared.settings
        guard settings.restoreTabsOnLaunch else {
            UserDefaults.standard.removeObject(forKey: AppKeys.tabSession)
            return
        }

        let regularTabs = tabs.filter { !$0.isBookmarkTab }
        let urls = regularTabs.compactMap { tab -> String? in
            guard !tab.isStartPage,
                  let url = tab.webView.url,
                  let scheme = url.scheme?.lowercased(),
                  scheme == "http" || scheme == "https" else {
                return nil
            }
            return url.absoluteString
        }

        guard !urls.isEmpty else {
            UserDefaults.standard.removeObject(forKey: AppKeys.tabSession)
            return
        }

        let selectedIndex: Int = {
            guard let selectedTabID else { return 0 }
            guard let idx = regularTabs.firstIndex(where: { $0.id == selectedTabID }) else { return 0 }
            return idx
        }()

        let session = TabSessionState(urls: urls, selectedIndex: selectedIndex)
        guard let data = try? JSONEncoder().encode(session) else { return }
        UserDefaults.standard.set(data, forKey: AppKeys.tabSession)
    }

    func closeSelectedTab() {
        guard let selectedTab else { return }
        closeTab(id: selectedTab.id)
    }

    func duplicateSelectedTab() {
        guard !isMusicWindow else {
            flashMessage("Duplicate not available in Music Window")
            return
        }
        guard let tab = selectedTab else { return }
        if let url = tab.webView.url {
            openNewTab(select: true, url: url, kind: .regular)
            flashMessage("Tab duplicated")
        } else {
            openNewTab(select: true)
            flashMessage("Tab duplicated")
        }
    }

    func restoreMostRecentlyClosedTab() {
        guard !isMusicWindow else {
            flashMessage("No closed tab history in Music Window")
            return
        }
        guard let record = recentlyClosedTabs.popLast() else {
            flashMessage("No recently closed tab")
            return
        }
        if let url = record.url {
            openNewTab(select: true, url: url, kind: .regular)
        } else {
            openNewTab(select: true)
        }
        let title = record.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty {
            flashMessage("Restored: \(title)")
        } else {
            flashMessage("Closed tab restored")
        }
    }

    func resetRegularTabsKeepingCurrent() {
        let currentRegularID: UUID? = {
            guard let current = selectedTab, !current.isBookmarkTab else { return nil }
            return current.id
        }()

        var removedCount = 0
        tabs.removeAll { tab in
            guard !tab.isBookmarkTab else { return false }
            if let currentRegularID, tab.id == currentRegularID {
                return false
            }
            tabMap.removeValue(forKey: ObjectIdentifier(tab.webView))
            removedCount += 1
            return true
        }

        guard removedCount > 0 else {
            flashMessage("Nothing to reset")
            return
        }

        if tabs.isEmpty {
            openNewTab(select: true)
            flashMessage("Reset regular tabs")
            return
        }

        if let currentRegularID,
           let kept = tabs.first(where: { $0.id == currentRegularID }) {
            selectedTabID = kept.id
            kept.markActive()
            syncSmartInputWithCurrentTab()
        } else {
            let selectionStillVisible = selectedTabID.map { id in tabs.contains(where: { $0.id == id }) } ?? false
            if !selectionStillVisible {
                selectedTabID = tabs[0].id
                tabs[0].markActive()
                syncSmartInputWithCurrentTab()
            }
        }

        flashMessage("Removed \(removedCount) regular tab(s)")
        saveTabSessionIfNeeded()
    }

    func selectTab(id: UUID) {
        selectedTabID = id
        selectedTab?.markActive()
        syncSmartInputWithCurrentTab()
        saveTabSessionIfNeeded()
    }

    func selectTab(index: Int) {
        guard tabs.indices.contains(index) else { return }
        selectedTabID = tabs[index].id
        tabs[index].markActive()
        syncSmartInputWithCurrentTab()
        saveTabSessionIfNeeded()
    }

    func selectRegularTabShortcut(index: Int) {
        let regularTabs = tabs.filter { !$0.isBookmarkTab }
        guard regularTabs.indices.contains(index) else { return }
        selectTab(id: regularTabs[index].id)
    }

    func moveBack() {
        selectedTab?.markActive()
        selectedTab?.webView.goBack()
    }

    func moveForward() {
        selectedTab?.markActive()
        selectedTab?.webView.goForward()
    }

    func reload() {
        selectedTab?.markActive()
        selectedTab?.webView.reload()
    }

    func hardReload() {
        selectedTab?.markActive()
        selectedTab?.webView.reloadFromOrigin()
        flashMessage("Hard reload")
    }

    func copyCurrentPageLinkToPasteboard() {
        guard let url = selectedTab?.webView.url else {
            flashMessage("No page URL to copy")
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
        flashMessage("Link copied")
    }

    func focusCurrentPage() {
        guard let webView = selectedTab?.webView else {
            flashMessage("No active page")
            return
        }
        let targetWindow = webView.window ?? NSApp.keyWindow ?? NSApp.mainWindow
        targetWindow?.makeKeyAndOrderFront(nil)
        targetWindow?.makeFirstResponder(webView)
        _ = webView.becomeFirstResponder()
    }

    func openSettingsWindow() {
        if NSApp.sendAction(NSSelectorFromString("showSettingsWindow:"), to: nil, from: nil) {
            return
        }
        _ = NSApp.sendAction(NSSelectorFromString("showPreferencesWindow:"), to: nil, from: nil)
    }

    func openHomePage() {
        guard let tab = selectedTab else {
            openNewTab(select: true)
            return
        }
        let settings = MCVSettingsStore.shared.settings
        switch settings.newTabStart {
        case .startPage:
            tab.loadNewTabPage(theme: chromeTheme)
            smartInput = ""
        case .blankPage:
            tab.loadNewTabPage(theme: chromeTheme)
            smartInput = ""
        case .customPage:
            let raw = settings.newTabCustomURL.trimmingCharacters(in: .whitespacesAndNewlines)
            if raw.isEmpty {
                tab.loadNewTabPage(theme: chromeTheme)
                smartInput = ""
                return
            }
            let target = raw.contains("://") ? raw : "https://\(raw)"
            guard let url = URL(string: target) else {
                flashMessage("Invalid home URL")
                return
            }
            clearPendingSmartLearn()
            tab.markActive()
            tab.load(url: url)
            smartInput = url.absoluteString
        }
    }

    func openDownloadsFolder() {
        let saved = MCVSettingsStore.shared.settings.downloadsFolderPath
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = NSSearchPathForDirectoriesInDomains(.downloadsDirectory, .userDomainMask, true).first
            ?? (NSHomeDirectory() + "/Downloads")
        let path = saved.isEmpty ? fallback : saved
        NSWorkspace.shared.open(URL(fileURLWithPath: path, isDirectory: true))
    }

    func removeHistoryItem(at index: Int) {
        guard history.indices.contains(index) else {
            flashMessage("History index out of range")
            return
        }
        let item = history[index]
        removeHistoryItem(item)
    }

    func setPlaybackRateCommand(_ raw: String?) {
        let cleaned = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !cleaned.isEmpty else {
            flashMessage("Usage: speed x1.5")
            return
        }

        let stripped = cleaned.hasPrefix("x") ? String(cleaned.dropFirst()) : cleaned
        guard let value = Double(stripped), value > 0.1, value <= 16.0 else {
            flashMessage("Invalid speed value")
            return
        }
        guard let webView = selectedTab?.webView else {
            flashMessage("No active tab")
            return
        }

        let js = """
        (() => {
          const rate = \(value);
          let changed = 0;
          const media = Array.from(document.querySelectorAll('video, audio'));
          for (const item of media) {
            try {
              item.playbackRate = rate;
              changed += 1;
            } catch (_) {}
          }
          return changed;
        })();
        """

        webView.evaluateJavaScript(js) { [weak self] result, _ in
            DispatchQueue.main.async {
                let count = (result as? NSNumber)?.intValue ?? 0
                if count > 0 {
                    self?.flashMessage("Speed set: x\(String(format: "%.2f", value))")
                } else {
                    self?.flashMessage("No media elements on page")
                }
            }
        }
    }

    func setScrollFactorCommand(_ raw: String?) {
        let cleaned = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !cleaned.isEmpty else {
            flashMessage("Usage: scroll x0.5")
            return
        }
        let stripped = cleaned.hasPrefix("x") ? String(cleaned.dropFirst()) : cleaned
        guard let value = Double(stripped), value >= 0.1, value <= 4.0 else {
            flashMessage("Invalid scroll factor")
            return
        }
        UserDefaults.standard.set(value, forKey: AppKeys.ctrlEScrollFactor)
        flashMessage("Scroll factor set: x\(String(format: "%.2f", value))")
    }

    func applyThemeCommand(_ raw: String?) {
        let value = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !value.isEmpty else {
            flashMessage("Usage: theme dark|light|off")
            return
        }

        let selection: AppearanceThemeOption
        switch value {
        case "dark":
            selection = .dark
        case "light":
            selection = .light
        case "off", "system", "default":
            selection = .system
        default:
            flashMessage("Unknown theme: \(value)")
            return
        }

        MCVSettingsStore.shared.update { $0.appearanceTheme = selection }
        flashMessage("Theme: \(selection.title)")
    }

    func applyOpacityCommand(_ raw: String?) {
        let value = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard let opacity = Double(value) else {
            flashMessage("Usage: pro opacity <0.05-1.0>")
            return
        }
        let clamped = min(max(opacity, 0.05), 1.0)
        MCVSettingsStore.shared.update { $0.interfaceOpacity = clamped }
        flashMessage("Opacity: \(String(format: "%.2f", clamped))")
    }

    func applyBlurCommand(_ raw: String?) {
        let value = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !value.isEmpty else {
            flashMessage("Usage: pro blur on|off")
            return
        }

        let target: Double
        if value == "on" {
            target = 0.8
        } else if value == "off" {
            target = 0.0
        } else if let numeric = Double(value) {
            target = min(max(numeric, 0.0), 1.0)
        } else {
            flashMessage("Invalid blur value")
            return
        }

        MCVSettingsStore.shared.update { $0.interfaceBlur = target }
        flashMessage("Blur: \(String(format: "%.2f", target))")
    }

    func applySuggestCommand(_ raw: String?) {
        let value = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard value == "on" || value == "off" else {
            flashMessage("Usage: pro suggest on|off")
            return
        }
        let enabled = value == "on"
        UserDefaults.standard.set(enabled, forKey: AppKeys.ctrlESuggestionsEnabled)
        flashMessage(enabled ? "Suggestions enabled" : "Suggestions disabled")
    }

    func applySmartCommand(_ raw: String?) {
        let value = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard value == "on" || value == "off" else {
            flashMessage("Usage: pro smart on|off")
            return
        }
        MCVSettingsStore.shared.update { $0.smartSearchEnabled = (value == "on") }
        flashMessage(value == "on" ? "Smart mode enabled" : "Smart mode disabled")
    }

    func applyRadiusCommand(_ raw: String?) {
        let value = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard let radius = Int(value), radius >= 4, radius <= 48 else {
            flashMessage("Usage: pro radius <int>")
            return
        }
        UserDefaults.standard.set(radius, forKey: AppKeys.ctrlECornerRadius)
        flashMessage("Ctrl+E radius: \(radius)")
    }

    func applySpotWindowCommand() {
        guard let window = activeWindow() else {
            flashMessage("No active window")
            return
        }
        window.setContentSize(NSSize(width: 980, height: 620))
        window.center()
        flashMessage("Compact window mode")
    }

    func toggleAlwaysOnTopWindow() {
        guard let window = activeWindow() else {
            flashMessage("No active window")
            return
        }
        if window.level == .floating {
            window.level = .normal
            flashMessage("Always-on-top: off")
        } else {
            window.level = .floating
            flashMessage("Always-on-top: on")
        }
    }

    func toggleMinimalWindow() {
        guard let window = activeWindow() else {
            flashMessage("No active window")
            return
        }
        window.toggleFullScreen(nil)
    }

    func resetCtrlEPreferences() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: AppKeys.ctrlESuggestionsEnabled)
        defaults.removeObject(forKey: AppKeys.ctrlEScrollFactor)
        defaults.removeObject(forKey: AppKeys.ctrlECornerRadius)
        flashMessage("Ctrl+E settings reset")
    }

    private func activeWindow() -> NSWindow? {
        NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first(where: { $0.isVisible })
    }

    private func makeConfiguration(for mode: SecurityModeOption) -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        applySecurityMode(mode, to: configuration)
        applyWebExtensions(to: configuration)
        return configuration
    }

    private func applySecurityMode(_ mode: SecurityModeOption, to configuration: WKWebViewConfiguration) {
        configuration.websiteDataStore = SecurityProfileRuntime.websiteDataStore(for: mode)
        configuration.processPool = SecurityProfileRuntime.processPool(for: mode)
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        if #available(macOS 12.3, *) {
            configuration.preferences.isElementFullscreenEnabled = true
        }
        if mode == .secure {
            let script = WKUserScript(
                source: SecureShield.scriptSource,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false
            )
            configuration.userContentController.addUserScript(script)
        }
    }

    private func applySecurityModeCommand(_ raw: String?) {
        let value = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let mode = SecurityModeOption(rawValue: value) else {
            flashMessage("Usage: mode classic|safe|secure")
            return
        }
        let changed = SecurityModeStore.set(mode)
        if changed {
            flashMessage("Security mode: \(mode.title) (opening new window)")
        } else {
            flashMessage("Security mode already \(mode.title)")
        }
    }

    private func applySecureJavaScriptCommand(_ raw: String?) {
        guard SecurityModeStore.current() == .secure else {
            flashMessage("`js on|off` is available only in secure mode")
            return
        }

        let value = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard value == "on" || value == "off" else {
            flashMessage("Usage: js on|off")
            return
        }

        guard let host = selectedTab?.webView.url?.host?.trimmingCharacters(in: .whitespacesAndNewlines),
              !host.isEmpty else {
            flashMessage("No active site host")
            return
        }

        let enabled = (value == "on")
        guard let normalizedHost = SecureJavaScriptPolicyStore.set(enabled: enabled, forHost: host) else {
            flashMessage("Invalid host")
            return
        }
        flashMessage(enabled ? "JavaScript enabled for \(normalizedHost)" : "JavaScript disabled for \(normalizedHost)")
        selectedTab?.webView.reload()
    }

    private func applyClearOnExitCommand(rawHost: String?, add: Bool) {
        guard SecurityModeStore.current() == .safe else {
            flashMessage("`clearonexit` is available only in safe mode")
            return
        }
        let raw = (rawHost ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else {
            flashMessage(add ? "Usage: clearonexit add <host>" : "Usage: clearonexit del <host>")
            return
        }
        if add {
            if let host = ClearOnExitStore.add(raw) {
                flashMessage("Will clear cookies on exit: \(host)")
            } else {
                flashMessage("Invalid host")
            }
            return
        }

        if let host = ClearOnExitStore.remove(raw) {
            flashMessage("Removed from clear-on-exit: \(host)")
        } else {
            flashMessage("Host not found")
        }
    }

    private func showClearOnExitHosts() {
        guard SecurityModeStore.current() == .safe else {
            flashMessage("`clearonexit list` is available only in safe mode")
            return
        }
        let hosts = ClearOnExitStore.hosts()
        if hosts.isEmpty {
            flashMessage("Clear-on-exit list is empty")
        } else {
            flashMessage("Clear-on-exit: \(hosts.joined(separator: ", "))")
        }
    }

    private func shouldBlockInsecureNavigation(_ url: URL?) -> Bool {
        guard SecurityModeStore.current() == .secure,
              let url,
              let scheme = url.scheme?.lowercased() else {
            return false
        }
        if scheme == "http" || scheme == "ws" {
            let now = Date()
            if now.timeIntervalSince(lastSecurityBlockMessageAt) > 0.85 {
                flashMessage("Secure mode blocked \(scheme.uppercased()) request")
                lastSecurityBlockMessageAt = now
            }
            return true
        }
        return false
    }

    private func secureJavaScriptEnabled(for url: URL?) -> Bool {
        guard SecurityModeStore.current() == .secure else { return true }
        guard let host = url?.host else { return true }
        return SecureJavaScriptPolicyStore.isEnabled(forHost: host)
    }

    private func requiresSafeDownloadConfirmation(_ navigationResponse: WKNavigationResponse) -> Bool {
        if !navigationResponse.canShowMIMEType {
            return true
        }
        guard let response = navigationResponse.response as? HTTPURLResponse,
              let contentDisposition = response.value(forHTTPHeaderField: "Content-Disposition")?.lowercased() else {
            return false
        }
        return contentDisposition.contains("attachment")
    }

    private func confirmSafeDownload(url: URL?) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Allow download in Safe mode?"
        alert.informativeText = url?.absoluteString ?? "Unknown download URL"
        alert.addButton(withTitle: "Allow")
        alert.addButton(withTitle: "Block")
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func shouldAllowDownload(url: URL?) -> Bool {
        guard SecurityModeStore.current() == .safe else {
            return true
        }
        let approved = confirmSafeDownload(url: url)
        if !approved {
            flashMessage("Download blocked in Safe mode")
        }
        return approved
    }

    private func defaultDownloadsDirectoryURL() -> URL {
        let fallback = NSSearchPathForDirectoriesInDomains(.downloadsDirectory, .userDomainMask, true).first
            ?? (NSHomeDirectory() + "/Downloads")
        return URL(fileURLWithPath: fallback, isDirectory: true)
    }

    private func downloadBaseDirectoryURL() -> URL {
        let settingsPath = MCVSettingsStore.shared.settings.downloadsFolderPath
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !settingsPath.isEmpty {
            return URL(fileURLWithPath: settingsPath, isDirectory: true)
        }
        return defaultDownloadsDirectoryURL()
    }

    private func ensureWritableDirectory(_ directory: URL) -> Bool {
        let fileManager = FileManager.default
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
        } catch {
            return false
        }
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: directory.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return false
        }
        return fileManager.isWritableFile(atPath: directory.path)
    }

    private func sanitizedDownloadFilename(_ suggestedFilename: String) -> String {
        var value = suggestedFilename.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty {
            value = "download"
        }
        value = value.replacingOccurrences(of: "/", with: "-")
        value = value.replacingOccurrences(of: ":", with: "-")
        value = value.replacingOccurrences(of: "\0", with: "")
        if value == "." || value == ".." || value.isEmpty {
            value = "download"
        }
        return value
    }

    private func nextDownloadDestination(for suggestedFilename: String) -> URL {
        let fileManager = FileManager.default
        let preferredDirectory = downloadBaseDirectoryURL()
        let fallbackDirectory = defaultDownloadsDirectoryURL()
        let directory: URL
        if ensureWritableDirectory(preferredDirectory) {
            directory = preferredDirectory
        } else if ensureWritableDirectory(fallbackDirectory) {
            directory = fallbackDirectory
            flashMessage("Downloads path unavailable, using ~/Downloads")
        } else {
            directory = preferredDirectory
        }

        let filename = sanitizedDownloadFilename(suggestedFilename)
        let base = (filename as NSString).deletingPathExtension
        let ext = (filename as NSString).pathExtension

        var candidate = directory.appendingPathComponent(filename, isDirectory: false)
        var suffix = 1
        while fileManager.fileExists(atPath: candidate.path) {
            let numbered = ext.isEmpty
                ? "\(base) (\(suffix))"
                : "\(base) (\(suffix)).\(ext)"
            candidate = directory.appendingPathComponent(numbered, isDirectory: false)
            suffix += 1
            if suffix > 10_000 {
                break
            }
        }
        return candidate
    }

    private func registerDownload(_ download: WKDownload, sourceURL: URL?) {
        activeDownloadSources[ObjectIdentifier(download)] = sourceURL
        download.delegate = self
    }

    private func addDownloadRecord(sourceURL: URL?, destinationURL: URL) {
        let path = destinationURL.path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return }

        let titleCandidate = destinationURL.lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = titleCandidate.isEmpty ? (sourceURL?.lastPathComponent ?? "download") : titleCandidate

        let item = DownloadItem(
            id: UUID(),
            title: title,
            sourceURL: sourceURL?.absoluteString ?? "",
            destinationPath: path,
            downloadedAt: Date()
        )

        downloads.removeAll { $0.destinationPath == item.destinationPath }
        downloads.insert(item, at: 0)
        if downloads.count > 300 {
            downloads = Array(downloads.prefix(300))
        }
        saveDownloads()
    }

    func captureAIPageSemanticSnapshot(completion: @escaping (AIPageSemanticSnapshot?) -> Void) {
        guard let webView = selectedTab?.webView else {
            DispatchQueue.main.async {
                completion(nil)
            }
            return
        }

        let js = #"""
        (() => {
          const normalize = (value) => String(value || "").replace(/\s+/g, " ").trim();
          const maxBlocks = 120;
          const maxBlockLen = 260;
          const maxActions = 100;
          const maxTextChars = 8000;
          const actionCounterByPrefix = { btn: 0, link: 0, input: 0, act: 0 };
          const actionCounterByBase = {};

          const isVisible = (el) => {
            if (!(el instanceof Element)) return false;
            const style = window.getComputedStyle(el);
            if (!style) return false;
            if (style.display === "none" || style.visibility === "hidden" || Number(style.opacity || "1") < 0.03) return false;
            const rect = el.getBoundingClientRect();
            if (!rect || rect.width < 2 || rect.height < 2) return false;
            if (rect.bottom < -6 || rect.right < -6 || rect.top > window.innerHeight + 6 || rect.left > window.innerWidth + 6) return false;
            return true;
          };

          const firstNonEmpty = (values) => {
            for (const item of values) {
              const text = normalize(item);
              if (text) return text;
            }
            return "";
          };

          const slugify = (value) => {
            const normalized = String(value || "").toLowerCase().trim();
            if (!normalized) return "";
            const collapsed = normalized.replace(/[^a-z0-9]+/g, "_").replace(/^_+|_+$/g, "");
            if (!collapsed) return "";
            return collapsed.slice(0, 24);
          };

          const nextActionID = (prefix, label) => {
            const slug = slugify(label);
            const base = slug ? `${prefix}_${slug}` : `${prefix}_item`;
            actionCounterByBase[base] = (actionCounterByBase[base] || 0) + 1;
            const index = actionCounterByBase[base];
            return index <= 1 ? base : `${base}_${index}`;
          };

          const selectorHint = (el) => {
            const tag = (el.tagName || "").toLowerCase();
            const id = normalize(el.getAttribute("id"));
            if (id) {
              return `${tag}#${id}`;
            }
            const classes = normalize(el.getAttribute("class")).split(" ").filter(Boolean).slice(0, 2);
            if (classes.length > 0) {
              return `${tag}.${classes.join(".")}`;
            }
            return tag;
          };

          const nearestContext = (el) => {
            let node = el;
            let depth = 0;
            while (node && depth < 6) {
              const aria = normalize(node.getAttribute && node.getAttribute("aria-label"));
              if (aria) return aria;

              if (node.matches && node.matches("form,section,article,aside,nav,main,header,footer,dialog")) {
                const heading = node.querySelector("h1,h2,h3,h4,legend,[aria-label]");
                if (heading) {
                  const headingText = normalize(heading.innerText || heading.textContent || heading.getAttribute("aria-label"));
                  if (headingText) return headingText;
                }
              }

              node = node.parentElement;
              depth += 1;
            }
            return "";
          };

          const describeAction = (el) => {
            const tag = (el.tagName || "").toUpperCase();
            const role = normalize(el.getAttribute("role"));
            let kind = "BUTTON";
            let prefix = "btn";
            if (tag === "A" || role === "link") {
              kind = "LINK";
              prefix = "link";
            } else if (tag === "INPUT" || tag === "TEXTAREA" || tag === "SELECT" || role === "textbox" || role === "searchbox") {
              kind = "INPUT";
              prefix = "input";
            } else if (role && role !== "button") {
              kind = "ACTION";
              prefix = "act";
            }

            const inputType = normalize(el.getAttribute("type"));
            const name = normalize(el.getAttribute("name"));
            const placeholder = normalize(el.getAttribute("placeholder"));
            const ariaLabel = normalize(el.getAttribute("aria-label"));
            const title = normalize(el.getAttribute("title"));
            const alt = normalize(el.getAttribute("alt"));
            const value = normalize(el.value);
            const ownText = normalize(el.innerText || el.textContent);
            const labelFromFor = (() => {
              const id = normalize(el.getAttribute("id"));
              if (!id) return "";
              const escaped = (window.CSS && CSS.escape) ? CSS.escape(id) : id.replace(/"/g, "");
              const label = document.querySelector(`label[for="${escaped}"]`);
              return label ? normalize(label.innerText || label.textContent) : "";
            })();
            const context = nearestContext(el);
            const label = firstNonEmpty([
              ariaLabel,
              labelFromFor,
              title,
              placeholder,
              alt,
              ownText,
              context,
              value,
              inputType ? `${kind.toLowerCase()} ${inputType}` : "",
              name
            ]);
            const hint = firstNonEmpty([inputType, name, placeholder]);

            let aiID = normalize(el.getAttribute("data-mcv-ai-id"));
            if (!aiID) {
                actionCounterByPrefix[prefix] = (actionCounterByPrefix[prefix] || 0) + 1;
              aiID = nextActionID(prefix, label || `${kind.toLowerCase()}_${actionCounterByPrefix[prefix]}`);
              el.setAttribute("data-mcv-ai-id", aiID);
            }

            return {
              id: aiID,
              kind,
              label: label || kind,
              role: role || tag.toLowerCase(),
              hint,
              context,
              selectorHint: selectorHint(el)
            };
          };

          try {
            const blocks = [];
            const seenBlocks = new Set();
            let totalChars = 0;
            const textSelectors = [
              "h1", "h2", "h3", "h4", "h5", "h6", "p", "li", "label", "button", "a", "summary",
              "article", "section", "main", "aside", "blockquote", "pre", "code"
            ];
            const textNodes = Array.from(document.querySelectorAll(textSelectors.join(",")));
            for (const el of textNodes) {
              if (blocks.length >= maxBlocks || totalChars >= maxTextChars) break;
              if (!isVisible(el)) continue;
              const text = normalize(el.innerText || el.textContent);
              if (!text || text.length < 2) continue;
              const clipped = text.length > maxBlockLen ? `${text.slice(0, maxBlockLen)}…` : text;
              if (seenBlocks.has(clipped)) continue;
              seenBlocks.add(clipped);
              blocks.push(clipped);
              totalChars += clipped.length;
            }

            const actions = [];
            const seenActionIDs = new Set();
            const candidates = Array.from(document.querySelectorAll([
              "button",
              "a[href]",
              "input:not([type='hidden'])",
              "textarea",
              "select",
              "[role='button']",
              "[role='link']",
              "[role='textbox']",
              "[role='searchbox']",
              "[tabindex]",
              "[onclick]"
            ].join(",")));
            for (const el of candidates) {
              if (actions.length >= maxActions) break;
              if (!isVisible(el)) continue;
              const action = describeAction(el);
              if (!action.id || seenActionIDs.has(action.id)) continue;
              seenActionIDs.add(action.id);
              actions.push(action);
            }

            return JSON.stringify({
              title: normalize(document.title || ""),
              url: normalize(location.href || ""),
              textBlocks: blocks,
              actions: actions
            });
          } catch (error) {
            return JSON.stringify({
              title: normalize(document.title || ""),
              url: normalize(location.href || ""),
              textBlocks: [],
              actions: [],
              error: String(error)
            });
          }
        })();
        """#

        webView.evaluateJavaScript(js) { [weak self] value, _ in
            guard let self else {
                DispatchQueue.main.async {
                    completion(nil)
                }
                return
            }
            let snapshot = self.parseAIPageSemanticSnapshot(from: value)
            DispatchQueue.main.async {
                completion(snapshot)
            }
        }
    }

    func executeAIPageAction(id rawID: String, typeText rawText: String?, completion: @escaping (Bool, String) -> Void) {
        let id = rawID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else {
            DispatchQueue.main.async {
                completion(false, "Action id is empty")
            }
            return
        }
        guard let webView = selectedTab?.webView else {
            DispatchQueue.main.async {
                completion(false, "No active tab")
            }
            return
        }

        let actionLiteral = jsStringLiteral(id)
        let textLiteral = jsStringLiteral(rawText ?? "")
        let modeLiteral = jsStringLiteral((rawText == nil) ? "click" : "type")

        let js = #"""
        (() => {
          const actionID = \#(actionLiteral);
          const mode = \#(modeLiteral);
          const value = \#(textLiteral);
          const normalize = (raw) => String(raw || "").replace(/\s+/g, " ").trim();

          const target = document.querySelector(`[data-mcv-ai-id="${actionID.replace(/"/g, '\\"')}"]`);
          if (!target) {
            return JSON.stringify({ success: false, message: "Action not found" });
          }

          try {
            target.scrollIntoView({ block: "center", inline: "center", behavior: "smooth" });
          } catch (_) {}

          if (mode === "type") {
            const textValue = String(value || "");
            if (target instanceof HTMLInputElement || target instanceof HTMLTextAreaElement) {
              target.focus();
              target.value = textValue;
              target.dispatchEvent(new Event("input", { bubbles: true }));
              target.dispatchEvent(new Event("change", { bubbles: true }));
              return JSON.stringify({ success: true, message: `Typed into ${actionID}` });
            }
            if (target.isContentEditable) {
              target.focus();
              target.textContent = textValue;
              target.dispatchEvent(new Event("input", { bubbles: true }));
              return JSON.stringify({ success: true, message: `Typed into ${actionID}` });
            }
            return JSON.stringify({ success: false, message: "Element is not typable" });
          }

          target.focus?.();
          target.click?.();
          const label = normalize(target.getAttribute("aria-label") || target.innerText || target.textContent || target.getAttribute("title"));
          return JSON.stringify({
            success: true,
            message: label ? `Clicked ${actionID} ${label}` : `Clicked ${actionID}`
          });
        })();
        """#

        webView.evaluateJavaScript(js) { [weak self] value, _ in
            guard let self else {
                DispatchQueue.main.async {
                    completion(false, "Action failed")
                }
                return
            }
            let payload = self.parseAIActionExecutionPayload(from: value)
            DispatchQueue.main.async {
                completion(payload.success, payload.message)
            }
        }
    }

    func findInCurrentPage(_ raw: String) {
        let query = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        searchInCurrentPage(query: query) { [weak self] suggestions, totalMatches in
            guard let self else { return }
            guard totalMatches > 0 else {
                self.flashMessage("Not found: \(query)")
                return
            }
            if let first = suggestions.first {
                self.focusFindSuggestion(markIndex: first.markIndex)
            }
            self.flashMessage("Found \(totalMatches) match(es)")
        }
    }

    func searchInCurrentPage(query raw: String, completion: @escaping ([PageFindSuggestion], Int) -> Void) {
        let query = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let webView = selectedTab?.webView else {
            DispatchQueue.main.async {
                completion([], 0)
            }
            return
        }

        guard !query.isEmpty else {
            clearFindHighlights(in: webView)
            DispatchQueue.main.async {
                completion([], 0)
            }
            return
        }

        let queryLiteral = jsStringLiteral(query)
        let js = #"""
        (() => {
          const query = \#(queryLiteral);
          const markAttr = "data-mcv-find-mark";
          const activeAttr = "data-mcv-find-active";
          const styleID = "__mcv_find_style";
          const maxSuggestions = 280;

          const clearMarks = () => {
            const marks = Array.from(document.querySelectorAll(`span[${markAttr}]`));
            for (const mark of marks) {
              const parent = mark.parentNode;
              if (!parent) continue;
              while (mark.firstChild) {
                parent.insertBefore(mark.firstChild, mark);
              }
              parent.removeChild(mark);
              parent.normalize();
            }
          };

          const ensureStyle = () => {
            let style = document.getElementById(styleID);
            if (!style) {
              style = document.createElement("style");
              style.id = styleID;
              (document.head || document.documentElement).appendChild(style);
            }
            style.textContent = `
              span[${markAttr}] {
                background: rgba(255, 220, 76, 0.65);
                color: inherit;
                border-radius: 2px;
                box-shadow: inset 0 0 0 1px rgba(229, 170, 26, 0.45);
              }
              span[${markAttr}][${activeAttr}="1"] {
                background: rgba(72, 154, 255, 0.74);
                box-shadow: inset 0 0 0 1px rgba(24, 89, 182, 0.66);
              }
            `;
          };

          const escapeRegExp = (value) => value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
          const toSnippet = (text, start, end) => {
            const left = Math.max(0, start - 30);
            const right = Math.min(text.length, end + 34);
            return text.slice(left, right).replace(/\s+/g, " ").trim();
          };

          const shouldSkipTag = (tag) => {
            if (!tag) return false;
            return ["SCRIPT", "STYLE", "NOSCRIPT", "TEXTAREA", "INPUT", "SELECT", "OPTION"].includes(tag);
          };

          try {
            clearMarks();
            const trimmed = String(query || "").trim();
            if (!trimmed) {
              return JSON.stringify({ suggestions: [], total: 0 });
            }

            ensureStyle();
            const regex = new RegExp(escapeRegExp(trimmed), "gi");
            const root = document.body || document.documentElement;
            if (!root) {
              return JSON.stringify({ suggestions: [], total: 0 });
            }

            const walker = document.createTreeWalker(
              root,
              NodeFilter.SHOW_TEXT,
              {
                acceptNode(node) {
                  if (!node || typeof node.nodeValue !== "string") {
                    return NodeFilter.FILTER_REJECT;
                  }
                  if (!node.nodeValue.trim()) {
                    return NodeFilter.FILTER_REJECT;
                  }
                  const parent = node.parentElement;
                  if (!parent || shouldSkipTag(parent.tagName)) {
                    return NodeFilter.FILTER_REJECT;
                  }
                  if (parent.closest(`span[${markAttr}]`)) {
                    return NodeFilter.FILTER_REJECT;
                  }
                  return NodeFilter.FILTER_ACCEPT;
                }
              }
            );

            const nodes = [];
            while (walker.nextNode()) {
              nodes.push(walker.currentNode);
            }

            const suggestions = [];
            let total = 0;
            for (const node of nodes) {
              const text = node.nodeValue || "";
              regex.lastIndex = 0;
              if (!regex.test(text)) {
                continue;
              }

              const fragment = document.createDocumentFragment();
              let last = 0;
              regex.lastIndex = 0;
              let match = null;
              while ((match = regex.exec(text)) !== null) {
                const start = match.index;
                const end = start + match[0].length;
                if (start > last) {
                  fragment.appendChild(document.createTextNode(text.slice(last, start)));
                }

                const span = document.createElement("span");
                span.setAttribute(markAttr, String(total));
                span.textContent = text.slice(start, end);
                fragment.appendChild(span);

                if (suggestions.length < maxSuggestions) {
                  suggestions.push({
                    id: total,
                    markIndex: total,
                    snippet: toSnippet(text, start, end)
                  });
                }

                total += 1;
                last = end;

                if (!match[0] || match[0].length === 0) {
                  regex.lastIndex += 1;
                }
              }

              if (last < text.length) {
                fragment.appendChild(document.createTextNode(text.slice(last)));
              }

              const parent = node.parentNode;
              if (parent) {
                parent.replaceChild(fragment, node);
              }
            }

            return JSON.stringify({
              suggestions,
              total
            });
          } catch (error) {
            return JSON.stringify({
              suggestions: [],
              total: 0,
              error: String(error)
            });
          }
        })();
        """#

        webView.evaluateJavaScript(js) { [weak self] value, _ in
            guard let self else { return }
            let payload = self.parseFindSuggestionsPayload(from: value)
            DispatchQueue.main.async {
                completion(payload.suggestions, payload.totalMatches)
            }
        }
    }

    func focusFindSuggestion(markIndex: Int, completion: ((Bool) -> Void)? = nil) {
        guard markIndex >= 0 else {
            completion?(false)
            return
        }
        guard let webView = selectedTab?.webView else {
            completion?(false)
            return
        }

        let js = #"""
        (() => {
          const markAttr = "data-mcv-find-mark";
          const activeAttr = "data-mcv-find-active";
          const marks = Array.from(document.querySelectorAll(`span[${markAttr}]`));
          if (marks.length === 0) return false;

          for (const mark of marks) {
            mark.removeAttribute(activeAttr);
          }

          const target = marks.find((item) => Number(item.getAttribute(markAttr)) === \#(markIndex));
          if (!target) return false;

          target.setAttribute(activeAttr, "1");
          target.scrollIntoView({
            block: "center",
            inline: "nearest",
            behavior: "smooth"
          });
          return true;
        })();
        """#

        webView.evaluateJavaScript(js) { value, _ in
            let succeeded = (value as? Bool) ?? ((value as? NSNumber)?.boolValue ?? false)
            DispatchQueue.main.async {
                completion?(succeeded)
            }
        }
    }

    func clearFindHighlights() {
        guard let webView = selectedTab?.webView else { return }
        clearFindHighlights(in: webView)
    }

    private func clearFindHighlights(in webView: WKWebView) {
        let js = #"""
        (() => {
          const markAttr = "data-mcv-find-mark";
          const styleID = "__mcv_find_style";
          try {
            const marks = Array.from(document.querySelectorAll(`span[${markAttr}]`));
            for (const mark of marks) {
              const parent = mark.parentNode;
              if (!parent) continue;
              while (mark.firstChild) {
                parent.insertBefore(mark.firstChild, mark);
              }
              parent.removeChild(mark);
              parent.normalize();
            }
            const style = document.getElementById(styleID);
            if (style && style.parentNode) {
              style.parentNode.removeChild(style);
            }
            return true;
          } catch (_) {
            return false;
          }
        })();
        """#
        webView.evaluateJavaScript(js, completionHandler: nil)
    }

    private func parseAIPageSemanticSnapshot(from value: Any?) -> AIPageSemanticSnapshot? {
        guard let raw = value as? String,
              let data = raw.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        let title = (object["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let url = (object["url"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let rawBlocks = object["textBlocks"] as? [Any] ?? []
        let visibleBlocks = rawBlocks.compactMap { item -> String? in
            let value = (item as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return value.isEmpty ? nil : value
        }

        let rawActions = object["actions"] as? [[String: Any]] ?? []
        let actions: [AIPageActionItem] = rawActions.compactMap { item in
            let id = (item["id"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !id.isEmpty else { return nil }
            let kind = (item["kind"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "ACTION"
            let label = (item["label"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? kind
            let role = (item["role"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let hint = (item["hint"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let context = (item["context"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let selectorHint = (item["selectorHint"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return AIPageActionItem(
                id: id,
                kind: kind,
                label: label,
                role: role,
                hint: hint,
                context: context,
                selectorHint: selectorHint
            )
        }

        return AIPageSemanticSnapshot(
            title: title,
            url: url,
            visibleTextBlocks: visibleBlocks,
            actions: actions
        )
    }

    private func parseAIActionExecutionPayload(from value: Any?) -> (success: Bool, message: String) {
        guard let raw = value as? String,
              let data = raw.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return (false, "Action failed")
        }

        let success: Bool
        if let boolValue = object["success"] as? Bool {
            success = boolValue
        } else if let number = object["success"] as? NSNumber {
            success = number.boolValue
        } else {
            success = false
        }
        let message = (object["message"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? (success ? "ok" : "failed")
        return (success, message)
    }

    private func parseFindSuggestionsPayload(from value: Any?) -> (suggestions: [PageFindSuggestion], totalMatches: Int) {
        guard let raw = value as? String,
              let data = raw.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return ([], 0)
        }

        let totalMatches = (object["total"] as? NSNumber)?.intValue ?? 0
        let rawSuggestions = object["suggestions"] as? [[String: Any]] ?? []
        let suggestions: [PageFindSuggestion] = rawSuggestions.compactMap { rawItem in
            let resolvedMarkIndex: Int
            if let numeric = rawItem["markIndex"] as? NSNumber {
                resolvedMarkIndex = numeric.intValue
            } else if let numericString = rawItem["markIndex"] as? String, let value = Int(numericString) {
                resolvedMarkIndex = value
            } else if let idNumeric = rawItem["id"] as? NSNumber {
                resolvedMarkIndex = idNumeric.intValue
            } else if let idString = rawItem["id"] as? String, let value = Int(idString) {
                resolvedMarkIndex = value
            } else {
                return nil
            }
            let snippetRaw = (rawItem["snippet"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let snippet = snippetRaw.isEmpty ? "Match \(resolvedMarkIndex + 1)" : snippetRaw
            return PageFindSuggestion(id: resolvedMarkIndex, markIndex: resolvedMarkIndex, snippet: snippet)
        }

        return (suggestions, max(totalMatches, suggestions.count))
    }

    private func jsStringLiteral(_ value: String) -> String {
        if let data = try? JSONSerialization.data(withJSONObject: [value], options: []),
           let encoded = String(data: data, encoding: .utf8),
           encoded.count >= 2 {
            let start = encoded.index(after: encoded.startIndex)
            let end = encoded.index(before: encoded.endIndex)
            return String(encoded[start..<end])
        }

        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
        return "\"\(escaped)\""
    }

    func openDevTools() {
        guard let webView = selectedTab?.webView else {
            flashMessage("No active tab")
            return
        }
        let opened = performInspectorAction(
            selectors: ["_showWebInspector", "_toggleWebInspector", "showWebInspector:"],
            on: webView
        )
        flashMessage(opened ? "DevTools opened" : "DevTools unavailable")
    }

    func openDevToolsConsole() {
        guard let webView = selectedTab?.webView else {
            flashMessage("No active tab")
            return
        }
        _ = performInspectorAction(
            selectors: ["_showWebInspector", "_toggleWebInspector", "showWebInspector:"],
            on: webView
        )
        let shown = performInspectorAction(
            selectors: ["_showJavaScriptConsole", "_showWebInspectorConsole", "_toggleWebInspectorJavaScriptConsole", "showConsole:"],
            on: webView
        )
        if shown {
            flashMessage("Console opened")
            return
        }
        webView.evaluateJavaScript("console.log('MCV: Cmd+J console shortcut')", completionHandler: nil)
        flashMessage("Console fallback")
    }

    @discardableResult
    private func performInspectorAction(selectors: [String], on webView: WKWebView) -> Bool {
        for selectorName in selectors {
            let selector = NSSelectorFromString(selectorName)
            guard webView.responds(to: selector) else { continue }
            if selectorName.hasSuffix(":") {
                _ = webView.perform(selector, with: nil)
            } else {
                _ = webView.perform(selector)
            }
            return true
        }
        return false
    }

    func focusCommandOverlay(mode: CommandOverlayMode = .mixed) {
        commandOverlayMode = mode
        isCommandOverlayVisible = true
        commandInput = ""
        overlayCommandArmed = (mode == .commandsOnly)
        commandSuggestions = mode == .commandsOnly
            ? commandCenterSuggestions(for: "")
            : searchOnlySuggestions(for: "")
        selectedCommandSuggestionIndex = nil
    }

    func closeCommandOverlay() {
        isCommandOverlayVisible = false
        commandOverlayMode = .mixed
        commandInput = ""
        overlayCommandArmed = false
        selectedCommandSuggestionIndex = nil
    }

    func toggleCommandOverlay(mode: CommandOverlayMode = .mixed) {
        if isCommandOverlayVisible, commandOverlayMode == mode {
            closeCommandOverlay()
        } else {
            focusCommandOverlay(mode: mode)
        }
    }

    func toggleCommandsOnlyOverlay() {
        toggleCommandOverlay(mode: .commandsOnly)
    }

    func updateCommandInput(_ value: String) {
        commandInput = value
        if commandOverlayMode == .commandsOnly {
            commandSuggestions = commandCenterSuggestions(for: value)
        } else {
            commandSuggestions = overlayCommandArmed ? suggestions(for: value) : searchOnlySuggestions(for: value)
        }
        selectedCommandSuggestionIndex = nil
    }

    func moveCommandSuggestionSelection(forward: Bool) {
        guard isCommandOverlayVisible else { return }
        guard !commandSuggestions.isEmpty else {
            selectedCommandSuggestionIndex = nil
            return
        }

        if let current = selectedCommandSuggestionIndex, commandSuggestions.indices.contains(current) {
            if forward {
                selectedCommandSuggestionIndex = (current + 1) % commandSuggestions.count
            } else {
                selectedCommandSuggestionIndex = (current - 1 + commandSuggestions.count) % commandSuggestions.count
            }
        } else {
            selectedCommandSuggestionIndex = forward ? 0 : commandSuggestions.count - 1
        }
    }

    func selectCommandSuggestion(at index: Int?) {
        guard let index else {
            selectedCommandSuggestionIndex = nil
            return
        }
        guard commandSuggestions.indices.contains(index) else {
            selectedCommandSuggestionIndex = nil
            return
        }
        selectedCommandSuggestionIndex = index
    }

    private func runCommandOverlayInput(_ input: String) {
        if isAIOverlayCommand(input) {
            flashMessage("AI command is available only in Mini MCV (Opt+Space)")
            closeCommandOverlay()
            return
        }

        if commandOverlayMode == .commandsOnly {
            if !applyBridge(for: input) {
                if !routeInputToMiniCalculatorIfNeeded(input) {
                    flashMessage("Unknown command")
                }
            }
            closeCommandOverlay()
            return
        }

        let commandPriority = MCVSettingsStore.shared.settings.commandPriority

        if overlayCommandArmed {
            if !applyBridge(for: input) {
                openResolvedInput(input)
            }
        } else {
            if commandPriority == .commandsFirst {
                if !applyBridge(for: input) {
                    openResolvedInput(input)
                }
            } else {
                openResolvedInput(input)
            }
        }
        closeCommandOverlay()
    }

    private func isAIOverlayCommand(_ input: String) -> Bool {
        let normalized = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized == "ai" || normalized.hasPrefix("ai ")
    }

    func executeCommandOverlay() {
        if let selected = selectedCommandSuggestionIndex,
           commandSuggestions.indices.contains(selected) {
            let suggestion = commandSuggestions[selected]
            if !suggestion.value.isEmpty {
                executeSuggestion(suggestion)
                return
            }
        }

        let input = commandInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return }
        runCommandOverlayInput(input)
    }

    func executeSuggestion(_ suggestion: CommandSuggestion) {
        guard !suggestion.value.isEmpty else { return }
        commandInput = suggestion.value
        runCommandOverlayInput(suggestion.value)
    }

    func submitSmartBar() {
        let input = smartInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return }
        let commandPriority = MCVSettingsStore.shared.settings.commandPriority

        if smartBarCommandArmed {
            if !applyBridge(for: input) {
                openResolvedInput(input)
            }
            return
        }

        if commandPriority == .commandsFirst {
            if !applyBridge(for: input) {
                openResolvedInput(input)
            }
        } else {
            openResolvedInput(input)
        }
    }

    func executeRawInput(_ raw: String) {
        let input = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return }
        if !applyBridge(for: input) {
            openResolvedInput(input)
        }
    }

    func executeMusicCommand(
        action: String,
        query: String? = nil,
        delta: Double? = nil,
        mood: String? = nil,
        sourceURL: String? = nil,
        sourceTitle: String? = nil
    ) {
        handleMusicCommand(
            action: action,
            query: query,
            delta: delta,
            mood: mood,
            sourceURL: sourceURL,
            sourceTitle: sourceTitle
        )
    }

    func fetchMusicWheelNowPlaying(_ completion: @escaping (MusicWheelNowPlaying) -> Void) {
        guard let tab = selectedTab else {
            completion(.placeholder)
            return
        }

        let fallbackTitle = tab.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "No track" : tab.title
        let fallbackSubtitle = tab.webView.url?.host() ?? (isMusicWindow ? "Music Window" : "Current tab")
        let fallback = MusicWheelNowPlaying(
            title: fallbackTitle,
            subtitle: fallbackSubtitle,
            progress: 0,
            artworkURL: nil,
            sourceURL: tab.webView.url?.absoluteString
        )

        let js = """
        (() => {
          const mediaList = Array.from(document.querySelectorAll('audio,video'));
          const active = mediaList.find((m) => {
            try { return !m.paused || Number(m.currentTime || 0) > 0; } catch (_) { return false; }
          }) || mediaList[0] || null;
          const metadata = navigator.mediaSession && navigator.mediaSession.metadata ? navigator.mediaSession.metadata : null;
          let artwork = '';
          if (metadata && Array.isArray(metadata.artwork) && metadata.artwork.length > 0) {
            artwork = metadata.artwork[0].src || '';
          }
          let progress = -1;
          if (active && Number.isFinite(active.duration) && active.duration > 0) {
            progress = Number(active.currentTime || 0) / Number(active.duration);
          }
          return JSON.stringify({
            title: (metadata && metadata.title) || document.title || '',
            artist: (metadata && metadata.artist) || '',
            progress,
            artwork,
            href: location.href || '',
            host: location.host || ''
          });
        })();
        """

        tab.webView.evaluateJavaScript(js) { value, _ in
            var result = fallback
            if let raw = value as? String,
               let data = raw.data(using: .utf8),
               let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let title = (object["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let artist = (object["artist"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let host = (object["host"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let source = (object["href"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                let progressRaw = (object["progress"] as? NSNumber)?.doubleValue ?? -1
                let progress = min(max(progressRaw, 0), 1)
                let artwork = (object["artwork"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                result = MusicWheelNowPlaying(
                    title: title.isEmpty ? fallback.title : title,
                    subtitle: artist.isEmpty ? (host.isEmpty ? fallback.subtitle : host) : artist,
                    progress: progressRaw >= 0 ? progress : fallback.progress,
                    artworkURL: (artwork?.isEmpty == false) ? artwork : nil,
                    sourceURL: (source?.isEmpty == false) ? source : fallback.sourceURL
                )
            }
            DispatchQueue.main.async {
                completion(result)
            }
        }
    }

    func toggleSmartBarCommandMode() {
        smartBarCommandArmed.toggle()
    }

    func toggleOverlayCommandMode() {
        guard commandOverlayMode != .commandsOnly else { return }
        overlayCommandArmed.toggle()
        commandSuggestions = overlayCommandArmed ? suggestions(for: commandInput) : searchOnlySuggestions(for: commandInput)
        selectedCommandSuggestionIndex = nil
    }

    func addCurrentTabToBookmarks() {
        selectedTab?.markActive()
        guard let tab = selectedTab,
              let url = tab.webView.url,
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            flashMessage("Cannot bookmark this page")
            return
        }

        let title = tab.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? (url.host ?? url.absoluteString) : tab.title
        let existingItem = bookmarks.first(where: { $0.url == url.absoluteString })
        let item = BookmarkItem(
            id: existingItem?.id ?? tab.bookmarkID ?? UUID(),
            title: title,
            url: url.absoluteString,
            addedAt: Date(),
            shortcut: existingItem?.shortcut
        )

        bookmarks.removeAll { $0.url == item.url }
        bookmarks.insert(item, at: 0)
        saveBookmarks()
        flashMessage("Bookmark added")
    }

    func openBookmark(_ item: BookmarkItem) {
        guard let url = URL(string: item.url) else { return }
        clearPendingSmartLearn()

        if isMusicWindow {
            selectedTab?.markActive()
            selectedTab?.load(url: url)
            utilityPanel = nil
            return
        }

        if let visible = tabs.first(where: { $0.bookmarkID == item.id }) {
            if visible.id == selectedTabID {
                hideBookmarkTab(visible)
                utilityPanel = nil
                return
            }
            selectTab(id: visible.id)
            utilityPanel = nil
            return
        }

        if let hidden = bookmarkTabsByID[item.id] {
            tabs.append(hidden)
            selectedTabID = hidden.id
            hidden.markActive()
            syncSmartInputWithCurrentTab()
            utilityPanel = nil
            return
        }

        let bookmarkTab = BrowserTab(kind: .bookmark(item.id))
        bookmarkTab.webView.navigationDelegate = self
        bookmarkTab.webView.uiDelegate = self
        setupAudioMonitoring(for: bookmarkTab)
        setupWebExtensionBridge(for: bookmarkTab)
        bookmarkTab.load(url: url)
        bookmarkTabsByID[item.id] = bookmarkTab
        tabMap[ObjectIdentifier(bookmarkTab.webView)] = bookmarkTab
        tabs.append(bookmarkTab)
        selectedTabID = bookmarkTab.id
        bookmarkTab.markActive()
        syncSmartInputWithCurrentTab()
        utilityPanel = nil
    }

    func openHistoryItem(_ item: HistoryItem) {
        guard let url = URL(string: item.url) else { return }
        clearPendingSmartLearn()
        selectedTab?.markActive()
        selectedTab?.load(url: url)
        utilityPanel = nil
    }

    func addCurrentTabToSaved(folderID: UUID?) {
        selectedTab?.markActive()
        guard let tab = selectedTab,
              let url = tab.webView.url,
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            flashMessage("Cannot save this page")
            return
        }

        let safeFolderID = resolveExistingSavedFolderID(folderID)
        let cleanTitle = tab.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = cleanTitle.isEmpty ? (url.host ?? url.absoluteString) : cleanTitle

        if let existingIndex = savedLinks.firstIndex(where: { $0.url == url.absoluteString && $0.folderID == safeFolderID }) {
            let existing = savedLinks[existingIndex]
            let updated = SavedLink(
                id: existing.id,
                title: title,
                url: url.absoluteString,
                folderID: safeFolderID,
                addedAt: Date()
            )
            savedLinks.remove(at: existingIndex)
            savedLinks.insert(updated, at: 0)
        } else {
            let link = SavedLink(
                id: UUID(),
                title: title,
                url: url.absoluteString,
                folderID: safeFolderID,
                addedAt: Date()
            )
            savedLinks.insert(link, at: 0)
        }

        saveSavedLibrary()
        flashMessage("Saved page")
    }

    @discardableResult
    func createSavedFolder(name raw: String, parentID: UUID?) -> SavedFolder? {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        let safeParentID = resolveExistingSavedFolderID(parentID)
        let duplicate = savedFolders.contains {
            $0.parentID == safeParentID && $0.name.caseInsensitiveCompare(name) == .orderedSame
        }
        guard !duplicate else {
            flashMessage("Folder already exists")
            return nil
        }
        let folder = SavedFolder(id: UUID(), name: name, parentID: safeParentID, createdAt: Date())
        savedFolders.append(folder)
        saveSavedLibrary()
        flashMessage("Folder created")
        return folder
    }

    func openSavedLink(_ item: SavedLink) {
        guard let url = URL(string: item.url) else {
            flashMessage("Invalid saved link")
            return
        }
        clearPendingSmartLearn()
        selectedTab?.markActive()
        selectedTab?.load(url: url)
    }

    func moveSavedLink(id: UUID, to folderID: UUID?) {
        guard let sourceIndex = savedLinks.firstIndex(where: { $0.id == id }) else { return }
        let safeFolderID = resolveExistingSavedFolderID(folderID)
        let source = savedLinks[sourceIndex]
        guard source.folderID != safeFolderID else { return }

        savedLinks.remove(at: sourceIndex)
        savedLinks.removeAll { candidate in
            candidate.url == source.url && candidate.folderID == safeFolderID
        }

        let moved = SavedLink(
            id: source.id,
            title: source.title,
            url: source.url,
            folderID: safeFolderID,
            addedAt: Date()
        )
        savedLinks.insert(moved, at: 0)
        saveSavedLibrary()
        if safeFolderID == nil {
            flashMessage("Link moved to Root")
        } else {
            flashMessage("Link moved")
        }
    }

    func removeSavedLink(_ item: SavedLink) {
        guard savedLinks.contains(where: { $0.id == item.id }) else { return }
        savedLinks.removeAll { $0.id == item.id }
        saveSavedLibrary()
        flashMessage("Saved link removed")
    }

    func removeSavedFolder(_ folder: SavedFolder) {
        guard savedFolders.contains(where: { $0.id == folder.id }) else { return }
        let cascadeFolderIDs = savedFolderCascade(folderID: folder.id)
        let deletedFolderIDs = Set(cascadeFolderIDs)

        savedFolders.removeAll { deletedFolderIDs.contains($0.id) }
        savedLinks.removeAll { link in
            guard let folderID = link.folderID else { return false }
            return deletedFolderIDs.contains(folderID)
        }
        saveSavedLibrary()
        flashMessage("Folder deleted")
    }

    func savedFolderCascadeCounts(folderID: UUID) -> (folders: Int, links: Int) {
        let cascadeFolderIDs = savedFolderCascade(folderID: folderID)
        let folders = cascadeFolderIDs.count
        let folderSet = Set(cascadeFolderIDs)
        let links = savedLinks.filter { link in
            guard let folderID = link.folderID else { return false }
            return folderSet.contains(folderID)
        }.count
        return (folders, links)
    }

    func savedChildFolders(parentID: UUID?) -> [SavedFolder] {
        let safeParent = resolveExistingSavedFolderID(parentID)
        return savedFolders
            .filter { $0.parentID == safeParent }
            .sorted { lhs, rhs in
                lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }

    func savedChildLinks(folderID: UUID?) -> [SavedLink] {
        let safeFolder = resolveExistingSavedFolderID(folderID)
        return savedLinks
            .filter { $0.folderID == safeFolder }
            .sorted { lhs, rhs in
                lhs.addedAt > rhs.addedAt
            }
    }

    func savedParentFolderID(for folderID: UUID?) -> UUID? {
        guard let folderID else { return nil }
        return savedFolders.first(where: { $0.id == folderID })?.parentID
    }

    func savedFolderPath(for folderID: UUID?) -> [SavedFolder] {
        guard let folderID else { return [] }

        var path: [SavedFolder] = []
        var cursor = folderID
        var guardLoop = 0

        while guardLoop < 200, let folder = savedFolders.first(where: { $0.id == cursor }) {
            path.append(folder)
            guard let parent = folder.parentID else { break }
            cursor = parent
            guardLoop += 1
        }

        return path.reversed()
    }

    func clearHistory() {
        history.removeAll()
        saveHistory()
    }

    func clearDownloads() {
        downloads.removeAll()
        saveDownloads()
        flashMessage("Download history cleared")
    }

    func clearWebsiteData() {
        let mode = SecurityModeStore.current()
        let store = SecurityProfileRuntime.websiteDataStore(for: mode)
        let dataTypes = WKWebsiteDataStore.allWebsiteDataTypes()
        store.fetchDataRecords(ofTypes: dataTypes) { [weak self] records in
            store.removeData(ofTypes: dataTypes, for: records) {
                DispatchQueue.main.async {
                    self?.flashMessage("Cookies and website data cleared")
                }
            }
        }
    }

    func removeHistoryItem(_ item: HistoryItem) {
        history.removeAll { $0.id == item.id }
        saveHistory()
        flashMessage("History entry removed")
    }

    func removeDownloadItem(_ item: DownloadItem) {
        downloads.removeAll { $0.id == item.id }
        saveDownloads()
    }

    func openDownloadItem(_ item: DownloadItem) {
        let path = item.destinationPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else {
            flashMessage("Downloaded file path is empty")
            return
        }
        let fileURL = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            flashMessage("Downloaded file not found")
            return
        }
        NSWorkspace.shared.open(fileURL)
    }

    func revealDownloadItem(_ item: DownloadItem) {
        let path = item.destinationPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else {
            flashMessage("Downloaded file path is empty")
            return
        }
        let fileURL = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            flashMessage("Downloaded file not found")
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
    }

    func removeBookmarkItem(_ item: BookmarkItem) {
        guard bookmarks.contains(where: { $0.id == item.id }) else { return }

        bookmarks.removeAll { $0.id == item.id }
        saveBookmarks()

        if let cached = bookmarkTabsByID.removeValue(forKey: item.id) {
            AudioFocusCoordinator.shared.releaseIfCurrent(cached.webView)
            cached.hasAudio = false
            tabMap.removeValue(forKey: ObjectIdentifier(cached.webView))
            audioHandlerByWebViewID.removeValue(forKey: ObjectIdentifier(cached.webView))
        }

        if let index = tabs.firstIndex(where: { $0.bookmarkID == item.id }) {
            let tab = tabs[index]
            AudioFocusCoordinator.shared.releaseIfCurrent(tab.webView)
            tab.hasAudio = false
            tabMap.removeValue(forKey: ObjectIdentifier(tab.webView))
            audioHandlerByWebViewID.removeValue(forKey: ObjectIdentifier(tab.webView))
            tabs.remove(at: index)

            if tabs.isEmpty {
                openNewTab(select: true)
            } else if selectedTabID == tab.id {
                let safeIndex = min(index, tabs.count - 1)
                selectedTabID = tabs[safeIndex].id
                tabs[safeIndex].markActive()
                syncSmartInputWithCurrentTab()
            }
        }

        saveTabSessionIfNeeded()
        flashMessage("Bookmark removed")
    }

    func clearBookmarks() {
        let selectedWasBookmark = selectedTab?.isBookmarkTab ?? false

        tabs.removeAll { $0.isBookmarkTab }
        for tab in bookmarkTabsByID.values {
            tabMap.removeValue(forKey: ObjectIdentifier(tab.webView))
        }
        bookmarkTabsByID.removeAll()

        bookmarks.removeAll()
        saveBookmarks()

        if tabs.isEmpty {
            openNewTab(select: true)
            return
        }

        let selectionStillVisible = selectedTabID.map { id in tabs.contains(where: { $0.id == id }) } ?? false
        if selectedWasBookmark || !selectionStillVisible {
            selectedTabID = tabs[0].id
            tabs[0].markActive()
            syncSmartInputWithCurrentTab()
        }
        saveTabSessionIfNeeded()
    }

    func clearSavedLibrary() {
        savedFolders.removeAll()
        savedLinks.removeAll()
        saveSavedLibrary()

        commandAliases.removeAll()
        saveCommandAliases()
    }

    func resetForFirstLaunchTesting() {
        clearPendingSmartLearn()
        smartPredictionCache.removeAll()
        smartPredictionMisses.removeAll()
        recentlyClosedTabs.removeAll()

        history.removeAll()
        saveHistory()

        downloads.removeAll()
        saveDownloads()

        bookmarks.removeAll()
        saveBookmarks()

        savedFolders.removeAll()
        savedLinks.removeAll()
        saveSavedLibrary()

        for tab in tabs {
            AudioFocusCoordinator.shared.releaseIfCurrent(tab.webView)
            tab.hasAudio = false
        }
        tabs.removeAll()
        tabMap.removeAll()
        bookmarkTabsByID.removeAll()
        audioScriptInstalledControllers.removeAll()
        audioHandlerByWebViewID.removeAll()
        selectedTabID = nil

        utilityPanel = nil
        isCommandOverlayVisible = false
        commandOverlayMode = .mixed
        commandInput = ""
        commandSuggestions = []
        selectedCommandSuggestionIndex = nil
        smartBarCommandArmed = false
        overlayCommandArmed = false
        transientMessage = nil

        chromeTheme = .default
        saveChromeTheme()

        openNewTab(select: true, kind: .regular)
    }

    func toggleBookmarksPanel() {
        if utilityPanel == .bookmarks {
            utilityPanel = nil
        } else {
            utilityPanel = .bookmarks
        }
    }

    func toggleHistoryPanel() {
        if utilityPanel == .history {
            utilityPanel = nil
        } else {
            utilityPanel = .history
        }
    }

    func toggleColorsPanel() {
        if utilityPanel == .colors {
            utilityPanel = nil
        } else {
            utilityPanel = .colors
        }
    }

    func toggleExtensionsPanel() {
        if utilityPanel == .extensions {
            utilityPanel = nil
        } else {
            utilityPanel = .extensions
        }
    }

    func reloadWebExtensionsRuntime(reloadTabs: Bool) {
        reloadWebExtensionsAndRefreshTabs(reloadTabs: reloadTabs)
    }

    func installExtensionFromInput(_ raw: String) {
        let argument = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !argument.isEmpty else {
            flashMessage("Usage: ext install <folder|webstore_url|extension_id>")
            return
        }
        installExtensionAsync(argument: argument)
    }

    func extensionBundlesForPanel() -> [WebExtensionBundle] {
        WebExtensionManager.shared.listBundles().sorted { lhs, rhs in
            if lhs.enabled != rhs.enabled {
                return lhs.enabled && !rhs.enabled
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    func copyExtensionIDToPasteboard(_ extensionID: String) {
        let cleaned = extensionID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            flashMessage("Extension id is empty")
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(cleaned, forType: .string)
        flashMessage("Extension id copied")
    }

    func removeExtensionFromPanel(_ extensionID: String) {
        let cleaned = extensionID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            flashMessage("Extension id is empty")
            return
        }
        if WebExtensionManager.shared.removeExtension(id: cleaned) {
            reloadWebExtensionsAndRefreshTabs(reloadTabs: true)
            flashMessage("Extension removed: \(cleaned)")
        } else {
            flashMessage("Extension not found: \(cleaned)")
        }
    }

    func renameExtensionFromPanel(_ extensionID: String, customName: String?) {
        let cleaned = extensionID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            flashMessage("Extension id is empty")
            return
        }
        do {
            guard try WebExtensionManager.shared.renameExtension(id: cleaned, customName: customName) else {
                flashMessage("Extension not found: \(cleaned)")
                return
            }
            reloadWebExtensionsAndRefreshTabs(reloadTabs: false)
            let visibleName = WebExtensionManager.shared.bundle(id: cleaned)?.name ?? cleaned
            flashMessage("Extension renamed: \(visibleName)")
        } catch {
            flashMessage("Rename failed: \(error.localizedDescription)")
        }
    }

    private func installExtensionAsync(argument: String) {
        let expandedPath = NSString(string: argument).expandingTildeInPath
        var isDirectory: ObjCBool = false
        let isFolderInstall = FileManager.default.fileExists(atPath: expandedPath, isDirectory: &isDirectory) && isDirectory.boolValue
        let isWebStoreInstall = WebStoreCRXInstaller.extractExtensionID(from: argument) != nil

        guard isFolderInstall || isWebStoreInstall else {
            flashMessage("Provide folder path or Chrome Web Store URL/ID")
            return
        }

        utilityPanel = .extensions
        beginExtensionInstallProgress(mode: isFolderInstall ? "Installing unpacked extension" : "Downloading extension")

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            do {
                let bundle: WebExtensionBundle
                if isFolderInstall {
                    bundle = try WebExtensionManager.shared.installUnpackedExtension(from: argument)
                } else {
                    bundle = try WebStoreCRXInstaller.shared.installFromWebStoreInput(argument)
                }
                DispatchQueue.main.async {
                    self.reloadWebExtensionsAndRefreshTabs(reloadTabs: true)
                    let message = "Installed \(bundle.name) (\(bundle.id), tier \(bundle.tier.title))"
                    self.finishExtensionInstallProgress(success: true, message: message)
                    self.flashMessage(message)
                }
            } catch {
                DispatchQueue.main.async {
                    let message = "Extension install failed: \(error.localizedDescription)"
                    self.finishExtensionInstallProgress(success: false, message: message)
                    self.flashMessage(message)
                }
            }
        }
    }

    private func beginExtensionInstallProgress(mode: String) {
        extensionInstallProgressTask?.cancel()
        extensionInstallProgressToken = UUID()
        let token = extensionInstallProgressToken
        extensionInstallInProgress = true
        extensionInstallProgress = 0.05
        extensionInstallStatus = mode
        extensionInstallProgressTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 350_000_000)
                if Task.isCancelled {
                    break
                }
                await MainActor.run {
                    guard let self else { return }
                    guard self.extensionInstallProgressToken == token else { return }
                    let remaining = max(0.0, 0.92 - self.extensionInstallProgress)
                    let step = max(0.015, remaining * 0.28)
                    self.extensionInstallProgress = min(0.92, self.extensionInstallProgress + step)
                }
            }
        }
    }

    private func finishExtensionInstallProgress(success: Bool, message: String) {
        extensionInstallProgressTask?.cancel()
        extensionInstallProgressTask = nil
        extensionInstallProgressToken = UUID()
        extensionInstallStatus = message
        if success {
            extensionInstallProgress = 1.0
        } else {
            extensionInstallProgress = max(0.10, min(extensionInstallProgress, 0.88))
        }

        let token = extensionInstallProgressToken
        let delay: TimeInterval = success ? 1.1 : 2.0
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            guard self.extensionInstallProgressToken == token else { return }
            self.extensionInstallInProgress = false
            self.extensionInstallProgress = 0.0
            self.extensionInstallStatus = ""
        }
    }

    func setChromeTheme(
        red: Double? = nil,
        green: Double? = nil,
        blue: Double? = nil,
        intensity: Double? = nil,
        broadcast: Bool = true
    ) {
        var next = chromeTheme
        if let red { next.red = red }
        if let green { next.green = green }
        if let blue { next.blue = blue }
        if let intensity { next.intensity = intensity }
        applyChromeTheme(next, broadcast: broadcast)
    }

    func applyChromePreset(_ preset: ChromeTheme) {
        applyChromeTheme(preset, broadcast: true)
    }

    func resetChromeTheme() {
        applyChromeTheme(.default, broadcast: true)
    }

    func selectBookmarkShortcut(index: Int) {
        guard bookmarks.indices.contains(index) else {
            flashMessage("No bookmark \(index + 1)")
            return
        }
        openBookmark(bookmarks[index])
    }

    func openBookmarkByCustomShortcut(event: NSEvent) -> Bool {
        guard let triggerKey = BookmarkShortcut.fromEvent(event)?.matchKey else { return false }
        guard let item = bookmarks.first(where: { $0.shortcut?.matchKey == triggerKey }) else {
            return false
        }
        openBookmark(item)
        return true
    }

    func setBookmarkShortcut(bookmarkID: UUID, input rawInput: String) {
        guard let targetIndex = bookmarks.firstIndex(where: { $0.id == bookmarkID }) else { return }
        let trimmed = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty {
            if bookmarks[targetIndex].shortcut != nil {
                bookmarks[targetIndex].shortcut = nil
                saveBookmarks()
                flashMessage("Bookmark hotkey cleared")
            }
            return
        }

        guard let parsed = BookmarkShortcut.parse(trimmed),
              let parsedKey = parsed.matchKey else {
            flashMessage("Invalid hotkey use one letter or digit")
            return
        }

        if let duplicateIndex = bookmarks.firstIndex(where: {
            $0.id != bookmarkID && $0.shortcut?.matchKey == parsedKey
        }) {
            bookmarks[duplicateIndex].shortcut = nil
        }

        bookmarks[targetIndex].shortcut = parsed
        saveBookmarks()
        flashMessage("Bookmark hotkey set \(parsed.displayLabel)")
    }

    func reorderBookmarks(draggedID: UUID, to targetID: UUID) {
        guard draggedID != targetID else { return }
        guard let sourceIndex = bookmarks.firstIndex(where: { $0.id == draggedID }),
              let targetIndex = bookmarks.firstIndex(where: { $0.id == targetID }) else {
            return
        }

        var updated = bookmarks
        let moved = updated.remove(at: sourceIndex)
        let destination = sourceIndex < targetIndex ? max(0, targetIndex - 1) : targetIndex
        updated.insert(moved, at: destination)
        bookmarks = updated
        saveBookmarks()
    }

    private func resolveExistingSavedFolderID(_ candidate: UUID?) -> UUID? {
        guard let candidate else { return nil }
        return savedFolders.contains(where: { $0.id == candidate }) ? candidate : nil
    }

    private func savedFolderCascade(folderID: UUID) -> [UUID] {
        var queue: [UUID] = [folderID]
        var index = 0
        var visited: Set<UUID> = []

        while index < queue.count {
            let current = queue[index]
            index += 1
            guard !visited.contains(current) else { continue }
            visited.insert(current)

            let children = savedFolders
                .filter { $0.parentID == current }
                .map(\.id)
            queue.append(contentsOf: children)
        }

        return Array(visited)
    }

    func cycleBookmarkTabs(forward: Bool) {
        cycleTabs(
            candidates: tabs.filter(\.isBookmarkTab),
            forward: forward,
            emptyMessage: "No bookmark tabs open"
        )
    }

    func cycleRegularTabs(forward: Bool) {
        cycleTabs(
            candidates: tabs.filter { !$0.isBookmarkTab },
            forward: forward,
            emptyMessage: "No regular tabs open"
        )
    }

    func syncSmartInputWithCurrentTab() {
        guard let tab = selectedTab else {
            smartInput = ""
            return
        }
        if tab.isStartPage {
            smartInput = ""
            return
        }
        if let url = tab.webView.url {
            smartInput = url.absoluteString
        } else {
            smartInput = tab.displayURL
        }
    }

    private func scheduleTabMaintenanceTimer() {
        tabMaintenanceTimer?.invalidate()
        let settings = MCVSettingsStore.shared.settings
        guard settings.unloadInactiveTabs else {
            tabMaintenanceTimer = nil
            return
        }
        let unloadSeconds = max(30, settings.unloadAfterSeconds)
        let timerInterval: TimeInterval = settings.energySaver
            ? min(120, max(30, Double(unloadSeconds) / 1.6))
            : min(90, max(40, Double(unloadSeconds) / 3.0))
        let timer = Timer.scheduledTimer(withTimeInterval: timerInterval, repeats: true) { [weak self] _ in
            self?.runTabMemoryMaintenance()
        }
        timer.tolerance = min(12, max(3, timerInterval * 0.35))
        RunLoop.main.add(timer, forMode: .common)
        tabMaintenanceTimer = timer
    }

    private func runTabMemoryMaintenance() {
        let settings = MCVSettingsStore.shared.settings
        guard settings.unloadInactiveTabs else { return }
        guard tabs.count > 1 else { return }
        let activeID = selectedTabID
        let cutoff = Date().addingTimeInterval(-TimeInterval(max(30, settings.unloadAfterSeconds)))
        var suspendedCount = 0

        for tab in tabs {
            if tab.id == activeID {
                continue
            }
            // Bookmark tabs should stay "hot" in RAM and only be hidden/shown.
            if tab.isBookmarkTab {
                continue
            }
            if tab.suspendIfNeeded(cutoff: cutoff) {
                suspendedCount += 1
            }
        }

        if suspendedCount > 0 {
            flashMessage("Suspended \(suspendedCount) background tab(s)")
        }
    }

    private func hideBookmarkTab(_ tab: BrowserTab) {
        guard let index = tabs.firstIndex(where: { $0.id == tab.id }) else { return }
        AudioFocusCoordinator.shared.releaseIfCurrent(tab.webView)
        tab.hasAudio = false
        tabs.remove(at: index)

        if tabs.isEmpty {
            openNewTab(select: true)
            return
        }

        let safeIndex = min(index, tabs.count - 1)
        selectedTabID = tabs[safeIndex].id
        tabs[safeIndex].markActive()
        syncSmartInputWithCurrentTab()
        saveTabSessionIfNeeded()
    }

    private func rememberClosedRegularTab(_ tab: BrowserTab) {
        guard !tab.isBookmarkTab else { return }
        let record = ClosedTabRecord(url: tab.webView.url, title: tab.title)
        recentlyClosedTabs.append(record)
        if recentlyClosedTabs.count > 24 {
            recentlyClosedTabs.removeFirst(recentlyClosedTabs.count - 24)
        }
    }

    private func closeTab(id: UUID) {
        guard let tab = tabs.first(where: { $0.id == id }),
              let index = tabs.firstIndex(where: { $0.id == id }) else {
            return
        }
        AudioFocusCoordinator.shared.releaseIfCurrent(tab.webView)
        tab.hasAudio = false
        audioHandlerByWebViewID.removeValue(forKey: ObjectIdentifier(tab.webView))

        if tab.isBookmarkTab {
            // Never destroy bookmark-tab webview here: keep it in memory and only hide.
            if let bookmarkID = tab.bookmarkID {
                bookmarkTabsByID[bookmarkID] = tab
            }
            tabs.remove(at: index)

            if selectedTabID == id {
                if tabs.isEmpty {
                    openNewTab(select: true)
                    return
                }
                let safeIndex = min(index, tabs.count - 1)
                selectedTabID = tabs[safeIndex].id
                tabs[safeIndex].markActive()
                syncSmartInputWithCurrentTab()
            }
            saveTabSessionIfNeeded()
            return
        }

        rememberClosedRegularTab(tab)

        if tabs.count <= 1 {
            tab.loadNewTabPage(theme: chromeTheme)
            if selectedTabID == id {
                syncSmartInputWithCurrentTab()
            }
            saveTabSessionIfNeeded()
            return
        }

        tabs.remove(at: index)
        tabMap.removeValue(forKey: ObjectIdentifier(tab.webView))

        if selectedTabID == id {
            let safeIndex = min(index, tabs.count - 1)
            selectedTabID = tabs[safeIndex].id
            tabs[safeIndex].markActive()
            syncSmartInputWithCurrentTab()
        }
        saveTabSessionIfNeeded()
    }

    private func cycleTabs(candidates: [BrowserTab], forward: Bool, emptyMessage: String) {
        guard !candidates.isEmpty else {
            flashMessage(emptyMessage)
            return
        }

        let targetIndex: Int
        if let currentID = selectedTabID,
           let currentIndex = candidates.firstIndex(where: { $0.id == currentID }) {
            if forward {
                targetIndex = (currentIndex + 1) % candidates.count
            } else {
                targetIndex = (currentIndex - 1 + candidates.count) % candidates.count
            }
        } else {
            targetIndex = forward ? 0 : candidates.count - 1
        }

        let targetID = candidates[targetIndex].id
        selectTab(id: targetID)
    }

    private func openHelpTab(context: String?) {
        openNewTab(select: true, kind: .help)
        guard let tab = selectedTab, tab.isHelpTab else { return }
        tab.showHelpDocument(context: context)
        syncSmartInputWithCurrentTab()
    }

    private func handleLocalExtensionCommand(_ input: String) -> Bool {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let parts = trimmed.split(maxSplits: 1, omittingEmptySubsequences: true, whereSeparator: \.isWhitespace)
        guard let headRaw = parts.first.map(String.init) else { return false }
        let head = headRaw.lowercased()
        guard head == "ext" || head == "extension" || head == "extensions" else { return false }

        let tail = parts.count > 1 ? String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines) : ""
        guard !tail.isEmpty else {
            utilityPanel = .extensions
            return true
        }

        let commandParts = tail.split(maxSplits: 1, omittingEmptySubsequences: true, whereSeparator: \.isWhitespace)
        guard let commandRaw = commandParts.first.map(String.init) else {
            flashMessage(extensionCommandUsage())
            return true
        }
        let command = commandRaw.lowercased()
        let argument = commandParts.count > 1 ? String(commandParts[1]).trimmingCharacters(in: .whitespacesAndNewlines) : ""

        switch command {
        case "list", "ls", "panel":
            utilityPanel = .extensions
            return true

        case "reload":
            reloadWebExtensionsAndRefreshTabs(reloadTabs: true)
            flashMessage("Extensions reloaded")
            return true

        case "install":
            guard !argument.isEmpty else {
                flashMessage("Usage: ext install <folder|webstore_url|extension_id>")
                return true
            }
            installExtensionFromInput(argument)
            return true

        case "webstore", "store":
            guard !argument.isEmpty else {
                flashMessage("Usage: ext webstore <url|id>")
                return true
            }
            installExtensionFromInput(argument)
            return true

        case "enable":
            guard !argument.isEmpty else {
                flashMessage("Usage: ext enable <id>")
                return true
            }
            if WebExtensionManager.shared.setEnabled(true, extensionID: argument) {
                reloadWebExtensionsAndRefreshTabs(reloadTabs: true)
                flashMessage("Extension enabled: \(argument)")
            } else {
                flashMessage("Extension not found: \(argument)")
            }
            return true

        case "disable":
            guard !argument.isEmpty else {
                flashMessage("Usage: ext disable <id>")
                return true
            }
            if WebExtensionManager.shared.setEnabled(false, extensionID: argument) {
                reloadWebExtensionsAndRefreshTabs(reloadTabs: true)
                flashMessage("Extension disabled: \(argument)")
            } else {
                flashMessage("Extension not found: \(argument)")
            }
            return true

        case "remove", "uninstall", "delete", "del":
            guard !argument.isEmpty else {
                flashMessage("Usage: ext remove <id>")
                return true
            }
            if WebExtensionManager.shared.removeExtension(id: argument) {
                reloadWebExtensionsAndRefreshTabs(reloadTabs: true)
                flashMessage("Extension removed: \(argument)")
            } else {
                flashMessage("Extension not found: \(argument)")
            }
            return true

        case "popup":
            guard !argument.isEmpty else {
                flashMessage("Usage: ext popup <id>")
                return true
            }
            openExtensionResource(extensionID: argument, popup: true)
            return true

        case "options":
            guard !argument.isEmpty else {
                flashMessage("Usage: ext options <id>")
                return true
            }
            openExtensionResource(extensionID: argument, popup: false)
            return true

        case "window", "sidebar":
            guard !argument.isEmpty else {
                flashMessage("Usage: ext window <id>")
                return true
            }
            openExtensionWindowFromPanel(argument)
            return true

        case "grant", "revoke":
            let args = argument.split(maxSplits: 1, omittingEmptySubsequences: true, whereSeparator: \.isWhitespace)
            guard args.count == 2 else {
                flashMessage("Usage: ext \(command) <id> <permission>")
                return true
            }
            let extensionID = String(args[0])
            let permission = String(args[1]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !permission.isEmpty else {
                flashMessage("Permission is empty")
                return true
            }
            if command == "grant" {
                WebExtensionPermissionGate.shared.grant(permission: permission, extensionID: extensionID)
                flashMessage("Granted \(permission) for \(extensionID)")
            } else {
                WebExtensionPermissionGate.shared.revoke(permission: permission, extensionID: extensionID)
                flashMessage("Revoked \(permission) for \(extensionID)")
            }
            return true

        case "logs", "debug":
            if extensionDebugEvents.isEmpty {
                flashMessage("Extension log is empty")
            } else {
                openHelpTab(context: extensionDebugEvents.suffix(6).joined(separator: " | "))
            }
            return true

        default:
            flashMessage(extensionCommandUsage())
            return true
        }
    }

    private func extensionCommandUsage() -> String {
        "ext list|panel | install <folder|url|id> | webstore <url|id> | enable <id> | disable <id> | remove <id> | popup <id> | options <id> | window <id> | grant/revoke <id> <permission> | reload"
    }

    private func openExtensionResource(extensionID: String, popup: Bool) {
        guard let bundle = WebExtensionManager.shared.bundle(id: extensionID) else {
            flashMessage("Extension not found: \(extensionID)")
            return
        }
        let relative = popup ? bundle.popupPath : bundle.optionsPath
        guard let relative, !relative.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            flashMessage(popup ? "Popup not declared for \(extensionID)" : "Options page not declared for \(extensionID)")
            return
        }
        let resourceURL = bundle.rootURL.appendingPathComponent(relative)
        guard FileManager.default.fileExists(atPath: resourceURL.path) else {
            flashMessage("Resource missing: \(relative)")
            return
        }
        clearPendingSmartLearn()
        openNewTab(select: true, url: resourceURL, kind: .regular)
        smartInput = resourceURL.absoluteString
        flashMessage(popup ? "Opened extension popup" : "Opened extension options")
    }

    func openExtensionWindowFromPanel(_ extensionID: String) {
        let cleaned = extensionID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            flashMessage("Extension id is empty")
            return
        }
        guard let bundle = WebExtensionManager.shared.bundle(id: cleaned) else {
            flashMessage("Extension not found: \(cleaned)")
            return
        }
        let relative = bundle.popupPath ?? bundle.optionsPath
        guard let relative, !relative.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            flashMessage("No popup/options page for \(cleaned)")
            return
        }
        let resourceURL = bundle.rootURL.appendingPathComponent(relative)
        guard FileManager.default.fileExists(atPath: resourceURL.path) else {
            flashMessage("Resource missing: \(relative)")
            return
        }

        ExtensionWindowManager.shared.present(
            resourceURL: resourceURL,
            readAccessURL: bundle.rootURL,
            title: "Extension • \(bundle.name)"
        )
        flashMessage("Opened extension window")
    }

    private func applyBridge(for input: String, aliasDepth: Int = 0) -> Bool {
        let trimmedInput = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedInput.isEmpty else { return false }

        if handleLocalExtensionCommand(trimmedInput) {
            return true
        }

        if handleLocalAliasCommand(trimmedInput) {
            return true
        }

        if let aliasExpression = resolveAliasExpression(for: trimmedInput) {
            if aliasDepth >= 8 {
                flashMessage("Alias depth limit reached")
                return true
            }
            let steps = parseAliasSequence(aliasExpression)
            if steps.isEmpty {
                flashMessage("Alias is empty")
                return true
            }
            for step in steps {
                if !applyBridge(for: step, aliasDepth: aliasDepth + 1) {
                    openResolvedInput(step)
                }
            }
            return true
        }

        guard let response = CommandHelperClient.shared.execute(input: trimmedInput) else { return false }
        if response.action == "not_command" { return false }

        switch response.action {
        case "navigate":
            guard let value = response.url, let url = URL(string: value) else {
                flashMessage(response.message ?? "Invalid URL")
                return true
            }
            clearPendingSmartLearn()
            selectedTab?.markActive()
            selectedTab?.load(url: url)
            smartInput = value
            return true

        case "search_web":
            var query = (response.query ?? trimmedInput).trimmingCharacters(in: .whitespacesAndNewlines)
            if !MCVSettingsStore.shared.settings.ddgBangsEnabled, query.hasPrefix("!") {
                query.removeFirst()
                query = query.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if query.isEmpty {
                flashMessage("Search query is empty")
                return true
            }
            openSearch(query)
            return true

        case "new_tab":
            openNewTab(select: true)
            return true

        case "close_tab":
            closeSelectedTab()
            return true

        case "reload_page":
            reload()
            return true

        case "go_back":
            moveBack()
            return true

        case "go_forward":
            moveForward()
            return true

        case "reset_tabs":
            resetRegularTabsKeepingCurrent()
            return true

        case "open_tab_index":
            let index = max(0, response.index ?? 0)
            selectTab(index: index)
            return true

        case "bookmark_add":
            addCurrentTabToBookmarks()
            return true

        case "open_history":
            toggleHistoryPanel()
            return true

        case "open_bookmarks":
            toggleBookmarksPanel()
            return true

        case "open_colors":
            toggleColorsPanel()
            return true

        case "open_settings":
            openSettingsWindow()
            return true

        case "open_home":
            openHomePage()
            return true

        case "open_private_window":
            flashMessage("Private window mode is not available yet")
            return true

        case "copy_link":
            copyCurrentPageLinkToPasteboard()
            return true

        case "open_devtools":
            openDevTools()
            return true

        case "open_console":
            openDevToolsConsole()
            return true

        case "set_security_mode":
            applySecurityModeCommand(response.query)
            return true

        case "set_secure_js":
            applySecureJavaScriptCommand(response.query)
            return true

        case "clearonexit_add":
            applyClearOnExitCommand(rawHost: response.query, add: true)
            return true

        case "clearonexit_del":
            applyClearOnExitCommand(rawHost: response.query, add: false)
            return true

        case "clearonexit_list":
            showClearOnExitHosts()
            return true

        case "clear_data":
            clearWebsiteData()
            return true

        case "open_downloads":
            openDownloadsFolder()
            return true

        case "downloads_clear":
            clearDownloads()
            return true

        case "history_clear":
            clearHistory()
            flashMessage("History cleared")
            return true

        case "history_delete":
            removeHistoryItem(at: max(0, response.index ?? 0))
            return true

        case "set_playback_rate":
            setPlaybackRateCommand(response.query)
            return true

        case "set_scroll_factor":
            setScrollFactorCommand(response.query)
            return true

        case "set_theme":
            applyThemeCommand(response.query)
            return true

        case "set_opacity":
            applyOpacityCommand(response.query)
            return true

        case "set_blur":
            applyBlurCommand(response.query)
            return true

        case "set_suggest":
            applySuggestCommand(response.query)
            return true

        case "set_smart":
            applySmartCommand(response.query)
            return true

        case "set_radius":
            applyRadiusCommand(response.query)
            return true

        case "spot_window":
            applySpotWindowCommand()
            return true

        case "toggle_floating":
            toggleAlwaysOnTopWindow()
            return true

        case "toggle_minimal":
            toggleMinimalWindow()
            return true

        case "pro_reset":
            resetCtrlEPreferences()
            return true

        case "open_music_window":
            NotificationCenter.default.post(
                name: .mcvRequestMusicAction,
                object: nil,
                userInfo: [
                    "action": "open_music_window",
                    "requestID": UUID().uuidString
                ]
            )
            return true

        case "music_stop", "music_pause", "music_toggle", "music_play_pause",
            "music_next", "music_previous", "music_prev", "music_play", "music_list",
            "music_volume_delta", "music_favorite", "music_playlist_context",
            "music_focus_mode", "music_find_context":
            var payload: [AnyHashable: Any] = [
                "action": response.action,
                "requestID": UUID().uuidString
            ]
            if let query = response.query, !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                payload["query"] = query
            }
            NotificationCenter.default.post(name: .mcvRequestMusicAction, object: nil, userInfo: payload)
            return true

        case "show_help":
            openHelpTab(context: response.message)
            return true

        case "notify":
            let rawTitle = response.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let rawMessage = response.message?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            postSystemNotification(
                title: rawTitle.isEmpty ? "MC Browser" : rawTitle,
                body: rawMessage.isEmpty ? "Notification" : rawMessage
            )
            return true

        case "show_message":
            flashMessage(response.message ?? "Done")
            return true

        case "ai_result":
            let payload = (response.message ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if response.isSuccess {
                if payload.isEmpty {
                    flashMessage("AI response is empty")
                } else {
                    presentAIResponse(
                        model: response.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "local",
                        text: payload,
                        isError: false
                    )
                }
            } else {
                let message = payload.isEmpty ? "AI request failed" : payload
                presentAIResponse(
                    model: response.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "local",
                    text: message,
                    isError: true
                )
            }
            return true

        default:
            flashMessage("Unknown action: \(response.action)")
            return true
        }
    }

    private func handleLocalAliasCommand(_ input: String) -> Bool {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let lower = trimmed.lowercased()
        guard lower == "alias" || lower.hasPrefix("alias ") else { return false }

        let tail = trimmed.dropFirst(5).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tail.isEmpty else {
            flashMessage(aliasesSummaryMessage())
            return true
        }

        if tail.lowercased() == "clear" {
            commandAliases.removeAll()
            saveCommandAliases()
            flashMessage("Aliases cleared")
            return true
        }

        if tail.lowercased().hasPrefix("del ") ||
            tail.lowercased().hasPrefix("remove ") ||
            tail.lowercased().hasPrefix("rm ") ||
            tail.lowercased().hasPrefix("delete ") {
            let deleteParts = tail.split(maxSplits: 1, omittingEmptySubsequences: true, whereSeparator: \.isWhitespace)
            guard deleteParts.count >= 2 else {
                flashMessage("Usage: alias del <name>")
                return true
            }
            let keyRaw = String(deleteParts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
            let key = normalizeAliasKey(keyRaw)
            guard !key.isEmpty else {
                flashMessage("Alias name supports a-z 0-9 _ -")
                return true
            }
            if commandAliases.removeValue(forKey: key) != nil {
                saveCommandAliases()
                flashMessage("Alias removed: \(key)")
            } else {
                flashMessage("Alias not found: \(key)")
            }
            return true
        }

        let parts = tail.split(maxSplits: 1, omittingEmptySubsequences: true, whereSeparator: \.isWhitespace)
        guard let rawName = parts.first.map(String.init) else {
            flashMessage("Usage: alias <name> <query>")
            return true
        }
        let key = normalizeAliasKey(rawName)
        guard !key.isEmpty else {
            flashMessage("Alias name supports a-z 0-9 _ -")
            return true
        }

        if parts.count == 1 {
            if let expression = commandAliases[key] {
                flashMessage("\(key) → \(expression)")
            } else {
                flashMessage("Alias not found: \(key)")
            }
            return true
        }

        let expression = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !expression.isEmpty else {
            flashMessage("Usage: alias <name> <query>")
            return true
        }

        commandAliases[key] = expression
        saveCommandAliases()
        flashMessage("Alias saved: \(key)")
        return true
    }

    private func resolveAliasExpression(for input: String) -> String? {
        let key = normalizeAliasKey(input)
        guard !key.isEmpty else { return nil }
        return commandAliases[key]
    }

    private func normalizeAliasKey(_ raw: String) -> String {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !value.isEmpty else { return "" }
        let underscore = UnicodeScalar(95)!
        let hyphen = UnicodeScalar(45)!
        let allowed = value.unicodeScalars.allSatisfy { scalar in
            CharacterSet.alphanumerics.contains(scalar) ||
            scalar == underscore ||
            scalar == hyphen
        }
        return allowed ? value : ""
    }

    private func parseAliasSequence(_ rawExpression: String) -> [String] {
        let expression = rawExpression.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !expression.isEmpty else { return [] }
        guard expression.hasPrefix("/") else { return [expression] }

        let knownCommands: Set<String> = [
            "open", "reload", "back", "forward", "home", "new", "newtab", "t", "private", "close", "closetab", "w",
            "reset", "resettabs", "tabsreset", "book", "bookmark", "pin", "bookmarks", "bm", "history", "hist",
            "downloads", "clear", "dev", "console", "speed", "scroll", "dark", "theme", "mode", "security",
            "colors", "color", "spot", "float", "minimal", "pro", "ollama", "c", "g", "ddg", "search",
            "yt", "youtube", "wiki", "wikipedia", "tw", "x", "gh", "github", "ghr", "tv", "bn",
            "coinglass", "cmc", "fear", "json", "cur", "perf", "alert", "notify", "notification",
            "settings", "copy", "copylink", "tab", "music", "alias", "fav", "js", "clearonexit", "help",
            "ext", "extension", "extensions"
        ]

        var separators: [String.Index] = []
        var cursor = expression.startIndex
        while cursor < expression.endIndex {
            guard expression[cursor] == "/" else {
                cursor = expression.index(after: cursor)
                continue
            }

            var isURLSchemeSlash = false
            if cursor > expression.startIndex {
                let previous = expression.index(before: cursor)
                if expression[previous] == ":" {
                    isURLSchemeSlash = true
                } else if expression[previous] == "/", previous > expression.startIndex {
                    let beforePrevious = expression.index(before: previous)
                    if expression[beforePrevious] == ":" {
                        isURLSchemeSlash = true
                    }
                }
            }

            if isURLSchemeSlash {
                cursor = expression.index(after: cursor)
                continue
            }

            var tokenStart = expression.index(after: cursor)
            while tokenStart < expression.endIndex && expression[tokenStart].isWhitespace {
                tokenStart = expression.index(after: tokenStart)
            }
            if tokenStart >= expression.endIndex {
                cursor = expression.index(after: cursor)
                continue
            }

            var tokenEnd = tokenStart
            while tokenEnd < expression.endIndex {
                let ch = expression[tokenEnd]
                if ch == "/" || ch.isWhitespace {
                    break
                }
                tokenEnd = expression.index(after: tokenEnd)
            }

            let token = normalizeAliasKey(String(expression[tokenStart..<tokenEnd]))
            if !token.isEmpty && (knownCommands.contains(token) || commandAliases[token] != nil) {
                separators.append(cursor)
            }

            cursor = expression.index(after: cursor)
        }

        guard !separators.isEmpty else { return [expression] }

        var commands: [String] = []
        for index in separators.indices {
            let start = expression.index(after: separators[index])
            let end = (index + 1 < separators.count) ? separators[index + 1] : expression.endIndex
            let command = String(expression[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !command.isEmpty {
                commands.append(command)
            }
        }
        return commands.isEmpty ? [expression] : commands
    }

    private func aliasesSummaryMessage() -> String {
        guard !commandAliases.isEmpty else {
            return "No aliases. Use: alias <name> <query>"
        }
        let sorted = commandAliases.keys.sorted()
        let preview = sorted.prefix(4).compactMap { key -> String? in
            guard let expression = commandAliases[key] else { return nil }
            return "\(key)→\(expression)"
        }
        let previewText = preview.joined(separator: " | ")
        return "Aliases \(sorted.count): \(previewText)"
    }

    private func routeInputToMiniCalculatorIfNeeded(_ input: String) -> Bool {
        guard let expression = detectCalculatorExpression(from: input) else { return false }
        MiniMCVPanelController.shared.showCalculator(expression: expression)
        return true
    }

    private func openResolvedInput(_ input: String) {
        if routeInputToMiniCalculatorIfNeeded(input) {
            return
        }
        let settings = MCVSettingsStore.shared.settings
        if let url = resolveURL(from: input) {
            clearPendingSmartLearn()
            selectedTab?.markActive()
            selectedTab?.load(url: url)
            smartInput = url.absoluteString
            return
        }

        if settings.smartSearchEnabled, let prediction = smartPrediction(for: input) {
            clearPendingSmartLearn()
            selectedTab?.markActive()
            selectedTab?.load(url: prediction.url)
            smartInput = prediction.url.absoluteString
            flashMessage("Smart: \(prediction.url.host ?? prediction.url.absoluteString)")
            return
        }

        openSearch(input)
    }

    private func openSearch(_ query: String) {
        let escaped = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let settings = MCVSettingsStore.shared.settings
        let urlString: String
        switch settings.defaultSearchEngine {
        case .duckduckgo:
            urlString = "https://duckduckgo.com/?q=\(escaped)"
        case .google:
            urlString = "https://www.google.com/search?q=\(escaped)"
        case .bing:
            urlString = "https://www.bing.com/search?q=\(escaped)"
        case .yahoo:
            urlString = "https://search.yahoo.com/search?p=\(escaped)"
        }
        guard let url = URL(string: urlString) else { return }
        if settings.smartSearchEnabled {
            beginPendingSmartLearn(query)
        } else {
            clearPendingSmartLearn()
        }
        selectedTab?.markActive()
        selectedTab?.load(url: url)
        smartInput = query
    }

    private func resolveURL(from input: String) -> URL? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }

        if trimmed.contains("://") {
            return URL(string: trimmed)
        }

        if trimmed.contains(".") && !trimmed.contains(" ") {
            return URL(string: "https://\(trimmed)")
        }

        return nil
    }

    private func shouldAttemptSmartPrediction(for query: String) -> Bool {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard normalized.count >= 4 else { return false }
        guard normalized.contains(" ") else { return false }
        guard resolveURL(from: normalized) == nil else { return false }
        if normalized.hasPrefix("!") {
            return false
        }
        if normalized == "yt" || normalized.hasPrefix("yt ") ||
            normalized == "wiki" || normalized.hasPrefix("wiki ") ||
            normalized == "gh" || normalized.hasPrefix("gh ") {
            return false
        }
        return true
    }

    private func normalizedSmartQuery(_ query: String) -> String {
        query
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    private func smartPrediction(for query: String) -> (url: URL, hits: Int)? {
        guard MCVSettingsStore.shared.settings.smartSearchEnabled else { return nil }
        guard shouldAttemptSmartPrediction(for: query) else { return nil }
        let key = normalizedSmartQuery(query)
        guard !key.isEmpty else { return nil }

        if let cached = smartPredictionCache[key] {
            return cached
        }
        if smartPredictionMisses.contains(key) {
            return nil
        }

        guard let prediction = CommandHelperClient.shared.predictSmartURL(for: key) else {
            smartPredictionMisses.insert(key)
            return nil
        }

        smartPredictionCache[key] = prediction
        return prediction
    }

    private func beginPendingSmartLearn(_ query: String) {
        let normalized = normalizedSmartQuery(query)
        guard !normalized.isEmpty else { return }
        pendingSmartLearnQuery = normalized
        pendingSmartLearnAt = Date()
    }

    private func clearPendingSmartLearn() {
        pendingSmartLearnQuery = nil
        pendingSmartLearnAt = nil
    }

    private func isSearchHost(_ host: String) -> Bool {
        let normalized = host.lowercased()
        if normalized == "duckduckgo.com" || normalized == "www.duckduckgo.com" {
            return true
        }
        if normalized == "bing.com" || normalized == "www.bing.com" {
            return true
        }
        if normalized == "search.yahoo.com" || normalized == "yahoo.com" || normalized == "www.yahoo.com" {
            return true
        }
        if normalized == "google.com" || normalized == "www.google.com" || normalized.hasSuffix(".google.com") {
            return true
        }
        return false
    }

    private func maybeLearnSmartMapping(from url: URL) {
        guard let query = pendingSmartLearnQuery,
              let started = pendingSmartLearnAt else {
            return
        }

        if Date().timeIntervalSince(started) > 300 {
            clearPendingSmartLearn()
            return
        }

        guard let host = url.host?.lowercased() else { return }
        if isSearchHost(host) {
            return
        }

        CommandHelperClient.shared.learnSmartMapping(query: query, url: url.absoluteString)
        smartPredictionCache.removeValue(forKey: query)
        smartPredictionMisses.remove(query)
        clearPendingSmartLearn()
    }

    private func suggestions(for raw: String) -> [CommandSuggestion] {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            return defaultSuggestions()
        }

        var rows: [CommandSuggestion] = []
        let lower = text.lowercased()

        if lower.hasPrefix("yt") || lower.contains("youtube") {
            rows.append(CommandSuggestion(icon: "play.rectangle.fill", title: "Search YouTube", subtitle: "yt <query>", value: text.hasPrefix("yt") ? text : "yt \(text)"))
        }
        if lower.hasPrefix("wiki") || lower.contains("wikipedia") {
            rows.append(CommandSuggestion(icon: "book.fill", title: "Search Wikipedia", subtitle: "wiki <query>", value: text.hasPrefix("wiki") ? text : "wiki \(text)"))
        }
        if lower.hasPrefix("gh") || lower.contains("github") {
            rows.append(CommandSuggestion(icon: "chevron.left.forwardslash.chevron.right", title: "Open GitHub", subtitle: "gh <user>", value: text.hasPrefix("gh") ? text : "gh \(text)"))
        }

        let commandPalette: [CommandSuggestion] = [
            CommandSuggestion(icon: "plus.square", title: "New Tab", subtitle: "new", value: "new"),
            CommandSuggestion(icon: "xmark.square", title: "Close Tab", subtitle: "close", value: "close"),
            CommandSuggestion(icon: "rectangle.compress.vertical", title: "Reset Regular Tabs", subtitle: "reset", value: "reset"),
            CommandSuggestion(icon: "bookmark", title: "Bookmark Current Tab", subtitle: "book", value: "book"),
            CommandSuggestion(icon: "clock", title: "Open History", subtitle: "history", value: "history"),
            CommandSuggestion(icon: "book.closed", title: "Open Bookmarks", subtitle: "bookmarks", value: "bookmarks"),
            CommandSuggestion(icon: "paintpalette", title: "Open Colors", subtitle: "colors", value: "colors"),
            CommandSuggestion(icon: "music.note", title: "Open Music Window", subtitle: "music", value: "music"),
            CommandSuggestion(icon: "stop.circle", title: "Stop Music Window Audio", subtitle: "music stop", value: "music stop"),
            CommandSuggestion(icon: "questionmark.circle", title: "Help", subtitle: "help", value: "help")
        ]

        rows.append(contentsOf: commandPalette.filter { item in
            item.title.lowercased().contains(lower) || item.value.lowercased().contains(lower)
        })

        let aliasRows = commandAliases
            .filter { pair in
                pair.key.contains(lower) || pair.value.lowercased().contains(lower)
            }
            .sorted { lhs, rhs in
                lhs.key < rhs.key
            }
            .prefix(4)
            .map { pair in
                CommandSuggestion(
                    icon: "bolt.horizontal.fill",
                    title: "Alias \(pair.key)",
                    subtitle: pair.value,
                    value: pair.key
                )
            }
        rows.append(contentsOf: aliasRows)

        let tabRows = tabs.enumerated().compactMap { index, tab -> CommandSuggestion? in
            let t = tab.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard t.lowercased().contains(lower) || tab.displayURL.lowercased().contains(lower) else {
                return nil
            }
            return CommandSuggestion(
                icon: "rectangle.on.rectangle",
                title: t.isEmpty ? "Tab \(index + 1)" : t,
                subtitle: "tab \(index + 1)",
                value: "tab \(index + 1)"
            )
        }
        rows.append(contentsOf: tabRows)

        return Array(rows.prefix(10))
    }

    private func searchOnlySuggestions(for raw: String) -> [CommandSuggestion] {
        let engineTitle = MCVSettingsStore.shared.settings.defaultSearchEngine.title
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            return [
                CommandSuggestion(icon: "magnifyingglass", title: "Search \(engineTitle)", subtitle: "Type query and press Enter", value: engineTitle.lowercased()),
                CommandSuggestion(icon: "globe", title: "Open URL", subtitle: "Type domain like example.com", value: "example.com")
            ]
        }

        var rows: [CommandSuggestion] = []
        if let url = resolveURL(from: text) {
            rows.append(
                CommandSuggestion(
                    icon: "globe",
                    title: "Open \(url.host ?? url.absoluteString)",
                    subtitle: url.absoluteString,
                    value: text
                )
            )
        }

        if resolveURL(from: text) == nil,
           let prediction = smartPrediction(for: text) {
            rows.append(
                CommandSuggestion(
                    icon: "sparkles",
                    title: "Smart: \(prediction.url.host ?? prediction.url.absoluteString)",
                    subtitle: "Learned \(max(2, prediction.hits))x",
                    value: prediction.url.absoluteString
                )
            )
        }

        rows.append(
            CommandSuggestion(
                icon: "magnifyingglass",
                title: "Search \(engineTitle)",
                subtitle: text,
                value: text
            )
        )

        return Array(rows.prefix(8))
    }

    private func defaultSuggestions() -> [CommandSuggestion] {
        var rows: [CommandSuggestion] = [
            CommandSuggestion(icon: "plus.square", title: "Open New Tab", subtitle: "new", value: "new"),
            CommandSuggestion(icon: "rectangle.compress.vertical", title: "Reset Regular Tabs", subtitle: "reset", value: "reset"),
            CommandSuggestion(icon: "play.rectangle.fill", title: "Search YouTube", subtitle: "yt <query>", value: "yt "),
            CommandSuggestion(icon: "book.fill", title: "Search Wikipedia", subtitle: "wiki <query>", value: "wiki "),
            CommandSuggestion(icon: "chevron.left.forwardslash.chevron.right", title: "Open GitHub", subtitle: "gh <user>", value: "gh "),
            CommandSuggestion(icon: "bookmark", title: "Add Bookmark", subtitle: "book", value: "book"),
            CommandSuggestion(icon: "clock", title: "Show History", subtitle: "history", value: "history"),
            CommandSuggestion(icon: "paintpalette", title: "Open Colors", subtitle: "colors", value: "colors"),
            CommandSuggestion(icon: "music.note", title: "Open Music Window", subtitle: "music", value: "music"),
            CommandSuggestion(icon: "questionmark.circle", title: "Command Help", subtitle: "help", value: "help")
        ]

        if let firstAlias = commandAliases.keys.sorted().first,
           let expression = commandAliases[firstAlias] {
            rows.append(
                CommandSuggestion(
                    icon: "bolt.horizontal.fill",
                    title: "Alias \(firstAlias)",
                    subtitle: expression,
                    value: firstAlias
                )
            )
        }

        return rows
    }

    private func helpSuggestions() -> [CommandSuggestion] {
        [
            CommandSuggestion(icon: "questionmark.circle.fill", title: "Commands", subtitle: "yt, wiki, gh, new, close, reset, book, history, bookmarks, colors", value: ""),
            CommandSuggestion(icon: "keyboard", title: "Hotkeys", subtitle: "Cmd+E overlay, Ctrl+E disabled, Cmd+S saved panel, Cmd+G tab wheel, Cmd+O music wheel, Ctrl+W reset", value: ""),
            CommandSuggestion(icon: "info.circle", title: "Concept", subtitle: "Normal outside, powerful inside", value: "")
        ]
    }

    private func commandCenterSuggestions(for raw: String) -> [CommandSuggestion] {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let catalog = commandCenterCatalog()
        let defaults = UserDefaults.standard
        let suggestionsEnabled: Bool = {
            if defaults.object(forKey: AppKeys.ctrlESuggestionsEnabled) == nil {
                return true
            }
            return defaults.bool(forKey: AppKeys.ctrlESuggestionsEnabled)
        }()

        if !suggestionsEnabled {
            if text.isEmpty {
                return [
                    CommandSuggestion(
                        icon: "terminal",
                        title: "Suggestions disabled",
                        subtitle: "Use `pro suggest on` to restore recommendations",
                        value: ""
                    )
                ]
            }
            return [
                CommandSuggestion(
                    icon: "terminal",
                    title: "Run command",
                    subtitle: "Execute exactly as typed",
                    value: text
                )
            ]
        }

        if text.isEmpty {
            return catalog
        }

        let lower = text.lowercased()
        var rows = catalog.filter { item in
            item.value.lowercased().contains(lower) ||
            item.title.lowercased().contains(lower) ||
            item.subtitle.lowercased().contains(lower)
        }

        if !text.isEmpty {
            let hasExact = rows.contains { $0.value.lowercased() == lower }
            if !hasExact {
                rows.insert(
                    CommandSuggestion(
                        icon: "terminal",
                        title: "Run command",
                        subtitle: "Execute exactly as typed",
                        value: text
                    ),
                    at: 0
                )
            }
        }

        return Array(rows.prefix(160))
    }

    private func commandCenterCatalog() -> [CommandSuggestion] {
        let rows: [CommandSuggestion] = [
            CommandSuggestion(icon: "terminal", title: "open <url>", subtitle: "Open URL in current tab", value: "open "),
            CommandSuggestion(icon: "terminal", title: "reload", subtitle: "Reload current page", value: "reload"),
            CommandSuggestion(icon: "terminal", title: "back", subtitle: "Go back", value: "back"),
            CommandSuggestion(icon: "terminal", title: "forward", subtitle: "Go forward", value: "forward"),
            CommandSuggestion(icon: "terminal", title: "home", subtitle: "Open home/start page", value: "home"),
            CommandSuggestion(icon: "terminal", title: "new", subtitle: "New empty tab", value: "new"),
            CommandSuggestion(icon: "terminal", title: "private", subtitle: "Open private window", value: "private"),
            CommandSuggestion(icon: "terminal", title: "close", subtitle: "Close current tab", value: "close"),

            CommandSuggestion(icon: "terminal", title: "g <query>", subtitle: "Google search", value: "g "),
            CommandSuggestion(icon: "terminal", title: "ddg <query>", subtitle: "DuckDuckGo search", value: "ddg "),
            CommandSuggestion(icon: "terminal", title: "yt <query>", subtitle: "YouTube search", value: "yt "),
            CommandSuggestion(icon: "terminal", title: "wiki <query>", subtitle: "Wikipedia search (en)", value: "wiki "),
            CommandSuggestion(icon: "terminal", title: "wiki <lang> <query>", subtitle: "Aliases: e/r/u/i/f/s/c", value: "wiki e "),
            CommandSuggestion(icon: "terminal", title: "tw <user>", subtitle: "Open Twitch channel", value: "tw "),
            CommandSuggestion(icon: "terminal", title: "x <user>", subtitle: "Open X profile", value: "x "),
            CommandSuggestion(icon: "terminal", title: "gh <user>", subtitle: "Open GitHub profile", value: "gh "),
            CommandSuggestion(icon: "terminal", title: "ghr <user/repo>", subtitle: "Open GitHub repository", value: "ghr "),
            CommandSuggestion(icon: "terminal", title: "tv <symbol> [tf]", subtitle: "TradingView BINANCE chart", value: "tv btc 1h"),
            CommandSuggestion(icon: "terminal", title: "bn btc|eth", subtitle: "Open Binance futures", value: "bn btc"),
            CommandSuggestion(icon: "terminal", title: "coinglass", subtitle: "Open liquidation map", value: "coinglass"),
            CommandSuggestion(icon: "terminal", title: "cmc btc|eth", subtitle: "Open CoinMarketCap", value: "cmc btc"),
            CommandSuggestion(icon: "terminal", title: "fear", subtitle: "Fear & Greed index", value: "fear"),
            CommandSuggestion(icon: "terminal", title: "json <url>", subtitle: "Open URL as raw JSON if available", value: "json "),
            CommandSuggestion(icon: "terminal", title: "c [prompt]", subtitle: "Open ChatGPT and pass prompt", value: "c "),

            CommandSuggestion(icon: "terminal", title: "cur <from> <to> [amount]", subtitle: "Quick converter (btc/eth/usd/eur/uah)", value: "cur u d 45"),
            CommandSuggestion(icon: "terminal", title: "mode classic|safe|secure", subtitle: "Switch security mode and open new window", value: "mode safe"),
            CommandSuggestion(icon: "terminal", title: "ollama on", subtitle: "Open Ollama setup", value: "ollama on"),
            CommandSuggestion(icon: "terminal", title: "ollama off", subtitle: "Disable local AI routing", value: "ollama off"),
            CommandSuggestion(icon: "terminal", title: "ollama status", subtitle: "Check local runtime status", value: "ollama status"),
            CommandSuggestion(icon: "terminal", title: "ollama test", subtitle: "Quick local model test", value: "ollama test"),
            CommandSuggestion(icon: "terminal", title: "ollama chat <message>", subtitle: "Ask local model directly", value: "ollama chat "),
            CommandSuggestion(icon: "terminal", title: "speed x1.5", subtitle: "Set media playback speed", value: "speed x1.5"),
            CommandSuggestion(icon: "terminal", title: "scroll x0.5", subtitle: "Set arrow-key scroll factor", value: "scroll x0.5"),
            CommandSuggestion(icon: "terminal", title: "notify <text>", subtitle: "Send macOS notification", value: "notify "),
            CommandSuggestion(icon: "terminal", title: "clear", subtitle: "Clear cookies/cache", value: "clear"),
            CommandSuggestion(icon: "terminal", title: "dev", subtitle: "Toggle DevTools panel", value: "dev"),
            CommandSuggestion(icon: "terminal", title: "perf status|gpu|fps [sec]", subtitle: "Performance diagnostics", value: "perf status"),
            CommandSuggestion(icon: "terminal", title: "downloads [clear]", subtitle: "Download history tools", value: "downloads"),
            CommandSuggestion(icon: "terminal", title: "history [sites|cmds|clear|del N]", subtitle: "History tools", value: "history sites"),
            CommandSuggestion(icon: "terminal", title: "ext list", subtitle: "Open extensions side panel", value: "ext list"),
            CommandSuggestion(icon: "terminal", title: "ext panel", subtitle: "Open extensions side panel", value: "ext panel"),
            CommandSuggestion(icon: "terminal", title: "ext install <folder|url|id>", subtitle: "Install unpacked or from Chrome Web Store", value: "ext install "),
            CommandSuggestion(icon: "terminal", title: "ext webstore <url|id>", subtitle: "Download CRX, unpack, install", value: "ext webstore "),
            CommandSuggestion(icon: "terminal", title: "ext enable <id>", subtitle: "Enable extension", value: "ext enable "),
            CommandSuggestion(icon: "terminal", title: "ext disable <id>", subtitle: "Disable extension", value: "ext disable "),
            CommandSuggestion(icon: "terminal", title: "ext popup <id>", subtitle: "Open extension popup page", value: "ext popup "),
            CommandSuggestion(icon: "terminal", title: "ext options <id>", subtitle: "Open extension options page", value: "ext options "),
            CommandSuggestion(icon: "terminal", title: "ext window <id>", subtitle: "Open extension popup/options in new window", value: "ext window "),
            CommandSuggestion(icon: "terminal", title: "ext reload", subtitle: "Reinject runtime and reload tabs", value: "ext reload"),

            CommandSuggestion(icon: "terminal", title: "alert btc > 43000", subtitle: "Trader alerts (beta)", value: "alert btc > 43000"),
            CommandSuggestion(icon: "terminal", title: "alert list", subtitle: "List trader alerts", value: "alert list"),
            CommandSuggestion(icon: "terminal", title: "alert del <id>", subtitle: "Delete trader alert", value: "alert del "),
            CommandSuggestion(icon: "terminal", title: "alert clear", subtitle: "Clear trader alerts", value: "alert clear"),

            CommandSuggestion(icon: "terminal", title: "dark", subtitle: "Force dark mode", value: "dark"),
            CommandSuggestion(icon: "terminal", title: "theme dark|light|off", subtitle: "Set theme", value: "theme dark"),
            CommandSuggestion(icon: "terminal", title: "spot", subtitle: "Compact window size", value: "spot"),
            CommandSuggestion(icon: "terminal", title: "float", subtitle: "Toggle always-on-top", value: "float"),
            CommandSuggestion(icon: "terminal", title: "minimal", subtitle: "Toggle fullscreen", value: "minimal"),

            CommandSuggestion(icon: "terminal", title: "pro", subtitle: "Open advanced settings hub", value: "pro"),
            CommandSuggestion(icon: "terminal", title: "pro opacity <0.05-1.0>", subtitle: "Window opacity", value: "pro opacity 0.85"),
            CommandSuggestion(icon: "terminal", title: "pro blur on|off", subtitle: "Spotlight blur", value: "pro blur on"),
            CommandSuggestion(icon: "terminal", title: "pro blur mini on|off", subtitle: "Mini MCV blur", value: "pro blur mini on"),
            CommandSuggestion(icon: "terminal", title: "pro suggest on|off", subtitle: "Search suggestions", value: "pro suggest off"),
            CommandSuggestion(icon: "terminal", title: "pro smart on|off", subtitle: "Smart learning", value: "pro smart on"),
            CommandSuggestion(icon: "terminal", title: "pro radius <int>", subtitle: "Spotlight corner radius", value: "pro radius 16"),
            CommandSuggestion(icon: "terminal", title: "pro cuts", subtitle: "Show keyboard shortcuts", value: "pro cuts"),
            CommandSuggestion(icon: "terminal", title: "pro cuts edit", subtitle: "Edit shortcuts file", value: "pro cuts edit"),
            CommandSuggestion(icon: "terminal", title: "pro cuts path", subtitle: "Show shortcuts config path", value: "pro cuts path"),
            CommandSuggestion(icon: "terminal", title: "pro cuts reload", subtitle: "Reload shortcuts from file", value: "pro cuts reload"),
            CommandSuggestion(icon: "terminal", title: "pro cuts reset", subtitle: "Reset shortcuts to defaults", value: "pro cuts reset"),
            CommandSuggestion(icon: "terminal", title: "pro reset", subtitle: "Reset Ctrl+E command center settings", value: "pro reset"),

            CommandSuggestion(icon: "terminal", title: "alias", subtitle: "List aliases", value: "alias"),
            CommandSuggestion(icon: "terminal", title: "alias <name> <query>", subtitle: "Set alias command or chain /new/open https://...", value: "alias tv /new/open https://tradingview.com/"),
            CommandSuggestion(icon: "terminal", title: "fav", subtitle: "Favorites shortcuts", value: "fav"),
            CommandSuggestion(icon: "terminal", title: "fav list", subtitle: "List favorites", value: "fav list"),
            CommandSuggestion(icon: "terminal", title: "fav open <key>", subtitle: "Open favorite by key", value: "fav open "),

            CommandSuggestion(icon: "terminal", title: "js on|off", subtitle: "Per-site JavaScript secure mode", value: "js off"),
            CommandSuggestion(icon: "terminal", title: "clearonexit add|del <host>", subtitle: "Clear cookies on exit", value: "clearonexit add example.com"),
            CommandSuggestion(icon: "terminal", title: "clearonexit list", subtitle: "Show clear-on-exit hosts", value: "clearonexit list"),
            CommandSuggestion(icon: "terminal", title: "wipe", subtitle: "Wipe safe/secure profile", value: "wipe"),
            CommandSuggestion(icon: "terminal", title: "pass set|save|fill|del|list|auto|ignore", subtitle: "Apple Keychain passwords", value: "pass save"),
            CommandSuggestion(icon: "terminal", title: "help", subtitle: "Command center help", value: "help"),
            CommandSuggestion(icon: "terminal", title: "help <cmd>", subtitle: "Help for specific command", value: "help theme")
        ]
        return rows
    }

    private func flashMessage(_ message: String) {
        transientMessage = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in
            if self?.transientMessage == message {
                self?.transientMessage = nil
            }
        }
    }

    private func postSystemNotification(title: String, body: String) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound, .badge]) { [weak self] granted, error in
            if let error {
                DispatchQueue.main.async {
                    self?.flashMessage("Notification error: \(error.localizedDescription)")
                }
                return
            }
            guard granted else {
                DispatchQueue.main.async {
                    self?.flashMessage("Allow notifications for MCV in macOS settings")
                }
                return
            }

            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default

            let request = UNNotificationRequest(
                identifier: "mcv.notify.\(UUID().uuidString)",
                content: content,
                trigger: nil
            )
            center.add(request) { addError in
                if let addError {
                    DispatchQueue.main.async {
                        self?.flashMessage("Notification failed: \(addError.localizedDescription)")
                    }
                }
            }
        }
    }

    private func presentAIResponse(model: String, text: String, isError: Bool) {
        let normalizedModel = model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "local" : model
        let payload = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let visible = payload.isEmpty ? (isError ? "AI request failed" : "AI returned empty response") : payload

        let alert = NSAlert()
        alert.alertStyle = isError ? .warning : .informational
        alert.messageText = isError ? "AI error • \(normalizedModel)" : "AI • \(normalizedModel)"
        alert.informativeText = String(visible.prefix(12000))
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Copy")

        NSApp.activate(ignoringOtherApps: true)
        let result = alert.runModal()
        if result == .alertSecondButtonReturn {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(visible, forType: .string)
            flashMessage("AI response copied")
        }
    }

    private func installThemeObserver() {
        themeObserver = NotificationCenter.default.addObserver(
            forName: .mcvChromeThemeDidChange,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self else { return }
            guard let incoming = note.object as? ChromeTheme else { return }
            let normalized = incoming.clamped
            if normalized != self.chromeTheme {
                self.chromeTheme = normalized
                self.refreshStartPagesTheme()
            }
        }
    }

    private func installSettingsObserver() {
        settingsObserver = NotificationCenter.default.addObserver(
            forName: .mcvSettingsDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            let settings = MCVSettingsStore.shared.settings
            if !settings.restoreTabsOnLaunch {
                UserDefaults.standard.removeObject(forKey: AppKeys.tabSession)
            } else {
                self.saveTabSessionIfNeeded()
            }
            self.tabMaintenanceTimer?.invalidate()
            self.scheduleTabMaintenanceTimer()
        }
    }

    private func installMusicCommandObserver() {
        musicCommandObserver = NotificationCenter.default.addObserver(
            forName: .mcvMusicCommand,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self, self.isMusicWindow else { return }
            guard let userInfo = note.userInfo,
                  let action = userInfo["action"] as? String else {
                return
            }
            let query = userInfo["query"] as? String
            let delta = (userInfo["delta"] as? NSNumber)?.doubleValue
            let mood = userInfo["mood"] as? String
            let sourceURL = userInfo["sourceURL"] as? String
            let sourceTitle = userInfo["sourceTitle"] as? String
            self.handleMusicCommand(
                action: action,
                query: query,
                delta: delta,
                mood: mood,
                sourceURL: sourceURL,
                sourceTitle: sourceTitle
            )
        }
    }

    private func setupAudioMonitoring(for tab: BrowserTab) {
        let controller = tab.webView.configuration.userContentController
        let controllerID = ObjectIdentifier(controller)

        if !audioScriptInstalledControllers.contains(controllerID) {
            let script = WKUserScript(
                source: AudioMonitor.scriptSource,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true
            )
            controller.addUserScript(script)
            audioScriptInstalledControllers.insert(controllerID)
        }

        let webViewID = ObjectIdentifier(tab.webView)
        controller.removeScriptMessageHandler(forName: AudioMonitor.messageName)
        let proxy = WeakScriptMessageHandler(target: self)
        controller.add(proxy, name: AudioMonitor.messageName)
        audioHandlerByWebViewID[webViewID] = proxy
    }

    private func applyWebExtensions(to configuration: WKWebViewConfiguration) {
        let controller = configuration.userContentController
        let controllerID = ObjectIdentifier(controller)
        guard !extensionBridgeInstalledControllers.contains(controllerID) else { return }

        let runtimeShim = WKUserScript(
            source: WebExtensionBridge.runtimeShimSource,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
        controller.addUserScript(runtimeShim)

        let bundles = WebExtensionManager.shared.enabledBundles()
        var scriptCount = 0
        for bundle in bundles {
            for plan in bundle.contentScripts {
                let wrapped = WebExtensionBridge.wrappedContentScriptSource(
                    extensionID: bundle.id,
                    scriptKey: plan.scriptKey,
                    matches: plan.matches,
                    code: plan.source
                )
                let userScript = WKUserScript(
                    source: wrapped,
                    injectionTime: plan.injectionTime,
                    forMainFrameOnly: plan.forMainFrameOnly
                )
                controller.addUserScript(userScript)
                scriptCount += 1
            }
        }

        extensionBridgeInstalledControllers.insert(controllerID)
        appendExtensionDebug("controller \(controllerID) scripts \(scriptCount)")
    }

    private func setupWebExtensionBridge(for tab: BrowserTab) {
        let configuration = tab.webView.configuration
        applyWebExtensions(to: configuration)
        let controller = configuration.userContentController
        let controllerID = ObjectIdentifier(controller)

        controller.removeScriptMessageHandler(forName: WebExtensionBridge.messageName)
        let proxy = WeakScriptMessageHandler(target: self)
        controller.add(proxy, name: WebExtensionBridge.messageName)
        extensionBridgeHandlerByControllerID[controllerID] = proxy
    }

    private func appendExtensionDebug(_ message: String) {
        let line = "[\(DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium))] \(message)"
        extensionDebugEvents.append(line)
        if extensionDebugEvents.count > 160 {
            extensionDebugEvents.removeFirst(extensionDebugEvents.count - 160)
        }
    }

    private func reloadWebExtensionsAndRefreshTabs(reloadTabs: Bool) {
        WebExtensionManager.shared.reload()
        extensionBridgeInstalledControllers.removeAll()
        extensionBridgeHandlerByControllerID.removeAll()

        let hiddenBookmarkTabs = bookmarkTabsByID.values.filter { hidden in
            !tabs.contains(where: { $0.id == hidden.id })
        }
        let allTabs = tabs + hiddenBookmarkTabs

        for tab in allTabs {
            applyWebExtensions(to: tab.webView.configuration)
            setupWebExtensionBridge(for: tab)
            if reloadTabs {
                tab.webView.reload()
            }
        }
    }

    private func respondToExtensionBridge(
        webView: WKWebView,
        requestId: String,
        ok: Bool,
        result: Any? = nil,
        error: String? = nil
    ) {
        var packet: [String: Any] = [
            "requestId": requestId,
            "ok": ok
        ]
        if ok {
            packet["result"] = mcvJSONPropertyListSafe(result ?? NSNull()) ?? NSNull()
        } else {
            packet["error"] = error ?? "extension bridge error"
        }
        guard let json = mcvJSONString(from: packet) else { return }
        let js = "window.\(WebExtensionBridge.responseFunction) && window.\(WebExtensionBridge.responseFunction)(\(json));"
        webView.evaluateJavaScript(js, completionHandler: nil)
    }

    private func handleExtensionBridgeMessage(_ message: WKScriptMessage) {
        guard let senderWebView = message.webView else { return }
        guard let body = message.body as? [String: Any],
              let requestId = body["requestId"] as? String,
              let op = body["op"] as? String,
              let extensionID = body["extensionId"] as? String else {
            return
        }

        guard let bundle = WebExtensionManager.shared.bundle(id: extensionID), bundle.enabled else {
            respondToExtensionBridge(webView: senderWebView, requestId: requestId, ok: false, error: "extension not enabled")
            return
        }

        let payload = (body["payload"] as? [String: Any]) ?? [:]
        if !WebExtensionPermissionGate.shared.isOperationAllowed(op, bundle: bundle, currentURL: senderWebView.url) {
            respondToExtensionBridge(webView: senderWebView, requestId: requestId, ok: false, error: "permission denied for \(op)")
            appendExtensionDebug("denied \(bundle.id) \(op)")
            return
        }

        switch op {
        case "storage.get":
            let keysPayload = payload["keys"]
            let result = WebExtensionStorageStore.shared.get(extensionID: extensionID, keysPayload: keysPayload)
            respondToExtensionBridge(webView: senderWebView, requestId: requestId, ok: true, result: result)
            appendExtensionDebug("storage.get \(bundle.id)")

        case "storage.set":
            let rawItems = (payload["items"] as? [String: Any]) ?? [:]
            var safeItems: [String: Any] = [:]
            for (key, value) in rawItems {
                if let safe = mcvJSONPropertyListSafe(value) {
                    safeItems[key] = safe
                }
            }
            WebExtensionStorageStore.shared.set(extensionID: extensionID, items: safeItems)
            respondToExtensionBridge(webView: senderWebView, requestId: requestId, ok: true, result: [:])
            appendExtensionDebug("storage.set \(bundle.id) keys \(safeItems.keys.count)")

        case "storage.remove":
            let rawKeys = payload["keys"]
            let keys: [String]
            if let one = rawKeys as? String {
                keys = [one]
            } else if let many = rawKeys as? [String] {
                keys = many
            } else {
                keys = []
            }
            WebExtensionStorageStore.shared.remove(extensionID: extensionID, keys: keys)
            respondToExtensionBridge(webView: senderWebView, requestId: requestId, ok: true, result: [:])
            appendExtensionDebug("storage.remove \(bundle.id) keys \(keys.count)")

        case "storage.clear":
            WebExtensionStorageStore.shared.clear(extensionID: extensionID)
            respondToExtensionBridge(webView: senderWebView, requestId: requestId, ok: true, result: [:])
            appendExtensionDebug("storage.clear \(bundle.id)")

        case "runtime.sendMessage":
            let value = payload["message"] ?? NSNull()
            respondToExtensionBridge(webView: senderWebView, requestId: requestId, ok: true, result: ["echo": value, "extensionId": extensionID])
            appendExtensionDebug("runtime.sendMessage \(bundle.id)")

        case "tabs.query":
            var result: [[String: Any]] = []
            if let selectedTab {
                result.append([
                    "id": selectedTab.id.uuidString,
                    "url": selectedTab.webView.url?.absoluteString ?? "",
                    "title": selectedTab.title,
                    "active": true
                ])
            }
            respondToExtensionBridge(webView: senderWebView, requestId: requestId, ok: true, result: result)
            appendExtensionDebug("tabs.query \(bundle.id)")

        case "tabs.create":
            let createProperties = (payload["createProperties"] as? [String: Any]) ?? [:]
            let targetURLString = (createProperties["url"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if let url = URL(string: targetURLString), !targetURLString.isEmpty {
                clearPendingSmartLearn()
                openNewTab(select: true, url: url, kind: .regular)
                respondToExtensionBridge(
                    webView: senderWebView,
                    requestId: requestId,
                    ok: true,
                    result: [
                        "id": selectedTab?.id.uuidString ?? "",
                        "url": url.absoluteString,
                        "active": true
                    ]
                )
                appendExtensionDebug("tabs.create \(bundle.id) \(url.absoluteString)")
            } else {
                respondToExtensionBridge(webView: senderWebView, requestId: requestId, ok: false, error: "tabs.create requires url")
            }

        case "scripting.executeScript":
            let details = (payload["details"] as? [String: Any]) ?? [:]
            let code = (details["code"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !code.isEmpty else {
                respondToExtensionBridge(webView: senderWebView, requestId: requestId, ok: false, error: "details.code is required")
                return
            }
            guard let target = selectedTab?.webView else {
                respondToExtensionBridge(webView: senderWebView, requestId: requestId, ok: false, error: "no active tab")
                return
            }
            target.evaluateJavaScript(code) { [weak self] result, error in
                if let error {
                    self?.respondToExtensionBridge(webView: senderWebView, requestId: requestId, ok: false, error: error.localizedDescription)
                    return
                }
                self?.respondToExtensionBridge(
                    webView: senderWebView,
                    requestId: requestId,
                    ok: true,
                    result: [["result": mcvJSONPropertyListSafe(result ?? NSNull()) ?? NSNull()]]
                )
            }
            appendExtensionDebug("scripting.executeScript \(bundle.id)")

        case "contextMenus.create":
            let createProperties = (payload["createProperties"] as? [String: Any]) ?? [:]
            let id = (createProperties["id"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let menuID = (id?.isEmpty == false ? id! : UUID().uuidString)
            respondToExtensionBridge(webView: senderWebView, requestId: requestId, ok: true, result: menuID)
            appendExtensionDebug("contextMenus.create \(bundle.id) \(menuID)")

        case "commands.getAll":
            respondToExtensionBridge(webView: senderWebView, requestId: requestId, ok: true, result: [])
            appendExtensionDebug("commands.getAll \(bundle.id)")

        case "notifications.create":
            let options = (payload["options"] as? [String: Any]) ?? [:]
            let title = (options["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? bundle.name
            let messageText = (options["message"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Extension notification"
            postSystemNotification(title: title, body: messageText)
            let notificationID = (payload["notificationId"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            respondToExtensionBridge(webView: senderWebView, requestId: requestId, ok: true, result: notificationID?.isEmpty == false ? notificationID! : UUID().uuidString)
            appendExtensionDebug("notifications.create \(bundle.id)")

        default:
            respondToExtensionBridge(webView: senderWebView, requestId: requestId, ok: false, error: "unsupported op \(op)")
            appendExtensionDebug("unsupported \(bundle.id) \(op)")
        }
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == WebExtensionBridge.messageName {
            handleExtensionBridgeMessage(message)
            return
        }

        guard message.name == AudioMonitor.messageName else { return }
        guard let senderWebView = message.webView else { return }

        if let body = message.body as? [String: Any], let type = body["type"] as? String {
            switch type.lowercased() {
            case "playing", "play", "active":
                handleAudioState(isPlaying: true, for: senderWebView)
            case "stopped", "pause", "paused", "inactive":
                handleAudioState(isPlaying: false, for: senderWebView)
            default:
                break
            }
            return
        }

        if let body = message.body as? String {
            switch body.lowercased() {
            case "playing", "play", "active":
                handleAudioState(isPlaying: true, for: senderWebView)
            case "stopped", "pause", "paused", "inactive":
                handleAudioState(isPlaying: false, for: senderWebView)
            default:
                break
            }
        }
    }

    private func handleAudioState(isPlaying: Bool, for webView: WKWebView) {
        guard let tab = tabMap[ObjectIdentifier(webView)] else { return }
        tab.hasAudio = isPlaying

        if isPlaying {
            if let previousWebView = AudioFocusCoordinator.shared.claim(webView), previousWebView !== webView {
                pauseAllMedia(in: previousWebView)
                if let previousTab = tabMap[ObjectIdentifier(previousWebView)] {
                    previousTab.hasAudio = false
                }
            }
        } else {
            AudioFocusCoordinator.shared.releaseIfCurrent(webView)
        }
    }

    private func pauseAllMedia(in webView: WKWebView) {
        let js = """
        (() => {
          try {
            const media = Array.from(document.querySelectorAll('audio,video'));
            for (const item of media) {
              try { item.pause(); } catch (_) {}
            }
            const candidateSelectors = [
              'button[aria-label*="Pause"]',
              'button[title*="Pause"]',
              '.playControls__play',
              '.playbackSoundBadge__actions button'
            ];
            for (const selector of candidateSelectors) {
              const btn = document.querySelector(selector);
              if (btn) {
                const aria = (btn.getAttribute('aria-label') || '').toLowerCase();
                const title = (btn.getAttribute('title') || '').toLowerCase();
                if (aria.includes('pause') || title.includes('pause')) {
                  btn.click();
                  break;
                }
              }
            }
          } catch (_) {}
        })();
        """
        webView.evaluateJavaScript(js, completionHandler: nil)
    }

    private func pauseAudioInMusicWindow() {
        for tab in tabs where !tab.isSuspended {
            pauseAllMedia(in: tab.webView)
            tab.hasAudio = false
        }
        if let selectedTab {
            AudioFocusCoordinator.shared.releaseIfCurrent(selectedTab.webView)
        }
        flashMessage("Music stopped")
    }

    private func nextInMusicWindow() {
        let now = Date()
        if now.timeIntervalSince(lastMusicNextAt) < 0.45 {
            return
        }
        lastMusicNextAt = now

        guard let tab = selectedTab else { return }
        let js = """
        (() => {
          const selectors = [
            'button[aria-label*="Next"]',
            'button[title*="Next"]',
            '.ytp-next-button',
            '.playControls__next'
          ];
          for (const selector of selectors) {
            const btn = document.querySelector(selector);
            if (btn) { btn.click(); return 'clicked'; }
          }
          const media = document.querySelector('audio,video');
          if (media && Number.isFinite(media.duration)) {
            media.currentTime = Math.max(0, media.duration - 0.2);
            return 'seeked';
          }
          return 'none';
        })();
        """
        tab.webView.evaluateJavaScript(js, completionHandler: nil)
        flashMessage("Next track")
    }

    private func previousInMusicWindow() {
        guard let tab = selectedTab else { return }
        let js = """
        (() => {
          const selectors = [
            'button[aria-label*="Previous"]',
            'button[title*="Previous"]',
            '.ytp-prev-button',
            '.playControls__prev'
          ];
          for (const selector of selectors) {
            const btn = document.querySelector(selector);
            if (btn) { btn.click(); return 'clicked'; }
          }
          const media = document.querySelector('audio,video');
          if (media) {
            media.currentTime = Math.max(0, Number(media.currentTime || 0) - 15);
            return 'seeked';
          }
          return 'none';
        })();
        """
        tab.webView.evaluateJavaScript(js, completionHandler: nil)
        flashMessage("Previous track")
    }

    private func togglePlayPauseInMusicWindow() {
        guard let tab = selectedTab else { return }
        let js = """
        (() => {
          const selectors = [
            'button[aria-label*="Play"]',
            'button[aria-label*="Pause"]',
            'button[title*="Play"]',
            'button[title*="Pause"]',
            '.ytp-play-button',
            '.playControls__play'
          ];
          for (const selector of selectors) {
            const btn = document.querySelector(selector);
            if (!btn) continue;
            btn.click();
            const aria = (btn.getAttribute('aria-label') || '').toLowerCase();
            const title = (btn.getAttribute('title') || '').toLowerCase();
            if (aria.includes('pause') || title.includes('pause')) return 'playing';
            if (aria.includes('play') || title.includes('play')) return 'paused';
            return 'toggled';
          }
          const media = document.querySelector('audio,video');
          if (!media) return 'none';
          if (media.paused) {
            media.play().catch(() => {});
            return 'playing';
          }
          media.pause();
          return 'paused';
        })();
        """
        tab.webView.evaluateJavaScript(js) { [weak self] value, _ in
            guard let self else { return }
            let state = (value as? String) ?? "toggled"
            switch state {
            case "playing":
                self.flashMessage("Play")
            case "paused":
                self.flashMessage("Pause")
            case "none":
                self.flashMessage("No active player")
            default:
                self.flashMessage("Play / Pause")
            }
        }
    }

    private func adjustVolumeInMusicWindow(delta: Double) {
        guard let tab = selectedTab else { return }
        let clampedDelta = min(max(delta, -0.25), 0.25)
        let deltaValue = String(format: "%.4f", locale: Locale(identifier: "en_US_POSIX"), clampedDelta)
        let js = """
        (() => {
          const shift = Number(\(deltaValue));
          const clamp = (v) => Math.min(1, Math.max(0, v));
          let latest = -1;
          const media = Array.from(document.querySelectorAll('audio,video'));
          for (const item of media) {
            try {
              item.muted = false;
              const next = clamp(Number(item.volume || 1) + shift);
              item.volume = next;
              latest = next;
            } catch (_) {}
          }
          return latest;
        })();
        """
        tab.webView.evaluateJavaScript(js) { [weak self] value, _ in
            guard let self else { return }
            guard let number = value as? NSNumber else { return }
            let volume = number.doubleValue
            guard volume >= 0 else { return }
            let now = Date()
            if now.timeIntervalSince(self.lastMusicVolumeFeedbackAt) > 0.22 {
                self.lastMusicVolumeFeedbackAt = now
                self.flashMessage("Volume \(Int((volume * 100).rounded()))%")
            }
        }
    }

    private func favoriteCurrentTrackInMusicWindow() {
        let beforeCount = bookmarks.count
        addCurrentTabToBookmarks()
        if bookmarks.count > beforeCount {
            flashMessage("Added to favorites")
        }
    }

    private func openURLInMusicWindow(_ url: URL) {
        if let tab = selectedTab {
            tab.load(url: url)
            selectedTabID = tab.id
            smartInput = url.absoluteString
        } else {
            openNewTab(select: true, url: url, kind: .regular)
        }
    }

    private func openPlaylistFromContextInMusicWindow(sourceURL: String?, sourceTitle: String?) {
        let contextURL = sourceURL ?? selectedTab?.webView.url?.absoluteString
        let contextTitle = sourceTitle ?? selectedTab?.title
        if let target = CommandHelperClient.shared.resolveMusicPlaylistURL(sourceURL: contextURL, title: contextTitle) {
            openURLInMusicWindow(target)
            flashMessage("Playlist mode")
            return
        }
        if let fallback = URL(string: "https://music.youtube.com/") {
            openURLInMusicWindow(fallback)
            flashMessage("Playlist mode")
        }
    }

    private func focusModeInMusicWindow(mood rawMood: String?) {
        let mood = normalizeMusicMood(rawMood)
        let query = CommandHelperClient.shared.resolveMusicFocusQuery(mood: mood.rawValue) ?? "\(mood.title.lowercased()) focus playlist"
        playInMusicWindow(query: query)
        flashMessage("Focus: \(mood.title)")
    }

    private func findTrackInMusicWindow(query: String?, sourceTitle: String?) {
        let cleanQuery = query?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !cleanQuery.isEmpty {
            playInMusicWindow(query: cleanQuery)
            return
        }
        let fallbackTitle = sourceTitle ?? selectedTab?.title
        let resolved = CommandHelperClient.shared.resolveMusicFindQuery(sourceTitle: fallbackTitle) ?? fallbackTitle ?? "top tracks mix"
        playInMusicWindow(query: resolved)
    }

    private func playInMusicWindow(query: String?) {
        let raw = query?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !raw.isEmpty else {
            flashMessage("Usage: music play <query>")
            return
        }
        let targetURL: URL?
        if let direct = resolveURL(from: raw) {
            targetURL = direct
        } else {
            let escaped = raw.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? raw
            targetURL = URL(string: "https://www.youtube.com/results?search_query=\(escaped)")
        }
        guard let url = targetURL else { return }
        if let tab = selectedTab {
            tab.load(url: url)
            selectedTabID = tab.id
            smartInput = url.absoluteString
        } else {
            openNewTab(select: true, url: url, kind: .regular)
        }
    }

    private func normalizeMusicMood(_ rawMood: String?) -> MusicWheelMood {
        guard let rawMood else { return .coding }
        switch rawMood.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "trading":
            return .trading
        case "night":
            return .night
        case "resonance":
            return .resonance
        default:
            return .coding
        }
    }

    private func handleMusicCommand(
        action: String,
        query: String?,
        delta: Double? = nil,
        mood: String? = nil,
        sourceURL: String? = nil,
        sourceTitle: String? = nil
    ) {
        switch action {
        case "music_stop", "music_pause":
            pauseAudioInMusicWindow()
        case "music_toggle", "music_play_pause":
            togglePlayPauseInMusicWindow()
        case "music_next":
            nextInMusicWindow()
        case "music_previous", "music_prev":
            previousInMusicWindow()
        case "music_play":
            playInMusicWindow(query: query)
        case "music_volume_delta":
            adjustVolumeInMusicWindow(delta: delta ?? 0.08)
        case "music_favorite":
            favoriteCurrentTrackInMusicWindow()
        case "music_playlist_context":
            openPlaylistFromContextInMusicWindow(sourceURL: sourceURL, sourceTitle: sourceTitle)
        case "music_focus_mode":
            focusModeInMusicWindow(mood: mood ?? query)
        case "music_find_context":
            findTrackInMusicWindow(query: query, sourceTitle: sourceTitle)
        case "music_list":
            guard let tab = selectedTab else {
                flashMessage("Music queue is empty")
                return
            }
            if let currentURL = tab.webView.url?.host(), !currentURL.isEmpty {
                flashMessage("Now playing: \(tab.title) (\(currentURL))")
            } else {
                flashMessage("Now playing: \(tab.title)")
            }
        default:
            break
        }
    }

    private func applyChromeTheme(_ nextTheme: ChromeTheme, broadcast: Bool) {
        let normalized = nextTheme.clamped
        if normalized == chromeTheme {
            return
        }
        chromeTheme = normalized
        saveChromeTheme()
        refreshStartPagesTheme()
        if broadcast {
            NotificationCenter.default.post(name: .mcvChromeThemeDidChange, object: normalized)
        }
    }

    private func refreshStartPagesTheme() {
        for tab in tabs where tab.isStartPage {
            tab.loadNewTabPage(theme: chromeTheme)
        }
    }

    private func loadBookmarks() {
        guard let data = UserDefaults.standard.data(forKey: AppKeys.bookmarks),
              let decoded = try? JSONDecoder().decode([BookmarkItem].self, from: data) else {
            bookmarks = []
            return
        }
        bookmarks = decoded
    }

    private func saveBookmarks() {
        guard let data = try? JSONEncoder().encode(bookmarks) else { return }
        UserDefaults.standard.set(data, forKey: AppKeys.bookmarks)
    }

    private func loadHistory() {
        guard let data = UserDefaults.standard.data(forKey: AppKeys.history),
              let decoded = try? JSONDecoder().decode([HistoryItem].self, from: data) else {
            history = []
            return
        }
        history = decoded
    }

    private func saveHistory() {
        guard let data = try? JSONEncoder().encode(history) else { return }
        UserDefaults.standard.set(data, forKey: AppKeys.history)
    }

    private func loadDownloads() {
        guard let data = UserDefaults.standard.data(forKey: AppKeys.downloads),
              let decoded = try? JSONDecoder().decode([DownloadItem].self, from: data) else {
            downloads = []
            return
        }
        downloads = decoded
    }

    private func saveDownloads() {
        guard let data = try? JSONEncoder().encode(downloads) else { return }
        UserDefaults.standard.set(data, forKey: AppKeys.downloads)
    }

    private func loadSavedLibrary() {
        if let foldersData = UserDefaults.standard.data(forKey: AppKeys.savedFolders),
           let decodedFolders = try? JSONDecoder().decode([SavedFolder].self, from: foldersData) {
            savedFolders = decodedFolders
        } else {
            savedFolders = []
        }

        if let linksData = UserDefaults.standard.data(forKey: AppKeys.savedLinks),
           let decodedLinks = try? JSONDecoder().decode([SavedLink].self, from: linksData) {
            savedLinks = decodedLinks.filter { item in
                guard let folderID = item.folderID else { return true }
                return savedFolders.contains(where: { $0.id == folderID })
            }
        } else {
            savedLinks = []
        }
    }

    private func saveSavedLibrary() {
        if let foldersData = try? JSONEncoder().encode(savedFolders) {
            UserDefaults.standard.set(foldersData, forKey: AppKeys.savedFolders)
        }
        if let linksData = try? JSONEncoder().encode(savedLinks) {
            UserDefaults.standard.set(linksData, forKey: AppKeys.savedLinks)
        }
    }

    private func loadCommandAliases() {
        guard let stored = UserDefaults.standard.dictionary(forKey: AppKeys.commandAliases) as? [String: String] else {
            commandAliases = [:]
            return
        }

        var normalized: [String: String] = [:]
        for (rawKey, rawExpression) in stored {
            let key = normalizeAliasKey(rawKey)
            let expression = rawExpression.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty, !expression.isEmpty else { continue }
            normalized[key] = expression
        }
        commandAliases = normalized
    }

    private func saveCommandAliases() {
        UserDefaults.standard.set(commandAliases, forKey: AppKeys.commandAliases)
    }

    private func loadChromeTheme() {
        guard let data = UserDefaults.standard.data(forKey: AppKeys.chromeTheme),
              let decoded = try? JSONDecoder().decode(ChromeTheme.self, from: data) else {
            chromeTheme = .default
            return
        }
        chromeTheme = decoded.clamped
    }

    private func saveChromeTheme() {
        guard let data = try? JSONEncoder().encode(chromeTheme.clamped) else { return }
        UserDefaults.standard.set(data, forKey: AppKeys.chromeTheme)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let tab = tabMap[ObjectIdentifier(webView)] else { return }

        if selectedTabID == tab.id {
            tab.markActive()
        }

        if selectedTabID == tab.id {
            syncSmartInputWithCurrentTab()
        }

        guard !tab.isStartPage,
              let url = webView.url,
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return
        }

        let title = tab.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? (url.host ?? url.absoluteString) : tab.title
        let entry = HistoryItem(id: UUID(), title: title, url: url.absoluteString, visitedAt: Date())
        history.insert(entry, at: 0)
        if history.count > 1000 {
            history.removeLast(history.count - 1000)
        }
        saveHistory()
        maybeLearnSmartMapping(from: url)
        saveTabSessionIfNeeded()
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        preferences: WKWebpagePreferences,
        decisionHandler: @escaping (WKNavigationActionPolicy, WKWebpagePreferences) -> Void
    ) {
        if #available(macOS 11.3, *), navigationAction.shouldPerformDownload {
            guard shouldAllowDownload(url: navigationAction.request.url) else {
                decisionHandler(.cancel, preferences)
                return
            }
            decisionHandler(.download, preferences)
            return
        }

        if shouldBlockInsecureNavigation(navigationAction.request.url) {
            decisionHandler(.cancel, preferences)
            return
        }

        if SecurityModeStore.current() == .secure {
            preferences.allowsContentJavaScript = secureJavaScriptEnabled(for: navigationAction.request.url)
        } else {
            preferences.allowsContentJavaScript = true
        }
        decisionHandler(.allow, preferences)
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        if #available(macOS 11.3, *), navigationAction.shouldPerformDownload {
            guard shouldAllowDownload(url: navigationAction.request.url) else {
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.download)
            return
        }

        if shouldBlockInsecureNavigation(navigationAction.request.url) {
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
    ) {
        guard requiresSafeDownloadConfirmation(navigationResponse) else {
            decisionHandler(.allow)
            return
        }

        guard shouldAllowDownload(url: navigationResponse.response.url) else {
            decisionHandler(.cancel)
            return
        }

        if #available(macOS 11.3, *) {
            decisionHandler(.download)
        } else {
            decisionHandler(.allow)
        }
    }

    @available(macOS 11.3, *)
    func webView(
        _ webView: WKWebView,
        navigationResponse: WKNavigationResponse,
        didBecome download: WKDownload
    ) {
        registerDownload(download, sourceURL: navigationResponse.response.url)
    }

    @available(macOS 11.3, *)
    func webView(
        _ webView: WKWebView,
        navigationAction: WKNavigationAction,
        didBecome download: WKDownload
    ) {
        registerDownload(download, sourceURL: navigationAction.request.url)
    }

    @available(macOS 11.3, *)
    func download(
        _ download: WKDownload,
        decideDestinationUsing response: URLResponse,
        suggestedFilename: String,
        completionHandler: @escaping (URL?) -> Void
    ) {
        let destination = nextDownloadDestination(for: suggestedFilename)
        activeDownloadDestinations[ObjectIdentifier(download)] = destination
        completionHandler(destination)
    }

    @available(macOS 11.3, *)
    func downloadDidFinish(_ download: WKDownload) {
        let key = ObjectIdentifier(download)
        let source = activeDownloadSources.removeValue(forKey: key) ?? nil
        if let destination = activeDownloadDestinations.removeValue(forKey: key) {
            addDownloadRecord(sourceURL: source, destinationURL: destination)
        }
        let sourceName = source?.host() ?? source?.lastPathComponent ?? "download"
        flashMessage("Downloaded: \(sourceName)")
    }

    @available(macOS 11.3, *)
    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        let key = ObjectIdentifier(download)
        _ = activeDownloadSources.removeValue(forKey: key)
        _ = activeDownloadDestinations.removeValue(forKey: key)
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
            return
        }
        if nsError.domain == NSCocoaErrorDomain && nsError.code == NSUserCancelledError {
            return
        }
        flashMessage("Download failed: \(error.localizedDescription)")
    }

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        let opensNewWindow = navigationAction.targetFrame == nil || navigationAction.targetFrame?.isMainFrame == false
        guard opensNewWindow else { return nil }
        let settings = MCVSettingsStore.shared.settings

        if isMusicWindow {
            if let popupURL = navigationAction.request.url {
                selectedTab?.markActive()
                selectedTab?.load(url: popupURL)
                smartInput = popupURL.absoluteString
            }
            return nil
        }

        if !settings.openLinksInNewTab {
            if let popupURL = navigationAction.request.url {
                clearPendingSmartLearn()
                selectedTab?.markActive()
                selectedTab?.load(url: popupURL)
                smartInput = popupURL.absoluteString
            }
            return nil
        }

        let activeSecurityMode = SecurityModeStore.current()
        applySecurityMode(activeSecurityMode, to: configuration)
        applyWebExtensions(to: configuration)
        let popupTab = BrowserTab(kind: .regular, webViewConfiguration: configuration)
        popupTab.webView.navigationDelegate = self
        popupTab.webView.uiDelegate = self
        setupAudioMonitoring(for: popupTab)
        setupWebExtensionBridge(for: popupTab)
        if !settings.customUserAgent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            popupTab.webView.customUserAgent = settings.customUserAgent.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        tabs.append(popupTab)
        tabMap[ObjectIdentifier(popupTab.webView)] = popupTab
        selectedTabID = popupTab.id
        popupTab.markActive()
        if let popupURL = navigationAction.request.url {
            clearPendingSmartLearn()
            popupTab.load(url: popupURL)
            smartInput = popupURL.absoluteString
        }
        syncSmartInputWithCurrentTab()
        saveTabSessionIfNeeded()
        return popupTab.webView
    }

    func webViewDidClose(_ webView: WKWebView) {
        guard let tab = tabMap[ObjectIdentifier(webView)] else { return }
        closeTab(id: tab.id)
    }
}

private struct BrowserWebView: NSViewRepresentable {
    let webView: WKWebView

    func makeNSView(context: Context) -> WKWebView {
        webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        // Intentionally empty.
    }
}

private struct OllamaSidebarHTMLView: NSViewRepresentable {
    let messages: [OllamaSidebarMessage]
    let isLoading: Bool
    let accentHex: String
    let accentTextHex: String

    final class Coordinator: NSObject, WKNavigationDelegate {
        var lastHTML = ""

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.evaluateJavaScript("window.__mcvScrollToBottom && window.__mcvScrollToBottom();", completionHandler: nil)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        webView.customUserAgent = "MCV-OllamaSidebar/1.0"
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let html = renderHTML()
        if context.coordinator.lastHTML != html {
            context.coordinator.lastHTML = html
            webView.loadHTMLString(html, baseURL: nil)
        } else {
            webView.evaluateJavaScript("window.__mcvScrollToBottom && window.__mcvScrollToBottom();", completionHandler: nil)
        }
    }

    private func renderHTML() -> String {
        let rows = renderRows()
        let loading = isLoading
            ? """
                <div class="row assistant">
                  <div class="bubble assistant">
                    <div class="text">generating<span class="dots">...</span></div>
                  </div>
                </div>
              """
            : ""

        return """
        <!doctype html>
        <html>
        <head>
          <meta charset="utf-8" />
          <meta name="viewport" content="width=device-width, initial-scale=1" />
          <style>
            :root {
              --accent: \(accentHex);
              --accent-text: \(accentTextHex);
              --assistant: rgba(255,255,255,0.10);
              --assistant-border: rgba(255,255,255,0.16);
              --system: rgba(255,82,82,0.22);
              --system-border: rgba(255,128,128,0.38);
            }
            html, body {
              margin: 0;
              padding: 0;
              width: 100%;
              height: 100%;
              background: transparent;
              color: rgba(246,250,255,0.96);
              font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "Segoe UI", sans-serif;
            }
            body {
              overflow-y: auto;
              overflow-x: hidden;
              padding: 6px 4px 10px;
            }
            .empty {
              margin: 10px 0 0;
              padding: 12px 10px;
              border-radius: 12px;
              border: 1px solid rgba(255,255,255,0.14);
              background: rgba(255,255,255,0.06);
              color: rgba(232,240,255,0.72);
              font-size: 12px;
              line-height: 1.45;
            }
            .row {
              width: 100%;
              display: flex;
              margin: 7px 0;
            }
            .row.user { justify-content: flex-end; }
            .row.assistant, .row.system { justify-content: flex-start; }
            .bubble {
              max-width: 88%;
              border-radius: 14px;
              padding: 10px 11px 9px;
              border: 1px solid transparent;
              box-sizing: border-box;
            }
            .bubble.user {
              background: linear-gradient(140deg, var(--accent), rgba(76,160,255,0.88));
              color: var(--accent-text);
              border-color: rgba(255,255,255,0.26);
            }
            .bubble.assistant {
              background: var(--assistant);
              color: rgba(246,250,255,0.94);
              border-color: var(--assistant-border);
            }
            .bubble.system {
              background: var(--system);
              color: rgba(255,214,214,0.98);
              border-color: var(--system-border);
            }
            .text {
              font-size: 12px;
              line-height: 1.42;
              white-space: pre-wrap;
              word-break: break-word;
              overflow-wrap: anywhere;
              text-wrap: pretty;
            }
            .meta {
              margin-top: 6px;
              font-size: 9px;
              letter-spacing: 0.04em;
              opacity: 0.62;
              font-weight: 600;
            }
            .user .meta { opacity: 0.72; }
            .image-note {
              margin: 0 0 6px;
              font-size: 10px;
              opacity: 0.84;
              padding: 4px 7px;
              border-radius: 8px;
              background: rgba(255,255,255,0.10);
              border: 1px solid rgba(255,255,255,0.16);
              display: inline-block;
              max-width: 100%;
              overflow: hidden;
              text-overflow: ellipsis;
              white-space: nowrap;
            }
            .dots {
              display: inline-block;
              width: 1.2em;
              text-align: left;
              animation: pulse 1.2s infinite;
            }
            @keyframes pulse {
              0%, 100% { opacity: 0.3; }
              50% { opacity: 1; }
            }
          </style>
        </head>
        <body>
          \(rows)
          \(loading)
          <script>
            window.__mcvScrollToBottom = function() {
              window.scrollTo({ top: document.body.scrollHeight + 80, behavior: "smooth" });
            };
            setTimeout(window.__mcvScrollToBottom, 12);
          </script>
        </body>
        </html>
        """
    }

    private func renderRows() -> String {
        if messages.isEmpty {
            return "<div class=\"empty\">Ask anything. This view is rendered as HTML/CSS for cleaner chat UX.</div>"
        }

        return messages.map { message in
            let roleClass: String
            switch message.role {
            case .user:
                roleClass = "user"
            case .assistant:
                roleClass = "assistant"
            case .system:
                roleClass = "system"
            }

            let imageNote: String
            if let imageURL = message.imageURL {
                imageNote = "<div class=\"image-note\">image: \(escapeHTML(imageURL.lastPathComponent))</div>"
            } else {
                imageNote = ""
            }

            return """
            <div class="row \(roleClass)">
              <div class="bubble \(roleClass)">
                \(imageNote)
                <div class="text">\(escapeHTML(message.text).replacingOccurrences(of: "\n", with: "<br/>"))</div>
                <div class="meta">\(escapeHTML(timeString(message.timestamp)))</div>
              </div>
            </div>
            """
        }.joined(separator: "")
    }

    private func timeString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }

    private func escapeHTML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}

private struct WelcomeTintPreset: Identifiable {
    let id: String
    let name: String
    let hex: String
    let theme: ChromeTheme

    var color: Color {
        theme.color
    }
}

private struct WelcomeView: View {
    let onFinish: () -> Void

    @State private var pageIndex = 0
    @State private var selectedTintHex: String
    @State private var animateGradient = false

    private let tintPresets: [WelcomeTintPreset] = [
        WelcomeTintPreset(id: "ocean", name: "Ocean", hex: "#2E73E6", theme: ChromeTheme(red: 0.18, green: 0.45, blue: 0.90, intensity: 0.60)),
        WelcomeTintPreset(id: "emerald", name: "Emerald", hex: "#18A37F", theme: ChromeTheme(red: 0.09, green: 0.64, blue: 0.50, intensity: 0.60)),
        WelcomeTintPreset(id: "sunset", name: "Sunset", hex: "#E27A2C", theme: ChromeTheme(red: 0.89, green: 0.48, blue: 0.17, intensity: 0.60)),
        WelcomeTintPreset(id: "violet", name: "Violet", hex: "#7B62F4", theme: ChromeTheme(red: 0.48, green: 0.38, blue: 0.96, intensity: 0.60)),
        WelcomeTintPreset(id: "rose", name: "Rose", hex: "#DA547D", theme: ChromeTheme(red: 0.85, green: 0.33, blue: 0.49, intensity: 0.60)),
        WelcomeTintPreset(id: "steel", name: "Steel", hex: "#2D8A9F", theme: ChromeTheme(red: 0.18, green: 0.54, blue: 0.62, intensity: 0.60)),
        WelcomeTintPreset(id: "lime", name: "Lime", hex: "#8CA731", theme: ChromeTheme(red: 0.55, green: 0.65, blue: 0.19, intensity: 0.60)),
        WelcomeTintPreset(id: "mono", name: "Mono", hex: "#64748B", theme: ChromeTheme(red: 0.39, green: 0.45, blue: 0.55, intensity: 0.60))
    ]

    init(onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
        let saved = Self.normalizedHex(MCVSettingsStore.shared.settings.interfaceTintHex)
        _selectedTintHex = State(initialValue: saved)
    }

    var body: some View {
        VStack(spacing: 0) {
            Group {
                if pageIndex == 0 {
                    welcomePage
                } else {
                    palettePage
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(38)
        }
        .frame(width: 760, height: 500)
        .background(
            ZStack {
                LinearGradient(
                    colors: welcomeBaseGradientColors,
                    startPoint: animateGradient ? .topLeading : .leading,
                    endPoint: animateGradient ? .bottomTrailing : .bottom
                )
                RadialGradient(
                    colors: [welcomeAccentA.opacity(animateGradient ? 0.28 : 0.16), Color.clear],
                    center: animateGradient ? UnitPoint(x: 0.18, y: 0.12) : UnitPoint(x: 0.78, y: 0.18),
                    startRadius: 30,
                    endRadius: 320
                )
                RadialGradient(
                    colors: [welcomeAccentB.opacity(animateGradient ? 0.24 : 0.12), Color.clear],
                    center: animateGradient ? UnitPoint(x: 0.82, y: 0.88) : UnitPoint(x: 0.24, y: 0.82),
                    startRadius: 20,
                    endRadius: 300
                )
                LinearGradient(
                    colors: [
                        welcomeAccentA.opacity(animateGradient ? 0.20 : 0.12),
                        welcomeAccentB.opacity(animateGradient ? 0.14 : 0.08),
                        welcomeAccentC.opacity(animateGradient ? 0.16 : 0.10)
                    ],
                    startPoint: animateGradient ? .top : .leading,
                    endPoint: animateGradient ? .bottomTrailing : .trailing
                )
            }
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.38), radius: 26, y: 12)
        .onAppear {
            guard !animateGradient else { return }
            withAnimation(.easeInOut(duration: 7.0).repeatForever(autoreverses: true)) {
                animateGradient = true
            }
        }
    }

    private var welcomePage: some View {
        VStack(spacing: 20) {
            Spacer()

            Text("Welcome to MCV browser!")
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)

            Text("Press Cmd+E for search")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.84))

            Button(action: nextPage) {
                Image(systemName: "arrow.right")
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 58, height: 58)
                    .background(
                        Circle()
                            .fill(Color.white.opacity(0.16))
                    )
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.28), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .padding(.top, 8)

            Spacer()
        }
    }

    private var palettePage: some View {
        HStack(spacing: 28) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Choose your color")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Text("Press Cmd+E for search")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.82))

                Text("You can change it later in Appearance.")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(Color.white.opacity(0.66))

                Spacer()

                HStack(spacing: 10) {
                    Button(action: previousPage) {
                        Image(systemName: "arrow.left")
                            .font(.system(size: 14, weight: .bold))
                            .frame(width: 36, height: 36)
                            .background(Circle().fill(Color.white.opacity(0.12)))
                    }
                    .buttonStyle(.plain)

                    Button("Start Browser") {
                        finish()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(selectedPreset.color.opacity(0.95))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 10) {
                Text("Palette")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.78))

                LazyVGrid(
                    columns: [GridItem(.fixed(56), spacing: 10), GridItem(.fixed(56), spacing: 10)],
                    alignment: .trailing,
                    spacing: 10
                ) {
                    ForEach(tintPresets) { preset in
                        tintButton(preset)
                    }
                }
            }
            .frame(width: 132, alignment: .trailing)
        }
    }

    private var selectedTheme: ChromeTheme {
        selectedPreset.theme.clamped
    }

    private var welcomeBaseGradientColors: [Color] {
        let t = selectedTheme
        return [
            Color(
                red: floorTint(t.red, floor: 0.03, weight: 0.24),
                green: floorTint(t.green, floor: 0.05, weight: 0.22),
                blue: floorTint(t.blue, floor: 0.12, weight: 0.32)
            ),
            Color(
                red: floorTint(t.red, floor: 0.04, weight: 0.18),
                green: floorTint(t.green, floor: 0.04, weight: 0.16),
                blue: floorTint(t.blue, floor: 0.10, weight: 0.24)
            ),
            Color(
                red: floorTint(t.red, floor: 0.03, weight: 0.14),
                green: floorTint(t.green, floor: 0.03, weight: 0.14),
                blue: floorTint(t.blue, floor: 0.08, weight: 0.18)
            )
        ]
    }

    private var welcomeAccentA: Color {
        let t = selectedTheme
        return Color(
            red: mix(t.red, 1.0, 0.26),
            green: mix(t.green, 1.0, 0.20),
            blue: mix(t.blue, 1.0, 0.24)
        )
    }

    private var welcomeAccentB: Color {
        let t = selectedTheme
        return Color(
            red: mix(t.green, 1.0, 0.20),
            green: mix(t.blue, 1.0, 0.14),
            blue: mix(t.red, 1.0, 0.22)
        )
    }

    private var welcomeAccentC: Color {
        let t = selectedTheme
        return Color(
            red: mix(t.blue, 1.0, 0.18),
            green: mix(t.red, 1.0, 0.14),
            blue: mix(t.green, 1.0, 0.20)
        )
    }

    private func floorTint(_ value: Double, floor: Double, weight: Double) -> Double {
        clamp(floor + value * weight)
    }

    private func mix(_ from: Double, _ to: Double, _ amount: Double) -> Double {
        clamp(from + (to - from) * amount)
    }

    private func clamp(_ value: Double) -> Double {
        min(max(value, 0.0), 1.0)
    }

    private func tintButton(_ preset: WelcomeTintPreset) -> some View {
        let isSelected = normalizedHex(preset.hex) == normalizedHex(selectedTintHex)
        return Button {
            applyTint(preset)
        } label: {
            Circle()
                .fill(preset.color)
                .frame(width: 42, height: 42)
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(isSelected ? 0.95 : 0.28), lineWidth: isSelected ? 3 : 1)
                )
                .shadow(color: preset.color.opacity(0.45), radius: isSelected ? 7 : 3, y: 2)
                .accessibilityLabel(Text(preset.name))
        }
        .buttonStyle(.plain)
    }

    private var selectedPreset: WelcomeTintPreset {
        tintPresets.first(where: { normalizedHex($0.hex) == normalizedHex(selectedTintHex) }) ?? tintPresets[0]
    }

    private func previousPage() {
        withAnimation(.easeInOut(duration: 0.16)) {
            pageIndex = max(0, pageIndex - 1)
        }
    }

    private func nextPage() {
        withAnimation(.easeInOut(duration: 0.16)) {
            pageIndex = min(1, pageIndex + 1)
        }
    }

    private static func normalizedHex(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if !value.hasPrefix("#") {
            value = "#\(value)"
        }
        return value
    }

    private func normalizedHex(_ raw: String) -> String {
        Self.normalizedHex(raw)
    }

    private func applyTint(_ preset: WelcomeTintPreset) {
        selectedTintHex = normalizedHex(preset.hex)
        MCVSettingsStore.shared.update { $0.interfaceTintHex = selectedTintHex }
        let theme = preset.theme.clamped
        if let data = try? JSONEncoder().encode(theme) {
            UserDefaults.standard.set(data, forKey: AppKeys.chromeTheme)
        }
        NotificationCenter.default.post(name: .mcvChromeThemeDidChange, object: theme)
    }

    private func finish() {
        applyTint(selectedPreset)
        UserDefaults.standard.set(true, forKey: AppKeys.welcomeShown)
        onFinish()
    }
}

private enum FocusTarget {
    case smartBar
    case commandBar
    case miniBar
    case findBar
}

private struct TrafficLightBaseline {
    let x: CGFloat
    let spacing: CGFloat
}

private struct BookmarkRowDropDelegate: DropDelegate {
    let targetID: UUID
    let onMove: (UUID, UUID) -> Void
    @Binding var draggedBookmarkID: UUID?

    func dropEntered(info: DropInfo) {
        guard let draggedBookmarkID, draggedBookmarkID != targetID else { return }
        onMove(draggedBookmarkID, targetID)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedBookmarkID = nil
        return true
    }

    func dropExited(info: DropInfo) {
        // Intentionally empty.
    }
}

private struct SavedLinkDropDelegate: DropDelegate {
    let targetFolderID: UUID?
    let onMoveLink: (UUID, UUID?) -> Void
    @Binding var draggedSavedLinkID: UUID?

    func dropEntered(info: DropInfo) {}

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        guard let draggedSavedLinkID else { return false }
        onMoveLink(draggedSavedLinkID, targetFolderID)
        self.draggedSavedLinkID = nil
        return true
    }

    func dropExited(info: DropInfo) {}
}

private struct HistorySection: Identifiable {
    let id: String
    let title: String
    let items: [HistoryItem]
}

private struct TabChipView: View {
    let index: Int
    let tab: BrowserTab
    let isSelected: Bool
    let style: TabStyleOption
    let accentColor: Color
    let onSelect: () -> Void
    let onDoubleTap: () -> Void
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: tab.isBookmarkTab ? "star.fill" : "globe")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tab.isBookmarkTab ? accentColor.opacity(0.90) : (isSelected ? Color.white.opacity(0.95) : Color.white.opacity(0.60)))

            Text(tab.title)
                .lineLimit(1)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isSelected ? Color.white.opacity(0.96) : Color.white.opacity(0.70))

            if tab.isSuspended {
                Image(systemName: "moon.zzz.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.orange.opacity(0.90))
                    .help("Suspended tab")
            }

            if tab.hasAudio {
                Image(systemName: "music.note")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(accentColor.opacity(0.92))
                    .help("Audio playing")
            }

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.58))
                    .frame(width: 14, height: 14)
                    .background(Circle().fill(Color.white.opacity(0.10)))
            }
            .buttonStyle(.plain)
            .opacity(isSelected ? 1 : 0)
        }
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(isSelected ? Color.white.opacity(0.18) : Color.white.opacity(style == .compact ? 0.05 : 0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(isSelected ? Color.white.opacity(0.32) : Color.white.opacity(style == .compact ? 0.09 : 0.12), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onTapGesture(count: 2, perform: onDoubleTap)
        .help(tab.isBookmarkTab ? "Bookmark Tab \\(index + 1)" : "Tab \\(index + 1)")
    }

    private var cornerRadius: CGFloat {
        switch style {
        case .system:
            return 9
        case .compact:
            return 7
        case .rounded:
            return 13
        }
    }
}

private struct WindowConfigurator: NSViewRepresentable {
    let configure: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            if let window = view.window {
                configure(window)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            if let window = nsView.window {
                configure(window)
            }
        }
    }
}

private final class GlobalWelcomeDimmer {
    static let shared = GlobalWelcomeDimmer()

    private var isActive = false
    private var overlayWindows: [ObjectIdentifier: NSWindow] = [:]

    private init() {}

    func setActive(_ active: Bool) {
        DispatchQueue.main.async {
            if active {
                self.activate()
            } else {
                self.deactivate()
            }
        }
    }

    private func activate() {
        if isActive {
            refreshOverlays()
            return
        }
        isActive = true
        refreshOverlays()
    }

    private func deactivate() {
        guard isActive else { return }
        isActive = false
        for window in overlayWindows.values {
            window.orderOut(nil)
        }
        overlayWindows.removeAll()
    }

    private func refreshOverlays() {
        let screens = NSScreen.screens
        var next: [ObjectIdentifier: NSWindow] = [:]

        for screen in screens {
            let key = ObjectIdentifier(screen)
            let window = overlayWindows[key] ?? makeOverlayWindow(for: screen)
            window.setFrame(screen.frame, display: true)
            window.orderFrontRegardless()
            next[key] = window
        }

        for (key, window) in overlayWindows where next[key] == nil {
            window.orderOut(nil)
        }
        overlayWindows = next
    }

    private func makeOverlayWindow(for screen: NSScreen) -> NSWindow {
        let window = NSWindow(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = NSColor.black.withAlphaComponent(0.62)
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        window.level = .mainMenu
        window.isReleasedWhenClosed = false
        return window
    }
}

private struct BrowserRootView: View {
    private struct MiniTranslateRequest {
        let source: String?
        let target: String
        let text: String
    }

    @StateObject private var store: BrowserStore
    @ObservedObject private var settingsStore = MCVSettingsStore.shared
    private let windowMode: BrowserWindowMode
    @State private var showWelcome: Bool
    @AppStorage(AppKeys.hintsForcedEnabled) private var hintsForcedEnabled = false
    @AppStorage(AppKeys.chromeBarGradientEnabled) private var chromeBarGradientEnabled = true
    @AppStorage(AppKeys.chromeBarGradientAnimationEnabled) private var chromeBarGradientAnimationEnabled = false
    @Environment(\.openWindow) private var openWindow

    @FocusState private var focusedTarget: FocusTarget?
    @State private var keyMonitor: Any?
    @State private var pointerMonitor: Any?
    @State private var hostWindowID: ObjectIdentifier?
    @State private var didApplyTerminalDefaultWindowSize = false
    @State private var windowLevelBeforeWelcome: NSWindow.Level?
    @State private var appIsActive = NSApp.isActive
    @State private var showTabsOverview = false
    @State private var showDownloadsOverview = false
    @State private var isBrowserChromeVisible = true
    @State private var draggedBookmarkID: UUID?
    @State private var draggedSavedLinkID: UUID?
    @State private var showMiniMCV = false
    @State private var miniInput = ""
    @State private var miniTitle = "Mini MCV"
    @State private var miniBody = "Type `calc`, `translate` or `ai` for instant result."
    @State private var miniDetail = "Examples: calc 12*7, tran r e привет, ai explain fibonacci retracement"
    @State private var miniIsError = false
    @State private var miniIsLoading = false
    @State private var miniTask: Task<Void, Never>?
    @State private var showTrafficLightTuner = false
    @State private var trafficLightXOffset: CGFloat = 3
    @State private var trafficLightY: CGFloat = 0
    @State private var trafficLightSpacingOffset: CGFloat = -1
    @State private var trafficLightBaselines: [ObjectIdentifier: TrafficLightBaseline] = [:]
    @State private var colorHexInput = ""
    @State private var colorRGBInput = ""
    @State private var colorInputMessage = ""
    @State private var colorInputError = false
    @State private var findInPageQuery = ""
    @State private var showFindOverlay = false
    @State private var findSuggestions: [PageFindSuggestion] = []
    @State private var findSelectedSuggestionIndex: Int?
    @State private var findTotalMatches = 0
    @State private var findSearchWorkItem: DispatchWorkItem?
    @State private var showSavedNavigator = false
    @State private var savedNavigatorFolderID: UUID?
    @State private var savedNavigatorSelectionIndex = 0
    @State private var bookmarksPanelSelectionIndex = 0
    @State private var bookmarkShortcutDraftByID: [UUID: String] = [:]
    @State private var showExtensionsInstallInput = false
    @State private var extensionsInstallInput = ""
    @State private var extensionsPanelBundles: [WebExtensionBundle] = []
    @State private var extensionRenameDraftByID: [String: String] = [:]
    @State private var ollamaSidebarInput = ""
    @State private var ollamaSidebarMessages: [OllamaSidebarMessage] = []
    @State private var ollamaSidebarSending = false
    @State private var ollamaSidebarAttachedImageURL: URL?
    @State private var ollamaSidebarTask: Task<Void, Never>?
    @State private var ollamaSidebarIncludePageContext = true
    @State private var ollamaSidebarPageActions: [AIPageActionItem] = []
    @State private var ollamaSidebarPageContextLine = ""
    @State private var animateChromeBarGradient = false
    @State private var tabStripSweepPhase: CGFloat = -0.60
    @State private var tabStripSweepStarted = false
    @State private var showTabWheel = false
    @State private var tabWheelCenter = CGPoint(x: 220, y: 220)
    @State private var tabWheelSelectionIndex = 0
    @State private var showMusicWheel = false
    @State private var musicWheelCenter = CGPoint(x: 200, y: 200)
    @State private var musicWheelDrag = CGSize.zero
    @State private var musicWheelSelection: MusicWheelAction = .playPause
    @State private var musicWheelNowPlaying: MusicWheelNowPlaying = .placeholder
    @State private var musicWheelMood: MusicWheelMood = .coding
    @State private var showLinkHintMode = false
    @State private var linkHintInput = ""
    @State private var securityMode: SecurityModeOption = SecurityModeStore.current()

    init(windowMode: BrowserWindowMode = .standard) {
        self.windowMode = windowMode
        _store = StateObject(wrappedValue: BrowserStore(windowMode: windowMode))
        let forceHints = UserDefaults.standard.bool(forKey: AppKeys.hintsForcedEnabled)
        let shouldShowOnboarding = HintLifecycle.shouldShowHints(forceEnabled: forceHints)
        let welcomeAlreadyShown = UserDefaults.standard.bool(forKey: AppKeys.welcomeShown)
        _showWelcome = State(initialValue: windowMode == .standard && shouldShowOnboarding && (forceHints || !welcomeAlreadyShown))
    }

    private var appSettings: MCVBrowserSettings {
        settingsStore.settings
    }

    private var shouldShowInAppHints: Bool {
        HintLifecycle.shouldShowHints(forceEnabled: hintsForcedEnabled)
    }

    private var preferredScheme: ColorScheme? {
        switch appSettings.appearanceTheme {
        case .system:
            return nil
        case .dark:
            return .dark
        case .light:
            return .light
        }
    }

    private var uiScale: CGFloat {
        CGFloat(min(max(appSettings.interfaceScale, 0.85), 1.25))
    }

    private var uiOpacity: Double {
        min(max(appSettings.interfaceOpacity, 0.05), 1.0)
    }

    var body: some View {
        reactiveLayer
            .preferredColorScheme(preferredScheme)
    }

    private var lifecycleLayer: some View {
        rootOverlayLayer
            .onAppear {
                securityMode = SecurityModeStore.current()
                appIsActive = NSApp.isActive
                setGlobalWelcomePresentation(showWelcome)
                startChromeBarAnimationsIfNeeded()
                refreshExtensionsPanelSnapshot()
                refreshBookmarkShortcutDrafts()
                installKeyboardMonitor()
                refreshPointerMonitor()
            }
            .onDisappear {
                setGlobalWelcomePresentation(false)
                removeKeyboardMonitor()
                removePointerMonitor()
                stopChromeBarAnimations()
                miniTask?.cancel()
                ollamaSidebarTask?.cancel()
                findSearchWorkItem?.cancel()
                showTabWheel = false
                showMusicWheel = false
                showDownloadsOverview = false
                showFindOverlay = false
                showSavedNavigator = false
                deactivateLinkHintMode(removeFromAllTabs: true)
                store.clearFindHighlights()
            }
            .onChange(of: showWelcome) { visible in
                setGlobalWelcomePresentation(visible)
                if visible {
                    stopChromeBarAnimations()
                } else {
                    startChromeBarAnimationsIfNeeded()
                }
            }
            .onChange(of: chromeBarGradientEnabled) { enabled in
                if enabled {
                    startChromeBarAnimationsIfNeeded()
                } else {
                    stopChromeBarAnimations()
                }
            }
            .onChange(of: chromeBarGradientAnimationEnabled) { enabled in
                if enabled {
                    startChromeBarAnimationsIfNeeded()
                } else {
                    stopChromeBarAnimations()
                }
            }
            .onChange(of: showTabWheel) { _ in refreshPointerMonitor() }
            .onChange(of: showMusicWheel) { _ in refreshPointerMonitor() }
            .onChange(of: showSavedNavigator) { _ in refreshPointerMonitor() }
            .onChange(of: showLinkHintMode) { _ in refreshPointerMonitor() }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                appIsActive = true
                startChromeBarAnimationsIfNeeded()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
                appIsActive = false
                stopChromeBarAnimations()
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name.NSProcessInfoPowerStateDidChange)) { _ in
                if shouldRunChromeAnimations {
                    startChromeBarAnimationsIfNeeded()
                } else {
                    stopChromeBarAnimations()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .mcvRequestMusicAction)) { note in
                handleMusicActionRequest(note)
            }
            .onReceive(NotificationCenter.default.publisher(for: .mcvSecurityModeDidChange)) { note in
                handleSecurityModeNotification(note)
            }
    }

    private var chromeAnimatedLayer: some View {
        lifecycleLayer
            .background(
                WindowConfigurator { window in
                    configureWindowChrome(window)
                }
            )
            .ignoresSafeArea(.container, edges: .top)
            .animation(.easeInOut(duration: 0.15), value: store.isCommandOverlayVisible)
            .animation(.easeInOut(duration: 0.15), value: store.utilityPanel)
            .animation(.easeInOut(duration: 0.15), value: isBrowserChromeVisible)
            .animation(.easeInOut(duration: 0.12), value: showFindOverlay)
            .animation(.easeInOut(duration: 0.12), value: showSavedNavigator)
            .animation(.easeInOut(duration: 0.12), value: showTabWheel)
            .animation(.easeInOut(duration: 0.12), value: showMusicWheel)
    }

    private var reactiveLayer: some View {
        chromeAnimatedLayer
            .onChange(of: store.selectedTabID) { _ in
                if showLinkHintMode {
                    deactivateLinkHintMode(removeFromAllTabs: true)
                }
                syncBookmarksPanelSelection(preferCurrent: true)
                guard showFindOverlay else { return }
                let query = findInPageQuery.trimmingCharacters(in: .whitespacesAndNewlines)
                if query.isEmpty {
                    store.clearFindHighlights()
                    findSuggestions = []
                    findSelectedSuggestionIndex = nil
                    findTotalMatches = 0
                } else {
                    scheduleFindSearch(for: query, immediate: true)
                }
                if store.utilityPanel == .ollamaChat, ollamaSidebarIncludePageContext {
                    refreshOllamaSidebarPageContext()
                }
            }
            .onChange(of: savedNavigatorFolderID) { _ in
                clampSavedNavigatorSelection()
            }
            .onChange(of: store.savedFolders.count) { _ in
                clampSavedNavigatorSelection()
            }
            .onChange(of: store.savedLinks.count) { _ in
                clampSavedNavigatorSelection()
            }
            .onChange(of: store.utilityPanel) { panel in
                if panel == .bookmarks {
                    syncBookmarksPanelSelection(preferCurrent: true)
                    refreshBookmarkShortcutDrafts()
                } else if panel == .extensions {
                    refreshExtensionsPanelSnapshot()
                } else if panel == .ollamaChat {
                    refreshOllamaSidebarPageContext()
                } else {
                    showExtensionsInstallInput = false
                    extensionsInstallInput = ""
                }
            }
            .onChange(of: store.extensionInstallInProgress) { inProgress in
                if !inProgress, store.utilityPanel == .extensions {
                    refreshExtensionsPanelSnapshot()
                }
            }
            .onChange(of: store.bookmarks.count) { _ in
                syncBookmarksPanelSelection(preferCurrent: false)
                refreshBookmarkShortcutDrafts()
            }
            .onChange(of: store.isCommandOverlayVisible) { visible in
                if visible, showLinkHintMode {
                    deactivateLinkHintMode(removeFromAllTabs: true)
                }
            }
    }

    private var rootOverlayLayer: some View {
        ZStack {
            content
                .blur(radius: showWelcome ? 7 : 0)
                .disabled(showWelcome)

            if showWelcome {
                ZStack {
                    Color.black.opacity(0.64)

                    LinearGradient(
                        colors: welcomeBackdropBaseColors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    LinearGradient(
                        colors: [
                            welcomeBackdropAccentA.opacity(0.24),
                            welcomeBackdropAccentB.opacity(0.18),
                            welcomeBackdropAccentC.opacity(0.15)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    RadialGradient(
                        colors: [welcomeBackdropAccentA.opacity(0.30), Color.clear],
                        center: .topLeading,
                        startRadius: 30,
                        endRadius: 560
                    )
                    RadialGradient(
                        colors: [welcomeBackdropAccentB.opacity(0.24), Color.clear],
                        center: .bottomTrailing,
                        startRadius: 40,
                        endRadius: 540
                    )
                    Color.black.opacity(0.42)
                }
                .ignoresSafeArea()
                .transition(.opacity)

                WelcomeView {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showWelcome = false
                    }
                }
                .transition(.opacity)
            }

            if showMiniMCV {
                miniMCVOverlay
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            if showTrafficLightTuner {
                trafficLightTunerOverlay
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            if showFindOverlay {
                findInPageOverlay
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            if showSavedNavigator {
                savedNavigatorOverlay
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }

            if store.isCommandOverlayVisible {
                commandOverlay
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
            }

            if showTabWheel {
                tabWheelOverlay
                    .transition(.opacity)
            }

            if showMusicWheel {
                musicWheelOverlay
                    .transition(.opacity)
            }

            if let message = store.transientMessage {
                VStack {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.green.opacity(0.92))
                        Text(message)
                            .foregroundStyle(Color.white.opacity(0.95))
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule(style: .continuous))
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(Color.white.opacity(0.24), lineWidth: 1)
                    )
                    .padding(.top, 10)
                    Spacer()
                }
                .allowsHitTesting(false)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    private var welcomeBackdropTheme: ChromeTheme {
        store.chromeTheme.clamped
    }

    private var welcomeBackdropBaseColors: [Color] {
        let t = welcomeBackdropTheme
        return [
            Color(
                red: backdropTint(t.red, floor: 0.03, weight: 0.22),
                green: backdropTint(t.green, floor: 0.07, weight: 0.24),
                blue: backdropTint(t.blue, floor: 0.18, weight: 0.34)
            ),
            Color(
                red: backdropTint(t.red, floor: 0.08, weight: 0.20),
                green: backdropTint(t.green, floor: 0.04, weight: 0.16),
                blue: backdropTint(t.blue, floor: 0.14, weight: 0.24)
            ),
            Color(
                red: backdropTint(t.red, floor: 0.03, weight: 0.12),
                green: backdropTint(t.green, floor: 0.08, weight: 0.18),
                blue: backdropTint(t.blue, floor: 0.10, weight: 0.20)
            )
        ]
    }

    private var welcomeBackdropAccentA: Color {
        let t = welcomeBackdropTheme
        return Color(
            red: backdropMix(t.red, 1.0, 0.26),
            green: backdropMix(t.green, 1.0, 0.22),
            blue: backdropMix(t.blue, 1.0, 0.30)
        )
    }

    private var welcomeBackdropAccentB: Color {
        let t = welcomeBackdropTheme
        return Color(
            red: backdropMix(t.green, 1.0, 0.18),
            green: backdropMix(t.blue, 1.0, 0.14),
            blue: backdropMix(t.red, 1.0, 0.20)
        )
    }

    private var welcomeBackdropAccentC: Color {
        let t = welcomeBackdropTheme
        return Color(
            red: backdropMix(t.blue, 1.0, 0.16),
            green: backdropMix(t.red, 1.0, 0.12),
            blue: backdropMix(t.green, 1.0, 0.18)
        )
    }

    private func backdropTint(_ value: Double, floor: Double, weight: Double) -> Double {
        backdropClamp(floor + value * weight)
    }

    private func backdropMix(_ from: Double, _ to: Double, _ amount: Double) -> Double {
        backdropClamp(from + (to - from) * amount)
    }

    private func backdropClamp(_ value: Double) -> Double {
        min(max(value, 0.0), 1.0)
    }

    private func setGlobalWelcomePresentation(_ enabled: Bool) {
        guard windowMode == .standard else { return }

        if enabled {
            GlobalWelcomeDimmer.shared.setActive(true)
            guard let window = hostWindow() else { return }
            if windowLevelBeforeWelcome == nil {
                windowLevelBeforeWelcome = window.level
            }
            if window.level.rawValue < NSWindow.Level.statusBar.rawValue {
                window.level = .statusBar
            }
            window.orderFrontRegardless()
        } else {
            GlobalWelcomeDimmer.shared.setActive(false)
            if let window = hostWindow(), let previousLevel = windowLevelBeforeWelcome {
                window.level = previousLevel
            }
            windowLevelBeforeWelcome = nil
        }
    }

    private func configureWindowChrome(_ window: NSWindow) {
        hostWindowID = ObjectIdentifier(window)
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.styleMask.insert(.fullSizeContentView)
        if !store.isMusicWindow {
            window.minSize = NSSize(width: 260, height: 180)
            if !didApplyTerminalDefaultWindowSize {
                didApplyTerminalDefaultWindowSize = true
                window.setContentSize(NSSize(width: 1340, height: 760))
            }
        }
        if #available(macOS 11.0, *) {
            window.titlebarSeparatorStyle = .none
        }
        window.acceptsMouseMovedEvents = true
        if store.isMusicWindow {
            MusicWindowManager.shared.register(window)
        }
        positionTrafficLights(in: window)
        setGlobalWelcomePresentation(showWelcome)
    }

    private func positionTrafficLights(in window: NSWindow) {
        guard let close = window.standardWindowButton(.closeButton),
              let mini = window.standardWindowButton(.miniaturizeButton),
              let zoom = window.standardWindowButton(.zoomButton) else {
            return
        }

        let buttons = [close, mini, zoom]
        let key = ObjectIdentifier(window)
        if trafficLightBaselines[key] == nil {
            let defaultSpacing = mini.frame.minX - close.frame.maxX
            let spacing = defaultSpacing > 0 ? defaultSpacing : 6
            trafficLightBaselines[key] = TrafficLightBaseline(x: close.frame.minX, spacing: spacing)
        }
        guard let baseline = trafficLightBaselines[key] else { return }

        let spacing = max(2, baseline.spacing + trafficLightSpacingOffset)
        let targetY = trafficLightY

        var x = baseline.x + trafficLightXOffset
        for button in buttons {
            var frame = button.frame
            frame.origin.x = x
            frame.origin.y = targetY
            button.setFrameOrigin(frame.origin)
            x += frame.width + spacing
        }
    }

    private var trafficLightTunerOverlay: some View {
        VStack {
            HStack {
                Spacer()
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Traffic Lights")
                            .font(.system(size: 13, weight: .semibold))
                        Spacer()
                        Button(action: { showTrafficLightTuner = false }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 11, weight: .bold))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.white.opacity(0.8))
                    }

                    tunerRow(
                        label: "X offset",
                        value: $trafficLightXOffset,
                        range: -36...120
                    )
                    tunerRow(
                        label: "Y",
                        value: $trafficLightY,
                        range: 0...30
                    )
                    tunerRow(
                        label: "Spacing",
                        value: $trafficLightSpacingOffset,
                        range: -8...20
                    )

                    HStack(spacing: 8) {
                        Button("Reset") {
                            trafficLightXOffset = 3
                            trafficLightY = 0
                            trafficLightSpacingOffset = -1
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Button("Copy") {
                            copyTrafficLightValues()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                    .padding(.top, 2)
                }
                .padding(12)
                .frame(width: 260)
                .background(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                .shadow(color: .black.opacity(0.33), radius: 14, y: 6)
                .padding(.top, 64)
                .padding(.trailing, 12)
            }
            Spacer()
        }
    }

    private func tunerRow(label: String, value: Binding<CGFloat>, range: ClosedRange<CGFloat>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.7))
                Spacer()
                Text("\(Int(value.wrappedValue))")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.95))
            }
            Slider(value: value, in: range, step: 1)
        }
    }

    private func copyTrafficLightValues() {
        let payload = "trafficLightXOffset=\(Int(trafficLightXOffset)); trafficLightY=\(Int(trafficLightY)); trafficLightSpacingOffset=\(Int(trafficLightSpacingOffset))"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(payload, forType: .string)
        store.transientMessage = "Traffic light values copied"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            if store.transientMessage == "Traffic light values copied" {
                store.transientMessage = nil
            }
        }
    }

    private var miniMCVOverlay: some View {
        ZStack {
            Color.black.opacity(0.24)
                .ignoresSafeArea()
                .onTapGesture {
                    closeMiniMCV()
                }

            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(Color.white.opacity(0.72))

                    TextField("Mini MCV command", text: Binding(
                        get: { miniInput },
                        set: { value in
                            miniInput = value
                            updateMiniHint(for: value)
                        }
                    ))
                    .textFieldStyle(.plain)
                    .font(.system(size: 25, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.96))
                    .focused($focusedTarget, equals: .miniBar)
                    .onSubmit {
                        runMiniCommand()
                    }
                }
                .padding(.horizontal, 16)
                .frame(height: 58)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.white.opacity(0.11))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.22), lineWidth: 1)
                )

                VStack(alignment: .leading, spacing: 8) {
                    if miniIsLoading {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Working...")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(Color.white.opacity(0.82))
                        }
                    } else {
                        Text(miniTitle)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(miniIsError ? Color.red.opacity(0.92) : adaptiveAccentColor.opacity(0.90))
                        Text(miniBody)
                            .font(.system(size: 20, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.white.opacity(0.95))
                            .lineLimit(3)
                            .textSelection(.enabled)
                        if !miniDetail.isEmpty {
                            Text(miniDetail)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Color.white.opacity(0.68))
                                .lineLimit(2)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .fill(Color.black.opacity(0.23))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )

                HStack(spacing: 8) {
                    miniPresetButton("calc 12*7")
                    miniPresetButton("translate привет")
                    miniPresetButton("ai explain trend following in 3 bullets")
                    Spacer()
                }
            }
            .padding(14)
            .frame(width: min(760, NSScreen.main?.frame.width ?? 760 - 120))
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        LinearGradient(
                            colors: [adaptiveAccentColor.opacity(0.15), Color.clear, Color.white.opacity(0.06)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.white.opacity(0.22), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.4), radius: 24, y: 8)
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
                    focusedTarget = .miniBar
                }
            }
        }
    }

    private func miniPresetButton(_ text: String) -> some View {
        Button(text) {
            miniInput = text
            updateMiniHint(for: text)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private func toggleMiniMCV() {
        if showMiniMCV {
            closeMiniMCV()
            return
        }
        deactivateLinkHintMode(removeFromAllTabs: false)
        if showFindOverlay {
            closeFindOverlay(clearHighlights: true)
        }
        if showSavedNavigator {
            closeSavedNavigator()
        }
        store.closeCommandOverlay()
        showMiniMCV = true
        miniInput = ""
        miniTask?.cancel()
        miniIsLoading = false
        miniIsError = false
        miniTitle = "Mini MCV"
        miniBody = "Type `calc`, `translate` or `ai` for instant result."
        miniDetail = "Examples: calc 12*7, tran r e привет, ai explain fibonacci retracement"
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
            focusedTarget = .miniBar
        }
    }

    private func closeMiniMCV() {
        showMiniMCV = false
        miniTask?.cancel()
        miniIsLoading = false
        if focusedTarget == .miniBar {
            focusedTarget = nil
        }
    }

    private func handleMusicActionRequest(_ note: Notification) {
        guard let userInfo = note.userInfo,
              let action = userInfo["action"] as? String else {
            return
        }
        if let requestID = userInfo["requestID"] as? String,
           !MusicActionDispatchDeduper.shared.claim(requestID) {
            return
        }

        let query = userInfo["query"] as? String
        let delta = (userInfo["delta"] as? NSNumber)?.doubleValue
        let mood = userInfo["mood"] as? String
        let sourceURL = userInfo["sourceURL"] as? String
        let sourceTitle = userInfo["sourceTitle"] as? String
        let hadLiveMusicWindow = MusicWindowManager.shared.hasLiveWindow
        MusicWindowManager.shared.present { id in
            openWindow(id: id)
        }

        guard action != "open_music_window" else { return }

        var payload: [AnyHashable: Any] = ["action": action]
        if let query, !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            payload["query"] = query
        }
        if let delta {
            payload["delta"] = delta
        }
        if let mood, !mood.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            payload["mood"] = mood
        }
        if let sourceURL, !sourceURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            payload["sourceURL"] = sourceURL
        }
        if let sourceTitle, !sourceTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            payload["sourceTitle"] = sourceTitle
        }
        let delay: TimeInterval = hadLiveMusicWindow ? 0.0 : 0.22
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            NotificationCenter.default.post(name: .mcvMusicCommand, object: nil, userInfo: payload)
        }
    }

    private func handleSecurityModeNotification(_ note: Notification) {
        guard windowMode == .standard else { return }
        let newMode = (note.object as? SecurityModeOption) ?? SecurityModeStore.current()
        let oldMode = securityMode
        securityMode = newMode
        guard newMode != oldMode else { return }

        guard let window = hostWindow(),
              window.isMainWindow || window.isKeyWindow else {
            return
        }

        closeMiniMCV()
        closeSavedNavigator()
        closeFindOverlay(clearHighlights: true)
        deactivateLinkHintMode(removeFromAllTabs: false)
        showTabWheel = false
        showMusicWheel = false
        store.closeCommandOverlay()
        focusedTarget = nil

        openWindow(id: AppSceneIDs.mainWindow)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
            window.close()
        }
    }

    private func toggleBrowserChromeVisibility() {
        isBrowserChromeVisible.toggle()
        if !isBrowserChromeVisible {
            showTabsOverview = false
            showDownloadsOverview = false
        }
    }

    private func promptResetBrowserToFirstLaunchState() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Reset browser to first-launch state?"
        alert.informativeText = "This clears tabs, bookmarks, saved links, history, settings, cookies and launch counters."
        alert.addButton(withTitle: "Reset")
        alert.addButton(withTitle: "Cancel")

        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return }
        performResetBrowserToFirstLaunchState()
    }

    private func performResetBrowserToFirstLaunchState() {
        findSearchWorkItem?.cancel()
        findSearchWorkItem = nil

        closeMiniMCV()
        closeSavedNavigator()
        closeFindOverlay(clearHighlights: true)
        deactivateLinkHintMode(removeFromAllTabs: true)
        store.closeCommandOverlay()

        showTrafficLightTuner = false
        showTabsOverview = false
        showDownloadsOverview = false
        showTabWheel = false
        showMusicWheel = false
        focusedTarget = nil

        settingsStore.resetToDefaults()
        hintsForcedEnabled = false
        store.resetForFirstLaunchTesting()

        let keysToClear = [
            AppKeys.welcomeShown,
            AppKeys.hintLaunchCount,
            AppKeys.hintsForcedEnabled,
            AppKeys.bookmarks,
            AppKeys.history,
            AppKeys.downloads,
            AppKeys.savedFolders,
            AppKeys.savedLinks,
            AppKeys.chromeTheme,
            AppKeys.settings,
            AppKeys.tabSession,
            AppKeys.ollamaModel,
            AppKeys.commandAliases,
            AppKeys.securityMode,
            AppKeys.clearOnExitHosts,
            AppKeys.secureJavaScriptRules,
            AppKeys.chromeBarGradientEnabled,
            AppKeys.chromeBarGradientAnimationEnabled
        ]
        for key in keysToClear {
            UserDefaults.standard.removeObject(forKey: key)
        }
        UserDefaults.standard.synchronize()

        HTTPCookieStorage.shared.removeCookies(since: .distantPast)
        SecurityProfileRuntime.clearAllWebsiteData()

        findInPageQuery = ""
        findSuggestions = []
        findSelectedSuggestionIndex = nil
        findTotalMatches = 0

        showWelcome = HintLifecycle.shouldShowHints(forceEnabled: false)

        store.transientMessage = "Browser reset to first-launch state"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            if store.transientMessage == "Browser reset to first-launch state" {
                store.transientMessage = nil
            }
        }
    }

    private func toggleLinkHintMode() {
        if showLinkHintMode {
            deactivateLinkHintMode(removeFromAllTabs: false)
        } else {
            activateLinkHintMode()
        }
    }

    private func activateLinkHintMode() {
        guard let webView = store.selectedTab?.webView else { return }
        linkHintInput = ""
        webView.evaluateJavaScript(linkHintsBootstrapScript()) { value, _ in
            let payload = parseLinkHintPayload(from: value)
            let total = (payload["total"] as? NSNumber)?.intValue ?? 0
            DispatchQueue.main.async {
                if total > 0 {
                    showLinkHintMode = true
                } else {
                    showLinkHintMode = false
                    linkHintInput = ""
                    store.transientMessage = "No keyboard targets on this page"
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                        if store.transientMessage == "No keyboard targets on this page" {
                            store.transientMessage = nil
                        }
                    }
                }
            }
        }
    }

    private func deactivateLinkHintMode(removeFromAllTabs: Bool) {
        let webViews: [WKWebView]
        if removeFromAllTabs {
            webViews = store.tabs.map(\.webView)
        } else if let selected = store.selectedTab?.webView {
            webViews = [selected]
        } else {
            webViews = []
        }

        let js = linkHintsTeardownScript()
        for webView in webViews {
            webView.evaluateJavaScript(js, completionHandler: nil)
        }
        showLinkHintMode = false
        linkHintInput = ""
    }

    private func applyLinkHintFilter(activateFirstMatch: Bool = false) {
        guard showLinkHintMode,
              let webView = store.selectedTab?.webView else {
            return
        }
        let query = linkHintInput.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let js = linkHintsFilterScript(prefix: query, activateFirstMatch: activateFirstMatch)
        webView.evaluateJavaScript(js) { value, _ in
            let payload = parseLinkHintPayload(from: value)
            let activated = (payload["activated"] as? NSNumber)?.boolValue ?? false
            let alive = (payload["alive"] as? NSNumber)?.boolValue ?? false

            DispatchQueue.main.async {
                if activated || !alive {
                    showLinkHintMode = false
                    linkHintInput = ""
                }
            }
        }
    }

    private func handleLinkHintKeyDown(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        if !flags.isEmpty {
            return false
        }

        switch event.keyCode {
        case 53: // Escape
            deactivateLinkHintMode(removeFromAllTabs: false)
            return true
        case 51, 117: // Delete / Forward Delete
            if !linkHintInput.isEmpty {
                linkHintInput.removeLast()
                applyLinkHintFilter()
            } else {
                deactivateLinkHintMode(removeFromAllTabs: false)
            }
            return true
        case 36, 76: // Return / Enter
            applyLinkHintFilter(activateFirstMatch: true)
            return true
        default:
            break
        }

        guard let chars = event.charactersIgnoringModifiers,
              chars.count == 1 else {
            return true
        }
        let upper = chars.uppercased()
        guard let scalar = upper.unicodeScalars.first,
              scalar.value >= 65,
              scalar.value <= 90 else {
            return true
        }

        linkHintInput.append(upper)
        applyLinkHintFilter()
        return true
    }

    private func parseLinkHintPayload(from value: Any?) -> [String: Any] {
        guard let raw = value as? String,
              let data = raw.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return object
    }

    private func linkHintsJSStringLiteral(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
        return "\"\(escaped)\""
    }

    private func linkHintsBootstrapScript() -> String {
        #"""
        (() => {
          const stateKey = "__mcvLinkHintsState";
          const layerID = "__mcv_link_hints_layer";
          const styleID = "__mcv_link_hints_style";
          const targetAttr = "data-mcv-link-hint-target";
          const visibleAttr = "data-mcv-link-hint-visible";
          const hintClass = "__mcv_link_hint_item";
          const selector = [
            "a[href]",
            "button",
            "input:not([type='hidden'])",
            "textarea",
            "select",
            "summary",
            "[role='button']",
            "[role='link']",
            "[onclick]",
            "[tabindex]"
          ].join(",");

          const clearExisting = () => {
            const previous = window[stateKey];
            if (previous && Array.isArray(previous.items)) {
              for (const item of previous.items) {
                try {
                  if (item && item.target) {
                    item.target.removeAttribute(targetAttr);
                    item.target.removeAttribute(visibleAttr);
                  }
                } catch (_) {}
              }
            }
            const oldNodes = Array.from(document.querySelectorAll(`[${targetAttr}]`));
            for (const node of oldNodes) {
              try {
                node.removeAttribute(targetAttr);
                node.removeAttribute(visibleAttr);
              } catch (_) {}
            }

            const layer = document.getElementById(layerID);
            if (layer && layer.parentNode) {
              layer.parentNode.removeChild(layer);
            }
            const style = document.getElementById(styleID);
            if (style && style.parentNode) {
              style.parentNode.removeChild(style);
            }
            delete window[stateKey];
          };

          const isVisible = (el) => {
            if (!(el instanceof HTMLElement)) return false;
            const rect = el.getBoundingClientRect();
            if (rect.width < 4 || rect.height < 4) return false;
            if (rect.bottom < 0 || rect.right < 0 || rect.top > window.innerHeight || rect.left > window.innerWidth) return false;
            const st = window.getComputedStyle(el);
            if (!st) return false;
            if (st.visibility === "hidden" || st.display === "none") return false;
            if (Number(st.opacity || "1") < 0.05) return false;
            if (el.hasAttribute("disabled")) return false;
            if (el.getAttribute("aria-disabled") === "true") return false;
            return true;
          };

          const ensureStyle = () => {
            let style = document.getElementById(styleID);
            if (!style) {
              style = document.createElement("style");
              style.id = styleID;
              (document.head || document.documentElement).appendChild(style);
            }
            style.textContent = `
              #${layerID} {
                position: fixed;
                inset: 0;
                z-index: 2147483647;
                pointer-events: none;
                font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
              }
              #${layerID} .${hintClass} {
                position: fixed;
                transform: translate(-50%, -50%);
                background: rgba(10, 15, 24, 0.92);
                color: #f5fbff;
                border: 1px solid rgba(78, 187, 255, 0.86);
                border-radius: 7px;
                padding: 1px 6px;
                min-width: 20px;
                text-align: center;
                font-weight: 800;
                font-size: 11px;
                line-height: 1.4;
                letter-spacing: 0.5px;
                box-shadow: 0 7px 22px rgba(0, 0, 0, 0.38);
                text-transform: uppercase;
                white-space: nowrap;
              }
              #${layerID} .${hintClass}[data-match="0"] {
                display: none;
              }
              #${layerID} .${hintClass}[data-prefix="1"] {
                background: rgba(35, 94, 182, 0.95);
                border-color: rgba(150, 214, 255, 0.95);
              }
              [${targetAttr}] {
                outline: 2px solid rgba(88, 187, 255, 0.58) !important;
                outline-offset: 2px !important;
                transition: outline-color 0.08s ease;
              }
              [${targetAttr}][${visibleAttr}="0"] {
                outline-color: rgba(88, 187, 255, 0.18) !important;
              }
              [${targetAttr}][${visibleAttr}="1"] {
                outline-color: rgba(97, 201, 255, 0.75) !important;
              }
            `;
          };

          const alphabet = "ASDFGHJKLQWERTYUIOPZXCVBNM";
          const base = alphabet.length;
          const codeLengthForCount = (count) => {
            const target = Math.max(1, count);
            let length = 1;
            let capacity = base;
            while (capacity < target) {
              length += 1;
              capacity *= base;
            }
            return length;
          };
          const makeCode = (index, length) => {
            let n = index;
            const chars = new Array(length).fill(alphabet[0]);
            for (let pos = length - 1; pos >= 0; pos -= 1) {
              chars[pos] = alphabet[n % base];
              n = Math.floor(n / base);
            }
            return chars.join("");
          };

          clearExisting();
          ensureStyle();

          const layer = document.createElement("div");
          layer.id = layerID;
          (document.body || document.documentElement).appendChild(layer);

          const nodes = Array.from(document.querySelectorAll(selector))
            .filter((node) => isVisible(node));
          const codeLength = codeLengthForCount(nodes.length);

          const items = [];
          let index = 0;
          for (const node of nodes) {
            if (!(node instanceof HTMLElement)) continue;
            const code = makeCode(index++, codeLength);
            const rect = node.getBoundingClientRect();
            const x = Math.min(window.innerWidth - 12, Math.max(12, rect.left + Math.min(rect.width * 0.45, 34)));
            const y = Math.min(window.innerHeight - 10, Math.max(10, rect.top + Math.min(rect.height * 0.35, 16)));

            node.setAttribute(targetAttr, code);
            node.setAttribute(visibleAttr, "1");

            const badge = document.createElement("span");
            badge.className = hintClass;
            badge.dataset.code = code;
            badge.dataset.match = "1";
            badge.dataset.prefix = "0";
            badge.style.left = `${x}px`;
            badge.style.top = `${y}px`;
            badge.textContent = code;
            layer.appendChild(badge);

            items.push({ code, target: node, badge });
          }

          window[stateKey] = {
            items,
            layerID,
            styleID,
            targetAttr,
            visibleAttr
          };

          return JSON.stringify({
            ok: true,
            total: items.length,
            matches: items.length
          });
        })();
        """#
    }

    private func linkHintsFilterScript(prefix: String, activateFirstMatch: Bool) -> String {
        let prefixLiteral = linkHintsJSStringLiteral(prefix)
        let activateFlag = activateFirstMatch ? "true" : "false"
        return #"""
        (() => {
          const state = window.__mcvLinkHintsState;
          if (!state || !Array.isArray(state.items)) {
            return JSON.stringify({
              ok: false,
              alive: false,
              matches: 0,
              activated: false,
              exact: false
            });
          }

          const prefix = \#(prefixLiteral);
          let matches = 0;
          let exactCode = "";
          let firstCode = "";

          for (const item of state.items) {
            const code = String(item.code || "");
            const matched = prefix.length === 0 || code.startsWith(prefix);

            if (item.badge) {
              item.badge.dataset.match = matched ? "1" : "0";
              item.badge.dataset.prefix = matched && prefix.length > 0 ? "1" : "0";
            }
            if (item.target) {
              item.target.setAttribute(state.visibleAttr, matched ? "1" : "0");
            }

            if (matched) {
              matches += 1;
              if (!firstCode) {
                firstCode = code;
              }
              if (!exactCode && code === prefix) {
                exactCode = code;
              }
            }
          }

          const activateByCode = (code) => {
            const item = state.items.find((entry) => entry.code === code);
            if (!item || !(item.target instanceof HTMLElement)) return false;
            try {
              item.target.focus({ preventScroll: false });
            } catch (_) {}
            try {
              item.target.click();
              return true;
            } catch (_) {
              return false;
            }
          };

          const teardown = () => {
            for (const item of state.items) {
              try {
                if (item && item.target) {
                  item.target.removeAttribute(state.targetAttr);
                  item.target.removeAttribute(state.visibleAttr);
                }
              } catch (_) {}
            }

            const layer = document.getElementById(state.layerID);
            if (layer && layer.parentNode) {
              layer.parentNode.removeChild(layer);
            }
            const style = document.getElementById(state.styleID);
            if (style && style.parentNode) {
              style.parentNode.removeChild(style);
            }
            delete window.__mcvLinkHintsState;
          };

          if (exactCode && matches === 1) {
            const activated = activateByCode(exactCode);
            teardown();
            return JSON.stringify({
              ok: true,
              alive: false,
              matches: 0,
              activated,
              exact: true,
              code: exactCode
            });
          }

          if (\#(activateFlag) && firstCode) {
            const activated = activateByCode(firstCode);
            teardown();
            return JSON.stringify({
              ok: true,
              alive: false,
              matches: 0,
              activated,
              exact: false,
              code: firstCode
            });
          }

          return JSON.stringify({
            ok: true,
            alive: true,
            matches,
            activated: false,
            exact: false,
            firstCode
          });
        })();
        """#
    }

    private func linkHintsTeardownScript() -> String {
        #"""
        (() => {
          const state = window.__mcvLinkHintsState;
          const targetAttr = state?.targetAttr || "data-mcv-link-hint-target";
          const visibleAttr = state?.visibleAttr || "data-mcv-link-hint-visible";
          const layerID = state?.layerID || "__mcv_link_hints_layer";
          const styleID = state?.styleID || "__mcv_link_hints_style";

          if (state && Array.isArray(state.items)) {
            for (const item of state.items) {
              try {
                if (item && item.target) {
                  item.target.removeAttribute(targetAttr);
                  item.target.removeAttribute(visibleAttr);
                }
              } catch (_) {}
            }
          }

          const tagged = Array.from(document.querySelectorAll(`[${targetAttr}]`));
          for (const node of tagged) {
            try {
              node.removeAttribute(targetAttr);
              node.removeAttribute(visibleAttr);
            } catch (_) {}
          }

          const layer = document.getElementById(layerID);
          if (layer && layer.parentNode) {
            layer.parentNode.removeChild(layer);
          }
          const style = document.getElementById(styleID);
          if (style && style.parentNode) {
            style.parentNode.removeChild(style);
          }
          delete window.__mcvLinkHintsState;
          return true;
        })();
        """#
    }

    private func openFindOverlay() {
        deactivateLinkHintMode(removeFromAllTabs: false)
        closeMiniMCV()
        store.closeCommandOverlay()
        if showSavedNavigator {
            closeSavedNavigator()
        }

        showFindOverlay = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
            focusedTarget = .findBar
        }
        scheduleFindSearch(for: findInPageQuery, immediate: true)
    }

    private func closeFindOverlay(clearHighlights: Bool) {
        findSearchWorkItem?.cancel()
        findSearchWorkItem = nil
        showFindOverlay = false
        findSuggestions = []
        findSelectedSuggestionIndex = nil
        findTotalMatches = 0
        if clearHighlights {
            store.clearFindHighlights()
        }
        if focusedTarget == .findBar {
            focusedTarget = nil
        }
    }

    private func scheduleFindSearch(for raw: String, immediate: Bool = false) {
        let query = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        findSearchWorkItem?.cancel()
        findSearchWorkItem = nil

        guard !query.isEmpty else {
            findSuggestions = []
            findSelectedSuggestionIndex = nil
            findTotalMatches = 0
            store.clearFindHighlights()
            return
        }

        let task = DispatchWorkItem {
            runFindSearch(query)
        }
        findSearchWorkItem = task

        let delay: TimeInterval = immediate ? 0 : 0.08
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: task)
    }

    private func runFindSearch(_ query: String) {
        store.searchInCurrentPage(query: query) { suggestions, totalMatches in
            guard showFindOverlay else { return }
            let current = findInPageQuery.trimmingCharacters(in: .whitespacesAndNewlines)
            guard current == query else { return }

            findSuggestions = suggestions
            findTotalMatches = totalMatches

            guard !suggestions.isEmpty else {
                findSelectedSuggestionIndex = nil
                return
            }

            if let selected = findSelectedSuggestionIndex,
               suggestions.indices.contains(selected) {
                store.focusFindSuggestion(markIndex: suggestions[selected].markIndex)
            } else {
                findSelectedSuggestionIndex = 0
                store.focusFindSuggestion(markIndex: suggestions[0].markIndex)
            }
        }
    }

    private func normalizedFindSuggestionIndex(_ raw: Int) -> Int {
        let count = findSuggestions.count
        guard count > 0 else { return 0 }
        return ((raw % count) + count) % count
    }

    private func moveFindSuggestionSelection(forward: Bool) {
        guard !findSuggestions.isEmpty else { return }
        let nextIndex: Int
        if let current = findSelectedSuggestionIndex, findSuggestions.indices.contains(current) {
            nextIndex = forward ? current + 1 : current - 1
        } else {
            nextIndex = forward ? 0 : findSuggestions.count - 1
        }
        selectFindSuggestion(at: normalizedFindSuggestionIndex(nextIndex))
    }

    private func selectFindSuggestion(at index: Int?) {
        guard let index, findSuggestions.indices.contains(index) else {
            findSelectedSuggestionIndex = nil
            return
        }
        findSelectedSuggestionIndex = index
        let markIndex = findSuggestions[index].markIndex
        store.focusFindSuggestion(markIndex: markIndex)
    }

    private func activateFindSuggestion() {
        guard !findSuggestions.isEmpty else { return }
        if let selected = findSelectedSuggestionIndex, findSuggestions.indices.contains(selected) {
            selectFindSuggestion(at: selected)
        } else {
            selectFindSuggestion(at: 0)
        }
    }

    private func findSuggestionRow(_ suggestion: PageFindSuggestion, index: Int) -> some View {
        let isSelected = findSelectedSuggestionIndex == index
        let line = suggestion.snippet.trimmingCharacters(in: .whitespacesAndNewlines)
        let rowText = line.isEmpty ? "Match \(index + 1)" : line

        return Button(action: {
            selectFindSuggestion(at: index)
        }) {
            HStack(spacing: 10) {
                Text("\(index + 1)")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(isSelected ? adaptiveAccentTextColor : Color.white.opacity(0.72))
                    .frame(width: 28)

                Text(rowText)
                    .lineLimit(2)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isSelected ? adaptiveAccentTextColor : Color.white.opacity(0.94))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? adaptiveAccentColor.opacity(0.92) : Color.white.opacity(0.07))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isSelected ? Color.white.opacity(0.85) : Color.white.opacity(0.1), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering {
                findSelectedSuggestionIndex = index
            }
        }
    }

    private var findInPageOverlay: some View {
        VStack {
            HStack {
                Spacer()
                VStack(spacing: 8) {
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(adaptiveAccentColor.opacity(0.9))

                        TextField("Find on page", text: Binding(
                            get: { findInPageQuery },
                            set: { value in
                                findInPageQuery = value
                                scheduleFindSearch(for: value)
                            }
                        ))
                        .textFieldStyle(.plain)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.96))
                        .focused($focusedTarget, equals: .findBar)
                        .onSubmit {
                            activateFindSuggestion()
                        }

                        Text(findTotalMatches > 0 ? "\(findTotalMatches)" : "0")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(0.72))
                            .padding(.horizontal, 8)
                            .frame(height: 24)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(Color.white.opacity(0.08))
                            )

                        Button(action: {
                            closeFindOverlay(clearHighlights: true)
                        }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Color.white.opacity(0.76))
                                .frame(width: 20, height: 20)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 42)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.white.opacity(0.10))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.white.opacity(0.24), lineWidth: 1)
                    )

                    Group {
                        if findInPageQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text("Type text to find all matches. Use ↑/↓ and Enter.")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Color.white.opacity(0.7))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 8)
                        } else if findSuggestions.isEmpty {
                            Text("No matches on this page")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Color.white.opacity(0.7))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 8)
                        } else {
                            ScrollView {
                                LazyVStack(spacing: 6) {
                                    ForEach(Array(findSuggestions.enumerated()), id: \.element.id) { index, suggestion in
                                        findSuggestionRow(suggestion, index: index)
                                    }
                                }
                                .padding(.vertical, 2)
                            }
                            .frame(maxHeight: 260)
                        }
                    }
                }
                .padding(10)
                .frame(width: min(620, max(360, (NSScreen.main?.frame.width ?? 940) - 140)))
                .background(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.22), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: .black.opacity(0.34), radius: 18, y: 8)
                Spacer()
            }
            .padding(.top, 64)
            Spacer()
        }
    }

    private var savedNavigatorEntries: [SavedNavigatorEntry] {
        let folders = store.savedChildFolders(parentID: savedNavigatorFolderID).map { folder in
            let childFoldersCount = store.savedChildFolders(parentID: folder.id).count
            let childLinksCount = store.savedChildLinks(folderID: folder.id).count
            let subtitle = "\(childFoldersCount) folders • \(childLinksCount) links"
            return SavedNavigatorEntry(
                id: folder.id,
                kind: .folder,
                title: folder.name,
                subtitle: subtitle,
                folderID: folder.id,
                folder: folder,
                link: nil
            )
        }
        let links = store.savedChildLinks(folderID: savedNavigatorFolderID).map { link in
            let host = URL(string: link.url)?.host()?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let subtitle = host.isEmpty ? link.url : host
            return SavedNavigatorEntry(
                id: link.id,
                kind: .link,
                title: link.title,
                subtitle: subtitle,
                folderID: nil,
                folder: nil,
                link: link
            )
        }
        return folders + links
    }

    private var savedNavigatorSelectedEntry: SavedNavigatorEntry? {
        let entries = savedNavigatorEntries
        guard entries.indices.contains(savedNavigatorSelectionIndex) else { return nil }
        return entries[savedNavigatorSelectionIndex]
    }

    private var savedNavigatorPathTitle: String {
        let path = store.savedFolderPath(for: savedNavigatorFolderID).map(\.name)
        if path.isEmpty {
            return "Root"
        }
        return "Root / " + path.joined(separator: " / ")
    }

    private func openSavedNavigator() {
        deactivateLinkHintMode(removeFromAllTabs: false)
        closeMiniMCV()
        store.closeCommandOverlay()
        if showFindOverlay {
            closeFindOverlay(clearHighlights: true)
        }
        store.utilityPanel = nil
        showTabWheel = false
        showMusicWheel = false
        showSavedNavigator = true
        savedNavigatorFolderID = nil
        savedNavigatorSelectionIndex = 0
        clampSavedNavigatorSelection()
    }

    private func closeSavedNavigator() {
        showSavedNavigator = false
    }

    private func toggleSavedNavigator() {
        if showSavedNavigator {
            closeSavedNavigator()
        } else {
            openSavedNavigator()
        }
    }

    private func clampSavedNavigatorSelection() {
        let count = savedNavigatorEntries.count
        guard count > 0 else {
            savedNavigatorSelectionIndex = 0
            return
        }
        savedNavigatorSelectionIndex = min(max(savedNavigatorSelectionIndex, 0), count - 1)
    }

    private func moveSavedNavigatorSelection(forward: Bool) {
        let count = savedNavigatorEntries.count
        guard count > 0 else { return }
        if forward {
            savedNavigatorSelectionIndex = (savedNavigatorSelectionIndex + 1) % count
        } else {
            savedNavigatorSelectionIndex = (savedNavigatorSelectionIndex - 1 + count) % count
        }
    }

    private func activateSavedNavigatorSelection() {
        guard let entry = savedNavigatorSelectedEntry else { return }
        switch entry.kind {
        case .folder:
            savedNavigatorFolderID = entry.folderID
            savedNavigatorSelectionIndex = 0
            clampSavedNavigatorSelection()
        case .link:
            guard let link = entry.link else { return }
            store.openSavedLink(link)
            closeSavedNavigator()
        }
    }

    private func goToSavedNavigatorParentFolder() {
        guard let current = savedNavigatorFolderID else { return }
        savedNavigatorFolderID = store.savedParentFolderID(for: current)
        savedNavigatorSelectionIndex = 0
        clampSavedNavigatorSelection()
    }

    private func handleSavedNavigatorScroll(_ event: NSEvent) {
        let raw = abs(event.scrollingDeltaY) >= abs(event.scrollingDeltaX) ? event.scrollingDeltaY : event.scrollingDeltaX
        guard abs(raw) > 0 else { return }
        moveSavedNavigatorSelection(forward: raw < 0)
    }

    private func promptCreateSavedFolder() {
        let alert = NSAlert()
        alert.messageText = "New folder"
        alert.informativeText = "Create folder in \(savedNavigatorPathTitle)"

        let input = NSTextField(string: "")
        input.placeholderString = "Folder name"
        input.frame = NSRect(x: 0, y: 0, width: 320, height: 24)
        alert.accessoryView = input
        alert.addButton(withTitle: "Create")
        alert.addButton(withTitle: "Cancel")

        NSApp.activate(ignoringOtherApps: true)
        let result = alert.runModal()
        guard result == .alertFirstButtonReturn else { return }

        let name = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        if let folder = store.createSavedFolder(name: name, parentID: savedNavigatorFolderID),
           let index = savedNavigatorEntries.firstIndex(where: { $0.kind == .folder && $0.folderID == folder.id }) {
            savedNavigatorSelectionIndex = index
        }
    }

    private func saveCurrentPageToSavedNavigatorFolder() {
        store.addCurrentTabToSaved(folderID: savedNavigatorFolderID)
        clampSavedNavigatorSelection()
    }

    private func moveSavedLink(_ linkID: UUID, to folderID: UUID?) {
        store.moveSavedLink(id: linkID, to: folderID)
        clampSavedNavigatorSelection()
    }

    private func removeSavedLink(_ link: SavedLink) {
        store.removeSavedLink(link)
        clampSavedNavigatorSelection()
    }

    private func promptDeleteSavedFolder(_ folder: SavedFolder) {
        let counts = store.savedFolderCascadeCounts(folderID: folder.id)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Delete folder \"\(folder.name)\"?"
        alert.informativeText = "This removes \(counts.folders) folder(s) and \(counts.links) link(s)."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")

        NSApp.activate(ignoringOtherApps: true)
        let result = alert.runModal()
        guard result == .alertFirstButtonReturn else { return }

        if savedNavigatorFolderID == folder.id {
            savedNavigatorFolderID = store.savedParentFolderID(for: folder.id)
            savedNavigatorSelectionIndex = 0
        }
        store.removeSavedFolder(folder)
        clampSavedNavigatorSelection()
    }

    private func promptDeleteCurrentSavedFolder() {
        guard let current = savedNavigatorFolderID,
              let folder = store.savedFolders.first(where: { $0.id == current }) else {
            return
        }
        promptDeleteSavedFolder(folder)
    }

    private func deleteSavedEntry(_ entry: SavedNavigatorEntry) {
        if let link = entry.link {
            removeSavedLink(link)
            return
        }
        if let folder = entry.folder {
            promptDeleteSavedFolder(folder)
        }
    }

    private func deleteSelectedSavedNavigatorEntry() {
        guard let entry = savedNavigatorSelectedEntry else { return }
        deleteSavedEntry(entry)
    }

    @ViewBuilder
    private func savedNavigatorRow(_ entry: SavedNavigatorEntry, index: Int) -> some View {
        let isSelected = index == savedNavigatorSelectionIndex
        let isFolder = entry.kind == .folder

        let row = HStack(spacing: 8) {
            Button(action: {
                savedNavigatorSelectionIndex = index
                activateSavedNavigatorSelection()
            }) {
                HStack(spacing: 10) {
                    Image(systemName: isFolder ? "folder.fill" : "link")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(isSelected ? adaptiveAccentTextColor : (isFolder ? adaptiveAccentColor.opacity(0.9) : Color.white.opacity(0.9)))
                        .frame(width: 18)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.title)
                            .lineLimit(1)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(isSelected ? adaptiveAccentTextColor : Color.white.opacity(0.95))
                        Text(entry.subtitle)
                            .lineLimit(1)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(isSelected ? adaptiveAccentSecondaryTextColor : Color.white.opacity(0.62))
                    }
                    Spacer(minLength: 6)
                    if isFolder {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(isSelected ? adaptiveAccentSecondaryTextColor : Color.white.opacity(0.48))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            Button(action: {
                deleteSavedEntry(entry)
            }) {
                Image(systemName: "trash")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(isSelected ? adaptiveAccentSecondaryTextColor : Color.white.opacity(0.58))
                    .frame(width: 22, height: 22)
                    .background(
                        Circle()
                            .fill(isSelected ? adaptiveAccentTextColor.opacity(0.12) : Color.white.opacity(0.08))
                    )
            }
            .buttonStyle(.plain)
            .help(isFolder ? "Delete folder" : "Delete link")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? adaptiveAccentColor.opacity(0.90) : Color.white.opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(isSelected ? Color.white.opacity(0.88) : Color.white.opacity(0.10), lineWidth: 1)
        )
        .onHover { hovering in
            if hovering {
                savedNavigatorSelectionIndex = index
            }
        }

        if let link = entry.link {
            row
                .onDrag {
                    draggedSavedLinkID = link.id
                    return NSItemProvider(object: NSString(string: "mcv.saved.link.\(link.id.uuidString)"))
                }
        } else if let folderID = entry.folderID {
            row
                .onDrop(
                    of: [UTType.text],
                    delegate: SavedLinkDropDelegate(
                        targetFolderID: folderID,
                        onMoveLink: moveSavedLink(_:to:),
                        draggedSavedLinkID: $draggedSavedLinkID
                    )
                )
        } else {
            row
        }
    }

    private var savedNavigatorOverlay: some View {
        ZStack {
            Color.black.opacity(0.22)
                .ignoresSafeArea()
                .onTapGesture {
                    closeSavedNavigator()
                }

            HStack {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Text("Saved")
                            .font(.system(size: 14, weight: .semibold))
                        Spacer()
                        Button(action: { closeSavedNavigator() }) {
                            Image(systemName: "xmark")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.white.opacity(0.78))
                    }

                    Text(savedNavigatorPathTitle)
                        .lineLimit(1)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(adaptiveAccentColor.opacity(0.86))

                    HStack(spacing: 6) {
                        Button("Save Page") {
                            saveCurrentPageToSavedNavigatorFolder()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)

                        Button("New Folder") {
                            promptCreateSavedFolder()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Button(action: {
                            goToSavedNavigatorParentFolder()
                        }) {
                            Image(systemName: "arrow.up.left")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(savedNavigatorFolderID == nil)

                        if savedNavigatorFolderID != nil {
                            Button(action: {
                                promptDeleteCurrentSavedFolder()
                            }) {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .help("Delete current folder")
                        }
                    }

                    Divider().overlay(Color.white.opacity(0.12))

                    if savedNavigatorFolderID != nil {
                        HStack(spacing: 8) {
                            Image(systemName: "tray.and.arrow.up")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(adaptiveAccentColor.opacity(0.9))
                            Text(shouldShowInAppHints ? "Drop link here to move to Root" : "Root")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Color.white.opacity(0.78))
                            Spacer()
                        }
                        .padding(.horizontal, 9)
                        .frame(height: 30)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.white.opacity(0.07))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color.white.opacity(0.12), lineWidth: 1)
                        )
                        .onDrop(
                            of: [UTType.text],
                            delegate: SavedLinkDropDelegate(
                                targetFolderID: nil,
                                onMoveLink: moveSavedLink(_:to:),
                                draggedSavedLinkID: $draggedSavedLinkID
                            )
                        )
                    }

                    Group {
                        if savedNavigatorEntries.isEmpty {
                            Text("Empty folder. Save page or create folder.")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Color.white.opacity(0.72))
                                .padding(.top, 4)
                        } else {
                            ScrollView {
                                LazyVStack(spacing: 6) {
                                    ForEach(Array(savedNavigatorEntries.enumerated()), id: \.element.id) { index, entry in
                                        savedNavigatorRow(entry, index: index)
                                    }
                                }
                                .padding(.vertical, 2)
                            }
                        }
                    }
                    .frame(maxHeight: .infinity)

                    Divider().overlay(Color.white.opacity(0.12))

                    if shouldShowInAppHints {
                        Text("Cmd+S close • ↑/↓ select • Enter open • ←/⌫ back • ⌘⌫ delete")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.64))
                    }
                }
                .padding(12)
                .frame(width: 360, height: min(560, (NSScreen.main?.frame.height ?? 760) - 120), alignment: .topLeading)
                .background(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(color: .black.opacity(0.34), radius: 18, y: 8)
                .padding(.leading, 12)
                .padding(.top, 62)
                Spacer()
            }
        }
    }

    private func updateMiniHint(for value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            miniIsError = false
            miniIsLoading = false
            miniTitle = "Mini MCV"
            miniBody = "Type `calc`, `translate` or `ai` for instant result."
            miniDetail = "Examples: calc 12*7, tran r e привет, ai explain fibonacci retracement"
            return
        }

        if let expression = parseCalcExpression(from: trimmed) {
            if let result = evaluateCalcExpression(expression) {
                miniIsError = false
                miniIsLoading = false
                miniTitle = "Calculator"
                miniBody = result
                miniDetail = expression
            } else {
                miniIsError = true
                miniIsLoading = false
                miniTitle = "Calculator"
                miniBody = "Cannot evaluate expression"
                miniDetail = expression
            }
            return
        }

        if let request = parseMiniTranslate(from: trimmed) {
            miniIsError = false
            miniIsLoading = false
            miniTitle = "Translator"
            miniBody = request.text
            let src = request.source ?? "auto"
            miniDetail = "Press Enter to translate (\(src) → \(request.target))"
            return
        }

        if isMiniAICommandPrefix(trimmed) {
            miniIsError = false
            miniIsLoading = false
            miniTitle = "Local AI"
            if let request = parseMiniAIRequest(from: trimmed) {
                miniBody = request.prompt
                miniDetail = "Press Enter to ask local model (\(selectedOllamaModelTag()))"
            } else {
                miniBody = "Usage: ai <prompt>"
                miniDetail = "Example: ai summarize this page in 3 bullets"
            }
            return
        }

        miniIsError = false
        miniIsLoading = false
        miniTitle = "Command"
        miniBody = trimmed
        miniDetail = "Press Enter to run in current tab"
    }

    private func runMiniCommand() {
        let input = miniInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return }

        if let expression = parseCalcExpression(from: input) {
            if let result = evaluateCalcExpression(expression) {
                miniIsError = false
                miniIsLoading = false
                miniTitle = "Calculator"
                miniBody = result
                miniDetail = expression
            } else {
                miniIsError = true
                miniIsLoading = false
                miniTitle = "Calculator"
                miniBody = "Cannot evaluate expression"
                miniDetail = expression
            }
            return
        }

        if let request = parseMiniTranslate(from: input) {
            executeMiniTranslate(request)
            return
        }

        if isMiniAICommandPrefix(input) {
            guard let request = parseMiniAIRequest(from: input) else {
                miniIsError = true
                miniIsLoading = false
                miniTitle = "Local AI"
                miniBody = "Usage: ai <prompt>"
                miniDetail = "Example: ai explain trend following strategy"
                return
            }
            executeMiniAI(request)
            return
        }

        closeMiniMCV()
        store.executeRawInput(input)
    }

    private func parseCalcExpression(from input: String) -> String? {
        detectCalculatorExpression(from: input)
    }

    private func evaluateCalcExpression(_ expression: String) -> String? {
        let sanitized = expression.replacingOccurrences(of: ",", with: ".")
        let allowed = CharacterSet(charactersIn: "0123456789.+-*/()% ")
        if sanitized.unicodeScalars.contains(where: { !allowed.contains($0) }) {
            return nil
        }

        let nsExpression = NSExpression(format: sanitized)
        guard let number = nsExpression.expressionValue(with: nil, context: nil) as? NSNumber else {
            return nil
        }

        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 8
        formatter.minimumFractionDigits = 0
        formatter.usesGroupingSeparator = true
        return formatter.string(from: number) ?? number.stringValue
    }

    private func parseMiniTranslate(from input: String) -> MiniTranslateRequest? {
        guard let parsed = parseTranslatePayload(from: input) else { return nil }
        return MiniTranslateRequest(source: parsed.source, target: parsed.target, text: parsed.text)
    }

    private func isMiniAICommandPrefix(_ input: String) -> Bool {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        return lower == "ai" || lower.hasPrefix("ai ")
    }

    private func parseMiniAIRequest(from input: String) -> MiniAIRequest? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        guard lower == "ai" || lower.hasPrefix("ai ") else { return nil }
        let prompt = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return nil }
        return MiniAIRequest(prompt: prompt)
    }

    private func selectedOllamaModelTag() -> String {
        let saved = UserDefaults.standard.string(forKey: AppKeys.ollamaModel)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return saved.isEmpty ? "llama3.2:3b" : saved
    }

    private func executeMiniAI(_ request: MiniAIRequest) {
        miniTask?.cancel()
        miniIsLoading = true
        miniIsError = false
        miniTitle = "Local AI"
        miniBody = request.prompt
        let model = selectedOllamaModelTag()
        miniDetail = "Thinking with \(model)..."

        miniTask = Task { [prompt = request.prompt, model] in
            let output = await Task.detached(priority: .userInitiated) {
                CommandHelperClient.shared.generateLocalAI(prompt: prompt, model: model)
            }.value

            await MainActor.run {
                guard !Task.isCancelled else { return }
                miniIsLoading = false
                if output.success {
                    miniIsError = false
                    miniTitle = "AI • \(output.model)"
                    miniBody = output.text
                    miniDetail = "Local response via Ollama"
                } else {
                    miniIsError = true
                    miniTitle = "AI error"
                    miniBody = output.message.isEmpty ? "Cannot run local model" : output.message
                    miniDetail = "Open Settings > General > Configure Ollama"
                }
            }
        }
    }

    private func executeMiniTranslate(_ request: MiniTranslateRequest) {
        miniTask?.cancel()
        miniIsLoading = true
        miniIsError = false
        miniTitle = "Translator"
        miniBody = request.text
        miniDetail = "Translating..."

        miniTask = Task {
            let source = request.source ?? "auto"
            let escaped = request.text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? request.text
            guard let url = URL(string: "https://translate.googleapis.com/translate_a/single?client=gtx&sl=\(source)&tl=\(request.target)&dt=t&q=\(escaped)") else {
                await MainActor.run {
                    miniIsLoading = false
                    miniIsError = true
                    miniTitle = "Translator"
                    miniBody = "Invalid translation request"
                    miniDetail = ""
                }
                return
            }

            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                if Task.isCancelled { return }
                guard let translated = parseTranslatedText(from: data) else {
                    await MainActor.run {
                        miniIsLoading = false
                        miniIsError = true
                        miniTitle = "Translator"
                        miniBody = "Translation failed"
                        miniDetail = "Try again"
                    }
                    return
                }

                await MainActor.run {
                    miniIsLoading = false
                    miniIsError = false
                    miniTitle = "Translation"
                    miniBody = translated
                    miniDetail = "\(source) → \(request.target)"
                }
            } catch {
                if Task.isCancelled { return }
                await MainActor.run {
                    miniIsLoading = false
                    miniIsError = true
                    miniTitle = "Translator"
                    miniBody = "Network error"
                    miniDetail = error.localizedDescription
                }
            }
        }
    }

    private func parseTranslatedText(from data: Data) -> String? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [Any],
              let segments = root.first as? [Any] else {
            return nil
        }

        var out = ""
        for segment in segments {
            if let row = segment as? [Any],
               let text = row.first as? String {
                out += text
            }
        }

        let trimmed = out.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private var chromeTintColor: Color {
        store.chromeTheme.color
    }

    private var chromeTintStrength: Double {
        min(max(store.chromeTheme.intensity, 0.0), 1.5)
    }

    private var adaptiveAccentComponents: (red: Double, green: Double, blue: Double) {
        let theme = store.chromeTheme.clamped
        let intensity = min(max(theme.intensity, 0.0), 1.5)
        let boost = 0.10 + 0.10 * min(intensity, 1.0)
        let red = min(max(theme.red + (1.0 - theme.red) * boost, 0.0), 1.0)
        let green = min(max(theme.green + (1.0 - theme.green) * boost, 0.0), 1.0)
        let blue = min(max(theme.blue + (1.0 - theme.blue) * boost, 0.0), 1.0)
        return (red, green, blue)
    }

    private var adaptiveAccentColor: Color {
        let c = adaptiveAccentComponents
        return Color(red: c.red, green: c.green, blue: c.blue)
    }

    private var adaptiveAccentTextColor: Color {
        let c = adaptiveAccentComponents
        let luminance = 0.2126 * c.red + 0.7152 * c.green + 0.0722 * c.blue
        return luminance > 0.58 ? Color.black.opacity(0.88) : Color.white.opacity(0.96)
    }

    private var adaptiveAccentSecondaryTextColor: Color {
        let c = adaptiveAccentComponents
        let luminance = 0.2126 * c.red + 0.7152 * c.green + 0.0722 * c.blue
        return luminance > 0.58 ? Color.black.opacity(0.72) : Color.white.opacity(0.78)
    }

    private var chromeBarGradientAnimationActive: Bool {
        chromeBarGradientEnabled && chromeBarGradientAnimationEnabled
    }

    private var shouldRunChromeAnimations: Bool {
        chromeBarGradientAnimationActive &&
            appIsActive &&
            !showWelcome &&
            !ProcessInfo.processInfo.isLowPowerModeEnabled &&
            !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    private var shouldMonitorPointerEvents: Bool {
        showTabWheel || showMusicWheel || showSavedNavigator || showLinkHintMode
    }

    private func startChromeBarAnimationsIfNeeded() {
        guard shouldRunChromeAnimations else {
            stopChromeBarAnimations()
            return
        }
        if !animateChromeBarGradient {
            withAnimation(.easeInOut(duration: 15.0).repeatForever(autoreverses: true)) {
                animateChromeBarGradient = true
            }
        }
        startTabStripSweepAnimationIfNeeded()
    }

    private func stopChromeBarAnimations() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            animateChromeBarGradient = false
            tabStripSweepPhase = -0.60
            tabStripSweepStarted = false
        }
    }

    private func startTabStripSweepAnimationIfNeeded() {
        guard shouldRunChromeAnimations else { return }
        guard !tabStripSweepStarted else { return }
        tabStripSweepStarted = true
        tabStripSweepPhase = -0.60
        withAnimation(.linear(duration: 9.5).repeatForever(autoreverses: false)) {
            tabStripSweepPhase = 1.45
        }
    }

    private var chromeBarBaseGradientColors: [Color] {
        let t = store.chromeTheme.clamped
        return [
            Color(
                red: chromeBarTint(t.red, floor: 0.02, weight: 0.20),
                green: chromeBarTint(t.green, floor: 0.04, weight: 0.24),
                blue: chromeBarTint(t.blue, floor: 0.10, weight: 0.30)
            ),
            Color(
                red: chromeBarTint(t.red, floor: 0.04, weight: 0.16),
                green: chromeBarTint(t.green, floor: 0.03, weight: 0.16),
                blue: chromeBarTint(t.blue, floor: 0.09, weight: 0.22)
            ),
            Color(
                red: chromeBarTint(t.red, floor: 0.02, weight: 0.12),
                green: chromeBarTint(t.green, floor: 0.03, weight: 0.12),
                blue: chromeBarTint(t.blue, floor: 0.06, weight: 0.16)
            )
        ]
    }

    private var chromeBarAccentA: Color {
        let t = store.chromeTheme.clamped
        return Color(
            red: chromeBarMix(t.red, 1.0, 0.22),
            green: chromeBarMix(t.green, 1.0, 0.18),
            blue: chromeBarMix(t.blue, 1.0, 0.26)
        )
    }

    private var chromeBarAccentB: Color {
        let t = store.chromeTheme.clamped
        return Color(
            red: chromeBarMix(t.green, 1.0, 0.14),
            green: chromeBarMix(t.blue, 1.0, 0.12),
            blue: chromeBarMix(t.red, 1.0, 0.16)
        )
    }

    private func chromeBarTint(_ value: Double, floor: Double, weight: Double) -> Double {
        chromeBarClamp(floor + value * weight)
    }

    private func chromeBarMix(_ from: Double, _ to: Double, _ amount: Double) -> Double {
        chromeBarClamp(from + (to - from) * amount)
    }

    private func chromeBarClamp(_ value: Double) -> Double {
        min(max(value, 0.0), 1.0)
    }

    private var content: some View {
        HStack(spacing: 0) {
            mainWindow
            if let panel = store.utilityPanel {
                utilityPanelView(panel)
                    .frame(width: 320)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .background(
            ZStack {
                Color(red: 0.06, green: 0.07, blue: 0.09)
                LinearGradient(
                    colors: [
                        chromeTintColor.opacity(0.10 + 0.16 * chromeTintStrength),
                        chromeTintColor.opacity(0.04 + 0.08 * chromeTintStrength)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
            .ignoresSafeArea()
        )
    }

    private var mainWindow: some View {
        VStack(spacing: 0) {
            if isBrowserChromeVisible {
                topBar
                if !store.isMusicWindow {
                    tabStrip
                }
                Divider().overlay(Color.white.opacity(0.09))
            }
            webContent
        }
    }

    private var topBar: some View {
        let progress = min(max(store.selectedTab?.loadingProgress ?? 0.0, 0.0), 1.0)
        let showProgress = (store.selectedTab?.isLoading ?? false) && progress > 0.001 && progress < 1.0

        return HStack(spacing: 8) {
            HStack(spacing: 8) {
                if store.smartBarCommandArmed {
                    commandModeIndicator
                }

                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Color.white.opacity(0.72))

                TextField("Search or enter address", text: $store.smartInput)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(Color.white.opacity(0.95))
                    .focused($focusedTarget, equals: .smartBar)
                    .onSubmit {
                        store.submitSmartBar()
                    }
            }
            .padding(.horizontal, 12)
            .frame(height: 34 * uiScale)
            .background(
                ZStack {
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity((0.08 + 0.10 * uiOpacity) * uiOpacity))
                    Capsule(style: .continuous)
                        .fill(chromeTintColor.opacity((0.10 + 0.16 * chromeTintStrength) * uiOpacity))
                }
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(
                        store.smartBarCommandArmed ? adaptiveAccentColor.opacity(0.52) : chromeTintColor.opacity(0.35 + 0.20 * chromeTintStrength),
                        lineWidth: 1
                    )
            )
            .overlay(alignment: .bottomLeading) {
                GeometryReader { geo in
                    let visualWidth = max(0, min(geo.size.width * 0.62, geo.size.width - 42))
                    let leadingInset = (geo.size.width - visualWidth) * 0.5
                    let filledWidth = max(0, visualWidth * progress)

                    ZStack(alignment: .leading) {
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(0.08))
                            .frame(width: visualWidth, height: 1.8)

                        if filledWidth > 0.3 {
                            Capsule(style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            adaptiveAccentColor.opacity(0.56),
                                            adaptiveAccentColor.opacity(0.42)
                                        ],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: filledWidth, height: 1.8)
                                .shadow(color: adaptiveAccentColor.opacity(0.16), radius: 1.8, y: 0)
                        }
                    }
                    .offset(x: leadingInset, y: -4.5)
                    .opacity(showProgress ? 0.92 : 0)
                    .animation(.easeOut(duration: 0.12), value: showProgress)
                    .animation(.linear(duration: 0.10), value: progress)
                }
                .allowsHitTesting(false)
            }
            .shadow(color: .black.opacity(0.26), radius: 6, y: 2)

            if !store.isMusicWindow {
                Button(action: { store.openNewTab(select: true) }) {
                    Image(systemName: "plus")
                        .font(.system(size: 14 * uiScale, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.9))
                }
                .buttonStyle(.plain)
                .frame(width: 26 * uiScale, height: 26 * uiScale)
                .background(Circle().fill(chromeTintColor.opacity(0.10 + 0.12 * chromeTintStrength)))
                .help("New Tab")

                Button(action: {
                    if showTabsOverview {
                        showTabsOverview = false
                    } else {
                        showDownloadsOverview = false
                        showTabsOverview = true
                    }
                }) {
                    Image(systemName: "rectangle.grid.2x2")
                        .font(.system(size: 13 * uiScale, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.9))
                }
                .buttonStyle(.plain)
                .frame(width: 26 * uiScale, height: 26 * uiScale)
                .background(Circle().fill(chromeTintColor.opacity(0.10 + 0.12 * chromeTintStrength)))
                .help("Tabs Overview")
                .popover(isPresented: $showTabsOverview, arrowEdge: .top) {
                    tabsOverview
                }

                Button(action: {
                    if showDownloadsOverview {
                        showDownloadsOverview = false
                    } else {
                        showTabsOverview = false
                        showDownloadsOverview = true
                    }
                }) {
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 13 * uiScale, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.9))
                }
                .buttonStyle(.plain)
                .frame(width: 26 * uiScale, height: 26 * uiScale)
                .background(Circle().fill(chromeTintColor.opacity(0.10 + 0.12 * chromeTintStrength)))
                .help("Downloads")
                .popover(isPresented: $showDownloadsOverview, arrowEdge: .top) {
                    downloadsOverview
                }

                Button(action: {
                    showTabsOverview = false
                    showDownloadsOverview = false
                    if store.utilityPanel == .ollamaChat {
                        store.utilityPanel = nil
                    } else {
                        store.utilityPanel = .ollamaChat
                    }
                }) {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.system(size: 13 * uiScale, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.9))
                }
                .buttonStyle(.plain)
                .frame(width: 26 * uiScale, height: 26 * uiScale)
                .background(Circle().fill(chromeTintColor.opacity(0.10 + 0.12 * chromeTintStrength)))
                .help("AI Chat")
            }

            Menu {
                if !store.isMusicWindow {
                    Button("New Tab") {
                        store.openNewTab(select: true)
                    }
                }
                Button("Open Music Window") {
                    MusicWindowManager.shared.present { id in
                        openWindow(id: id)
                    }
                }
                Button("Reload") {
                    store.reload()
                }
                Button("Add Bookmark") {
                    store.addCurrentTabToBookmarks()
                }

                Divider()

                Button("Bookmarks") {
                    store.utilityPanel = .bookmarks
                }
                Button("History") {
                    store.utilityPanel = .history
                }
                Button("Downloads") {
                    if showDownloadsOverview {
                        showDownloadsOverview = false
                    } else {
                        showTabsOverview = false
                        showDownloadsOverview = true
                    }
                }
                Button("Colors") {
                    store.utilityPanel = .colors
                }
                Button("AI Chat") {
                    store.utilityPanel = .ollamaChat
                }
                Button("Settings…") {
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                }

                Divider()

                Button("Quit") {
                    NSApp.terminate(nil)
                }
            } label: {
                Image(systemName: "person.crop.circle")
                    .font(.system(size: 15, weight: .semibold))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 26 * uiScale, height: 26 * uiScale)
            .background(
                Circle().fill(chromeTintColor.opacity(0.10 + 0.12 * chromeTintStrength))
            )
            .help("Menu")
        }
        .padding(.leading, 78)
        .padding(.trailing, 10)
        .padding(.vertical, 9)
        .background(
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                if chromeBarGradientEnabled {
                    LinearGradient(
                        colors: chromeBarBaseGradientColors.map { $0.opacity((0.26 + 0.20 * chromeTintStrength) * uiOpacity) },
                        startPoint: chromeBarGradientAnimationActive && animateChromeBarGradient ? .topLeading : .leading,
                        endPoint: chromeBarGradientAnimationActive && animateChromeBarGradient ? .bottomTrailing : .bottom
                    )
                    RadialGradient(
                        colors: [chromeBarAccentA.opacity(chromeBarGradientAnimationActive && animateChromeBarGradient ? 0.20 : 0.12), Color.clear],
                        center: chromeBarGradientAnimationActive && animateChromeBarGradient ? UnitPoint(x: 0.16, y: 0.0) : UnitPoint(x: 0.82, y: 0.0),
                        startRadius: 20,
                        endRadius: 360
                    )
                    RadialGradient(
                        colors: [chromeBarAccentB.opacity(chromeBarGradientAnimationActive && animateChromeBarGradient ? 0.16 : 0.10), Color.clear],
                        center: chromeBarGradientAnimationActive && animateChromeBarGradient ? UnitPoint(x: 0.90, y: 1.0) : UnitPoint(x: 0.20, y: 1.0),
                        startRadius: 20,
                        endRadius: 320
                    )
                } else {
                    Rectangle()
                        .fill(chromeTintColor.opacity((0.10 + 0.12 * chromeTintStrength) * uiOpacity))
                }
                Rectangle()
                    .fill(Color.black.opacity(0.14))
                Rectangle()
                    .fill(Color.white.opacity(0.02 + 0.10 * min(max(appSettings.interfaceBlur, 0.0), 1.0)))
            }
        )
    }

    private var tabStrip: some View {
        let tabItems = Array(store.tabs.filter { !$0.isBookmarkTab }.enumerated())
        return ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: true) {
                HStack(spacing: 6) {
                    ForEach(tabItems, id: \.element.id) { item in
                        let tab = item.element
                        TabChipView(
                            index: item.offset,
                            tab: tab,
                            isSelected: tab.id == store.selectedTabID,
                            style: appSettings.tabStyle,
                            accentColor: adaptiveAccentColor,
                            onSelect: {
                                store.selectTab(id: tab.id)
                            },
                            onDoubleTap: {
                                if appSettings.closeTabOnDoubleClick {
                                    if tab.id == store.selectedTabID {
                                        store.closeSelectedTab()
                                    } else {
                                        store.selectTab(id: tab.id)
                                        store.closeSelectedTab()
                                    }
                                }
                            },
                            onClose: {
                                if tab.id == store.selectedTabID {
                                    store.closeSelectedTab()
                                } else {
                                    store.selectTab(id: tab.id)
                                    store.closeSelectedTab()
                                }
                            }
                        )
                        .id(tab.id)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            }
            .onChange(of: store.selectedTabID) { selectedID in
                guard let selectedID else { return }
                withAnimation(.easeInOut(duration: 0.16)) {
                    proxy.scrollTo(selectedID, anchor: .center)
                }
            }
            .onChange(of: store.tabs.count) { _ in
                guard let selectedID = store.selectedTabID else { return }
                DispatchQueue.main.async {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        proxy.scrollTo(selectedID, anchor: .trailing)
                    }
                }
            }
        }
        .background(
            ZStack {
                if chromeBarGradientEnabled {
                    LinearGradient(
                        colors: chromeBarBaseGradientColors.map { $0.opacity(0.18 + 0.16 * chromeTintStrength) },
                        startPoint: chromeBarGradientAnimationActive && animateChromeBarGradient ? .leading : .topLeading,
                        endPoint: chromeBarGradientAnimationActive && animateChromeBarGradient ? .trailing : .bottomTrailing
                    )
                    RadialGradient(
                        colors: [chromeBarAccentA.opacity(0.13), Color.clear],
                        center: chromeBarGradientAnimationActive && animateChromeBarGradient ? UnitPoint(x: 0.06, y: 0.0) : UnitPoint(x: 0.92, y: 0.0),
                        startRadius: 16,
                        endRadius: 260
                    )
                    if chromeBarGradientAnimationActive {
                        LinearGradient(
                            colors: [
                                Color.clear,
                                chromeBarAccentA.opacity(0.18),
                                Color.white.opacity(0.07),
                                Color.clear
                            ],
                            startPoint: UnitPoint(x: tabStripSweepPhase - 0.55, y: -0.10),
                            endPoint: UnitPoint(x: tabStripSweepPhase + 0.20, y: 1.10)
                        )
                    }
                } else {
                    Rectangle()
                        .fill(chromeTintColor.opacity(0.08 + 0.10 * chromeTintStrength))
                }
                Rectangle().fill(Color.black.opacity(0.18))
            }
        )
    }

    private var webContent: some View {
        Group {
            if let selected = store.selectedTab {
                if selected.isHelpTab && selected.showsNativeHelpContent {
                    nativeHelpContent(for: selected)
                        .id(selected.id)
                } else if selected.isStartPage {
                    nativeStartSurface(for: selected)
                        .id(selected.id)
                } else {
                    BrowserWebView(webView: selected.webView)
                        .id(selected.id)
                }
            } else {
                Color.clear
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func nativeStartSurface(for _: BrowserTab) -> some View {
        ZStack {
            LinearGradient(
                colors: [
                    chromeTintColor.opacity(0.20 + 0.18 * chromeTintStrength),
                    Color(red: 0.08, green: 0.10, blue: 0.14),
                    Color(red: 0.06, green: 0.08, blue: 0.12)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            RadialGradient(
                colors: [
                    adaptiveAccentColor.opacity(0.28),
                    Color.clear
                ],
                center: .topLeading,
                startRadius: 20,
                endRadius: 360
            )
            RadialGradient(
                colors: [
                    adaptiveAccentColor.opacity(0.18),
                    Color.clear
                ],
                center: .bottomTrailing,
                startRadius: 20,
                endRadius: 340
            )

            VStack(spacing: 12) {
                Text("New Tab")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.96))

                Text("Native start surface without webview")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.74))

                if shouldShowInAppHints {
                    Text("Cmd+E command overlay  •  Cmd+L focus smart bar")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.60))
                }

                HStack(spacing: 8) {
                    Button("Focus Search") {
                        focusedTarget = .smartBar
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(adaptiveAccentColor.opacity(0.92))

                    Button("Command Overlay") {
                        store.toggleCommandOverlay(mode: .mixed)
                        if store.isCommandOverlayVisible {
                            focusedTarget = .commandBar
                        }
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 22)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
            )
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func nativeHelpContent(for tab: BrowserTab) -> some View {
        let helpSections: [(title: String, lines: [String])] = [
            (
                title: "Navigation",
                lines: [
                    "open <url>  open url",
                    "reload  reload current page",
                    "back  go back",
                    "forward  go forward",
                    "home  open home page",
                    "new  open new tab",
                    "close  close current tab"
                ]
            ),
            (
                title: "Search and Sites",
                lines: [
                    "g <query>  google search",
                    "ddg <query>  duckduckgo search",
                    "yt <query>  youtube search",
                    "wiki <query>  wikipedia search",
                    "gh <user>  github profile",
                    "ghr <user/repo>  github repo",
                    "x <user>  x profile"
                ]
            ),
            (
                title: "Extensions",
                lines: [
                    "ext list  open extensions side panel",
                    "ext panel  open extensions side panel",
                    "ext install <folder|url|id>  install unpacked or from web store",
                    "ext webstore <url|id>  download crx and install",
                    "ext enable <id>  enable extension",
                    "ext disable <id>  disable extension",
                    "ext remove <id>  uninstall extension",
                    "ext popup <id>  open extension popup page",
                    "ext options <id>  open extension options page",
                    "ext window <id>  open extension popup/options in new window",
                    "ext grant <id> <permission>  grant permission override",
                    "ext revoke <id> <permission>  revoke permission override",
                    "ext reload  reload runtime and reinject scripts",
                    "ext logs  open recent extension logs"
                ]
            ),
            (
                title: "Tools",
                lines: [
                    "book  add bookmark",
                    "history  open history panel",
                    "bookmarks  open bookmarks panel",
                    "downloads [clear]  download history tools",
                    "notify <text>  macos notification",
                    "dev  toggle devtools",
                    "perf status|gpu|fps [sec]  performance diagnostics",
                    "help [cmd]  open help"
                ]
            ),
            (
                title: "Interface",
                lines: [
                    "dark  force dark mode",
                    "theme dark|light|off  set theme",
                    "colors  open colors panel",
                    "spot  compact window size",
                    "float  toggle always on top",
                    "minimal  toggle fullscreen"
                ]
            ),
            (
                title: "Security",
                lines: [
                    "mode classic|safe|secure  switch security mode",
                    "js on|off  per site javascript in secure mode",
                    "clearonexit add|del <host>  clear cookies on exit",
                    "clearonexit list  show clear on exit list",
                    "wipe  wipe safe or secure profile data",
                    "pass set|save|fill|del|list|auto|ignore  keychain passwords"
                ]
            ),
            (
                title: "Pro and Aliases",
                lines: [
                    "pro  advanced settings hub",
                    "pro opacity <0.05-1.0>  window opacity",
                    "pro blur on|off  spotlight blur",
                    "pro suggest on|off  command suggestions",
                    "alias <name> <query>  save alias",
                    "alias tv /new/open https://tradingview.com/  chain alias",
                    "fav list  list favorites",
                    "fav open <key>  open favorite"
                ]
            )
        ]

        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("MCV Help")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.96))

                if !tab.helpContextLine.isEmpty {
                    Text(tab.helpContextLine)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(adaptiveAccentColor.opacity(0.92))
                } else {
                    Text("Type commands in Cmd+E and press Enter.")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.78))
                }

                Divider().overlay(Color.white.opacity(0.12))

                Text("Commands by section")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.90))

                VStack(alignment: .leading, spacing: 12) {
                    ForEach(helpSections, id: \.title) { section in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(section.title)
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(adaptiveAccentColor.opacity(0.95))

                            ForEach(section.lines, id: \.self) { line in
                                Text(line)
                                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                                    .foregroundStyle(Color.white.opacity(0.80))
                                    .textSelection(.enabled)
                            }
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .fill(Color.white.opacity(0.04))
                        )
                    }
                }
            }
            .padding(22)
            .frame(maxWidth: 860, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            ZStack {
                Color(red: 0.06, green: 0.07, blue: 0.09)
                LinearGradient(
                    colors: [
                        adaptiveAccentColor.opacity(0.18),
                        adaptiveAccentColor.opacity(0.06),
                        Color.black.opacity(0.08)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        )
    }

    private var tabsOverview: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Tabs")
                .font(.system(size: 16, weight: .semibold))

            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(Array(store.tabs.enumerated()), id: \.element.id) { index, tab in
                        HStack(spacing: 8) {
                            Text("\(index + 1)")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .frame(width: 20)
                                .foregroundStyle(Color.white.opacity(0.75))

                            VStack(alignment: .leading, spacing: 2) {
                                Text(tab.title)
                                    .lineLimit(1)
                                    .font(.system(size: 13, weight: .semibold))
                                Text(tab.displayURL.isEmpty ? "New Tab" : tab.displayURL)
                                    .lineLimit(1)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                if tab.isBookmarkTab {
                                    Text("Bookmark tab")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(adaptiveAccentColor.opacity(0.86))
                                }
                                if tab.hasAudio {
                                    Text("Playing audio")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(adaptiveAccentColor.opacity(0.86))
                                }
                                if tab.isSuspended {
                                    Text("Suspended")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(Color.orange.opacity(0.86))
                                }
                            }
                            Spacer()

                            Button("Open") {
                                store.selectTab(id: tab.id)
                                showTabsOverview = false
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(tab.id == store.selectedTabID ? adaptiveAccentColor.opacity(0.16) : Color.white.opacity(0.05))
                        )
                    }
                }
            }
            .frame(maxHeight: 280)
        }
        .padding(12)
        .frame(width: 420)
        .background(.ultraThinMaterial)
    }

    private var downloadsOverview: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Downloads")
                .font(.system(size: 16, weight: .semibold))

            if store.downloads.isEmpty {
                Text("No downloads yet")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.68))
                    .padding(.vertical, 8)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(Array(store.downloads.enumerated()), id: \.element.id) { index, item in
                            HStack(spacing: 8) {
                                Text("\(index + 1)")
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .frame(width: 20)
                                    .foregroundStyle(Color.white.opacity(0.75))

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.title)
                                        .lineLimit(1)
                                        .font(.system(size: 13, weight: .semibold))
                                    Text(item.destinationPath)
                                        .lineLimit(1)
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                    Text(historyTimeString(item.downloadedAt))
                                        .lineLimit(1)
                                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                        .foregroundStyle(adaptiveAccentColor.opacity(0.86))
                                }
                                Spacer()

                                Button("Open") {
                                    store.openDownloadItem(item)
                                    showDownloadsOverview = false
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)

                                Button("Show") {
                                    store.revealDownloadItem(item)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)

                                Button(action: { store.removeDownloadItem(item) }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(Color.white.opacity(0.58))
                                        .frame(width: 20, height: 20)
                                }
                                .buttonStyle(.plain)
                                .help("Delete entry")
                            }
                            .padding(8)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color.white.opacity(0.05))
                            )
                        }
                    }
                }
                .frame(maxHeight: 280)
            }

            HStack(spacing: 8) {
                Button("Clear") {
                    store.clearDownloads()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("Folder") {
                    store.openDownloadsFolder()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Spacer()
            }
        }
        .padding(12)
        .frame(width: 480)
        .background(.ultraThinMaterial)
    }

    private func utilityPanelView(_ kind: UtilityPanelKind) -> some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(utilityPanelTitle(kind))
                        .font(.system(size: 14, weight: .semibold))
                    if kind == .bookmarks, let subtitle = bookmarksPanelSubtitle {
                        Text(subtitle)
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(bookmarksPanelHasCurrentSelection ? adaptiveAccentColor.opacity(0.92) : Color.white.opacity(0.66))
                            .lineLimit(1)
                    } else if kind == .extensions, let subtitle = extensionsPanelSubtitle {
                        Text(subtitle)
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(0.72))
                            .lineLimit(1)
                    } else if kind == .ollamaChat {
                        Text(ollamaSidebarSubtitle)
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(0.72))
                            .lineLimit(1)
                    }
                }
                Spacer()
                if kind == .extensions {
                    Button(action: {
                        showExtensionsInstallInput.toggle()
                        if showExtensionsInstallInput {
                            extensionsInstallInput = ""
                        }
                    }) {
                        Image(systemName: showExtensionsInstallInput ? "minus" : "plus")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.white.opacity(0.86))
                    .help(showExtensionsInstallInput ? "Hide install input" : "Install extension")
                }
                Button(action: { store.utilityPanel = nil }) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.white.opacity(0.78))
            }
            .padding(12)

            Divider().overlay(Color.white.opacity(0.12))

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    if kind == .colors {
                        colorsSettingsPanel
                    } else {
                        utilityRows(for: kind)
                    }
                }
                .padding(10)
            }

            Divider().overlay(Color.white.opacity(0.12))

            HStack {
                switch kind {
                case .bookmarks:
                    Button("Clear") { store.clearBookmarks() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                case .history:
                    Button("Clear") { store.clearHistory() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                case .colors:
                    Button("Reset") { store.resetChromeTheme() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                case .extensions:
                    Button("Reload") {
                        store.reloadWebExtensionsRuntime(reloadTabs: true)
                        refreshExtensionsPanelSnapshot()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                case .ollamaChat:
                    Button("Clear") {
                        clearOllamaSidebarConversation()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                Spacer()
            }
            .padding(10)
        }
        .background(
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(Color.black.opacity(0.20))
        )
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Color.white.opacity(0.12))
                .frame(width: 1)
        }
    }

    private var currentBookmarkID: UUID? {
        store.selectedTab?.bookmarkID
    }

    private var bookmarksPanelHasCurrentSelection: Bool {
        guard let currentBookmarkID else { return false }
        return store.bookmarks.contains(where: { $0.id == currentBookmarkID })
    }

    private var bookmarksPanelSubtitle: String? {
        guard !store.bookmarks.isEmpty else { return nil }
        guard let currentBookmarkID,
              let index = store.bookmarks.firstIndex(where: { $0.id == currentBookmarkID }) else {
            return "Current: not in bookmarks"
        }
        return "Current: \(index + 1)/\(store.bookmarks.count)"
    }

    private var extensionsPanelSubtitle: String? {
        if extensionsPanelBundles.isEmpty {
            return "Installed: 0"
        }
        let enabledCount = extensionsPanelBundles.filter(\.enabled).count
        return "Installed: \(extensionsPanelBundles.count)  enabled: \(enabledCount)"
    }

    private var ollamaSidebarSubtitle: String {
        let model = configuredOllamaModelForSidebar
        if ollamaSidebarSending {
            return "Model: \(model)  generating..."
        }
        if !ollamaSidebarPageContextLine.isEmpty {
            return "Model: \(model)  \(ollamaSidebarPageContextLine)"
        }
        if let imageURL = ollamaSidebarAttachedImageURL {
            return "Model: \(model)  image: \(imageURL.lastPathComponent)"
        }
        return "Model: \(model)"
    }

    private var ollamaSidebarChatPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Toggle(isOn: $ollamaSidebarIncludePageContext) {
                    Text("Page context")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.82))
                }
                .toggleStyle(.switch)

                Spacer()

                Button("Scan page") {
                    refreshOllamaSidebarPageContext()
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }

            if !ollamaSidebarPageActions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Array(ollamaSidebarPageActions.prefix(16)), id: \.id) { action in
                            Button(action.label.isEmpty ? action.id : action.label) {
                                runQuickOllamaAction(action.id)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                            .lineLimit(1)
                            .help("[\(action.id)] \(action.kind) \(action.label)")
                        }
                    }
                    .padding(.vertical, 1)
                }
            }

            OllamaSidebarHTMLView(
                messages: ollamaSidebarMessages,
                isLoading: ollamaSidebarSending,
                accentHex: ollamaSidebarAccentHex,
                accentTextHex: ollamaSidebarAccentTextHex
            )
            .frame(minHeight: 260)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.14), lineWidth: 1)
            )

            if let imageURL = ollamaSidebarAttachedImageURL {
                HStack(spacing: 8) {
                    if let image = NSImage(contentsOf: imageURL) {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 44, height: 44)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(Color.white.opacity(0.20), lineWidth: 1)
                            )
                    } else {
                        Image(systemName: "photo")
                            .foregroundStyle(Color.white.opacity(0.72))
                            .frame(width: 44, height: 44)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color.white.opacity(0.06))
                            )
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(imageURL.lastPathComponent)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.88))
                            .lineLimit(1)
                        Text("will be sent with next prompt")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.62))
                            .lineLimit(1)
                    }

                    Spacer()

                    Button(action: { ollamaSidebarAttachedImageURL = nil }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Color.white.opacity(0.70))
                    }
                    .buttonStyle(.plain)
                    .help("Remove image")
                }
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                )
            }

            HStack(alignment: .bottom, spacing: 8) {
                Button(action: pickOllamaSidebarImage) {
                    Image(systemName: "photo")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.90))
                        .frame(width: 32, height: 32)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.white.opacity(0.10))
                        )
                }
                .buttonStyle(.plain)
                .help("Attach image")

                TextField("Message local model", text: $ollamaSidebarInput, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...5)
                    .font(.system(size: 12, weight: .medium))
                    .onSubmit {
                        sendOllamaSidebarMessage()
                    }

                Button(action: sendOllamaSidebarMessage) {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(ollamaSidebarSending || (ollamaSidebarInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && ollamaSidebarAttachedImageURL == nil))
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
    }

    private var ollamaSidebarAccentHex: String {
        colorHexString(adaptiveAccentColor, fallback: "#3B82F6")
    }

    private var ollamaSidebarAccentTextHex: String {
        colorHexString(adaptiveAccentTextColor, fallback: "#FFFFFF")
    }

    private func colorHexString(_ color: Color, fallback: String) -> String {
        guard let deviceRGB = NSColor(color).usingColorSpace(.deviceRGB) else {
            return fallback
        }
        let red = Int(min(max(deviceRGB.redComponent, 0), 1) * 255.0)
        let green = Int(min(max(deviceRGB.greenComponent, 0), 1) * 255.0)
        let blue = Int(min(max(deviceRGB.blueComponent, 0), 1) * 255.0)
        return String(format: "#%02X%02X%02X", red, green, blue)
    }

    private var configuredOllamaModelForSidebar: String {
        let configured = UserDefaults.standard.string(forKey: AppKeys.ollamaModel)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return configured.isEmpty ? "llama3.2:3b" : configured
    }

    private func pickOllamaSidebarImage() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Attach"
        panel.allowedContentTypes = [.image]
        if panel.runModal() == .OK, let selected = panel.url {
            ollamaSidebarAttachedImageURL = selected
        }
    }

    private func sendOllamaSidebarMessage() {
        if ollamaSidebarSending {
            return
        }

        let rawInput = ollamaSidebarInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let imageURL = ollamaSidebarAttachedImageURL
        if rawInput.isEmpty && imageURL == nil {
            return
        }

        let displayText = rawInput.isEmpty ? "describe this image" : rawInput
        let prompt = rawInput.isEmpty ? "describe this image with key details and context" : rawInput
        let model = configuredOllamaModelForSidebar
        let imagePath = imageURL?.path

        ollamaSidebarMessages.append(
            OllamaSidebarMessage(role: .user, text: displayText, imageURL: imageURL)
        )
        ollamaSidebarInput = ""
        ollamaSidebarAttachedImageURL = nil
        ollamaSidebarSending = true

        ollamaSidebarTask?.cancel()
        ollamaSidebarTask = Task { @MainActor in
            let snapshot: AIPageSemanticSnapshot?
            if ollamaSidebarIncludePageContext {
                snapshot = await captureOllamaSidebarPageContext()
            } else {
                snapshot = nil
            }
            let promptWithContext = composeOllamaPrompt(userPrompt: prompt, snapshot: snapshot)

            let result = await Task.detached(priority: .userInitiated) {
                CommandHelperClient.shared.generateLocalAIChat(
                    prompt: promptWithContext,
                    model: model,
                    imagePath: imagePath
                )
            }.value

            self.ollamaSidebarSending = false
            if result.success {
                let answer = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
                let output = answer.isEmpty ? "Model returned empty response" : answer
                self.ollamaSidebarMessages.append(
                    OllamaSidebarMessage(
                        role: .assistant,
                        text: output,
                        imageURL: nil
                    )
                )
                let commands = parseOllamaToolCommands(from: output)
                if !commands.isEmpty {
                    await runOllamaToolCommands(commands)
                }
            } else {
                let message = result.message.trimmingCharacters(in: .whitespacesAndNewlines)
                self.ollamaSidebarMessages.append(
                    OllamaSidebarMessage(
                        role: .system,
                        text: message.isEmpty ? "generation failed" : message,
                        imageURL: nil
                    )
                )
            }
        }
    }

    private func refreshOllamaSidebarPageContext() {
        Task { @MainActor in
            _ = await captureOllamaSidebarPageContext()
        }
    }

    @MainActor
    private func captureOllamaSidebarPageContext() async -> AIPageSemanticSnapshot? {
        await withCheckedContinuation { continuation in
            store.captureAIPageSemanticSnapshot { snapshot in
                if let snapshot {
                    self.ollamaSidebarPageActions = snapshot.actions
                    self.ollamaSidebarPageContextLine = "actions: \(snapshot.actions.count)  text: \(snapshot.visibleTextBlocks.count)"
                } else {
                    self.ollamaSidebarPageActions = []
                    self.ollamaSidebarPageContextLine = "no page context"
                }
                continuation.resume(returning: snapshot)
            }
        }
    }

    private func composeOllamaPrompt(userPrompt: String, snapshot: AIPageSemanticSnapshot?) -> String {
        guard let snapshot else {
            return userPrompt
        }

        let textBlocks = snapshot.visibleTextBlocks.prefix(80).enumerated().map { index, block in
            "\(index + 1). \(block)"
        }.joined(separator: "\n")

        let actions = snapshot.actions.prefix(80).map { action in
            var line = "[\(action.id)] \(action.kind) \"\(action.label)\""
            if !action.role.isEmpty {
                line += " role=\(action.role)"
            }
            if !action.hint.isEmpty {
                line += " hint=\(action.hint)"
            }
            if !action.context.isEmpty {
                line += " context=\(action.context)"
            }
            if !action.selectorHint.isEmpty {
                line += " selector=\(action.selectorHint)"
            }
            return line
        }.joined(separator: "\n")

        return """
        You are local browser assistant.
        analyze the page context and answer the user.
        if you need browser interaction, use tool commands.

        tool format:
        TOOL click <action_id>
        TOOL type <action_id> <text>
        TOOL click "<label>"
        TOOL type "<label>" <text>

        current page:
        title: \(snapshot.title)
        url: \(snapshot.url)

        visible text blocks:
        \(textBlocks.isEmpty ? "(none)" : textBlocks)

        available actions:
        \(actions.isEmpty ? "(none)" : actions)

        user request:
        \(userPrompt)
        """
    }

    private struct OllamaToolCommand {
        enum Kind {
            case click
            case type
        }

        let kind: Kind
        let actionID: String
        let text: String
    }

    private func parseOllamaToolCommands(from raw: String) -> [OllamaToolCommand] {
        let lines = raw.split(whereSeparator: \.isNewline).map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        var commands: [OllamaToolCommand] = []

        for line in lines {
            guard !line.isEmpty else { continue }
            let lower = line.lowercased()
            if lower.hasPrefix("tool click ") {
                let reference = normalizeOllamaActionID(String(line.dropFirst("tool click ".count)))
                if !reference.isEmpty {
                    commands.append(OllamaToolCommand(kind: .click, actionID: reference, text: ""))
                }
                continue
            }
            if lower.hasPrefix("tool type ") {
                let payload = String(line.dropFirst("tool type ".count))
                if let parsed = parseOllamaToolTypePayload(payload) {
                    commands.append(OllamaToolCommand(kind: .type, actionID: parsed.reference, text: parsed.text))
                }
                continue
            }

            if lower.hasPrefix("click(") {
                let inside = line.dropFirst("click(".count).dropLast(line.hasSuffix(")") ? 1 : 0)
                let reference = normalizeOllamaActionID(String(inside))
                if !reference.isEmpty {
                    commands.append(OllamaToolCommand(kind: .click, actionID: reference, text: ""))
                }
                continue
            }
            if lower.hasPrefix("type(") {
                let inside = line.dropFirst("type(".count).dropLast(line.hasSuffix(")") ? 1 : 0)
                let pair = inside.split(separator: ",", maxSplits: 1, omittingEmptySubsequences: false)
                if let first = pair.first {
                    let reference = normalizeOllamaActionID(String(first))
                    let text = pair.count > 1 ? String(pair[1]).trimmingCharacters(in: CharacterSet(charactersIn: "\"' ")) : ""
                    if !reference.isEmpty {
                        commands.append(OllamaToolCommand(kind: .type, actionID: reference, text: text))
                    }
                }
                continue
            }
        }

        return Array(commands.prefix(3))
    }

    private func parseOllamaToolTypePayload(_ payload: String) -> (reference: String, text: String)? {
        let trimmed = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.hasPrefix("\"") || trimmed.hasPrefix("'") {
            guard let quote = trimmed.first else { return nil }
            let tail = trimmed.dropFirst()
            if let closing = tail.firstIndex(of: quote) {
                let referenceRaw = String(tail[..<closing])
                let afterClosing = tail.index(after: closing)
                let textRaw: String
                if afterClosing < tail.endIndex {
                    textRaw = String(tail[afterClosing...]).trimmingCharacters(in: .whitespacesAndNewlines)
                } else {
                    textRaw = ""
                }
                let reference = normalizeOllamaActionID(referenceRaw)
                guard !reference.isEmpty else { return nil }
                return (reference, textRaw)
            }
        }

        let parts = trimmed.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        guard let first = parts.first else { return nil }
        let reference = normalizeOllamaActionID(String(first))
        guard !reference.isEmpty else { return nil }
        let text = parts.count > 1 ? String(parts[1]).trimmingCharacters(in: CharacterSet(charactersIn: "\"'")) : ""
        return (reference, text)
    }

    private func normalizeOllamaActionID(_ raw: String) -> String {
        let cleaned = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'[]()"))
            .replacingOccurrences(of: ",", with: "")
        return cleaned
    }

    private func canonicalActionToken(_ raw: String) -> String {
        let lowered = raw.lowercased()
        let separators = CharacterSet.alphanumerics.inverted
        let words = lowered
            .components(separatedBy: separators)
            .filter { !$0.isEmpty }
        return words.joined(separator: " ")
    }

    private func resolveOllamaActionReference(_ rawReference: String) -> String? {
        let reference = normalizeOllamaActionID(rawReference)
        guard !reference.isEmpty else { return nil }

        if let exact = ollamaSidebarPageActions.first(where: { $0.id.caseInsensitiveCompare(reference) == .orderedSame }) {
            return exact.id
        }

        let normalizedUnderscore = reference
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")
        if let direct = ollamaSidebarPageActions.first(where: {
            $0.id.lowercased() == normalizedUnderscore.lowercased()
        }) {
            return direct.id
        }

        let canonicalRef = canonicalActionToken(reference)
        guard !canonicalRef.isEmpty else { return nil }

        if let byLabelExact = ollamaSidebarPageActions.first(where: {
            canonicalActionToken($0.label) == canonicalRef
        }) {
            return byLabelExact.id
        }

        if let byCombinedExact = ollamaSidebarPageActions.first(where: {
            canonicalActionToken("\($0.label) \($0.context)") == canonicalRef
        }) {
            return byCombinedExact.id
        }

        if let byContains = ollamaSidebarPageActions.first(where: {
            let value = canonicalActionToken("\($0.label) \($0.context) \($0.hint)")
            return value.contains(canonicalRef) || canonicalRef.contains(value)
        }) {
            return byContains.id
        }

        return nil
    }

    @MainActor
    private func runOllamaToolCommands(_ commands: [OllamaToolCommand]) async {
        for command in commands {
            let resolvedID = resolveOllamaActionReference(command.actionID)
            guard let actionID = resolvedID else {
                ollamaSidebarMessages.append(
                    OllamaSidebarMessage(
                        role: .system,
                        text: "tool fail: action `\(command.actionID)` not found in current page actions",
                        imageURL: nil
                    )
                )
                continue
            }

            let result = await withCheckedContinuation { continuation in
                switch command.kind {
                case .click:
                    store.executeAIPageAction(id: actionID, typeText: nil) { success, message in
                        continuation.resume(returning: (success, message))
                    }
                case .type:
                    store.executeAIPageAction(id: actionID, typeText: command.text) { success, message in
                        continuation.resume(returning: (success, message))
                    }
                }
            }

            let prefix = result.0 ? "tool ok" : "tool fail"
            ollamaSidebarMessages.append(
                OllamaSidebarMessage(
                    role: .system,
                    text: "\(prefix): \(result.1)",
                    imageURL: nil
                )
            )
        }

        _ = await captureOllamaSidebarPageContext()
    }

    private func runQuickOllamaAction(_ actionID: String) {
        store.executeAIPageAction(id: actionID, typeText: nil) { success, message in
            let prefix = success ? "tool ok" : "tool fail"
            self.ollamaSidebarMessages.append(
                OllamaSidebarMessage(
                    role: .system,
                    text: "\(prefix): \(message)",
                    imageURL: nil
                )
            )
            self.refreshOllamaSidebarPageContext()
        }
    }

    private func clearOllamaSidebarConversation() {
        ollamaSidebarTask?.cancel()
        ollamaSidebarSending = false
        ollamaSidebarInput = ""
        ollamaSidebarAttachedImageURL = nil
        ollamaSidebarPageContextLine = ""
        ollamaSidebarPageActions = []
        ollamaSidebarMessages.removeAll()
    }

    private func refreshExtensionsPanelSnapshot() {
        let items = store.extensionBundlesForPanel()
        extensionsPanelBundles = items
        var drafts: [String: String] = [:]
        for bundle in items {
            drafts[bundle.id] = bundle.name
        }
        extensionRenameDraftByID = drafts
    }

    private func commitExtensionRename(id: String) {
        let value = extensionRenameDraftByID[id]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let customName = value.isEmpty ? nil : value
        store.renameExtensionFromPanel(id, customName: customName)
        refreshExtensionsPanelSnapshot()
    }

    private func refreshBookmarkShortcutDrafts() {
        var drafts: [UUID: String] = [:]
        for item in store.bookmarks {
            drafts[item.id] = item.shortcut?.inputValue ?? ""
        }
        bookmarkShortcutDraftByID = drafts
    }

    private func bookmarkShortcutBinding(for item: BookmarkItem) -> Binding<String> {
        Binding(
            get: { bookmarkShortcutDraftByID[item.id] ?? (item.shortcut?.inputValue ?? "") },
            set: { bookmarkShortcutDraftByID[item.id] = $0 }
        )
    }

    private func commitBookmarkShortcut(for item: BookmarkItem) {
        let value = bookmarkShortcutDraftByID[item.id] ?? ""
        store.setBookmarkShortcut(bookmarkID: item.id, input: value)
        if let updated = store.bookmarks.first(where: { $0.id == item.id }) {
            bookmarkShortcutDraftByID[item.id] = updated.shortcut?.inputValue ?? ""
        } else {
            bookmarkShortcutDraftByID.removeValue(forKey: item.id)
        }
    }

    private func clearBookmarkShortcut(for item: BookmarkItem) {
        bookmarkShortcutDraftByID[item.id] = ""
        store.setBookmarkShortcut(bookmarkID: item.id, input: "")
    }

    private var selectedBookmarkPanelID: UUID? {
        guard store.bookmarks.indices.contains(bookmarksPanelSelectionIndex) else { return nil }
        return store.bookmarks[bookmarksPanelSelectionIndex].id
    }

    private func clampBookmarksPanelSelection() {
        let count = store.bookmarks.count
        guard count > 0 else {
            bookmarksPanelSelectionIndex = 0
            return
        }
        bookmarksPanelSelectionIndex = min(max(bookmarksPanelSelectionIndex, 0), count - 1)
    }

    private func syncBookmarksPanelSelection(preferCurrent: Bool) {
        guard store.utilityPanel == .bookmarks else { return }
        guard !store.bookmarks.isEmpty else {
            bookmarksPanelSelectionIndex = 0
            return
        }
        if preferCurrent,
           let currentBookmarkID,
           let currentIndex = store.bookmarks.firstIndex(where: { $0.id == currentBookmarkID }) {
            bookmarksPanelSelectionIndex = currentIndex
            return
        }
        clampBookmarksPanelSelection()
    }

    private func moveBookmarksPanelSelection(forward: Bool) {
        let count = store.bookmarks.count
        guard count > 0 else { return }
        if forward {
            bookmarksPanelSelectionIndex = (bookmarksPanelSelectionIndex + 1) % count
        } else {
            bookmarksPanelSelectionIndex = (bookmarksPanelSelectionIndex - 1 + count) % count
        }
    }

    private func activateBookmarksPanelSelection() {
        guard store.bookmarks.indices.contains(bookmarksPanelSelectionIndex) else { return }
        store.openBookmark(store.bookmarks[bookmarksPanelSelectionIndex])
    }

    private func utilityPanelTitle(_ kind: UtilityPanelKind) -> String {
        switch kind {
        case .bookmarks:
            return "Bookmarks"
        case .history:
            return "History"
        case .colors:
            return "Colors"
        case .extensions:
            return "Extensions"
        case .ollamaChat:
            return "AI Chat"
        }
    }

    @ViewBuilder
    private func utilityRows(for kind: UtilityPanelKind) -> some View {
        if kind == .bookmarks {
            if store.bookmarks.isEmpty {
                emptyPanelText("No bookmarks yet")
            } else {
                ForEach(Array(store.bookmarks.enumerated()), id: \.element.id) { index, item in
                    bookmarkRow(item, index: index, isKeyboardSelected: selectedBookmarkPanelID == item.id)
                    .onHover { hovering in
                        if hovering {
                            bookmarksPanelSelectionIndex = index
                        }
                    }
                    .onDrag {
                        draggedBookmarkID = item.id
                        return NSItemProvider(object: NSString(string: item.id.uuidString))
                    }
                    .onDrop(of: [UTType.text], delegate: BookmarkRowDropDelegate(
                        targetID: item.id,
                        onMove: { draggedID, targetID in
                            store.reorderBookmarks(draggedID: draggedID, to: targetID)
                        },
                        draggedBookmarkID: $draggedBookmarkID
                    ))
                }
            }
        } else if kind == .history {
            if store.history.isEmpty {
                emptyPanelText("No history yet")
            } else {
                ForEach(historySections()) { section in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(section.title)
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.white.opacity(0.72))
                            .padding(.horizontal, 2)

                        ForEach(section.items) { item in
                            historyRow(item)
                        }
                    }
                }
            }
        } else if kind == .extensions {
            if store.extensionInstallInProgress || !store.extensionInstallStatus.isEmpty {
                extensionInstallProgressRow
            }
            if showExtensionsInstallInput {
                extensionInstallInputRow
            }
            if extensionsPanelBundles.isEmpty {
                emptyPanelText("No extensions installed")
            } else {
                ForEach(extensionsPanelBundles, id: \.id) { bundle in
                    extensionPanelRow(bundle)
                }
            }
        } else if kind == .ollamaChat {
            ollamaSidebarChatPanel
        }
    }

    private var colorsSettingsPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            store.chromeTheme.color.opacity(0.92),
                            store.chromeTheme.color.opacity(0.38)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.white.opacity(0.20), lineWidth: 1)
                )
                .frame(height: 56)

            Toggle(isOn: $chromeBarGradientEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Tab bar gradient")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.90))
                    Text(chromeBarGradientEnabled ? "Animated gradient is enabled" : "Flat tint without gradient")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.66))
                }
            }
            .toggleStyle(.switch)

            if chromeBarGradientEnabled {
                Toggle(isOn: $chromeBarGradientAnimationEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Tab bar animation")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.90))
                        Text(chromeBarGradientAnimationEnabled ? "Animated movement is enabled" : "Gradient stays static")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.66))
                    }
                }
                .toggleStyle(.switch)

                Text("dont turn on bad pc")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.red.opacity(0.92))
            }

            colorSliderRow(
                label: "Red",
                value: Binding(
                    get: { store.chromeTheme.red },
                    set: { store.setChromeTheme(red: $0) }
                ),
                tint: .red
            )
            colorSliderRow(
                label: "Green",
                value: Binding(
                    get: { store.chromeTheme.green },
                    set: { store.setChromeTheme(green: $0) }
                ),
                tint: .green
            )
            colorSliderRow(
                label: "Blue",
                value: Binding(
                    get: { store.chromeTheme.blue },
                    set: { store.setChromeTheme(blue: $0) }
                ),
                tint: .blue
            )
            colorSliderRow(
                label: "Intensity",
                value: Binding(
                    get: { store.chromeTheme.intensity },
                    set: { store.setChromeTheme(intensity: $0) }
                ),
                range: 0...1.5,
                tint: store.chromeTheme.color
            )

            Text("Presets")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.72))

            HStack(spacing: 8) {
                ForEach(chromeThemePresets.indices, id: \.self) { index in
                    let preset = chromeThemePresets[index]
                    Button(action: { store.applyChromePreset(preset) }) {
                        Circle()
                            .fill(preset.color.opacity(0.92))
                            .overlay(
                                Circle()
                                    .stroke(Color.white.opacity(0.22), lineWidth: 1)
                            )
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                    .help("Preset \(index + 1)")
                }
            }

            Divider().overlay(Color.white.opacity(0.12))

            Text("Custom Color")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.72))

            VStack(alignment: .leading, spacing: 4) {
                Text("Current HTML: \(currentHTMLColorString())")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.82))
                Text("Current RGB: \(currentRGBColorString())")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.72))
            }

            HStack(spacing: 8) {
                TextField("#4A9BFF", text: $colorHexInput)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                Button("Apply HEX") {
                    applyHexColorInput()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            HStack(spacing: 8) {
                TextField("rgb(74,155,255) or 74,155,255", text: $colorRGBInput)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                Button("Apply RGB") {
                    applyRGBColorInput()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            if !colorInputMessage.isEmpty {
                Text(colorInputMessage)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(colorInputError ? Color.red.opacity(0.88) : Color.green.opacity(0.88))
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
    }

    private var chromeThemePresets: [ChromeTheme] {
        [
            .default,
            ChromeTheme(red: 0.12, green: 0.76, blue: 0.90, intensity: 0.60),
            ChromeTheme(red: 0.24, green: 0.58, blue: 0.98, intensity: 0.72),
            ChromeTheme(red: 0.62, green: 0.39, blue: 0.94, intensity: 0.66),
            ChromeTheme(red: 0.90, green: 0.33, blue: 0.48, intensity: 0.68),
            ChromeTheme(red: 0.14, green: 0.82, blue: 0.58, intensity: 0.56)
        ]
    }

    private func colorSliderRow(
        label: String,
        value: Binding<Double>,
        range: ClosedRange<Double> = 0...1,
        tint: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.74))
                Spacer()
                Text(String(format: "%.2f", value.wrappedValue))
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.94))
            }
            Slider(value: value, in: range)
                .tint(tint.opacity(0.9))
        }
    }

    private func currentHTMLColorString() -> String {
        let r = Int((store.chromeTheme.red * 255.0).rounded())
        let g = Int((store.chromeTheme.green * 255.0).rounded())
        let b = Int((store.chromeTheme.blue * 255.0).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    private func currentRGBColorString() -> String {
        let r = Int((store.chromeTheme.red * 255.0).rounded())
        let g = Int((store.chromeTheme.green * 255.0).rounded())
        let b = Int((store.chromeTheme.blue * 255.0).rounded())
        return "\(r), \(g), \(b)"
    }

    private func applyHexColorInput() {
        guard let (r, g, b) = parseHTMLColor(colorHexInput) else {
            colorInputError = true
            colorInputMessage = "Invalid HTML color. Use #RRGGBB or #RGB."
            return
        }
        store.setChromeTheme(red: r, green: g, blue: b)
        colorInputError = false
        colorInputMessage = "HEX color applied"
        colorHexInput = ""
    }

    private func applyRGBColorInput() {
        guard let (r, g, b) = parseRGBColor(colorRGBInput) else {
            colorInputError = true
            colorInputMessage = "Invalid RGB color. Use rgb(74,155,255) or 74,155,255."
            return
        }
        store.setChromeTheme(red: r, green: g, blue: b)
        colorInputError = false
        colorInputMessage = "RGB color applied"
        colorRGBInput = ""
    }

    private func parseHTMLColor(_ rawInput: String) -> (Double, Double, Double)? {
        var raw = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.hasPrefix("#") {
            raw.removeFirst()
        }
        if raw.count == 3 {
            raw = raw.map { "\($0)\($0)" }.joined()
        }
        guard raw.count == 6 else { return nil }
        guard let value = Int(raw, radix: 16) else { return nil }
        let r = Double((value >> 16) & 0xFF) / 255.0
        let g = Double((value >> 8) & 0xFF) / 255.0
        let b = Double(value & 0xFF) / 255.0
        return (r, g, b)
    }

    private func parseRGBColor(_ rawInput: String) -> (Double, Double, Double)? {
        var raw = rawInput.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if raw.hasPrefix("rgb("), raw.hasSuffix(")") {
            raw.removeFirst(4)
            raw.removeLast()
        }
        let parts = raw.split { $0 == "," || $0 == " " || $0 == ";" }.map(String.init).filter { !$0.isEmpty }
        guard parts.count == 3 else { return nil }
        guard let rv = Double(parts[0]), let gv = Double(parts[1]), let bv = Double(parts[2]) else {
            return nil
        }
        guard (0...255).contains(rv), (0...255).contains(gv), (0...255).contains(bv) else {
            return nil
        }
        return (rv / 255.0, gv / 255.0, bv / 255.0)
    }

    private func bookmarkRow(_ item: BookmarkItem, index: Int, isKeyboardSelected: Bool = false) -> some View {
        let isCurrent = currentBookmarkID == item.id

        return HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 5) {
                Button(action: { store.openBookmark(item) }) {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "bookmark.fill")
                            .foregroundStyle(isKeyboardSelected ? adaptiveAccentTextColor : (isCurrent ? adaptiveAccentColor.opacity(0.96) : adaptiveAccentColor.opacity(0.90)))

                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text(item.title)
                                    .lineLimit(1)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(isKeyboardSelected ? adaptiveAccentTextColor : Color.white.opacity(0.95))
                                if isCurrent {
                                    Text("CURRENT")
                                        .font(.system(size: 9, weight: .bold, design: .rounded))
                                        .foregroundStyle(adaptiveAccentTextColor)
                                        .padding(.horizontal, 6)
                                        .frame(height: 16)
                                        .background(
                                            Capsule(style: .continuous)
                                                .fill(isKeyboardSelected ? adaptiveAccentColor.opacity(0.28) : adaptiveAccentColor.opacity(0.92))
                                        )
                                }
                            }
                            Text(item.url)
                                .lineLimit(1)
                                .font(.system(size: 11))
                                .foregroundStyle(isKeyboardSelected ? adaptiveAccentSecondaryTextColor : Color.white.opacity(0.62))
                            if let shortcut = item.shortcut {
                                Text("Active: \(shortcut.displayLabel)")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(isKeyboardSelected ? adaptiveAccentSecondaryTextColor : Color.white.opacity(0.60))
                            }
                        }
                        Spacer(minLength: 6)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)

                HStack(spacing: 6) {
                    TextField(
                        "hotkey ex: o",
                        text: bookmarkShortcutBinding(for: item)
                    )
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .onSubmit {
                        commitBookmarkShortcut(for: item)
                    }
                    .onTapGesture {
                        bookmarksPanelSelectionIndex = index
                    }

                    Button("Set") {
                        commitBookmarkShortcut(for: item)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.mini)

                    if item.shortcut != nil {
                        Button("Clear") {
                            clearBookmarkShortcut(for: item)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                    } else if index < 9 {
                        Text("default \(index + 1)")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(isKeyboardSelected ? adaptiveAccentSecondaryTextColor : Color.white.opacity(0.46))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: { store.removeBookmarkItem(item) }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isKeyboardSelected ? adaptiveAccentSecondaryTextColor : Color.white.opacity(0.58))
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .help("Delete bookmark")
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isKeyboardSelected ? adaptiveAccentColor.opacity(0.90) : (isCurrent ? adaptiveAccentColor.opacity(0.20) : Color.white.opacity(0.06)))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(isKeyboardSelected ? Color.white.opacity(0.88) : (isCurrent ? adaptiveAccentColor.opacity(0.58) : Color.white.opacity(0.08)), lineWidth: 1)
        )
    }

    private var extensionInstallProgressRow: some View {
        let clamped = min(max(store.extensionInstallProgress, 0.0), 1.0)
        return VStack(alignment: .leading, spacing: 6) {
            ProgressView(value: clamped, total: 1.0)
                .progressViewStyle(.linear)
            HStack(spacing: 6) {
                Text(store.extensionInstallStatus.isEmpty ? "Installing extension..." : store.extensionInstallStatus)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.80))
                Spacer()
                Text("\(Int(clamped * 100))%")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.72))
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
    }

    private var extensionInstallInputRow: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Install extension")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.84))
            HStack(spacing: 6) {
                TextField("folder path or chrome web store url or extension id", text: $extensionsInstallInput)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11, weight: .medium))
                    .onSubmit {
                        let value = extensionsInstallInput.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !value.isEmpty else { return }
                        store.installExtensionFromInput(value)
                    }
                Button("Install") {
                    let value = extensionsInstallInput.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !value.isEmpty else { return }
                    store.installExtensionFromInput(value)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(store.extensionInstallInProgress)
            }
            Text("Examples: cfhdojbkjhnklbpkdaibdccddilifddb or https://chromewebstore.google.com/detail/.../<id>")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.58))
                .lineLimit(2)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
    }

    private func extensionPanelRow(_ bundle: WebExtensionBundle) -> some View {
        let renameBinding = Binding(
            get: { extensionRenameDraftByID[bundle.id] ?? bundle.name },
            set: { extensionRenameDraftByID[bundle.id] = $0 }
        )

        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "puzzlepiece.extension.fill")
                    .foregroundStyle(bundle.enabled ? adaptiveAccentColor.opacity(0.92) : Color.white.opacity(0.46))

                VStack(alignment: .leading, spacing: 4) {
                    Text(bundle.name)
                        .lineLimit(1)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.95))
                    Text(bundle.id)
                        .lineLimit(1)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.62))
                }
                Spacer(minLength: 4)
                Text(bundle.enabled ? "on" : "off")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(bundle.enabled ? Color.green.opacity(0.9) : Color.orange.opacity(0.9))
            }

            HStack(spacing: 6) {
                TextField("Extension name", text: renameBinding)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11, weight: .medium))
                    .onSubmit {
                        commitExtensionRename(id: bundle.id)
                    }

                Button("Rename") {
                    commitExtensionRename(id: bundle.id)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            HStack(spacing: 6) {
                Button("Copy id") {
                    store.copyExtensionIDToPasteboard(bundle.id)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("Window") {
                    store.openExtensionWindowFromPanel(bundle.id)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button(bundle.enabled ? "Disable" : "Enable") {
                    _ = WebExtensionManager.shared.setEnabled(!bundle.enabled, extensionID: bundle.id)
                    store.reloadWebExtensionsRuntime(reloadTabs: true)
                    refreshExtensionsPanelSnapshot()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("Remove") {
                    store.removeExtensionFromPanel(bundle.id)
                    refreshExtensionsPanelSnapshot()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
    }

    private func historyRow(_ item: HistoryItem) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Button(action: { store.openHistoryItem(item) }) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "clock.fill")
                        .foregroundStyle(Color.orange.opacity(0.90))

                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.title)
                            .lineLimit(1)
                            .font(.system(size: 13, weight: .semibold))
                        Text(item.url)
                            .lineLimit(1)
                            .font(.system(size: 11))
                            .foregroundStyle(Color.white.opacity(0.62))
                        Text(historyTimeString(item.visitedAt))
                            .lineLimit(1)
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(adaptiveAccentColor.opacity(0.82))
                    }
                    Spacer(minLength: 6)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            Button(action: { store.removeHistoryItem(item) }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.58))
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .help("Delete entry")
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
    }

    private func historySections() -> [HistorySection] {
        let sorted = store.history.sorted { $0.visitedAt > $1.visitedAt }
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: sorted) { item in
            calendar.startOfDay(for: item.visitedAt)
        }

        return grouped.keys.sorted(by: >).map { day in
            let items = (grouped[day] ?? []).sorted { $0.visitedAt > $1.visitedAt }
            return HistorySection(
                id: String(Int(day.timeIntervalSince1970)),
                title: historyDateTitle(day),
                items: items
            )
        }
    }

    private func historyDateTitle(_ day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) {
            return "Today"
        }
        if calendar.isDateInYesterday(day) {
            return "Yesterday"
        }
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: day)
    }

    private func historyTimeString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }

    private func emptyPanelText(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Color.white.opacity(0.62))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 10)
            .padding(.horizontal, 2)
    }

    private var ctrlEOverlayCornerRadius: CGFloat {
        let stored = UserDefaults.standard.integer(forKey: AppKeys.ctrlECornerRadius)
        let normalized = stored > 0 ? stored : 20
        return CGFloat(min(max(normalized, 8), 48))
    }

    private var commandOverlayHeader: some View {
        HStack(spacing: 8) {
            if store.overlayCommandArmed && store.commandOverlayMode != .commandsOnly {
                commandModeIndicator
            }

            if store.commandOverlayMode != .commandsOnly {
                Image(systemName: "command")
                    .foregroundStyle(store.overlayCommandArmed ? adaptiveAccentColor.opacity(0.92) : Color.white.opacity(0.78))
            }

            TextField(store.commandOverlayMode == .commandsOnly ? "Type command" : "Type command, address or search", text: Binding(
                get: { store.commandInput },
                set: { store.updateCommandInput($0) }
            ))
            .textFieldStyle(.plain)
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(Color.white.opacity(0.96))
            .focused($focusedTarget, equals: .commandBar)
            .onSubmit {
                store.executeCommandOverlay()
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 54)
        .background(
            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.12))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(
                    (store.overlayCommandArmed || store.commandOverlayMode == .commandsOnly) ? adaptiveAccentColor.opacity(0.52) : Color.white.opacity(0.24),
                    lineWidth: 1
                )
        )
    }

    private var commandModeIndicator: some View {
        HStack(spacing: 5) {
            Rectangle()
                .fill(adaptiveAccentColor.opacity(0.92))
                .frame(width: 2, height: 13)
                .clipShape(Capsule(style: .continuous))

            Text("COMMANDS")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .tracking(0.3)
        }
        .foregroundStyle(Color.white.opacity(0.95))
        .padding(.horizontal, 7)
        .frame(height: 20)
        .background(
            Capsule(style: .continuous)
                .fill(adaptiveAccentColor.opacity(0.28))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(adaptiveAccentColor.opacity(0.58), lineWidth: 1)
        )
    }

    private func commandSuggestionRow(_ suggestion: CommandSuggestion, isSelected: Bool) -> some View {
        Button(action: { store.executeSuggestion(suggestion) }) {
            HStack(spacing: 10) {
                if store.commandOverlayMode != .commandsOnly {
                    Image(systemName: suggestion.icon)
                        .frame(width: 18)
                        .foregroundStyle(adaptiveAccentColor.opacity(0.88))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(suggestion.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.95))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(suggestion.subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.white.opacity(0.62))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Spacer()
                if !suggestion.value.isEmpty {
                    Text(suggestion.value)
                        .lineLimit(1)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.56))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(isSelected ? adaptiveAccentColor.opacity(0.24) : Color.white.opacity(0.07))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(isSelected ? adaptiveAccentColor.opacity(0.66) : Color.white.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var commandOverlay: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture {
                    store.closeCommandOverlay()
                }

            VStack(spacing: 10) {
                commandOverlayHeader

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 6) {
                            ForEach(Array(store.commandSuggestions.enumerated()), id: \.element.id) { index, suggestion in
                                commandSuggestionRow(suggestion, isSelected: store.selectedCommandSuggestionIndex == index)
                                    .id(suggestion.id)
                            }
                        }
                        .padding(10)
                    }
                    .frame(maxHeight: 300)
                    .onChange(of: store.selectedCommandSuggestionIndex) { selected in
                        guard let selected,
                              store.commandSuggestions.indices.contains(selected) else {
                            return
                        }
                        let targetID = store.commandSuggestions[selected].id
                        withAnimation(.easeInOut(duration: 0.12)) {
                            proxy.scrollTo(targetID, anchor: .center)
                        }
                    }
                }
            }
            .padding(12)
            .frame(width: min(860, NSScreen.main?.frame.width ?? 860 - 120))
            .background(
                RoundedRectangle(cornerRadius: ctrlEOverlayCornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: ctrlEOverlayCornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.22), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.35), radius: 20, y: 8)
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
                    focusedTarget = .commandBar
                }
            }
        }
    }

    private var tabWheelTabs: [BrowserTab] {
        store.tabs
    }

    private func normalizedTabWheelIndex(_ raw: Int) -> Int {
        let count = tabWheelTabs.count
        guard count > 0 else { return 0 }
        return ((raw % count) + count) % count
    }

    private var selectedTabWheelTab: BrowserTab? {
        guard !tabWheelTabs.isEmpty else { return nil }
        return tabWheelTabs[normalizedTabWheelIndex(tabWheelSelectionIndex)]
    }

    private var tabWheelVisibleIndices: [Int] {
        let count = tabWheelTabs.count
        guard count > 0 else { return [] }
        let visibleCount = min(count, 8)
        return (0..<visibleCount).map { offset in
            normalizedTabWheelIndex(tabWheelSelectionIndex + offset)
        }
    }

    private func tabWheelNode(slot: Int, index: Int, total: Int) -> some View {
        let tab = tabWheelTabs[index]
        let safeTotal = max(1, total)
        let angle = (Double(slot) / Double(safeTotal)) * 360.0 - 90.0
        let radians = angle * Double.pi / 180.0
        let radius: CGFloat = 122
        let x = CGFloat(cos(radians)) * radius
        let y = CGFloat(sin(radians)) * radius
        let isSelected = index == normalizedTabWheelIndex(tabWheelSelectionIndex)
        let title = tab.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Tab" : tab.title

        return VStack(spacing: 3) {
            Image(systemName: tab.isBookmarkTab ? "bookmark.fill" : "rectangle.on.rectangle")
                .font(.system(size: 11, weight: .semibold))
            Text(title)
                .font(.system(size: 9, weight: .semibold))
                .lineLimit(1)
                .frame(maxWidth: 90)
        }
        .foregroundStyle(isSelected ? adaptiveAccentTextColor : Color.white.opacity(0.9))
        .frame(width: 98, height: 42)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? adaptiveAccentColor.opacity(0.95) : Color.white.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(isSelected ? Color.white.opacity(0.86) : Color.white.opacity(0.18), lineWidth: 1)
        )
        .offset(x: x, y: y)
    }

    private var tabWheelCenterCard: some View {
        VStack(spacing: 8) {
            Text("TAB WHEEL")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(adaptiveAccentColor.opacity(0.9))

            if let tab = selectedTabWheelTab {
                Text(tab.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "New Tab" : tab.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.96))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 140)
                Text(tab.displayURL.isEmpty ? "New Tab" : tab.displayURL)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.66))
                    .lineLimit(1)
                    .frame(maxWidth: 160)
            } else {
                Text("No tabs")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.9))
            }

            Text("Scroll / arrows to cycle")
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.72))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(width: 184, height: 118)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.black.opacity(0.34))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.20), lineWidth: 1)
        )
    }

    private var tabWheelOverlay: some View {
        let visibleIndices = tabWheelVisibleIndices
        let count = visibleIndices.count

        return ZStack {
            Color.black.opacity(0.25)
                .ignoresSafeArea()

            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 322, height: 322)
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.22), lineWidth: 1)
                    )

                ForEach(Array(visibleIndices.enumerated()), id: \.offset) { slot, index in
                    tabWheelNode(slot: slot, index: index, total: count)
                }

                tabWheelCenterCard
            }
            .frame(width: 328, height: 328)
            .position(tabWheelCenter)
            .shadow(color: .black.opacity(0.35), radius: 20, y: 8)
        }
        .allowsHitTesting(false)
    }

    private var musicWheelOverlay: some View {
        ZStack {
            Color.black.opacity(0.20)
                .ignoresSafeArea()

            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 294, height: 294)
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.22), lineWidth: 1)
                    )
                    .overlay(
                        Circle()
                            .stroke(adaptiveAccentColor.opacity(0.20), lineWidth: 2)
                            .blur(radius: 1)
                    )

                ForEach(MusicWheelAction.ringOrder) { action in
                    musicWheelNode(for: action)
                }

                musicWheelCenterNode
            }
            .frame(width: 300, height: 300)
            .position(musicWheelCenter)
            .shadow(color: .black.opacity(0.34), radius: 18, y: 8)
        }
        .allowsHitTesting(false)
    }

    private func musicWheelNode(for action: MusicWheelAction) -> some View {
        let isSelected = action == musicWheelSelection
        let radius: CGFloat = 108
        let offsetX = action.unitVector.dx * radius
        let offsetY = action.unitVector.dy * radius

        return VStack(spacing: 4) {
            Image(systemName: action.symbolName)
                .font(.system(size: 14, weight: .semibold))
            Text(action.title)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
        }
        .foregroundStyle(isSelected ? adaptiveAccentTextColor : Color.white.opacity(0.88))
        .frame(width: 80, height: 54)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isSelected ? adaptiveAccentColor.opacity(0.95) : Color.white.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isSelected ? Color.white.opacity(0.85) : Color.white.opacity(0.20), lineWidth: 1)
        )
        .offset(x: offsetX, y: offsetY)
    }

    private var musicWheelCenterNode: some View {
        VStack(spacing: 7) {
            Group {
                if let value = musicWheelNowPlaying.artworkURL,
                   let url = URL(string: value) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case let .success(image):
                            image
                                .resizable()
                                .scaledToFill()
                        default:
                            Circle()
                                .fill(Color.white.opacity(0.16))
                                .overlay(
                                    Image(systemName: "music.note")
                                        .font(.system(size: 20, weight: .semibold))
                                        .foregroundStyle(Color.white.opacity(0.75))
                                )
                        }
                    }
                } else {
                    Circle()
                        .fill(Color.white.opacity(0.16))
                        .overlay(
                            Image(systemName: "music.note")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(Color.white.opacity(0.75))
                        )
                }
            }
            .frame(width: 58, height: 58)
            .clipShape(Circle())
            .overlay(
                Circle()
                    .stroke(Color.white.opacity(0.22), lineWidth: 1)
            )

            Text(musicWheelNowPlaying.title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.95))
                .lineLimit(1)
                .frame(maxWidth: 108)

            Text(musicWheelNowPlaying.subtitle)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.66))
                .lineLimit(1)
                .frame(maxWidth: 108)

            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.16))
                Capsule(style: .continuous)
                    .fill(adaptiveAccentColor.opacity(0.86))
                    .frame(width: max(4, 62 * CGFloat(min(max(musicWheelNowPlaying.progress, 0), 1))))
            }
            .frame(width: 62, height: 4)

            Text(musicWheelMood.title.uppercased())
                .font(.system(size: 8, weight: .bold, design: .rounded))
                .foregroundStyle(adaptiveAccentColor.opacity(0.92))
        }
        .frame(width: 124, height: 164)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.black.opacity(0.36))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.20), lineWidth: 1)
        )
    }

    private func hostWindow() -> NSWindow? {
        if let hostWindowID,
           let window = NSApp.windows.first(where: { ObjectIdentifier($0) == hostWindowID }) {
            return window
        }
        if let keyWindow = NSApp.keyWindow {
            return keyWindow
        }
        if let mainWindow = NSApp.mainWindow {
            return mainWindow
        }
        return NSApp.windows.first
    }

    private func mouseLocationInRootView() -> CGPoint {
        guard let window = hostWindow() else {
            return CGPoint(x: 400, y: 260)
        }

        let bounds = window.contentView?.bounds ?? NSRect(x: 0, y: 0, width: window.frame.width, height: window.frame.height)
        let screenLocation = NSEvent.mouseLocation
        let windowLocation = window.convertPoint(fromScreen: screenLocation)
        let x = min(max(windowLocation.x, 30), max(30, bounds.width - 30))
        let y = min(max(bounds.height - windowLocation.y, 30), max(30, bounds.height - 30))
        return CGPoint(x: x, y: y)
    }

    private func openTabWheel() {
        guard !store.tabs.isEmpty else { return }
        deactivateLinkHintMode(removeFromAllTabs: false)
        closeMiniMCV()
        store.closeCommandOverlay()
        if showFindOverlay {
            closeFindOverlay(clearHighlights: true)
        }
        if showSavedNavigator {
            closeSavedNavigator()
        }
        showTabsOverview = false
        showDownloadsOverview = false
        showMusicWheel = false
        showTabWheel = true
        tabWheelCenter = mouseLocationInRootView()
        if let selectedID = store.selectedTabID,
           let selectedIndex = store.tabs.firstIndex(where: { $0.id == selectedID }) {
            tabWheelSelectionIndex = selectedIndex
        } else {
            tabWheelSelectionIndex = 0
        }
    }

    private func closeTabWheel(executeSelection: Bool) {
        guard showTabWheel else { return }
        if executeSelection {
            selectTabFromWheel()
        }
        showTabWheel = false
    }

    private func selectTabFromWheel() {
        guard !tabWheelTabs.isEmpty else { return }
        let index = normalizedTabWheelIndex(tabWheelSelectionIndex)
        let targetID = tabWheelTabs[index].id
        store.selectTab(id: targetID)
    }

    private func advanceTabWheel(forward: Bool) {
        let count = tabWheelTabs.count
        guard count > 0 else { return }
        if forward {
            tabWheelSelectionIndex = normalizedTabWheelIndex(tabWheelSelectionIndex + 1)
        } else {
            tabWheelSelectionIndex = normalizedTabWheelIndex(tabWheelSelectionIndex - 1)
        }
    }

    private func handleTabWheelScroll(_ event: NSEvent) {
        let vertical = event.scrollingDeltaY
        let horizontal = event.scrollingDeltaX
        let primary = abs(vertical) >= abs(horizontal) ? vertical : horizontal
        guard abs(primary) > 0.01 else { return }
        advanceTabWheel(forward: primary < 0)
    }

    private func openMusicWheel() {
        deactivateLinkHintMode(removeFromAllTabs: false)
        closeMiniMCV()
        store.closeCommandOverlay()
        if showFindOverlay {
            closeFindOverlay(clearHighlights: true)
        }
        if showSavedNavigator {
            closeSavedNavigator()
        }
        showTabWheel = false
        showMusicWheel = true
        musicWheelCenter = mouseLocationInRootView()
        musicWheelDrag = .zero
        musicWheelSelection = .playPause
        refreshMusicWheelNowPlaying()
    }

    private func closeMusicWheel(executeSelection: Bool) {
        guard showMusicWheel else { return }
        if executeSelection {
            executeMusicWheelSelection()
        }
        showMusicWheel = false
    }

    private func refreshMusicWheelNowPlaying() {
        store.fetchMusicWheelNowPlaying { nowPlaying in
            musicWheelNowPlaying = nowPlaying
        }
    }

    private func updateMusicWheelSelection() {
        let point = mouseLocationInRootView()
        let dx = point.x - musicWheelCenter.x
        let dy = point.y - musicWheelCenter.y
        musicWheelDrag = CGSize(width: dx, height: dy)
        musicWheelSelection = musicWheelAction(for: musicWheelDrag)
    }

    private func musicWheelAction(for drag: CGSize) -> MusicWheelAction {
        let distance = hypot(drag.width, drag.height)
        if distance < 24 {
            return .playPause
        }
        let normalized = CGVector(dx: drag.width / distance, dy: drag.height / distance)
        var best = MusicWheelAction.playPause
        var bestScore = -Double.infinity
        for action in MusicWheelAction.ringOrder {
            let score = Double(normalized.dx * action.unitVector.dx + normalized.dy * action.unitVector.dy)
            if score > bestScore {
                best = action
                bestScore = score
            }
        }
        return best
    }

    private func executeMusicWheelSelection() {
        var action = musicWheelSelection
        let dx = musicWheelDrag.width
        let dy = musicWheelDrag.height
        if abs(dx) > 120, abs(dy) < 58 {
            action = dx > 0 ? .next : .previous
        }
        performMusicWheelAction(action)
    }

    private func performMusicWheelAction(_ action: MusicWheelAction) {
        switch action {
        case .playPause:
            dispatchMusicWheelAction(action: "music_toggle")
        case .next:
            dispatchMusicWheelAction(action: "music_next")
        case .previous:
            dispatchMusicWheelAction(action: "music_previous")
        case .volume:
            dispatchMusicWheelAction(action: "music_volume_delta", delta: 0.08)
        case .favorite:
            let title = musicWheelNowPlaying.title == "No track" ? nil : musicWheelNowPlaying.title
            dispatchMusicWheelAction(action: "music_favorite", sourceTitle: title)
        case .playlist:
            let title = musicWheelNowPlaying.title == "No track" ? nil : musicWheelNowPlaying.title
            dispatchMusicWheelAction(
                action: "music_playlist_context",
                sourceURL: musicWheelNowPlaying.sourceURL,
                sourceTitle: title
            )
        case .focus:
            let mood = musicWheelMood
            musicWheelMood = mood.next
            dispatchMusicWheelAction(action: "music_focus_mode", mood: mood.rawValue)
        case .search:
            let query = musicWheelNowPlaying.title == "No track" ? nil : musicWheelNowPlaying.title
            dispatchMusicWheelAction(action: "music_find_context", query: query, sourceTitle: query)
        }
    }

    private func dispatchMusicWheelAction(
        action: String,
        query: String? = nil,
        delta: Double? = nil,
        mood: String? = nil,
        sourceURL: String? = nil,
        sourceTitle: String? = nil
    ) {
        if store.isMusicWindow {
            store.executeMusicCommand(
                action: action,
                query: query,
                delta: delta,
                mood: mood,
                sourceURL: sourceURL,
                sourceTitle: sourceTitle
            )
            return
        }

        var payload: [AnyHashable: Any] = [
            "action": action,
            "requestID": UUID().uuidString
        ]
        if let query, !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            payload["query"] = query
        }
        if let delta {
            payload["delta"] = delta
        }
        if let mood, !mood.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            payload["mood"] = mood
        }
        if let sourceURL, !sourceURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            payload["sourceURL"] = sourceURL
        }
        if let sourceTitle, !sourceTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            payload["sourceTitle"] = sourceTitle
        }
        NotificationCenter.default.post(name: .mcvRequestMusicAction, object: nil, userInfo: payload)
    }

    private func handleMusicWheelScroll(_ event: NSEvent) {
        let raw = event.scrollingDeltaY
        guard abs(raw) > 0 else { return }
        musicWheelSelection = .volume
        let delta = Double(raw) / 220.0
        let clamped = min(max(delta, -0.15), 0.15)
        dispatchMusicWheelAction(action: "music_volume_delta", delta: clamped)
    }

    private func isEventTargetingHostWindow(_ event: NSEvent) -> Bool {
        if let hostWindowID {
            let keyWindowID = NSApp.keyWindow.map { ObjectIdentifier($0) }
            guard keyWindowID == hostWindowID else {
                return false
            }
            if let eventWindow = event.window, ObjectIdentifier(eventWindow) != hostWindowID {
                return false
            }
        }
        return true
    }

    private func refreshPointerMonitor() {
        if shouldMonitorPointerEvents {
            installPointerMonitor()
        } else {
            removePointerMonitor()
        }
    }

    private func installPointerMonitor() {
        guard pointerMonitor == nil else { return }
        pointerMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged, .scrollWheel, .leftMouseUp]
        ) { event in
            guard isEventTargetingHostWindow(event) else {
                return event
            }
            return handlePointerMonitorEvent(event)
        }
    }

    private func handlePointerMonitorEvent(_ event: NSEvent) -> NSEvent? {
        if showTabWheel {
            switch event.type {
            case .scrollWheel:
                handleTabWheelScroll(event)
                return nil
            case .leftMouseUp:
                closeTabWheel(executeSelection: true)
                return nil
            default:
                return nil
            }
        }

        if showMusicWheel {
            switch event.type {
            case .mouseMoved, .leftMouseDragged:
                updateMusicWheelSelection()
                return nil
            case .scrollWheel:
                handleMusicWheelScroll(event)
                return nil
            case .leftMouseUp:
                closeMusicWheel(executeSelection: true)
                return nil
            default:
                return nil
            }
        }

        if showLinkHintMode, event.type == .leftMouseUp {
            deactivateLinkHintMode(removeFromAllTabs: false)
            return event
        }

        if showSavedNavigator, event.type == .scrollWheel {
            handleSavedNavigatorScroll(event)
            return nil
        }

        return event
    }

    private func removePointerMonitor() {
        if let pointerMonitor {
            NSEvent.removeMonitor(pointerMonitor)
            self.pointerMonitor = nil
        }
    }

    private func installKeyboardMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.keyDown, .flagsChanged]
        ) { event in
            guard isEventTargetingHostWindow(event) else {
                return event
            }

            if showTabWheel {
                switch event.type {
                case .flagsChanged:
                    let hasCommand = event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command)
                    if !hasCommand {
                        closeTabWheel(executeSelection: true)
                    }
                    return nil
                case .keyDown:
                    switch event.keyCode {
                    case 53: // Escape
                        closeTabWheel(executeSelection: false)
                    case 123, 126: // Left, Up
                        advanceTabWheel(forward: false)
                    case 124, 125: // Right, Down
                        advanceTabWheel(forward: true)
                    case 36, 76: // Return, Keypad Enter
                        closeTabWheel(executeSelection: true)
                    default:
                        break
                    }
                    return nil
                default:
                    return nil
                }
            }

            if showMusicWheel {
                switch event.type {
                case .flagsChanged:
                    let hasCommand = event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command)
                    if !hasCommand {
                        closeMusicWheel(executeSelection: true)
                    }
                    return nil
                case .keyDown:
                    if event.keyCode == 53 { // Escape
                        closeMusicWheel(executeSelection: false)
                    }
                    return nil
                default:
                    return nil
                }
            }

            if showLinkHintMode, event.type == .keyDown {
                if handleLinkHintKeyDown(event) {
                    return nil
                }
                deactivateLinkHintMode(removeFromAllTabs: false)
            }

            if showSavedNavigator, event.type == .keyDown {
                let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
                if flags == [.control], event.keyCode == 14 { // Ctrl+E
                    return nil
                }
                if flags == [.control], event.keyCode == 15 {
                    openWindow(id: AppSceneIDs.performanceWindow)
                    return nil
                }
                if flags == [.control], event.keyCode == 13 { // Ctrl+W
                    promptResetBrowserToFirstLaunchState()
                    return nil
                }
                if flags == [.command], event.keyCode == 1 { // Cmd+S
                    closeSavedNavigator()
                    return nil
                }
                if flags == [.command], event.keyCode == 51 { // Cmd+Delete
                    deleteSelectedSavedNavigatorEntry()
                    return nil
                }
                if event.keyCode == 53 { // Escape
                    closeSavedNavigator()
                    return nil
                }
                if flags.isEmpty {
                    switch event.keyCode {
                    case 125: // Down Arrow
                        moveSavedNavigatorSelection(forward: true)
                    case 126: // Up Arrow
                        moveSavedNavigatorSelection(forward: false)
                    case 123, 51: // Left Arrow, Delete
                        goToSavedNavigatorParentFolder()
                    case 117: // Forward Delete
                        deleteSelectedSavedNavigatorEntry()
                    case 124, 36, 76: // Right Arrow, Return, Keypad Enter
                        activateSavedNavigatorSelection()
                    default:
                        break
                    }
                }
                return nil
            }

            if showFindOverlay, event.type == .keyDown {
                let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
                if event.keyCode == 53 { // Escape
                    closeFindOverlay(clearHighlights: true)
                    return nil
                }
                if flags.isEmpty {
                    switch event.keyCode {
                    case 125: // Down Arrow
                        moveFindSuggestionSelection(forward: true)
                        return nil
                    case 126: // Up Arrow
                        moveFindSuggestionSelection(forward: false)
                        return nil
                    case 36, 76: // Return, Keypad Enter
                        activateFindSuggestion()
                        return nil
                    default:
                        break
                    }
                }
            }

            if store.utilityPanel == .bookmarks,
               !store.isCommandOverlayVisible,
               event.type == .keyDown {
                let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
                if flags.isEmpty {
                    switch event.keyCode {
                    case 125: // Down Arrow
                        moveBookmarksPanelSelection(forward: true)
                        return nil
                    case 126: // Up Arrow
                        moveBookmarksPanelSelection(forward: false)
                        return nil
                    case 36, 76: // Return, Keypad Enter
                        activateBookmarksPanelSelection()
                        return nil
                    default:
                        break
                    }
                }
            }

            guard event.type == .keyDown else {
                return event
            }

            let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])

            if flags == [.control], event.keyCode == 12 { // Ctrl+Q
                showTrafficLightTuner.toggle()
                return nil
            }

            if flags == [.control], event.keyCode == 14 { // Ctrl+E
                return nil
            }

            if flags == [.control], event.keyCode == 13 { // Ctrl+W
                promptResetBrowserToFirstLaunchState()
                return nil
            }

            if flags == [.control], event.keyCode == 15 {
                openWindow(id: AppSceneIDs.performanceWindow)
                return nil
            }

            if event.keyCode == 53, showLinkHintMode { // Escape
                deactivateLinkHintMode(removeFromAllTabs: false)
                return nil
            }

            if event.keyCode == 53, showMiniMCV { // Escape
                closeMiniMCV()
                return nil
            }

            if event.keyCode == 53, store.isCommandOverlayVisible { // Escape
                store.closeCommandOverlay()
                return nil
            }

            if flags.isEmpty,
               event.keyCode == 53,
               !showWelcome,
               !showTrafficLightTuner,
               !showMiniMCV,
               !showFindOverlay,
               !showSavedNavigator,
               !showTabWheel,
               !showMusicWheel,
               !store.isCommandOverlayVisible,
               store.utilityPanel == nil {
                toggleLinkHintMode()
                return nil
            }

            if flags.isEmpty && event.keyCode == 48 { // Tab
                if focusedTarget == .smartBar {
                    store.toggleSmartBarCommandMode()
                    return nil
                }
                if focusedTarget == .commandBar && store.isCommandOverlayVisible {
                    store.toggleOverlayCommandMode()
                    return nil
                }
            }

            let overlayNavigationModifiers = flags.intersection([.command, .option, .control, .shift])
            if overlayNavigationModifiers.isEmpty,
               store.isCommandOverlayVisible {
                switch event.keyCode {
                case 125: // Down Arrow
                    store.moveCommandSuggestionSelection(forward: true)
                    return nil
                case 126: // Up Arrow
                    store.moveCommandSuggestionSelection(forward: false)
                    return nil
                default:
                    break
                }
            }

            if flags == [.option] {
                if store.openBookmarkByCustomShortcut(event: event) {
                    return nil
                }
                if event.keyCode == 3 { // F
                    store.copyCurrentPageLinkToPasteboard()
                    return nil
                }
                if event.keyCode == 15 { // R
                    store.hardReload()
                    return nil
                }
                if let bookmarkIndex = bookmarkShortcutIndex(for: event.keyCode) {
                    store.selectBookmarkShortcut(index: bookmarkIndex)
                    return nil
                }
                switch event.keyCode {
                case 123, 126: // Left, Up Arrow
                    store.cycleBookmarkTabs(forward: false)
                    return nil
                case 124, 125: // Right, Down Arrow
                    store.cycleBookmarkTabs(forward: true)
                    return nil
                default:
                    break
                }
            }

            if flags == [.command, .shift] {
                switch event.keyCode {
                case 11: // B
                    store.addCurrentTabToBookmarks()
                    return nil
                case 2: // D
                    store.duplicateSelectedTab()
                    return nil
                case 17: // T
                    store.restoreMostRecentlyClosedTab()
                    return nil
                default:
                    break
                }
            }

            if flags == [.command] {
                switch event.keyCode {
                case 31: // O
                    openMusicWheel()
                    return nil
                case 1: // S
                    toggleSavedNavigator()
                    return nil
                case 5: // G
                    openTabWheel()
                    return nil
                case 3: // F
                    openFindOverlay()
                    return nil
                case 14: // E
                    if showFindOverlay {
                        closeFindOverlay(clearHighlights: true)
                    }
                    if showSavedNavigator {
                        closeSavedNavigator()
                    }
                    closeMiniMCV()
                    store.toggleCommandOverlay(mode: .mixed)
                    focusedTarget = store.isCommandOverlayVisible ? .commandBar : nil
                    return nil
                case 37: // L
                    focusedTarget = .smartBar
                    return nil
                case 32: // U
                    if showFindOverlay {
                        closeFindOverlay(clearHighlights: true)
                    }
                    if showSavedNavigator {
                        closeSavedNavigator()
                    }
                    closeMiniMCV()
                    store.closeCommandOverlay()
                    focusedTarget = nil
                    store.focusCurrentPage()
                    return nil
                case 33: // [
                    store.moveBack()
                    return nil
                case 30: // ]
                    store.moveForward()
                    return nil
                case 15: // R
                    store.reload()
                    return nil
                case 17: // T
                    if store.isMusicWindow {
                        openWindow(id: AppSceneIDs.mainWindow)
                    } else {
                        store.openNewTab(select: true)
                    }
                    return nil
                case 13: // W
                    if store.tabs.count <= 1 {
                        let activeWindow = event.window ?? NSApp.keyWindow
                        activeWindow?.orderOut(nil)
                    } else {
                        store.closeSelectedTab()
                    }
                    return nil
                case 16: // Y
                    store.toggleHistoryPanel()
                    return nil
                case 2: // D
                    toggleBrowserChromeVisibility()
                    return nil
                case 34: // I
                    store.openDevTools()
                    return nil
                case 38: // J
                    store.openDevToolsConsole()
                    return nil
                case 11: // B
                    store.toggleBookmarksPanel()
                    return nil
                case 123, 126: // Left, Up Arrow
                    store.cycleRegularTabs(forward: false)
                    return nil
                case 124, 125: // Right, Down Arrow
                    store.cycleRegularTabs(forward: true)
                    return nil
                case 18...25, 26, 28, 29: // 1..9,0
                    if let index = tabIndex(for: event.keyCode) {
                        store.selectRegularTabShortcut(index: index)
                        return nil
                    }
                default:
                    break
                }
            }

            if focusedTarget == nil,
               !showMiniMCV,
               !showFindOverlay,
               !showSavedNavigator,
               !store.isCommandOverlayVisible,
               store.openBookmarkByCustomShortcut(event: event) {
                return nil
            }

            return event
        }
    }

    private func removeKeyboardMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }

    private func tabIndex(for keyCode: UInt16) -> Int? {
        switch keyCode {
        case 18: return 0
        case 19: return 1
        case 20: return 2
        case 21: return 3
        case 23: return 4
        case 22: return 5
        case 26: return 6
        case 28: return 7
        case 25: return 8
        case 29: return 9
        default: return nil
        }
    }

    private func bookmarkShortcutIndex(for keyCode: UInt16) -> Int? {
        switch keyCode {
        case 18: return 0
        case 19: return 1
        case 20: return 2
        case 21: return 3
        case 23: return 4
        case 22: return 5
        case 26: return 6
        case 28: return 7
        case 25: return 8
        default: return nil
        }
    }
}

private struct MCVSettingsView: View {
    @ObservedObject private var settingsStore = MCVSettingsStore.shared
    @AppStorage(AppKeys.hintsForcedEnabled) private var hintsForcedEnabled = false
    @AppStorage(AppKeys.ollamaModel) private var ollamaModel = "llama3.2:3b"

    @State private var downloadsPathDraft = ""
    @State private var tintDraft = ""
    @State private var userAgentDraft = ""
    @State private var customCommandsDraft = ""
    @State private var ollamaModelDraft = "llama3.2:3b"
    @State private var ollamaStatusText = "Not checked"
    @State private var ollamaBinaryPath = ""
    @State private var ollamaInstalledModels: [String] = []
    @State private var ollamaIsBusy = false
    @State private var ollamaDownloadProgress = 0.0
    @State private var ollamaDownloadStatus = ""
    @State private var ollamaDownloadStartedAt: Date?
    @State private var ollamaProgressTask: Task<Void, Never>?
    @State private var defaultBrowserStatusText = "Not checked"
    @State private var defaultBrowserIsMCV = false
    @State private var defaultBrowserIsBusy = false
    @State private var securityMode: SecurityModeOption = SecurityModeStore.current()
    @State private var infoMessage = ""
    @State private var webExtensionsSnapshot: [WebExtensionBundle] = []

    private var settings: MCVBrowserSettings {
        settingsStore.settings
    }

    private let ollamaRecommendedModels: [String] = [
        "llama3.2:3b",
        "llama3.1:8b",
        "qwen2.5:7b",
        "mistral:7b",
        "phi4:latest"
    ]

    private var aiModelOptions: [String] {
        var rows: [String] = []
        func appendUnique(_ value: String) {
            let model = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !model.isEmpty else { return }
            if !rows.contains(model) {
                rows.append(model)
            }
        }

        appendUnique(ollamaModel)
        for model in ollamaInstalledModels {
            appendUnique(model)
        }
        for model in ollamaRecommendedModels {
            appendUnique(model)
        }
        appendUnique(ollamaModelDraft)
        return rows
    }

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("General", systemImage: "gearshape") }
            appearanceTab
                .tabItem { Label("Appearance", systemImage: "paintbrush.pointed") }
            tabsTab
                .tabItem { Label("Tabs", systemImage: "rectangle.on.rectangle") }
            privacyTab
                .tabItem { Label("Privacy", systemImage: "hand.raised") }
            searchTab
                .tabItem { Label("Search", systemImage: "magnifyingglass") }
            performanceTab
                .tabItem { Label("Performance", systemImage: "speedometer") }
            shortcutsTab
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }
            advancedTab
                .tabItem { Label("Advanced", systemImage: "wrench.and.screwdriver") }
        }
        .frame(width: 920, height: 620)
        .onAppear {
            syncDraftsFromSettings()
            securityMode = SecurityModeStore.current()
            refreshOllamaStatus()
            refreshDefaultBrowserStatus()
            refreshWebExtensionsSnapshot()
        }
        .onDisappear {
            stopOllamaDownloadProgress()
        }
        .onReceive(NotificationCenter.default.publisher(for: .mcvSecurityModeDidChange)) { _ in
            securityMode = SecurityModeStore.current()
        }
    }

    private var generalTab: some View {
        settingsScroll {
            settingsSection("General", subtitle: "Core browser behavior.") {
                Picker("Default search engine", selection: binding(\.defaultSearchEngine)) {
                    ForEach(SearchEngineOption.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }

                Picker("New tab opens", selection: binding(\.newTabStart)) {
                    ForEach(NewTabStartOption.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }

                if settings.newTabStart == .customPage {
                    TextField("https://example.com", text: Binding(
                        get: { settings.newTabCustomURL },
                        set: { value in
                            settingsStore.update { $0.newTabCustomURL = value }
                        }
                    ))
                }

                Toggle("Restore tabs after restart", isOn: binding(\.restoreTabsOnLaunch))
                Toggle("Always show hints and onboarding", isOn: $hintsForcedEnabled)
                    .onChange(of: hintsForcedEnabled) { enabled in
                        infoMessage = enabled
                            ? "Hints are forced on for every launch"
                            : "Hints auto-hide after \(HintLifecycle.maxLaunchesWithHints) launches"
                    }

                Picker("Browser language", selection: binding(\.browserLanguage)) {
                    ForEach(BrowserLanguageOption.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }

                Divider().padding(.vertical, 2)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Default browser")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Set MCV as default app for http and https links.")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        Button(defaultBrowserIsMCV ? "MCV is default" : "Set MCV as default") {
                            setMCVAsDefaultBrowser()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(defaultBrowserIsBusy || defaultBrowserIsMCV)

                        Button("Refresh") {
                            refreshDefaultBrowserStatus()
                        }
                        .buttonStyle(.bordered)
                        .disabled(defaultBrowserIsBusy)

                        if defaultBrowserIsBusy {
                            ProgressView()
                                .controlSize(.small)
                        }

                        Spacer()
                    }

                    Text("Status: \(defaultBrowserStatusText)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(defaultBrowserIsMCV ? Color.green.opacity(0.9) : Color.secondary)
                }

                HStack {
                    Text("Downloads folder")
                    Spacer()
                    TextField("Downloads path", text: $downloadsPathDraft)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 380)
                        .onSubmit {
                            settingsStore.update { $0.downloadsFolderPath = downloadsPathDraft.trimmingCharacters(in: .whitespacesAndNewlines) }
                        }
                    Button("Choose…") { chooseDownloadsFolder() }
                }

                Divider().padding(.vertical, 2)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Configure Ollama")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Local AI runtime. Uses Ollama (llama.cpp backend) on your machine.")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)

                    Picker("Model to download", selection: $ollamaModelDraft) {
                        ForEach(ollamaRecommendedModels, id: \.self) { model in
                            Text(model).tag(model)
                        }
                    }

                    Picker("AI model for `ai` command", selection: Binding(
                        get: {
                            ollamaModel.trimmingCharacters(in: .whitespacesAndNewlines)
                        },
                        set: { value in
                            let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !normalized.isEmpty else { return }
                            ollamaModel = normalized
                            infoMessage = "AI command model: \(normalized)"
                        }
                    )) {
                        ForEach(aiModelOptions, id: \.self) { model in
                            Text(model).tag(model)
                        }
                    }

                    HStack(spacing: 8) {
                        Button("Download model") {
                            downloadOllamaModel()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(ollamaIsBusy)

                        Button("Refresh status") {
                            refreshOllamaStatus()
                        }
                        .buttonStyle(.bordered)
                        .disabled(ollamaIsBusy)

                        if ollamaIsBusy {
                            ProgressView()
                                .controlSize(.small)
                        }

                        Spacer()
                    }

                    if ollamaIsBusy && !ollamaDownloadStatus.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            ProgressView(value: min(max(ollamaDownloadProgress, 0.0), 1.0), total: 1.0)
                                .progressViewStyle(.linear)
                            HStack(spacing: 8) {
                                Text("\(ollamaDownloadStatus) \(Int(min(max(ollamaDownloadProgress, 0.0), 1.0) * 100))%")
                                if let startedAt = ollamaDownloadStartedAt {
                                    Text("Elapsed \(formatElapsedTime(since: startedAt))")
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                        }
                    }

                    Text("Active model: \(ollamaModel)")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text("Used only by Mini MCV (`ai <prompt>`).")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)

                    Text("Status: \(ollamaStatusText)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(ollamaStatusText.lowercased().contains("ready") ? Color.green.opacity(0.9) : Color.secondary)

                    if !ollamaBinaryPath.isEmpty {
                        Text("Binary: \(ollamaBinaryPath)")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(0.75))
                            .lineLimit(1)
                    }

                    if !ollamaInstalledModels.isEmpty {
                        Text("Installed: \(ollamaInstalledModels.joined(separator: ", "))")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.75))
                            .lineLimit(2)
                    }
                }
            }
        }
    }

    private var appearanceTab: some View {
        settingsScroll {
            settingsSection("Appearance", subtitle: "Theme, tint and density.") {
                Picker("Theme", selection: binding(\.appearanceTheme)) {
                    ForEach(AppearanceThemeOption.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }

                HStack {
                    Text("Interface tint")
                    Spacer()
                    TextField("#2E73E6", text: $tintDraft)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 180)
                    Button("Apply") { applyTintHex() }
                }

                sliderRow(
                    title: "Interface opacity",
                    value: Binding(
                        get: { settings.interfaceOpacity },
                        set: { newValue in
                            settingsStore.update { $0.interfaceOpacity = min(max(newValue, 0.05), 1.0) }
                        }
                    ),
                    range: 0.05...1.0
                )

                sliderRow(
                    title: "Blur",
                    value: Binding(
                        get: { settings.interfaceBlur },
                        set: { newValue in
                            settingsStore.update { $0.interfaceBlur = min(max(newValue, 0.0), 1.0) }
                        }
                    ),
                    range: 0...1
                )

                Picker("Tab style", selection: binding(\.tabStyle)) {
                    ForEach(TabStyleOption.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }

                sliderRow(
                    title: "Interface scale",
                    value: Binding(
                        get: { settings.interfaceScale },
                        set: { newValue in
                            settingsStore.update { $0.interfaceScale = min(max(newValue, 0.85), 1.25) }
                        }
                    ),
                    range: 0.85...1.25
                )
            }
        }
    }

    private var tabsTab: some View {
        settingsScroll {
            settingsSection("Tabs", subtitle: "Tab behavior and limits.") {
                Toggle("Open popup links in new tab", isOn: binding(\.openLinksInNewTab))

                Picker("New tab position", selection: binding(\.newTabPosition)) {
                    ForEach(NewTabPositionOption.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }

                Toggle("Close tab on double click", isOn: binding(\.closeTabOnDoubleClick))
                Toggle("Enable tab wheel behavior", isOn: binding(\.tabWheelEnabled))

                Stepper(value: binding(\.tabLimit), in: 1...300) {
                    Text("Tab limit: \(settings.tabLimit)")
                }
            }
        }
    }

    private var privacyTab: some View {
        settingsScroll {
            settingsSection("Privacy", subtitle: "Data and tracking controls.") {
                Picker("Security mode", selection: Binding(
                    get: { securityMode },
                    set: { applySecurityModeSelection($0) }
                )) {
                    ForEach(SecurityModeOption.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }

                Group {
                    Text("classic: normal profile cookies cache history and downloads are saved")
                    Text("safe: separate SafeProfile downloads require confirmation and clearonexit is available")
                    Text("secure: isolated SecureProfile no persistent cookies no disk cache push is off and strict network filtering is enabled")
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)

                Toggle("Block trackers (basic)", isOn: binding(\.blockTrackers))
                Toggle("Disable WebRTC", isOn: binding(\.disableWebRTC))
                Toggle("Clear data on app close", isOn: binding(\.clearDataOnClose))
                Toggle("Send Do Not Track", isOn: binding(\.doNotTrack))

                HStack {
                    Button("Clear cookies and site data now") {
                        clearWebsiteDataNow()
                    }
                    .buttonStyle(.borderedProminent)
                    Spacer()
                }
            }
        }
    }

    private var searchTab: some View {
        settingsScroll {
            settingsSection("Search / Commands", subtitle: "Cmd+E behavior and smart mode.") {
                Toggle("Enable smart search learning", isOn: binding(\.smartSearchEnabled))
                Picker("Priority", selection: binding(\.commandPriority)) {
                    ForEach(CommandPriorityOption.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                Toggle("Enable DDG bangs", isOn: binding(\.ddgBangsEnabled))
                Toggle("Enable local AI command routing", isOn: binding(\.localLLMEnabled))
                Text("Model and downloads are configured in General > Configure Ollama.")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var performanceTab: some View {
        settingsScroll {
            settingsSection("Performance", subtitle: "Memory and background behavior.") {
                Stepper(value: binding(\.processLimit), in: 1...16) {
                    Text("Process limit: \(settings.processLimit)")
                }

                Toggle("Unload inactive tabs", isOn: binding(\.unloadInactiveTabs))

                Stepper(value: binding(\.unloadAfterSeconds), in: 30...1800, step: 15) {
                    Text("Unload after: \(settings.unloadAfterSeconds) sec")
                }

                Toggle("Energy saver mode", isOn: binding(\.energySaver))
                Toggle("Enable diagnostics overlay flag", isOn: binding(\.developerMode))
            }
        }
    }

    private var shortcutsTab: some View {
        settingsScroll {
            settingsSection("Shortcuts", subtitle: "Current hotkeys and custom commands.") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Cmd+E  Command overlay")
                    Text("Ctrl+E  command center disabled")
                    Text("Cmd+L  Focus smart bar")
                    Text("Cmd+S  Saved navigator")
                    Text("Cmd+G  Tab Wheel")
                    Text("Cmd+O  Music Wheel")
                    Text("Cmd+Shift+T  Reopen closed tab")
                    Text("Cmd+Shift+B  Add bookmark")
                    Text("Cmd+Shift+D  Duplicate tab")
                    Text("Opt+F  Copy current link")
                    Text("Opt+R  Hard reload page")
                    Text("Cmd+F  Find on page")
                    Text("Cmd+I  DevTools")
                    Text("Cmd+J  Console")
                    Text("Cmd+U  Focus current page")
                    Text("Esc  Vimium-style keyboard hints on page")
                    Text("Cmd+T  New tab")
                    Text("Cmd+W  Close tab / hide window")
                    Text("ctrl+w  reset browser to first launch state temporary")
                    Text("Opt+Space  Mini MCV")
                    Text("Mini MCV  ai <prompt> (local Ollama)")
                    Text("Cmd+,  Settings")
                }
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.secondary)

                Text("Custom commands")
                    .font(.system(size: 12, weight: .semibold))
                TextEditor(text: $customCommandsDraft)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(minHeight: 160)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.white.opacity(0.10), lineWidth: 1)
                    )
                HStack {
                    Button("Save custom commands") {
                        settingsStore.update { $0.customCommandsText = customCommandsDraft }
                        infoMessage = "Custom commands saved"
                    }
                    Spacer()
                }
            }
        }
    }

    private var advancedTab: some View {
        settingsScroll {
            settingsSection("Advanced", subtitle: "Developer and network options.") {
                TextField("Custom User Agent", text: $userAgentDraft)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Button("Apply User Agent") {
                        settingsStore.update { $0.customUserAgent = userAgentDraft.trimmingCharacters(in: .whitespacesAndNewlines) }
                    }
                    Spacer()
                }

                Toggle("Developer mode", isOn: binding(\.developerMode))
                Toggle("Experimental features", isOn: binding(\.experimentalFeatures))

                Picker("Network settings", selection: binding(\.networkProfile)) {
                    ForEach(NetworkProfileOption.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }

                Divider().padding(.vertical, 2)

                VStack(alignment: .leading, spacing: 8) {
                    Text("WebExtensions (WK bridge)")
                        .font(.system(size: 13, weight: .semibold))
                    Text("MVP compatibility layer with chrome.* shim and content scripts.")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        Button("Reload list") {
                            WebExtensionManager.shared.reload()
                            refreshWebExtensionsSnapshot()
                            infoMessage = "Extensions reloaded"
                        }
                        .buttonStyle(.bordered)
                    }

                    if webExtensionsSnapshot.isEmpty {
                        Text("No extensions installed. use command: ext install <folder|url|id>")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(webExtensionsSnapshot, id: \.id) { item in
                            HStack(spacing: 8) {
                                Text(item.enabled ? "on" : "off")
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundStyle(item.enabled ? Color.green : Color.orange)
                                    .frame(width: 26)
                                Text(item.id)
                                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                    .lineLimit(1)
                                Text(item.tier.title)
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundStyle(Color.cyan)
                                    .frame(width: 20)
                                Text(item.name)
                                    .font(.system(size: 11, weight: .medium))
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                                Button(item.enabled ? "Disable" : "Enable") {
                                    _ = WebExtensionManager.shared.setEnabled(!item.enabled, extensionID: item.id)
                                    WebExtensionManager.shared.reload()
                                    refreshWebExtensionsSnapshot()
                                    infoMessage = item.enabled ? "Extension disabled: \(item.id)" : "Extension enabled: \(item.id)"
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                }

                HStack {
                    Button("Reset all settings") {
                        settingsStore.resetToDefaults()
                        _ = SecurityModeStore.set(.classic)
                        UserDefaults.standard.removeObject(forKey: AppKeys.clearOnExitHosts)
                        UserDefaults.standard.removeObject(forKey: AppKeys.secureJavaScriptRules)
                        securityMode = .classic
                        hintsForcedEnabled = false
                        ollamaModel = "llama3.2:3b"
                        syncDraftsFromSettings()
                        infoMessage = "Settings reset to defaults"
                    }
                    .buttonStyle(.bordered)
                    Spacer()
                }
            }
        }
    }

    private func settingsScroll<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                content()
                if !infoMessage.isEmpty {
                    Text(infoMessage)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.secondary)
                }
                Spacer(minLength: 4)
            }
            .padding(18)
        }
    }

    private func settingsSection<Content: View>(
        _ title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 16, weight: .bold))
            Text(subtitle)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            Divider()
            content()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
    }

    private func sliderRow(title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        HStack {
            Text(title)
            Slider(value: value, in: range)
            Text(String(format: "%.2f", value.wrappedValue))
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .frame(width: 44, alignment: .trailing)
        }
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<MCVBrowserSettings, Value>) -> Binding<Value> {
        Binding(
            get: { settingsStore.settings[keyPath: keyPath] },
            set: { newValue in
                settingsStore.update { $0[keyPath: keyPath] = newValue }
            }
        )
    }

    private func applySecurityModeSelection(_ mode: SecurityModeOption) {
        securityMode = mode
        let changed = SecurityModeStore.set(mode)
        if changed {
            infoMessage = "Security mode switched to \(mode.title). New browser window will open."
        } else {
            infoMessage = "Security mode is already \(mode.title)."
        }
    }

    private func syncDraftsFromSettings() {
        downloadsPathDraft = settings.downloadsFolderPath
        tintDraft = settings.interfaceTintHex
        userAgentDraft = settings.customUserAgent
        customCommandsDraft = settings.customCommandsText
        let trimmedModel = ollamaModel.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedModel.isEmpty {
            ollamaModelDraft = trimmedModel
        }
    }

    private func refreshOllamaStatus() {
        if ollamaIsBusy {
            return
        }
        ollamaIsBusy = true

        Task {
            let response = await Task.detached(priority: .userInitiated) { () -> (OllamaStatusInfo, [String]) in
                let status = CommandHelperClient.shared.fetchOllamaStatus()
                let installed = status.installedModels.isEmpty
                    ? CommandHelperClient.shared.fetchInstalledOllamaModels()
                    : status.installedModels
                return (status, installed)
            }.value

            let status = response.0
            let installed = response.1
            ollamaIsBusy = false
            ollamaBinaryPath = status.binaryPath
            ollamaInstalledModels = installed
            ollamaStatusText = status.statusText
            if !ollamaModelDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                ollamaModel = ollamaModelDraft.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
    }

    private func downloadOllamaModel() {
        let selected = ollamaModelDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !selected.isEmpty else {
            infoMessage = "Choose model first"
            return
        }
        if ollamaIsBusy {
            return
        }

        ollamaModel = selected
        ollamaIsBusy = true
        infoMessage = "Downloading \(selected)..."
        startOllamaDownloadProgress(model: selected)

        Task {
            let response = await Task.detached(priority: .userInitiated) { () -> (OllamaPullOutput, OllamaStatusInfo) in
                let pull = CommandHelperClient.shared.pullOllamaModel(selected)
                let status = CommandHelperClient.shared.fetchOllamaStatus()
                return (pull, status)
            }.value

            let pull = response.0
            let status = response.1
            ollamaIsBusy = false
            stopOllamaDownloadProgress()
            ollamaBinaryPath = status.binaryPath
            ollamaInstalledModels = pull.installedModels.isEmpty ? status.installedModels : pull.installedModels
            ollamaStatusText = status.statusText
            infoMessage = pull.success ? pull.message : "Download failed: \(pull.message)"
        }
    }

    private func chooseDownloadsFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Select"
        if panel.runModal() == .OK, let url = panel.url {
            downloadsPathDraft = url.path
            settingsStore.update { $0.downloadsFolderPath = url.path }
        }
    }

    private func refreshDefaultBrowserStatus() {
        let workspace = NSWorkspace.shared
        let httpURL = URL(string: "http://example.com")!
        let httpsURL = URL(string: "https://example.com")!
        let appURL = Bundle.main.bundleURL.standardizedFileURL

        let httpHandler = workspace.urlForApplication(toOpen: httpURL)?.standardizedFileURL
        let httpsHandler = workspace.urlForApplication(toOpen: httpsURL)?.standardizedFileURL
        let httpIsMCV = (httpHandler == appURL)
        let httpsIsMCV = (httpsHandler == appURL)

        defaultBrowserIsMCV = httpIsMCV && httpsIsMCV
        if defaultBrowserIsMCV {
            defaultBrowserStatusText = "MCV handles http and https"
            return
        }

        let httpName = httpHandler?.deletingPathExtension().lastPathComponent ?? "Unknown"
        let httpsName = httpsHandler?.deletingPathExtension().lastPathComponent ?? "Unknown"
        defaultBrowserStatusText = "http: \(httpName)  https: \(httpsName)"
    }

    private func refreshWebExtensionsSnapshot() {
        webExtensionsSnapshot = WebExtensionManager.shared.listBundles()
    }

    private func setMCVAsDefaultBrowser() {
        if defaultBrowserIsBusy {
            return
        }

        defaultBrowserIsBusy = true
        let appURL = Bundle.main.bundleURL
        let workspace = NSWorkspace.shared

        workspace.setDefaultApplication(at: appURL, toOpenURLsWithScheme: "http") { httpError in
            workspace.setDefaultApplication(at: appURL, toOpenURLsWithScheme: "https") { httpsError in
                DispatchQueue.main.async {
                    defaultBrowserIsBusy = false
                    if let error = httpError ?? httpsError {
                        infoMessage = "Failed to set default browser: \(error.localizedDescription)"
                    } else {
                        infoMessage = "MCV set as default browser"
                    }
                    refreshDefaultBrowserStatus()
                }
            }
        }
    }

    private func startOllamaDownloadProgress(model: String) {
        stopOllamaDownloadProgress()
        ollamaDownloadStatus = "Downloading \(model)"
        ollamaDownloadStartedAt = Date()
        ollamaDownloadProgress = 0.03
        ollamaProgressTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled {
                    break
                }
                await MainActor.run {
                    let gap = max(0.0, 0.94 - ollamaDownloadProgress)
                    let step = max(0.02, gap * 0.25)
                    ollamaDownloadProgress = min(0.94, ollamaDownloadProgress + step)
                }
            }
        }
    }

    private func stopOllamaDownloadProgress() {
        ollamaProgressTask?.cancel()
        ollamaProgressTask = nil
        ollamaDownloadStatus = ""
        ollamaDownloadStartedAt = nil
        ollamaDownloadProgress = 0.0
    }

    private func formatElapsedTime(since start: Date) -> String {
        let elapsed = max(0, Int(Date().timeIntervalSince(start)))
        let minutes = elapsed / 60
        let seconds = elapsed % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private func applyTintHex() {
        let hex = normalizeHexColor(tintDraft)
        guard let (r, g, b) = parseHexColor(hex) else {
            infoMessage = "Invalid tint color. Use #RRGGBB."
            return
        }

        settingsStore.update { $0.interfaceTintHex = hex }
        let theme = ChromeTheme(red: r, green: g, blue: b, intensity: 0.6)
        if let data = try? JSONEncoder().encode(theme.clamped) {
            UserDefaults.standard.set(data, forKey: AppKeys.chromeTheme)
        }
        NotificationCenter.default.post(name: .mcvChromeThemeDidChange, object: theme.clamped)
        infoMessage = "Tint applied"
    }

    private func normalizeHexColor(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if !value.hasPrefix("#") {
            value = "#\(value)"
        }
        return value.uppercased()
    }

    private func parseHexColor(_ raw: String) -> (Double, Double, Double)? {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") {
            value.removeFirst()
        }
        guard value.count == 6, let rgb = Int(value, radix: 16) else {
            return nil
        }
        let r = Double((rgb >> 16) & 0xFF) / 255.0
        let g = Double((rgb >> 8) & 0xFF) / 255.0
        let b = Double(rgb & 0xFF) / 255.0
        return (r, g, b)
    }

    private func clearWebsiteDataNow() {
        let mode = SecurityModeStore.current()
        let store = SecurityProfileRuntime.websiteDataStore(for: mode)
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        store.fetchDataRecords(ofTypes: types) { records in
            store.removeData(ofTypes: types, for: records) {
                DispatchQueue.main.async {
                    infoMessage = "Cookies and website data cleared"
                }
            }
        }
    }
}

private struct PerformanceSnapshot {
    let timestamp: Date
    let processCount: Int?
    let cpuPercent: Double?
    let gpuPercent: Double?
    let ramUsed: String
    let ramFree: String
    let swapUsed: String
    let swapFree: String
    let energyImpact: Double?
    let fpsApprox: Double?

    static let placeholder = PerformanceSnapshot(
        timestamp: Date(),
        processCount: nil,
        cpuPercent: nil,
        gpuPercent: nil,
        ramUsed: "--",
        ramFree: "--",
        swapUsed: "--",
        swapFree: "--",
        energyImpact: nil,
        fpsApprox: nil
    )
}

private final class PerformanceMonitorModel: ObservableObject {
    @Published private(set) var snapshot: PerformanceSnapshot = .placeholder

    private let queue = DispatchQueue(label: "mcv.performance.monitor", qos: .utility)
    private var timer: Timer?
    private var refreshInFlight = false

    func start() {
        guard timer == nil else { return }
        refresh()
        let scheduled = Timer.scheduledTimer(withTimeInterval: 2.4, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        scheduled.tolerance = 0.9
        RunLoop.main.add(scheduled, forMode: .common)
        timer = scheduled
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        refreshInFlight = false
    }

    private func refresh() {
        guard !refreshInFlight else { return }
        refreshInFlight = true
        queue.async { [weak self] in
            guard let self else { return }
            let nextSnapshot = self.collectSnapshot()
            DispatchQueue.main.async {
                self.snapshot = nextSnapshot
                self.refreshInFlight = false
            }
        }
    }

    private func collectSnapshot() -> PerformanceSnapshot {
        let topOutput = Self.runCommand(
            "/usr/bin/top",
            arguments: ["-l", "1", "-n", "768", "-stats", "pid,command,cpu,power", "-o", "power"]
        )
        let swapOutput = Self.runCommand("/usr/sbin/sysctl", arguments: ["vm.swapusage"])
        let gpuOutput = Self.runCommand("/usr/sbin/ioreg", arguments: ["-r", "-d", "1", "-c", "IOAccelerator"])

        let cpuPercent = Self.parseCPUPercent(from: topOutput)
        let gpuPercent = Self.parseGPUPercent(from: gpuOutput)
        let memory = Self.parsePhysMem(from: topOutput)
        let swap = Self.parseSwap(from: swapOutput)
        let energy = Self.parseEnergyImpact(from: topOutput)
        let processCount = Self.parseProcessCount(from: topOutput)
        let fpsApprox = Self.displayRefreshRate()

        return PerformanceSnapshot(
            timestamp: Date(),
            processCount: processCount,
            cpuPercent: cpuPercent,
            gpuPercent: gpuPercent,
            ramUsed: memory.used ?? "--",
            ramFree: memory.free ?? "--",
            swapUsed: swap.used ?? "--",
            swapFree: swap.free ?? "--",
            energyImpact: energy,
            fpsApprox: fpsApprox
        )
    }

    private static func runCommand(_ executablePath: String, arguments: [String]) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
        } catch {
            return ""
        }

        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }

    private static func parseCPUPercent(from text: String) -> Double? {
        guard let captures = firstCapturedGroups(
            pattern: #"CPU usage:\s*([0-9]+(?:\.[0-9]+)?)%\s*user,\s*([0-9]+(?:\.[0-9]+)?)%\s*sys,\s*([0-9]+(?:\.[0-9]+)?)%\s*idle"#,
            in: text
        ),
        captures.count >= 2,
        let user = Double(captures[0]),
        let system = Double(captures[1]) else {
            return nil
        }
        return min(max(user + system, 0), 100)
    }

    private static func parseProcessCount(from text: String) -> Int? {
        guard let value = firstCapturedGroups(pattern: #"Processes:\s*([0-9]+)\s+total"#, in: text)?.first else {
            return nil
        }
        return Int(value)
    }

    private static func parsePhysMem(from text: String) -> (used: String?, free: String?) {
        let used = firstCapturedGroups(
            pattern: #"PhysMem:\s*([0-9]+(?:\.[0-9]+)?(?:[A-Za-z]+)?)\s*used"#,
            in: text
        )?.first
        let free = firstCapturedGroups(
            pattern: #",\s*([0-9]+(?:\.[0-9]+)?(?:[A-Za-z]+)?)\s*unused"#,
            in: text
        )?.first
        return (used, free)
    }

    private static func parseSwap(from text: String) -> (used: String?, free: String?) {
        guard let captures = firstCapturedGroups(
            pattern: #"used\s*=\s*([0-9]+(?:\.[0-9]+)?(?:[A-Za-z]+)?)\s+free\s*=\s*([0-9]+(?:\.[0-9]+)?(?:[A-Za-z]+)?)"#,
            in: text
        ),
        captures.count >= 2 else {
            return (nil, nil)
        }
        return (captures[0], captures[1])
    }

    private static func parseGPUPercent(from text: String) -> Double? {
        let values = allCapturedDoubles(
            pattern: #"\"Device Utilization %\"\s*=\s*([0-9]+(?:\.[0-9]+)?)"#,
            in: text
        )
        guard !values.isEmpty else { return nil }
        let sum = values.reduce(0, +)
        return min(max(sum / Double(values.count), 0), 100)
    }

    private static func parseEnergyImpact(from text: String) -> Double? {
        let lines = text.components(separatedBy: .newlines)
        guard let headerIndex = lines.firstIndex(where: { $0.contains("PID") && $0.contains("POWER") }),
              headerIndex + 1 < lines.count else {
            return nil
        }

        var total: Double = 0
        var hasValue = false
        for line in lines[(headerIndex + 1)...] {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let parts = trimmed.split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard let last = parts.last, let value = Double(last) else { continue }
            total += value
            hasValue = true
        }
        return hasValue ? total : nil
    }

    private static func displayRefreshRate() -> Double? {
        guard let mode = CGDisplayCopyDisplayMode(CGMainDisplayID()) else { return nil }
        let refresh = mode.refreshRate
        guard refresh > 1 else { return nil }
        return refresh
    }

    private static func firstCapturedGroups(pattern: String, in text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return nil
        }
        let searchRange = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: searchRange),
              match.numberOfRanges > 1 else {
            return nil
        }

        var values: [String] = []
        for index in 1..<match.numberOfRanges {
            let range = match.range(at: index)
            guard range.location != NSNotFound, let swiftRange = Range(range, in: text) else {
                values.append("")
                continue
            }
            values.append(String(text[swiftRange]))
        }
        return values
    }

    private static func allCapturedDoubles(pattern: String, in text: String) -> [Double] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return []
        }
        let searchRange = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, options: [], range: searchRange).compactMap { match in
            guard match.numberOfRanges > 1 else { return nil }
            let range = match.range(at: 1)
            guard range.location != NSNotFound, let swiftRange = Range(range, in: text) else {
                return nil
            }
            return Double(String(text[swiftRange]))
        }
    }
}

private struct PerformanceTerminalView: View {
    @StateObject private var model = PerformanceMonitorModel()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            ScrollView {
                Text(terminalText)
                    .font(.system(size: 14, weight: .regular, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.95))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .textSelection(.enabled)
            }
        }
        .onAppear {
            model.start()
        }
        .onDisappear {
            model.stop()
        }
    }

    private var terminalText: String {
        let snapshot = model.snapshot
        let updated = Self.timeFormatter.string(from: snapshot.timestamp)
        let processCount = snapshot.processCount.map(String.init) ?? "--"
        let cpu = formatPercent(snapshot.cpuPercent)
        let gpu = formatPercent(snapshot.gpuPercent)
        let energy = formatNumber(snapshot.energyImpact, digits: 2)
        let fps = snapshot.fpsApprox.map { String(format: "%.0f approx", $0) } ?? "n/a"

        return [
            "mcv system monitor",
            "",
            "updated: \(updated)",
            "processes: \(processCount)",
            "",
            "CPU %: \(cpu)",
            "GPU %: \(gpu)",
            "RAM: \(snapshot.ramUsed) used, \(snapshot.ramFree) free",
            "swap: \(snapshot.swapUsed) used, \(snapshot.swapFree) free",
            "Energy Impact: \(energy)",
            "FPS: \(fps)"
        ].joined(separator: "\n")
    }

    private func formatPercent(_ value: Double?) -> String {
        formatNumber(value, digits: 1)
    }

    private func formatNumber(_ value: Double?, digits: Int) -> String {
        guard let value else { return "--" }
        return String(format: "%.\(digits)f", value)
    }
}

@main
struct SpotlightWebKitApp: App {
    @NSApplicationDelegateAdaptor(MCVAppDelegate.self) private var appDelegate

    init() {
        _ = HintLifecycle.registerLaunchIfNeeded()
    }

    var body: some Scene {
        WindowGroup("MC Browser V 1.0", id: AppSceneIDs.mainWindow) {
            BrowserRootView(windowMode: .standard)
                .frame(minWidth: 260, minHeight: 180)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            MCVWindowCommands()
        }

        Window("MCV Music Window", id: AppSceneIDs.musicWindow) {
            BrowserRootView(windowMode: .music)
                .frame(minWidth: 980, minHeight: 620)
        }
        .windowStyle(.hiddenTitleBar)

        Window("MCV Performance", id: AppSceneIDs.performanceWindow) {
            PerformanceTerminalView()
                .frame(minWidth: 220, minHeight: 140)
        }

        Settings {
            MCVSettingsView()
        }
    }
}

private final class MCVAppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        GlobalHotKeyManager.shared.registerOptionSpace {
            MiniMCVPanelController.shared.toggle()
        }
        UNUserNotificationCenter.current().delegate = self
    }

    func applicationWillTerminate(_ notification: Notification) {
        let securityMode = SecurityModeStore.current()
        if securityMode == .safe {
            let hosts = ClearOnExitStore.hosts()
            if !hosts.isEmpty {
                SecurityProfileRuntime.clearCookies(forHosts: hosts, mode: .safe)
            }
        }

        guard MCVSettingsStore.shared.settings.clearDataOnClose else { return }
        HTTPCookieStorage.shared.removeCookies(since: .distantPast)
        let store = SecurityProfileRuntime.websiteDataStore(for: securityMode)
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        store.fetchDataRecords(ofTypes: types) { records in
            store.removeData(ofTypes: types, for: records, completionHandler: {})
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}

private struct MCVWindowCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Window") {
                openWindow(id: AppSceneIDs.mainWindow)
            }
            .keyboardShortcut("n", modifiers: [.command])

            Button("New Music Window") {
                MusicWindowManager.shared.present { id in
                    openWindow(id: id)
                }
            }
            .keyboardShortcut("m", modifiers: [.command, .shift])
        }

    }
}
