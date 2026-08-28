import AppKit
import Carbon.HIToolbox
import Foundation

enum HALInstallationRequirement: Equatable, Sendable {
    case none
    case install
    case update
    case repair
    case openInstalled

    var actionTitle: String {
        switch self {
        case .none: ""
        case .install: "Install HAL"
        case .update: "Update HAL"
        case .repair: "Repair HAL"
        case .openInstalled: "Open HAL"
        }
    }
}

struct HALBundleVersion: Equatable, Sendable {
    let shortVersion: String
    let build: String

    static func read(from appURL: URL) -> Self? {
        let infoURL = appURL.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: infoURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let values = plist as? [String: Any],
              let shortVersion = values["CFBundleShortVersionString"] as? String,
              let build = values["CFBundleVersion"] as? String
        else { return nil }
        return Self(shortVersion: shortVersion, build: build)
    }
}

struct HALInstallationContext: Sendable {
    static let controlCenterBundleID = "com.hal.inputmethod.HALSettings"
    static let inputMethodBundleID = "com.hal.inputmethod.HAL"
    static let inputMethodName = "HAL_input.app"
    static let payloadName = "HAL_input.zip"

    let sourceAppURL: URL
    let payloadArchiveURL: URL
    let installedAppURL: URL
    let installedInputURL: URL
    let requirement: HALInstallationRequirement

    var isRunningFromInstalledApp: Bool {
        Self.sameLocation(sourceAppURL, installedAppURL)
    }

    init(sourceAppURL: URL, homeDirectoryURL: URL, fileManager: FileManager = .default) {
        self.sourceAppURL = sourceAppURL
        payloadArchiveURL = sourceAppURL
            .appendingPathComponent("Contents/Resources")
            .appendingPathComponent(Self.payloadName)
        installedAppURL = homeDirectoryURL
            .appendingPathComponent("Applications", isDirectory: true)
            .appendingPathComponent("HAL.app", isDirectory: true)
        installedInputURL = homeDirectoryURL
            .appendingPathComponent("Library/Input Methods", isDirectory: true)
            .appendingPathComponent(Self.inputMethodName, isDirectory: true)
        requirement = Self.resolveRequirement(
            sourceAppURL: sourceAppURL,
            payloadArchiveURL: payloadArchiveURL,
            installedAppURL: installedAppURL,
            installedInputURL: installedInputURL,
            fileManager: fileManager
        )
    }

    static func live() -> Self {
        Self(sourceAppURL: Bundle.main.bundleURL,
             homeDirectoryURL: FileManager.default.homeDirectoryForCurrentUser)
    }

    private static func resolveRequirement(
        sourceAppURL: URL,
        payloadArchiveURL: URL,
        installedAppURL: URL,
        installedInputURL: URL,
        fileManager: FileManager
    ) -> HALInstallationRequirement {
        guard fileManager.fileExists(atPath: payloadArchiveURL.path) else { return .none }

        let expectedVersion = HALBundleVersion.read(from: sourceAppURL)
        let inputIsCurrent = expectedVersion != nil
            && HALBundleVersion.read(from: installedInputURL) == expectedVersion

        if sameLocation(sourceAppURL, installedAppURL) {
            return inputIsCurrent ? .none : .repair
        }

        let appIsCurrent = expectedVersion != nil
            && HALBundleVersion.read(from: installedAppURL) == expectedVersion
        if appIsCurrent {
            return inputIsCurrent ? .openInstalled : .repair
        }
        return fileManager.fileExists(atPath: installedAppURL.path) ? .update : .install
    }

    private static func sameLocation(_ lhs: URL, _ rhs: URL) -> Bool {
        lhs.standardizedFileURL.resolvingSymlinksInPath()
            == rhs.standardizedFileURL.resolvingSymlinksInPath()
    }
}

enum HALInstallationError: LocalizedError {
    case missingPayload
    case invalidPayload
    case commandFailed(name: String, status: Int32, output: String)
    case conflictingRegistration(bundleID: String)

    var errorDescription: String? {
        switch self {
        case .missingPayload:
            "HAL's input method payload is missing. Download HAL again."
        case .invalidPayload:
            "HAL's input method payload is invalid. Download HAL again."
        case let .commandFailed(name, status, output):
            output.isEmpty ? "\(name) failed (\(status))." : "\(name) failed (\(status)): \(output)"
        case let .conflictingRegistration(bundleID):
            "Another app still owns \(bundleID)."
        }
    }
}

protocol HALInputPayloadExtracting: Sendable {
    func extract(archiveURL: URL, to directoryURL: URL) throws -> URL
}

struct HALDittoPayloadExtractor: HALInputPayloadExtracting {
    func extract(archiveURL: URL, to directoryURL: URL) throws -> URL {
        try HALCommand.run("/usr/bin/ditto", arguments: [
            "-x", "-k", archiveURL.path, directoryURL.path
        ])
        return directoryURL.appendingPathComponent(HALInstallationContext.inputMethodName,
                                                    isDirectory: true)
    }
}

enum HALBundleDeployer {
    static func deploy<Extractor: HALInputPayloadExtracting>(
        context: HALInstallationContext,
        extractor: Extractor
    ) throws {
        let fileManager = FileManager()
        guard fileManager.fileExists(atPath: context.payloadArchiveURL.path) else {
            throw HALInstallationError.missingPayload
        }

        if !context.isRunningFromInstalledApp {
            try replaceBundle(from: context.sourceAppURL,
                              at: context.installedAppURL,
                              fileManager: fileManager)
        }

        let installedPayload = context.installedAppURL
            .appendingPathComponent("Contents/Resources")
            .appendingPathComponent(HALInstallationContext.payloadName)
        guard fileManager.fileExists(atPath: installedPayload.path) else {
            throw HALInstallationError.missingPayload
        }

        let inputParent = context.installedInputURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: inputParent, withIntermediateDirectories: true)
        let extractionRoot = inputParent.appendingPathComponent(
            ".HAL-input-extract-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: extractionRoot, withIntermediateDirectories: false)
        defer { try? fileManager.removeItem(at: extractionRoot) }

        let extractedInput = try extractor.extract(archiveURL: installedPayload,
                                                   to: extractionRoot)
        guard fileManager.fileExists(atPath: extractedInput.path),
              HALBundleVersion.read(from: extractedInput)
                == HALBundleVersion.read(from: context.installedAppURL)
        else { throw HALInstallationError.invalidPayload }

        try replaceBundle(from: extractedInput,
                          at: context.installedInputURL,
                          fileManager: fileManager)
    }

    static func removeInstalledBundles(context: HALInstallationContext) throws {
        let fileManager = FileManager()
        if fileManager.fileExists(atPath: context.installedInputURL.path) {
            try fileManager.removeItem(at: context.installedInputURL)
        }
        if fileManager.fileExists(atPath: context.installedAppURL.path) {
            try fileManager.removeItem(at: context.installedAppURL)
        }
    }

    private static func replaceBundle(from source: URL, at destination: URL,
                                      fileManager: FileManager) throws {
        let parent = destination.deletingLastPathComponent()
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)

        let suffix = UUID().uuidString
        let staging = parent.appendingPathComponent(
            ".\(destination.lastPathComponent).installing-\(suffix)", isDirectory: true)
        let backup = parent.appendingPathComponent(
            ".\(destination.lastPathComponent).backup-\(suffix)", isDirectory: true)
        defer { try? fileManager.removeItem(at: staging) }

        try fileManager.copyItem(at: source, to: staging)
        guard fileManager.fileExists(atPath: destination.path) else {
            try fileManager.moveItem(at: staging, to: destination)
            return
        }

        try fileManager.moveItem(at: destination, to: backup)
        do {
            try fileManager.moveItem(at: staging, to: destination)
            try? fileManager.removeItem(at: backup)
        } catch {
            if !fileManager.fileExists(atPath: destination.path) {
                try? fileManager.moveItem(at: backup, to: destination)
            }
            throw error
        }
    }
}

enum HALLaunchServicesParser {
    static func registeredPaths(in dump: String, bundleID: String) -> [String] {
        var currentPath: String?
        var paths: [String] = []

        for line in dump.split(whereSeparator: \.isNewline) {
            let value = String(line)
            if value.hasPrefix("path:") {
                var path = value.dropFirst("path:".count)
                    .trimmingCharacters(in: .whitespaces)
                if let suffix = path.range(of: " (0x", options: .backwards) {
                    path.removeSubrange(suffix.lowerBound...)
                }
                currentPath = path
            } else if value.hasPrefix("identifier:") {
                let identifier = value.dropFirst("identifier:".count)
                    .trimmingCharacters(in: .whitespaces)
                if identifier == bundleID, let currentPath {
                    paths.append(currentPath)
                }
                currentPath = nil
            }
        }
        return Array(Set(paths)).sorted()
    }
}

enum HALCommand {
    @discardableResult
    static func run(_ executable: String, arguments: [String],
                    allowFailure: Bool = false) throws -> String {
        let process = Process()
        let outputPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        try process.run()
        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let output = String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard allowFailure || process.terminationStatus == 0 else {
            throw HALInstallationError.commandFailed(
                name: URL(fileURLWithPath: executable).lastPathComponent,
                status: process.terminationStatus,
                output: output
            )
        }
        return output
    }
}

enum HALSystemInstaller {
    private static let launchServices =
        "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

    static func install(context: HALInstallationContext) throws {
        try HALCommand.run("/usr/bin/killall", arguments: ["HAL_input"], allowFailure: true)
        try HALBundleDeployer.deploy(context: context, extractor: HALDittoPayloadExtractor())

        try HALCommand.run("/usr/bin/codesign", arguments: [
            "--verify", "--deep", "--strict", context.installedAppURL.path
        ])
        try HALCommand.run("/usr/bin/codesign", arguments: [
            "--verify", "--deep", "--strict", context.installedInputURL.path
        ])
        try HALCommand.run("/usr/bin/xattr", arguments: [
            "-dr", "com.apple.quarantine", context.installedAppURL.path
        ], allowFailure: true)
        try HALCommand.run("/usr/bin/xattr", arguments: [
            "-dr", "com.apple.quarantine", context.installedInputURL.path
        ], allowFailure: true)

        try HALCommand.run(launchServices, arguments: ["-f", context.installedAppURL.path],
                           allowFailure: true)
        try unregisterStrays(bundleID: HALInstallationContext.controlCenterBundleID,
                             allowedURL: context.installedAppURL)
        try unregisterStrays(bundleID: HALInstallationContext.inputMethodBundleID,
                             allowedURL: context.installedInputURL)

        let inputExecutable = context.installedInputURL
            .appendingPathComponent("Contents/MacOS/HAL_input").path
        try HALCommand.run(inputExecutable, arguments: ["--register"])
        try HALCommand.run("/usr/bin/open", arguments: [context.installedInputURL.path],
                           allowFailure: true)
        try assertSoleOwner(bundleID: HALInstallationContext.controlCenterBundleID,
                            allowedURL: context.installedAppURL)
        try assertSoleOwner(bundleID: HALInstallationContext.inputMethodBundleID,
                            allowedURL: context.installedInputURL)
    }

    static func uninstall(context: HALInstallationContext) throws {
        try HALCommand.run("/usr/bin/killall", arguments: ["HAL_input"], allowFailure: true)
        try HALCommand.run("/usr/bin/hidutil", arguments: [
            "property", "--set", #"{"UserKeyMapping":[]}"#
        ], allowFailure: true)
        try HALCommand.run(launchServices, arguments: ["-u", context.installedInputURL.path],
                           allowFailure: true)
        try HALCommand.run(launchServices, arguments: ["-u", context.installedAppURL.path],
                           allowFailure: true)
        try HALBundleDeployer.removeInstalledBundles(context: context)
    }

    static func launchInstalledApp(context: HALInstallationContext, newInstance: Bool) throws {
        let arguments = newInstance
            ? ["-n", context.installedAppURL.path]
            : [context.installedAppURL.path]
        try HALCommand.run("/usr/bin/open", arguments: arguments)
    }

    private static func unregisterStrays(bundleID: String, allowedURL: URL) throws {
        let dump = try HALCommand.run(launchServices, arguments: ["-dump"])
        let allowedPath = allowedURL.standardizedFileURL.resolvingSymlinksInPath().path
        for path in HALLaunchServicesParser.registeredPaths(in: dump, bundleID: bundleID) {
            let normalized = URL(fileURLWithPath: path).standardizedFileURL
                .resolvingSymlinksInPath().path
            guard normalized != allowedPath else { continue }
            try HALCommand.run(launchServices, arguments: ["-u", path], allowFailure: true)
        }
    }

    private static func assertSoleOwner(bundleID: String, allowedURL: URL) throws {
        let dump = try HALCommand.run(launchServices, arguments: ["-dump"])
        let allowedPath = allowedURL.standardizedFileURL.resolvingSymlinksInPath().path
        let hasConflict = HALLaunchServicesParser.registeredPaths(in: dump, bundleID: bundleID)
            .map { URL(fileURLWithPath: $0).standardizedFileURL.resolvingSymlinksInPath().path }
            .contains { $0 != allowedPath }
        if hasConflict {
            throw HALInstallationError.conflictingRegistration(bundleID: bundleID)
        }
    }
}

@MainActor
enum HALRunningApplicationCoordinator {
    static func stopOtherControlCenters() async {
        let currentPID = ProcessInfo.processInfo.processIdentifier
        let others = NSRunningApplication
            .runningApplications(withBundleIdentifier: HALInstallationContext.controlCenterBundleID)
            .filter { $0.processIdentifier != currentPID }
        others.forEach { $0.terminate() }

        for _ in 0..<20 {
            if others.allSatisfy(\.isTerminated) { return }
            try? await Task.sleep(for: .milliseconds(100))
        }
        others.filter { !$0.isTerminated }.forEach { $0.forceTerminate() }
    }
}

enum HALInputSourceStatus {
    static let keyboardSettingsURL =
        "x-apple.systempreferences:com.apple.Keyboard-Settings.extension?InputSources"

    /// The installed HAL input source, enabled or not. Nil until the bundle is registered.
    private static var inputSource: TISInputSource? {
        let filter = [kTISPropertyInputSourceID as String:
                        HALInstallationContext.inputMethodBundleID] as CFDictionary
        let list = TISCreateInputSourceList(filter, true)?.takeRetainedValue()
            as? [TISInputSource]
        return list?.first
    }

    static var isEnabled: Bool {
        guard let source = inputSource,
              let enabled = TISGetInputSourceProperty(source, kTISPropertyInputSourceIsEnabled)
        else { return false }
        return unsafeBitCast(enabled, to: CFBoolean.self) == kCFBooleanTrue
    }
}
