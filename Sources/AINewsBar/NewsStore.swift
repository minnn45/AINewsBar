import Foundation
import SwiftUI
import AppKit
import Translation
import ServiceManagement

/// A day of past news, split into topic groups.
struct DayGroup: Identifiable {
    let day: Date
    let groups: [(category: NewsCategory, articles: [Article])]
    var id: Date { day }
    var count: Int { groups.reduce(0) { $0 + $1.articles.count } }
}

@MainActor
final class NewsStore: ObservableObject {
    /// Lets the notification click handler reach the live store.
    static weak var shared: NewsStore?

    @Published private(set) var notifyBigNews = UserDefaults.standard.object(forKey: "notifyBigNews") as? Bool ?? true
    /// Every article seen in the last `archiveDays` days (persisted), newest first.
    @Published private(set) var articles: [Article] = []
    @Published private(set) var summaries: [String: SummaryInfo] = [:]
    @Published private(set) var translations: [String: String] = [:]   // English text → Korean
    @Published private(set) var isLoading = false
    @Published private(set) var isTranslating = false
    @Published private(set) var lastUpdated: Date?
    @Published var errorMessage: String?
    @Published private(set) var readLinks: Set<String>
    @Published private(set) var hasAPIKey = Keychain.load() != nil
    @Published private(set) var launchAtLogin = SMAppService.mainApp.status == .enabled
    @Published var language: AppLanguage {
        didSet { UserDefaults.standard.set(language.rawValue, forKey: "language") }
    }

    private let archiveDays = 30
    private let summarizeWindow: TimeInterval = 3 * 24 * 3600   // only spend API calls on recent stories
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []

    // MARK: Persistence

    private static let dir: URL = {
        let d = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AINewsBar", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()
    private static func load<T: Decodable>(_ name: String, as: T.Type) -> T? {
        guard let data = try? Data(contentsOf: dir.appendingPathComponent(name)) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
    private static func save<T: Encodable>(_ value: T, _ name: String) {
        if let data = try? JSONEncoder().encode(value) { try? data.write(to: dir.appendingPathComponent(name)) }
    }

    init() {
        readLinks = Set(UserDefaults.standard.stringArray(forKey: "readLinks") ?? [])
        language = AppLanguage(rawValue: UserDefaults.standard.string(forKey: "language") ?? "") ?? .en
        articles = Self.load("archive.json", as: [Article].self) ?? []
        summaries = Self.load("summaries.json", as: [String: SummaryInfo].self) ?? [:]
        translations = Self.load("translations_ko.json", as: [String: String].self) ?? [:]

        // Turn on launch-at-login the first time the app runs; after that, respect the user's choice.
        if !UserDefaults.standard.bool(forKey: "didSetupLoginItem") {
            UserDefaults.standard.set(true, forKey: "didSetupLoginItem")
            setLaunchAtLogin(true)
        }

        NewsStore.shared = self
        Notifier.shared.start()
        // Ask for notification permission without holding up the first news load.
        if notifyBigNews { Task { _ = await Notifier.shared.requestPermission() } }
        Task { await refresh() }

        // Keep the list current: every 30 min, at midnight, and when the Mac wakes up.
        timer = Timer.scheduledTimer(withTimeInterval: 30 * 60, repeats: true) { [weak self] _ in
            Task { await self?.refresh() }
        }
        let refreshNow: (Notification) -> Void = { [weak self] _ in Task { await self?.refresh() } }
        observers.append(NotificationCenter.default.addObserver(
            forName: .NSCalendarDayChanged, object: nil, queue: .main, using: refreshNow))
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main, using: refreshNow))
    }

    // MARK: Derived

    func isPromotional(_ a: Article) -> Bool {
        LocalHeuristics.isPromotional(a) || (summaries[a.link]?.promotional ?? false)
    }
    func category(_ a: Article) -> NewsCategory {
        summaries[a.link]?.category ?? LocalHeuristics.category(a)
    }
    private func englishSummary(_ a: Article) -> String {
        summaries[a.link]?.summary ?? LocalHeuristics.shortSummary(a)
    }

    func title(_ a: Article) -> String { localized(a.title) }
    func summary(_ a: Article) -> String { localized(englishSummary(a)) }
    private func localized(_ s: String) -> String {
        language == .ko ? (translations[s] ?? s) : s
    }

    private func shown(_ cat: NewsCategory) -> [Article] {
        articles.filter { !isPromotional($0) && (cat == .all || category($0) == cat) }
    }

    // MARK: Big news

    private static let majorEntities = try! NSRegularExpression(pattern:
        "\\b(openai|deepmind|google|gemini|gpt|chatgpt|sora|codex|anthropic|claude|meta|llama|nvidia|microsoft|copilot|apple|xai|grok|mistral|deepseek|qwen|alibaba)\\b",
        options: .caseInsensitive)
    private static let launchWords = try! NSRegularExpression(pattern:
        "\\b(introduc\\w*|launch\\w*|unveil\\w*|releas\\w*|announc\\w*|debut\\w*|(next|new)( \\w+)? (frontier )?model|next[- ]gen\\w*|open[- ](weight|source)\\w*|acquir\\w*|acquisition|ipo|raises|valuation|breakthrough)\\b",
        options: .caseInsensitive)
    /// Product-style names like "Genie 4", "GPT-6.1", "Gemini 4 Carbon" – used to spot one story covered by several sources.
    private static let productName = try! NSRegularExpression(pattern:
        "\\b[A-Z][A-Za-z]+[- ]?\\d+(\\.\\d+)?\\b")

    private func storyKeys(_ a: Article) -> [String] {
        let r = NSRange(a.title.startIndex..., in: a.title)
        return Self.productName.matches(in: a.title, range: r).compactMap {
            Range($0.range, in: a.title).map { a.title[$0].lowercased().replacingOccurrences(of: "-", with: " ") }
        }
    }

    /// How many distinct sources mention each product name (recomputed when articles change).
    private var coverage: [String: Int] {
        let version = "\(articles.count)|\(articles.first?.link ?? "")"
        if let c = coverageCache, c.0 == version { return c.1 }
        var sourcesByKey: [String: Set<String>] = [:]
        for a in articles { for k in storyKeys(a) { sourcesByKey[k, default: []].insert(a.sourceID) } }
        let result = sourcesByKey.mapValues(\.count)
        coverageCache = (version, result)
        return result
    }
    private var coverageCache: (String, [String: Int])?

    func importance(_ a: Article) -> Int {
        let r = NSRange(a.title.startIndex..., in: a.title)
        var score = 0
        if a.source?.official == true { score += 2 }
        if Self.majorEntities.firstMatch(in: a.title, range: r) != nil { score += 1 }
        if Self.launchWords.firstMatch(in: a.title, range: r) != nil { score += 2 }
        if storyKeys(a).contains(where: { (coverage[$0] ?? 0) >= 2 }) { score += 1 }
        if summaries[a.link]?.major == true { score += 3 }
        return score
    }

    func isBig(_ a: Article) -> Bool { importance(a) >= 4 }

    /// Pinned headline stories from the last 5 days, one per story, official posts preferred.
    func bigNews(_ cat: NewsCategory) -> [Article] {
        let cutoff = Date().addingTimeInterval(-5 * 24 * 3600)
        let candidates = shown(cat).filter { $0.date > cutoff && isBig($0) }
            .sorted { (importance($0), $0.source?.official == true ? 1 : 0, $0.date)
                    > (importance($1), $1.source?.official == true ? 1 : 0, $1.date) }
        var usedKeys = Set<String>(), out: [Article] = []
        for a in candidates {
            let keys = storyKeys(a)
            if keys.contains(where: usedKeys.contains) { continue }
            usedKeys.formUnion(keys)
            out.append(a)
            if out.count == 6 { break }
        }
        return out.sorted { $0.date > $1.date }
    }

    /// Stories from the last 24 hours (excluding ones already pinned under Big news).
    func today(_ cat: NewsCategory) -> [Article] {
        let cutoff = Date().addingTimeInterval(-24 * 3600)
        let pinned = Set(bigNews(cat).map(\.link))
        return shown(cat).filter { $0.date > cutoff && !pinned.contains($0.link) }
    }

    /// Older stories, grouped by calendar day and then by topic.
    func pastDays(_ cat: NewsCategory) -> [DayGroup] {
        let cutoff = Date().addingTimeInterval(-24 * 3600)
        let cal = Calendar.current
        let byDay = Dictionary(grouping: shown(cat).filter { $0.date <= cutoff }) { cal.startOfDay(for: $0.date) }
        return byDay.keys.sorted(by: >).map { day in
            let byCat = Dictionary(grouping: byDay[day]!) { category($0) }
            let groups = NewsCategory.allCases.compactMap { c in
                byCat[c].map { arts in (c, arts.sorted { (isBig($0) ? 1 : 0, $0.date) > (isBig($1) ? 1 : 0, $1.date) }) }
            }
            return DayGroup(day: day, groups: groups)
        }
    }

    var unreadCount: Int { (bigNews(.all) + today(.all)).filter { !readLinks.contains($0.link) }.count }

    // MARK: Translation

    /// English strings on screen that don't have a Korean translation yet.
    var untranslated: [String] {
        guard language == .ko else { return [] }
        var seen = Set<String>()
        return shown(.all).flatMap { [$0.title, englishSummary($0)] }
            .filter { !$0.isEmpty && translations[$0] == nil && seen.insert($0).inserted }
    }

    /// Called from the view's `.translationTask`, which supplies the on-device session
    /// (and asks the user to download the Korean language pack the first time).
    func translatePending(using session: TranslationSession) async {
        let pending = untranslated
        guard !pending.isEmpty, !isTranslating else { return }
        isTranslating = true
        defer { isTranslating = false }
        do {
            for start in stride(from: 0, to: pending.count, by: 40) {
                let chunk = pending[start..<min(start + 40, pending.count)]
                let requests = chunk.enumerated().map {
                    TranslationSession.Request(sourceText: $0.element, clientIdentifier: String($0.offset))
                }
                for r in try await session.translations(from: requests) {
                    if let i = Int(r.clientIdentifier ?? "") { translations[chunk[chunk.startIndex + i]] = r.targetText }
                }
            }
        } catch {
            errorMessage = language.t(.translateFailed) + " (\(error.localizedDescription))"
        }
        pruneAndSaveTranslations()
    }

    private func pruneAndSaveTranslations() {
        let live = Set(articles.flatMap { [$0.title, englishSummary($0)] })
        translations = translations.filter { live.contains($0.key) }
        Self.save(translations, "translations_ko.json")
    }

    // MARK: Actions

    func open(_ a: Article) {
        markRead(a)
        if let url = URL(string: a.link) { NSWorkspace.shared.open(url) }
    }
    func markRead(_ a: Article) { readLinks.insert(a.link); persistRead() }
    func markAllRead() { readLinks.formUnion(articles.map(\.link)); persistRead() }

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            errorMessage = (language == .ko ? "로그인 시 실행 설정 실패: " : "Couldn't change login item: ")
                + error.localizedDescription
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func setAPIKey(_ key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        Keychain.save(trimmed)
        hasAPIKey = !trimmed.isEmpty
        if hasAPIKey { Task { await refresh() } }
    }

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let fetched = await withTaskGroup(of: [Article].self) { group in
            for src in FeedSource.all {
                group.addTask {
                    var req = URLRequest(url: src.url, timeoutInterval: 20)
                    req.setValue("Mozilla/5.0 (Macintosh) AINewsBar/1.0", forHTTPHeaderField: "User-Agent")
                    guard let (data, _) = try? await URLSession.shared.data(for: req) else { return [] }
                    return FeedParser.parse(data, sourceID: src.id)
                }
            }
            var all: [Article] = []
            for await batch in group { all += batch }
            return all
        }

        if fetched.isEmpty {
            errorMessage = language.t(.offline)
        } else {
            lastUpdated = Date()
        }

        // Merge into the archive: new feed items win, old ones are kept until they age out.
        let cutoff = Date().addingTimeInterval(-Double(archiveDays) * 24 * 3600)
        var seenLinks = Set<String>(), seenTitles = Set<String>()
        articles = (fetched + articles)
            .filter { $0.date > cutoff }
            .filter { seenLinks.insert($0.link).inserted && seenTitles.insert($0.title.lowercased()).inserted }
            .sorted { $0.date > $1.date }
        Self.save(articles, "archive.json")

        await summarizeNew()
        if notifyBigNews && !fetched.isEmpty {
            await Notifier.shared.announce(bigNews(.all), text: { (self.title($0), self.summary($0)) },
                                           ko: language == .ko)
        }
    }

    func setNotifyBigNews(_ on: Bool) {
        notifyBigNews = on
        UserDefaults.standard.set(on, forKey: "notifyBigNews")
        guard on else { return }
        Task {
            if await !Notifier.shared.requestPermission() {
                errorMessage = language == .ko
                    ? "알림이 꺼져 있어요. 시스템 설정 → 알림 → AI News에서 허용해 주세요."
                    : "Notifications are blocked. Allow them in System Settings → Notifications → AI News."
            }
        }
    }

    func markRead(link: String) { readLinks.insert(link); persistRead() }

    private func summarizeNew() async {
        defer { pruneAndSaveSummaries() }
        guard let key = Keychain.load(), !key.isEmpty else { return }
        let recent = Date().addingTimeInterval(-summarizeWindow)
        let pending = articles.filter {
            $0.date > recent && summaries[$0.link] == nil && !LocalHeuristics.isPromotional($0)
        }
        do {
            for start in stride(from: 0, to: pending.count, by: 15) {
                let chunk = Array(pending[start..<min(start + 15, pending.count)])
                let result = try await ClaudeSummarizer(apiKey: key).summarize(chunk)
                summaries.merge(result) { _, new in new }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func pruneAndSaveSummaries() {
        let keep = Set(articles.map(\.link))
        summaries = summaries.filter { keep.contains($0.key) }
        Self.save(summaries, "summaries.json")
    }

    private func persistRead() {
        UserDefaults.standard.set(Array(readLinks.suffix(1000)), forKey: "readLinks")
    }
}
