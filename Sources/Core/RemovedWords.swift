import Foundation

/// The words the user took out of the candidate list (D29). InputSession hides them on every
/// page, and the patch writer hands them to librime as `translator/dictionary_exclude` so
/// they stay out of sentences too.
///
/// Unlike Settings.json this file has two writers: the input method adds a word on Shift+⌫
/// and the control center restores one. Both re-read the file right before writing, so
/// neither drops the other's change.
enum RemovedWords {
    /// What a missing file means, so a fresh install starts without these.
    static let defaults = [
        "拜登", "白嫖", "百事", "白丝", "爆表", "爆肝", "宝箱", "本王", "变身", "沉眠",
        "辰星", "锤石", "打怪", "呆毛", "灯神", "地神", "敌袭", "掉帧", "法鸡", "法阵",
        "废柴", "腐国", "福利姬", "复联", "符箓", "钢剑", "杠精", "钩拳", "鬼厉", "鬼斯",
        "海狗", "灰机", "剑姬", "结界", "禁断", "开服", "开盒", "氪金", "琅琊榜", "雷剧",
        "泪目", "魔都", "男主", "棋士", "乔巴", "忍法", "神剧", "神友", "锁甲", "舔狗",
        "同人", "汪星", "位面", "五杀", "仙六", "仙魔", "仙缘", "献忠", "写本", "星爷",
        "凶魂", "杨迪", "妖界", "妖族", "蚁人", "异色", "银魂", "御姐", "原神", "悦刻",
        "甄姬", "正太", "中二", "祖安"
    ]

    static var url: URL {
        SettingsStore.directory.appendingPathComponent("RemovedWords.json")
    }

    /// Read on every keystroke, so a load costs one stat unless the file changed.
    private struct CacheEntry {
        let url: URL
        let modified: Date
        let size: Int
        let words: [String]
    }

    /// Main-thread only, the same contract as `SettingsStore`'s cache.
    nonisolated(unsafe) private static var cache: CacheEntry?

    static func load() -> [String] {
        let url = url
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let modified = attributes[.modificationDate] as? Date,
              let size = attributes[.size] as? Int else {
            cache = nil
            return defaults
        }
        if let cache, cache.url == url, cache.modified == modified, cache.size == size {
            return cache.words
        }
        let words: [String]
        do {
            words = try JSONDecoder().decode([String].self, from: Data(contentsOf: url))
        } catch {
            SettingsStore.log.error("RemovedWords.json is unreadable, using defaults: \(error.localizedDescription, privacy: .public)")
            words = defaults
        }
        cache = CacheEntry(url: url, modified: modified, size: size, words: words)
        return words
    }

    static func add(_ word: String) {
        let words = load()
        guard !words.contains(word) else { return }
        save(words + [word])
    }

    static func restore(_ word: String) {
        save(load().filter { $0 != word })
    }

    private static func save(_ words: [String]) {
        do {
            let data = try JSONEncoder().encode(words)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            cache = nil
        } catch {
            SettingsStore.log.error("could not save RemovedWords.json: \(error.localizedDescription, privacy: .public)")
        }
    }
}
