import AppKit
import ServiceManagement
import Darwin
import CryptoKit

private let appIdentifier = "com.yoren.neoncircuit"
private let settings = UserDefaults.standard
settings.register(defaults: ["themeEnabled": true, "wantLaunchAtLogin": false])

private struct OperationError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

private struct HelperResult {
    let arguments: [String]
    let code: Int32
    let stdout: String
    let stderr: String
    var record: [String: Any] {
        ["arguments": arguments, "exitCode": code, "stdout": stdout, "stderr": stderr]
    }
}

private enum CursorAction: String { case apply, restore }

private struct OperationResult {
    let success: Bool
    let message: String
    let log: [String: Any]
}

private struct SystemIdentity {
    let version: String
    let majorVersion: Int
    let build: String
    let architecture: String

    static func string(_ name: String) -> String {
        var length = 0
        guard sysctlbyname(name, nil, &length, nil, 0) == 0, length > 0 else { return "unknown" }
        var bytes = [CChar](repeating: 0, count: length)
        guard sysctlbyname(name, &bytes, &length, nil, 0) == 0 else { return "unknown" }
        return String(cString: bytes)
    }

    static var current: SystemIdentity {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        return SystemIdentity(version: "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)",
            majorVersion: os.majorVersion, build: string("kern.osversion"), architecture: string("hw.machine"))
    }

    var record: [String: Any] { ["version": version, "build": build, "architecture": architecture] }
}

private final class CursorController {
    let support: URL
    let backup: URL
    let helper: URL
    let theme: URL
    private let legacyBackup: URL
    private let system = SystemIdentity.current
    private let preservedNames: Set<String> = ["com.apple.coregraphics.Wait", "com.apple.coregraphics.Empty"]

    init() {
        support = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/NEON Circuit", isDirectory: true)
        backup = support.appendingPathComponent("original-cursors.cape")
        legacyBackup = support.appendingPathComponent("original-macos-27.cape")
        let contents = Bundle.main.bundleURL.appendingPathComponent("Contents", isDirectory: true)
        helper = contents.appendingPathComponent("MacOS/neon-cursorctl")
        theme = contents.appendingPathComponent("Resources/NEON-CIRCUIT.cape")
    }

    private func loadCape(_ url: URL) throws -> [String: Any] {
        let value = try PropertyListSerialization.propertyList(from: Data(contentsOf: url), options: [], format: nil)
        guard let cape = value as? [String: Any], let cursors = cape["Cursors"] as? [String: Any], !cursors.isEmpty else {
            throw OperationError(message: "Cursor file is invalid. No cursors were changed.")
        }
        return cape
    }

    private func themeNames() throws -> Set<String> {
        let cape = try loadCape(theme)
        let cursors = cape["Cursors"] as! [String: Any]
        let names = Set(cursors.keys)
        guard names.count <= 256, names.isDisjoint(with: preservedNames), names.allSatisfy({ name in
            !name.utf8.contains(0) && name.utf8.count <= 255 &&
            (name.hasPrefix("com.apple.coregraphics.") || name.hasPrefix("com.apple.cursor."))
        }) else {
            throw OperationError(message: "This theme has unsupported cursor names or changes the reserved native Wait/Empty cursors. No cursors were changed.")
        }
        return names
    }

    private func themeHash() throws -> String {
        SHA256.hash(data: try Data(contentsOf: theme)).map { String(format: "%02x", $0) }.joined()
    }

    private func requireSupportedSystem() throws {
        guard system.majorVersion == 27, system.build != "unknown", system.architecture != "unknown" else {
            throw OperationError(message: "Compatibility is unverified on macOS \(system.version) (\(system.build)), \(system.architecture). This release allows macOS 27 only and has been tested on Apple Silicon, build 26A428. No cursors were changed.")
        }
    }

    private func runHelper(_ arguments: [String]) throws -> HelperResult {
        guard FileManager.default.isExecutableFile(atPath: helper.path) else {
            throw OperationError(message: "The bundled cursor helper is missing or is not executable. Download the complete app again.")
        }
        let process = Process()
        process.executableURL = helper
        process.arguments = arguments
        let output = Pipe(), errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        try process.run()
        let readers = DispatchGroup()
        let lock = NSLock()
        var outData = Data(), errData = Data()
        readers.enter()
        DispatchQueue.global(qos: .utility).async {
            let data = output.fileHandleForReading.readDataToEndOfFile()
            lock.lock(); outData = data; lock.unlock()
            readers.leave()
        }
        readers.enter()
        DispatchQueue.global(qos: .utility).async {
            let data = errors.fileHandleForReading.readDataToEndOfFile()
            lock.lock(); errData = data; lock.unlock()
            readers.leave()
        }
        let timeout = DispatchWorkItem {
            if process.isRunning {
                process.terminate()
                DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 2) {
                    if process.isRunning { kill(process.processIdentifier, SIGKILL) }
                }
            }
        }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 45, execute: timeout)
        process.waitUntilExit()
        timeout.cancel()
        readers.wait()
        return HelperResult(arguments: arguments, code: process.terminationStatus,
            stdout: String(data: outData, encoding: .utf8) ?? "",
            stderr: String(data: errData, encoding: .utf8) ?? "")
    }

    private func requireSuccess(_ result: HelperResult, _ label: String) throws {
        guard result.code == 0 else {
            let detail = result.stderr.isEmpty ? "The helper could not verify this operation." : result.stderr
            throw OperationError(message: "\(label) failed (exit \(result.code)): \(detail.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
    }

    // The helper additionally checks decodability, raster geometry, provider
    // bytes and color-space metadata before it can restore this raw snapshot.
    private func validateRaw(_ cape: [String: Any], required: Set<String>, exactNames: Bool) throws {
        guard (cape["NeonCursorctlRawVersion"] as? NSNumber)?.intValue == 1,
              let cursors = cape["Cursors"] as? [String: Any],
              required.isSubset(of: Set(cursors.keys)),
              !exactNames || Set(cursors.keys) == required else {
            throw OperationError(message: "The original backup does not contain exactly the cursor names needed by this theme. No cursors were changed.")
        }
        for name in required {
            guard let cursor = cursors[name] as? [String: Any],
                  let frames = cursor["FrameCount"] as? NSNumber, frames.intValue >= 1, frames.intValue <= 4096,
                  frames.doubleValue == Double(frames.intValue),
                  let duration = cursor["FrameDuration"] as? NSNumber, duration.doubleValue.isFinite, duration.doubleValue >= 0,
                  let width = cursor["PointsWide"] as? NSNumber, width.doubleValue.isFinite, width.doubleValue > 0,
                  let height = cursor["PointsHigh"] as? NSNumber, height.doubleValue.isFinite, height.doubleValue > 0,
                  let hx = cursor["HotSpotX"] as? NSNumber, hx.doubleValue.isFinite,
                  let hy = cursor["HotSpotY"] as? NSNumber, hy.doubleValue.isFinite,
                  let representations = cursor["Representations"] as? [Data],
                  !representations.isEmpty, representations.allSatisfy({ !$0.isEmpty }),
                  let raw = cursor["RawRepresentations"] as? [[String: Any]],
                  raw.count == representations.count,
                  raw.allSatisfy({ ($0["Data"] as? Data)?.isEmpty == false }) else {
                throw OperationError(message: "Original backup data is invalid for \(name). No cursors were changed.")
            }
        }
    }

    private func validatedBackup(required: Set<String>) throws -> [String: Any] {
        let cape = try loadCape(backup)
        try validateRaw(cape, required: required, exactNames: true)
        guard let metadata = cape["NeonCircuitBackup"] as? [String: Any],
              (metadata["schemaVersion"] as? NSNumber)?.intValue == 1,
              let os = metadata["system"] as? [String: Any],
              let hash = metadata["themeSHA256"] as? String, hash.count == 64,
              let savedNames = metadata["cursorNames"] as? [String], Set(savedNames) == required else {
            throw OperationError(message: "The original backup is missing its provenance metadata. No cursors were changed.")
        }
        guard os["version"] as? String == system.version,
              os["build"] as? String == system.build,
              os["architecture"] as? String == system.architecture else {
            throw OperationError(message: "This original backup belongs to a different macOS version, build or architecture. Automatic apply and restore are blocked. After a macOS update, disable launch at login and restart to native cursors before rebuilding an original backup; do not capture the theme as an original.")
        }
        return cape
    }

    private func saveNewBackup(_ raw: [String: Any], required: Set<String>, provenance: String) throws {
        let fm = FileManager.default
        var cape = raw
        let cursors = raw["Cursors"] as! [String: Any]
        cape["Cursors"] = cursors.filter { required.contains($0.key) }
        cape["NeonCircuitBackup"] = ["schemaVersion": 1, "system": system.record,
            "themeSHA256": try themeHash(), "cursorNames": required.sorted(),
            "preservedNames": preservedNames.sorted(), "provenance": provenance,
            "capturedUTC": ISO8601DateFormatter().string(from: Date())]
        try validateRaw(cape, required: required, exactNames: true)
        let staging = support.appendingPathComponent(".original-\(UUID().uuidString).cape")
        defer { try? fm.removeItem(at: staging) }
        let data = try PropertyListSerialization.data(fromPropertyList: cape, format: .binary, options: 0)
        try data.write(to: staging, options: .atomic)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: staging.path)
        // Refuse to overwrite any concurrent or previously saved original.
        try fm.moveItem(at: staging, to: backup)
    }

    private func ensureBackup(required: Set<String>, records: inout [[String: Any]]) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: backup.path) {
            _ = try validatedBackup(required: required)
            return
        }
        if fm.fileExists(atPath: legacyBackup.path) {
            // This filename was used only by the original local deployment on
            // Apple Silicon, macOS 27.0 build 26A428. Never guess provenance on
            // another build; retain the existing file untouched.
            guard system.majorVersion == 27, system.build == "26A428", system.architecture == "arm64" else {
                throw OperationError(message: "A legacy original backup exists but was captured on Apple Silicon, macOS 27 build 26A428. Migration is blocked on this system. Keep that backup and restore native cursors on its original system first.")
            }
            let legacy = try loadCape(legacyBackup)
            try validateRaw(legacy, required: required, exactNames: false)
            try saveNewBackup(legacy, required: required, provenance: "legacy-local-macos-27-26A428-arm64")
            return
        }
        let alreadyThemed = try runHelper(["verify", theme.path])
        records.append(alreadyThemed.record)
        let targetNames = required.subtracting(preservedNames)
        var checkedNames = Set<String>()
        var hasThemedCursor = false
        guard alreadyThemed.code == 0 || alreadyThemed.code == 1 else {
            throw OperationError(message: "Current cursor provenance could not be checked completely. No original backup was created and no cursors were changed.")
        }
        for line in alreadyThemed.stdout.split(whereSeparator: { $0.isNewline }) {
            guard let data = String(line).data(using: .utf8),
                  let entry = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let name = entry["cursor"] as? String, targetNames.contains(name),
                  checkedNames.insert(name).inserted,
                  let verified = entry["verified"] as? NSNumber,
                  CFGetTypeID(verified) == CFBooleanGetTypeID() else {
                throw OperationError(message: "Current cursor provenance could not be checked completely. No original backup was created and no cursors were changed.")
            }
            hasThemedCursor = hasThemedCursor || verified.boolValue
        }
        guard checkedNames == targetNames else {
            throw OperationError(message: "Current cursor provenance could not be checked completely. No original backup was created and no cursors were changed.")
        }
        guard !hasThemedCursor && alreadyThemed.code == 1 else {
            throw OperationError(message: "One or more NEON Circuit cursors are already active, but the original backup is missing. Capturing even a partially applied theme would make restoration unsafe. No backup was created and no cursors were changed. Quit cursor theme apps, restart to native cursors, then choose Reapply Theme.")
        }
        let id = UUID().uuidString
        let snapshotURL = support.appendingPathComponent(".capture-\(id).cape")
        let namesURL = support.appendingPathComponent(".names-\(id).json")
        defer { try? fm.removeItem(at: snapshotURL); try? fm.removeItem(at: namesURL) }
        try JSONSerialization.data(withJSONObject: required.sorted()).write(to: namesURL, options: .atomic)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: namesURL.path)
        // snapshot reads every theme name and the reserved native names. If any
        // name is unreadable, the helper fails before it writes this snapshot.
        let snapshot = try runHelper(["snapshot", snapshotURL.path, namesURL.path])
        records.append(snapshot.record)
        try requireSuccess(snapshot, "Lossless original cursor backup")
        let raw = try loadCape(snapshotURL)
        try validateRaw(raw, required: required, exactNames: true)
        let readback = try runHelper(["verify", snapshotURL.path])
        records.append(readback.record)
        try requireSuccess(readback, "Original backup readback")
        try saveNewBackup(raw, required: required, provenance: "lossless-live-capture")
    }

    private func preservedCape(from cape: [String: Any], at url: URL) throws {
        var preserved = cape
        let cursors = cape["Cursors"] as! [String: Any]
        preserved["Cursors"] = cursors.filter { preservedNames.contains($0.key) }
        try PropertyListSerialization.data(fromPropertyList: preserved, format: .binary, options: 0)
            .write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private func persistLog(_ log: [String: Any]) throws {
        let target = support.appendingPathComponent("last-operation.json")
        let data = try JSONSerialization.data(withJSONObject: log, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: target, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
    }

    // Pure file/OS inspection. It neither launches the helper nor creates
    // files, changes cursors, settings, or login items. Raw originals and user
    // paths are deliberately excluded from shareable diagnostics.
    func diagnostics() -> [String: Any] {
        var value: [String: Any] = ["appVersion": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
            "system": system.record, "allowedOSMajorVersion": 27,
            "testedSystem": ["version": "27.0", "build": "26A428", "architecture": "arm64"],
            "backupPresent": FileManager.default.fileExists(atPath: backup.path),
            "legacyBackupPresent": FileManager.default.fileExists(atPath: legacyBackup.path),
            "helperExecutable": FileManager.default.isExecutableFile(atPath: helper.path),
            "themeEnabled": settings.bool(forKey: "themeEnabled"),
            "launchAtLoginRequested": settings.bool(forKey: "wantLaunchAtLogin"), "cursorAPIsInvoked": false]
        do {
            try requireSupportedSystem()
            guard FileManager.default.isExecutableFile(atPath: helper.path) else {
                throw OperationError(message: "The bundled cursor helper is missing or is not executable. Download the complete app again.")
            }
            let names = try themeNames(), required = names.union(preservedNames)
            value["themeSHA256"] = try themeHash()
            value["themeCursorCount"] = names.count
            value["backupCursorCountRequired"] = required.count
            value["preservedCursorNames"] = preservedNames.sorted()
            if FileManager.default.fileExists(atPath: backup.path) {
                let cape = try validatedBackup(required: required)
                let meta = cape["NeonCircuitBackup"] as! [String: Any]
                value["backupSystem"] = meta["system"]
                value["backupProvenance"] = meta["provenance"]
                value["backupThemeSHA256"] = meta["themeSHA256"]
                value["fileChecksPassed"] = true
                value["nextOperation"] = "validate compatibility, apply theme, verify theme and unchanged Wait/Empty; rollback on failure"
            } else {
                if FileManager.default.fileExists(atPath: legacyBackup.path) {
                    guard system.majorVersion == 27, system.build == "26A428", system.architecture == "arm64" else {
                        throw OperationError(message: "The legacy original backup cannot be safely migrated on this system.")
                    }
                    try validateRaw(loadCape(legacyBackup), required: required, exactNames: false)
                    value["legacyBackupMigrationAvailable"] = true
                    value["legacyBackupOrigin"] = "Original local deployment: Apple Silicon, macOS 27 build 26A428"
                }
                value["fileChecksPassed"] = true
                value["nextOperation"] = "check compatibility, reject full or partial active theme, capture and validate originals, apply, verify; rollback on failure"
            }
            value["liveCompatibilityVerified"] = false
        } catch {
            value["fileChecksPassed"] = false
            // Foundation errors may include a full path; emit only our own
            // controlled messages in compact shareable diagnostics.
            value["error"] = (error as? OperationError)?.message ?? "A required cursor file could not be read or parsed."
        }
        return value
    }

    func perform(_ action: CursorAction, reason: String) -> OperationResult {
        // A restore request also means stop the theme. Keep that intent even
        // when a missing/stale backup or helper failure prevents restoration.
        if action == .restore { settings.set(false, forKey: "themeEnabled") }
        var records: [[String: Any]] = []
        var result: [String: Any] = ["action": action.rawValue, "reason": reason,
            "timestamp": ISO8601DateFormatter().string(from: Date()), "system": system.record]
        var lockedFile: Int32 = -1
        var hasLock = false
        var mutationAttempted = false
        var preservedURL: URL?
        defer {
            if let url = preservedURL { try? FileManager.default.removeItem(at: url) }
            if hasLock { flock(lockedFile, LOCK_UN) }
            if lockedFile >= 0 { close(lockedFile) }
        }
        do {
            try requireSupportedSystem()
            let required = try themeNames().union(preservedNames)
            result["themeSHA256"] = try themeHash()
            result["themeCursorCount"] = required.count - preservedNames.count
            try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700])
            lockedFile = open(support.appendingPathComponent("operation.lock").path, O_CREAT | O_RDWR, mode_t(0o600))
            guard lockedFile >= 0, flock(lockedFile, LOCK_EX | LOCK_NB) == 0 else {
                throw OperationError(message: "Another cursor operation is running. Try again when it has finished.")
            }
            hasLock = true
            if action == .apply {
                let compatibility = try runHelper(["preflight", theme.path])
                records.append(compatibility.record)
                try requireSuccess(compatibility, "Read-only compatibility check")
            }
            if action == .apply { try ensureBackup(required: required, records: &records) }
            let originals = try validatedBackup(required: required)
            let backupCheck = try runHelper(["validate", backup.path])
            records.append(backupCheck.record)
            try requireSuccess(backupCheck, "Original backup file validation")
            let reserved = support.appendingPathComponent(".preserved-\(UUID().uuidString).cape")
            preservedURL = reserved
            try preservedCape(from: originals, at: reserved)
            if action == .apply {
                let unchanged = try runHelper(["verify", reserved.path])
                records.append(unchanged.record)
                try requireSuccess(unchanged, "Native Wait/Empty compatibility check")
            }
            let source = action == .apply ? theme : backup
            mutationAttempted = true
            let applied = try runHelper([action.rawValue, source.path])
            records.append(applied.record)
            try requireSuccess(applied, action == .apply ? "Apply theme" : "Restore original cursors")
            let verified = try runHelper(["verify", source.path])
            records.append(verified.record)
            try requireSuccess(verified, "Cursor readback")
            if action == .apply {
                let native = try runHelper(["verify", reserved.path])
                records.append(native.record)
                try requireSuccess(native, "Unchanged native Wait/Empty readback")
            }
            settings.set(action == .apply, forKey: "themeEnabled")
            result["success"] = true
            result["verified"] = true
            result["helperOperations"] = records
            var message = action == .apply ? "Theme applied and verified." : "Original cursors restored and verified."
            do { try persistLog(result) }
            catch { message += " The local operation log could not be saved." }
            return OperationResult(success: true, message: message, log: result)
        } catch {
            let primaryError = error.localizedDescription
            var message = primaryError
            settings.set(false, forKey: "themeEnabled")
            if action == .restore {
                message += "\nAutomatic application is off. Restoration has not been verified; keep the original backup and retry when the reported problem is resolved."
                result["automaticApplicationStopped"] = true
            }
            if action == .apply && mutationAttempted && hasLock {
                do {
                    let required = try themeNames().union(preservedNames)
                    _ = try validatedBackup(required: required)
                    let restored = try runHelper(["restore", backup.path])
                    records.append(restored.record)
                    try requireSuccess(restored, "Rollback to original cursors")
                    let verified = try runHelper(["verify", backup.path])
                    records.append(verified.record)
                    try requireSuccess(verified, "Rollback readback")
                    result["rollbackVerified"] = true
                    message += "\nOriginal cursors were restored. Automatic application is now off."
                } catch {
                    result["rollbackVerified"] = false
                    result["rollbackError"] = error.localizedDescription
                    message += "\nRestoration could not be verified: \(error.localizedDescription)"
                }
            }
            result["success"] = false
            result["verified"] = false
            result["error"] = primaryError
            result["helperOperations"] = records
            if hasLock {
                do { try persistLog(result) }
                catch { message += "\nThe local operation log could not be saved." }
            }
            return OperationResult(success: false, message: message, log: result)
        }
    }
}
private final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let controller = CursorController()
    private let operations = DispatchQueue(label: "com.yoren.neoncircuit.operations", qos: .userInitiated)
    private var statusItem: NSStatusItem!
    private var stateItem: NSMenuItem!
    private var applyItem: NSMenuItem!
    private var restoreItem: NSMenuItem!
    private var loginItem: NSMenuItem!
    private var quitItem: NSMenuItem!
    private var busy = false
    private var state = "Starting…"
    private var observerTokens: [NSObjectProtocol] = []
    private var wakeDebounce: DispatchWorkItem?
    private var pendingWake = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "cursorarrow.rays", accessibilityDescription: "NEON CIRCUIT")
            button.toolTip = "NEON CIRCUIT cursor theme"
        }
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self
        stateItem = NSMenuItem(title: "NEON CIRCUIT · Starting…", action: nil, keyEquivalent: "")
        stateItem.isEnabled = false
        menu.addItem(stateItem)
        menu.addItem(.separator())
        applyItem = add("Reapply Theme", #selector(applyTheme), to: menu)
        restoreItem = add("Restore Original Cursors", #selector(restoreNative), to: menu)
        loginItem = add("Launch at Login", #selector(toggleLogin), to: menu)
        menu.addItem(.separator())
        _ = add("Open Backup Folder", #selector(openBackupFolder), to: menu)
        _ = add("Getting Started / Help", #selector(showHelp), to: menu)
        quitItem = add("Quit", #selector(quit), to: menu)
        statusItem.menu = menu
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            observerTokens.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.scheduleWakeReapply()
            })
        }
        reconcileLoginIntent()
        if settings.bool(forKey: "themeEnabled") { start(.apply, reason: "launch", interactive: false) }
        else { state = "Original cursors"; refreshMenu() }
    }

    private func add(_ title: String, _ action: Selector, to menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        menu.addItem(item)
        return item
    }

    private func loginStatusText() -> String {
        switch SMAppService.mainApp.status {
        case .enabled: return ""
        case .requiresApproval: return " (approval required)"
        case .notRegistered: return settings.bool(forKey: "wantLaunchAtLogin") ? " (not registered)" : ""
        case .notFound: return " (move to Applications first)"
        @unknown default: return " (unknown status)"
        }
    }

    private func refreshMenu() {
        stateItem.title = "NEON CIRCUIT · \(state)"
        statusItem.button?.toolTip = "NEON CIRCUIT · \(state)"
        applyItem.isEnabled = !busy
        restoreItem.isEnabled = !busy
        quitItem.isEnabled = !busy
        loginItem.isEnabled = !busy
        loginItem.title = "Launch at Login\(loginStatusText())"
        loginItem.state = settings.bool(forKey: "wantLaunchAtLogin") ? .on : .off
    }

    func menuWillOpen(_ menu: NSMenu) { refreshMenu() }

    private func start(_ action: CursorAction, reason: String, interactive: Bool) {
        guard !busy else { return }
        busy = true
        state = action == .apply ? "Applying…" : "Restoring…"
        refreshMenu()
        operations.async { [weak self] in
            guard let self else { return }
            let result = self.controller.perform(action, reason: reason)
            DispatchQueue.main.async {
                self.busy = false
                self.state = result.success ? (action == .apply ? "Applied" : "Original cursors") : "Operation stopped"
                self.refreshMenu()
                if !result.success { self.alert("Cursor operation stopped", result.message) }
                else if interactive && action == .restore {
                    self.alert("Original cursors restored", "Automatic application is now off. Future launches keep the original cursors until you choose Reapply Theme.")
                } else if result.success && reason == "launch" && !settings.bool(forKey: "hasShownGettingStarted") {
                    settings.set(true, forKey: "hasShownGettingStarted")
                    self.showHelp()
                }
                if self.pendingWake {
                    self.pendingWake = false
                    self.scheduleWakeReapply()
                }
            }
        }
    }

    private func scheduleWakeReapply() {
        guard settings.bool(forKey: "themeEnabled") else { return }
        wakeDebounce?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self, settings.bool(forKey: "themeEnabled") else { return }
            if self.busy { self.pendingWake = true }
            else { self.start(.apply, reason: "wake-or-session-active", interactive: false) }
        }
        wakeDebounce = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: item)
    }

    private func reconcileLoginIntent() {
        guard settings.bool(forKey: "wantLaunchAtLogin") else { return }
        let service = SMAppService.mainApp
        guard service.status != .enabled, service.status != .requiresApproval else { return }
        do { try service.register() }
        catch { state = "Login item registration failed" }
    }

    @objc private func applyTheme() { start(.apply, reason: "menu", interactive: true) }
    @objc private func restoreNative() {
        wakeDebounce?.cancel()
        pendingWake = false
        start(.restore, reason: "menu", interactive: true)
    }
    @objc private func toggleLogin() {
        let wanted = !settings.bool(forKey: "wantLaunchAtLogin")
        settings.set(wanted, forKey: "wantLaunchAtLogin")
        do {
            if wanted { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch { alert("Login item was not changed", error.localizedDescription) }
        refreshMenu()
    }
    @objc private func openBackupFolder() {
        do {
            try FileManager.default.createDirectory(at: controller.support, withIntermediateDirectories: true)
            NSWorkspace.shared.open(controller.support)
        } catch { alert("Cannot open the backup folder", error.localizedDescription) }
    }
    @objc private func showHelp() {
        alert("NEON CIRCUIT — Getting Started",
            "Open the app to apply the bundled cursor theme. Your originals are saved locally before any changes. Use the cursor icon in the menu bar for these controls:\n\n" +
            "Restore Original Cursors restores the backup and turns off automatic application. Reapply Theme turns it on again. Quit closes the app; registered cursors remain for this session.\n\n" +
            "Launch at Login is optional and off by default. Move the app to Applications before enabling it. If approval is required, allow it in System Settings → General → Login Items.\n\n" +
            "This is a preview for macOS 27. It has been tested on Apple Silicon with build 26A428. Other macOS versions are blocked. Native Wait/Empty are preserved; apps that draw their own cursors remain in control.\n\n" +
            "The theme reapplies after wake or session activation while enabled. After a macOS build update, automatic apply and restore stop to protect your originals; see the included README before rebuilding a backup.\n\n" +
            "Use Open Backup Folder to find your original backup and the last operation log. Neither is uploaded.")
    }
    @objc private func quit() { if !busy { NSApp.terminate(nil) } }
    private func alert(_ title: String, _ message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        busy ? .terminateCancel : .terminateNow
    }
    func applicationWillTerminate(_ notification: Notification) {
        wakeDebounce?.cancel()
        for token in observerTokens { NSWorkspace.shared.notificationCenter.removeObserver(token) }
    }
}

let arguments = CommandLine.arguments
if arguments.contains("--login-status") {
    let status = SMAppService.mainApp.status
    let name: String
    switch status {
    case .enabled: name = "enabled"
    case .requiresApproval: name = "requiresApproval"
    case .notRegistered: name = "notRegistered"
    case .notFound: name = "notFound"
    @unknown default: name = "unknown"
    }
    let value: [String: Any] = ["status": name, "wantLaunchAtLogin": settings.bool(forKey: "wantLaunchAtLogin"), "themeEnabled": settings.bool(forKey: "themeEnabled")]
    let data = try! JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data("\n".utf8))
    exit(0)
}
if arguments.contains("--dry-run") || arguments.contains("--diagnostics") {
    var value = CursorController().diagnostics()
    value["mode"] = arguments.contains("--dry-run") ? "dry-run" : "diagnostics"
    if let json = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]) {
        FileHandle.standardOutput.write(json)
        FileHandle.standardOutput.write(Data("\n".utf8))
    }
    exit(value["fileChecksPassed"] as? Bool == true ? 0 : 1)
}
if arguments.contains("--headless-apply") || arguments.contains("--headless-restore") {
    let controller = CursorController()
    let action: CursorAction = arguments.contains("--headless-restore") ? .restore : .apply
    let result = controller.perform(action, reason: "headless")
    var summary = controller.diagnostics()
    summary["mode"] = "headless-\(action.rawValue)"
    summary["success"] = result.success
    summary["verified"] = result.log["verified"]
    summary["rollbackVerified"] = result.log["rollbackVerified"]
    summary["cursorAPIsInvoked"] = !((result.log["helperOperations"] as? [[String: Any]]) ?? []).isEmpty
    if let json = try? JSONSerialization.data(withJSONObject: summary, options: [.prettyPrinted, .sortedKeys]) {
        FileHandle.standardOutput.write(json)
        FileHandle.standardOutput.write(Data("\n".utf8))
    }
    // The detailed helper output stays in the private local operation log.
    if !result.success { FileHandle.standardError.write(Data("Cursor operation stopped. See the local last-operation.json file through Open Backup Folder.\n".utf8)) }
    exit(result.success ? 0 : 1)
}
let app = NSApplication.shared
if NSRunningApplication.runningApplications(withBundleIdentifier: appIdentifier)
    .contains(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
    exit(0)
}
private let delegate = AppDelegate()
app.delegate = delegate
app.run()
