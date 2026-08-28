import Foundation

extension URL {
    /// D6: HAL keeps its own Rime directory instead of sharing ~/Library/Rime, so that an
    /// installed Squirrel and HAL cannot corrupt each other's user dictionary.
    static var rimeUserDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("HAL/Rime")
    }
}
