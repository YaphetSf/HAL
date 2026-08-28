import AppKit

/// What a mode switch plays (D26) — one choice, not a skin switch plus an artwork switch.
/// `miku` is the artwork HAL ships with and starts on, `custom` is the user's own import,
/// and `serve` is the original tennis animation, which brings its own ball.
enum ModeFeedbackChoice: Equatable, Codable {
    case miku
    case serve
    case custom(String)

    var customName: String? {
        if case .custom(let name) = self { return name }
        return nil
    }

    /// Stored in Settings.json as `miku` / `tennis` / `file:<name>`, so the settings file
    /// stays readable and hand-editable (D21). Anything unrecognized is the default.
    private static let filePrefix = "file:"

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        switch raw {
        case "serve":
            self = .serve
        case let raw where raw.hasPrefix(Self.filePrefix):
            self = .custom(String(raw.dropFirst(Self.filePrefix.count)))
        default:
            self = .miku
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .miku: try container.encode("miku")
        case .serve: try container.encode("serve")
        case .custom(let name): try container.encode(Self.filePrefix + name)
        }
    }
}

/// The user's own mode-feedback artwork (D26). The control center imports it, the input
/// method reads it, and both go through this one type so the file layout and — more
/// importantly — the fallback story exist in exactly one place.
enum ModeFeedbackArtwork {
    /// The panel draws the artwork at 72pt. Anything bigger than this is a poster the input
    /// method has no business holding in memory, so it is refused at import time.
    static let maximumByteCount = 4 * 1024 * 1024
    /// Imports are kept: each one lands as custom1, custom2, … and the user picks between
    /// them (D26). The number is what the control center shows as its name.
    static let customPrefix = "custom"

    static var directory: URL {
        SettingsStore.directory.appendingPathComponent("Artwork")
    }

    /// Settings.json holds a bare file name, never a path: a hand-edited settings file must
    /// not be able to point the input method at an arbitrary place on disk.
    static func url(named name: String) -> URL? {
        guard !name.isEmpty, !name.hasPrefix("."), !name.contains("/") else { return nil }
        return directory.appendingPathComponent(name)
    }

    /// Every artwork the user has imported, oldest number first. They stay until removed:
    /// switching to Miku or the serve is not a reason to throw someone's picture away.
    static var installedNames: [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? [])
            .compactMap { name in index(of: name).map { (name, $0) } }
            .sorted { $0.1 < $1.1 }
            .map(\.0)
    }

    /// `custom3.svg` -> 3. nil for anything that is not one of ours.
    static func index(of name: String) -> Int? {
        let stem = (name as NSString).deletingPathExtension
        guard stem.hasPrefix(customPrefix) else { return nil }
        return Int(stem.dropFirst(customPrefix.count))
    }

    enum ImportError: Error, Equatable {
        case tooLarge
        case unreadable
    }

    /// Copies the file into the artwork directory and returns the name to store in
    /// Settings.json, replacing any earlier import. The copy is the point: the original
    /// usually lives in Downloads, where it gets moved or deleted.
    @discardableResult
    static func install(from source: URL) throws -> String {
        // Size first, from the file system: dropping a 2 GB file should not read it.
        let declaredSize = (try? source.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard declaredSize <= maximumByteCount else { throw ImportError.tooLarge }
        let data = try Data(contentsOf: source)
        guard data.count <= maximumByteCount else { throw ImportError.tooLarge }
        guard let image = NSImage(data: data), image.size.width > 0, image.size.height > 0 else {
            throw ImportError.unreadable
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let suffix = source.pathExtension.lowercased()
        let taken = Set(installedNames.compactMap(index(of:)))
        let number = (1...).first { !taken.contains($0) } ?? taken.count + 1
        let stem = "\(customPrefix)\(number)"
        let name = suffix.isEmpty ? stem : "\(stem).\(suffix)"
        try data.write(to: directory.appendingPathComponent(name), options: .atomic)
        cache = nil
        return name
    }

    /// Removing one is the user's call; nothing else deletes an import.
    static func remove(named name: String) {
        guard let url = url(named: name) else { return }
        try? FileManager.default.removeItem(at: url)
        cache = nil
    }

    /// nil means "draw the serve skin's own ball": every way a file can fail — missing,
    /// moved, or no longer decodable — lands here, and none of them is an error the input
    /// method has to handle.
    static func image(for choice: ModeFeedbackChoice) -> NSImage? {
        switch choice {
        case .serve:
            return nil
        case .miku:
            return BrandMark.image
        case .custom(let name):
            return url(named: name).flatMap(load)
        }
    }

    private static func load(_ url: URL) -> NSImage? {
        let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey])
            .contentModificationDate
        if let cache, cache.url == url, cache.modified == modified { return cache.image }
        guard let data = try? Data(contentsOf: url), let image = NSImage(data: data) else {
            cache = nil
            return nil
        }
        cache = Cached(url: url, modified: modified, image: image)
        return image
    }

    private struct Cached {
        let url: URL
        let modified: Date?
        let image: NSImage
    }

    /// Touched from the main thread only: the panel draws there and so does the control
    /// center. Same rationale as SettingsStore.directoryOverride.
    nonisolated(unsafe) private static var cache: Cached?
}
