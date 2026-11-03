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
    /// Whether the on-device English→Korean pack is installed (nil until checked).
    @Published private(set) var translationReady: Bool?
    /// Article open in the in-app reader (Korean mode), nil when showing the list.
    @Published var reading: Article?
    /// Translated article-body paragraphs (English → Korean), kept in memory only.
    @Published private(set) var bodyTranslations: [String: String] = [:]
    private var articleBodies: [String: [ArticleBlock]] = [:]
    /// Saved stories, most recently saved first (kept even after they leave the 30-day archive).
    @Published private(set) var bookmarks: [Article] = []
    /// Story highlighted by keyboard navigation.
    @Published var selectedLink: String?
    @Published private(set) var briefing: Briefing?
    @Published private(set) var isBriefing = false
    @Published private(set) var notifyBriefing = UserDefaults.standard.object(forKey: "notifyBriefing") as? Bool ?? true
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
        bookmarks = Self.load("bookmarks.json", as: [Article].self) ?? []
        briefing = Self.load("briefing.json", as: Briefing.self)

        // Turn on launch-at-login the first time the app runs; after that, respect the user's choice.
        if !UserDefaults.standard.bool(forKey: "didSetupLoginItem") {
            UserDefaults.standard.set(true, forKey: "didSetupLoginItem")
            setLaunchAtLogin(true)
        }

        NewsStore.shared = self
        Notifier.shared.start()
        // Ask for notification permission without holding up the first news load.
        if notifyBigNews { Task { _ = await Notifier.shared.requestPermission() } }
        Task { await checkTranslationAvailability() }
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
    private func englishBullets(_ a: Article) -> [String] {
        if let info = summaries[a.link] {
            return info.bullets ?? LocalHeuristics.sentences(info.summary, max: 3)
        }
        return LocalHeuristics.bullets(a)
    }

    func title(_ a: Article) -> String { localized(a.title) }
    /// Key points shown under the headline, in the current language.
    func bullets(_ a: Article) -> [String] { englishBullets(a).map(localized) }
    private func localized(_ s: String) -> String {
        language == .ko ? (translations[s] ?? s) : s
    }

    private func shown(_ cat: NewsCategory) -> [Article] {
        articles.filter { !isPromotional($0) && (cat == .all || category($0) == cat) }
    }

    // MARK: Search

    /// Stories from the archive and Saved whose title, key points or excerpt (English or Korean) match every word.
    func search(_ query: String, category cat: NewsCategory) -> [Article] {
        let words = query.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return [] }
        var seen = Set<String>()
        return (articles + bookmarks)
            .filter { seen.insert($0.link).inserted && !isPromotional($0) && (cat == .all || category($0) == cat) }
            .filter { a in
                let en = englishBullets(a)
                let hay = ([a.title, a.excerpt, a.source?.name ?? ""] + en
                           + ([a.title] + en).compactMap { translations[$0] })
                    .joined(separator: " ").lowercased()
                return words.allSatisfy(hay.contains)
            }
            .sorted { $0.date > $1.date }
            .prefix(100).map { $0 }
    }

    // MARK: Bookmarks

    func article(link: String) -> Article? {
        articles.first { $0.link == link } ?? bookmarks.first { $0.link == link }
    }

    func isBookmarked(_ a: Article) -> Bool { bookmarks.contains { $0.link == a.link } }

    func toggleBookmark(_ a: Article) {
        if isBookmarked(a) { bookmarks.removeAll { $0.link == a.link } } else { bookmarks.insert(a, at: 0) }
        Self.save(bookmarks, "bookmarks.json")
    }

    func saved(_ cat: NewsCategory) -> [Article] {
        bookmarks.filter { cat == .all || category($0) == cat }
    }

    // MARK: Daily briefing

    /// What the briefing card shows: Claude's briefing when there is one for today, else a simple local digest.
    struct BriefingView {
        let headline: String
        let points: [(text: String, link: String?)]
        let byClaude: Bool
    }

    func currentBriefing() -> BriefingView? {
        let ko = language == .ko
        if let b = briefing, Date().timeIntervalSince(b.generated) < 24 * 3600 {
            return BriefingView(headline: ko ? b.headlineKO : b.headlineEN,
                                points: b.points.map { (ko ? $0.ko : $0.en, $0.links.first) }, byClaude: true)
        }
        let stories = bigNews(.all) + today(.all)
        guard !stories.isEmpty else { return nil }
        let big = bigNews(.all).count
        let topCat = Dictionary(grouping: stories, by: category).max { $0.value.count < $1.value.count }?.key
        var headline = ko ? "지난 24시간 AI 소식 \(stories.count)개" : "\(stories.count) AI stories in the last 24 hours"
        if big > 0 { headline += ko ? " · 주요 뉴스 \(big)개" : " · \(big) big" }
        if let topCat { headline += ko ? " · \(topCat.name(.ko)) 소식이 가장 많아요" : " · mostly \(topCat.rawValue)" }
        let top = stories.sorted { importance($0) > importance($1) }.prefix(3)
        return BriefingView(headline: headline, points: top.map { (title($0), $0.link) }, byClaude: false)
    }

    /// Stories the briefing is written from: the last 24h, most important first.
    private func briefingStories() -> [Article] {
        let cutoff = Date().addingTimeInterval(-24 * 3600)
        return shown(.all).filter { $0.date > cutoff }
            .sorted { (importance($0), $0.date) > (importance($1), $1.date) }
            .prefix(30).map { $0 }
    }

    /// Writes a new briefing when there's none for today, or when many new stories arrived (at most every 2h).
    private func updateBriefing() async {
        guard let key = Keychain.load(), !key.isEmpty, !isBriefing else { return }
        let stories = briefingStories()
        guard stories.count >= 3 else { return }
        if let b = briefing, Calendar.current.isDateInToday(b.generated) {
            let grew = stories.count >= b.storyCount + 5 || stories.contains { isBig($0) && $0.date > b.generated }
            guard grew, Date().timeIntervalSince(b.generated) > 2 * 3600 else { return }
        }
        isBriefing = true
        defer { isBriefing = false }
        do {
            let b = try await ClaudeSummarizer(apiKey: key).briefing(stories, bullets: Dictionary(uniqueKeysWithValues: stories.map { ($0.link, englishBullets($0)) }))
            briefing = b
            Self.save(b, "briefing.json")
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func announceBriefingIfMorning() async {
        guard notifyBriefing, Calendar.current.component(.hour, from: Date()) >= 7,
              let b = currentBriefing() else { return }
        await Notifier.shared.announceBriefing(title: "☀️ " + language.t(.briefing),
                                               headline: b.headline,
                                               points: b.points.map(\.text))
    }

    func setNotifyBriefing(_ on: Bool) {
        notifyBriefing = on
        UserDefaults.standard.set(on, forKey: "notifyBriefing")
        if on { Task { _ = await Notifier.shared.requestPermission() } }
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

    /// Translation sessions hang if the language pack is missing (the download prompt can't appear
    /// from a menu bar popover), so only translate once the pack is actually installed.
    func checkTranslationAvailability() async {
        let status = await LanguageAvailability().status(from: Locale.Language(identifier: "en"),
                                                         to: Locale.Language(identifier: "ko"))
        translationReady = status == .installed
    }

    /// Opens a regular window that can show the system's language-pack download prompt.
    func downloadKoreanPack() {
        LanguagePackWindow.show(store: self)
    }

    func openTranslationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Localization-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    /// English strings on screen that don't have a Korean translation yet.
    var untranslated: [String] {
        guard language == .ko, translationReady == true else { return [] }
        var seen = Set<String>()
        return (shown(.all) + bookmarks).flatMap { [$0.title] + englishBullets($0) }
            .filter { !$0.isEmpty && translations[$0] == nil && seen.insert($0).inserted }
    }

    /// Called from the view's `.translationTask`, which supplies the on-device session
    /// (and asks the user to download the Korean language pack the first time).
    func translatePending(using session: TranslationSession) async {
        let pending = untranslated
        guard translationReady == true, !pending.isEmpty, !isTranslating else { return }
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
        let live = Set((articles + bookmarks).flatMap { [$0.title] + englishBullets($0) })
        translations = translations.filter { live.contains($0.key) }
        Self.save(translations, "translations_ko.json")
    }

    // MARK: Article reader

    /// Body of an article for the reader, fetched once per session.
    func articleBody(_ a: Article) async throws -> [ArticleBlock] {
        if let cached = articleBodies[a.link] { return cached }
        let blocks = try await ArticleExtractor.fetch(a.link)
        if !blocks.isEmpty { articleBodies[a.link] = blocks }
        return blocks
    }

    /// Translates article paragraphs a few at a time so the reader fills in progressively.
    func translateBody(_ blocks: [ArticleBlock], using session: TranslationSession) async {
        var seen = Set<String>()
        let pending = blocks.map(\.text).filter { bodyTranslations[$0] == nil && seen.insert($0).inserted }
        do {
            for start in stride(from: 0, to: pending.count, by: 6) {
                let chunk = Array(pending[start..<min(start + 6, pending.count)])
                let requests = chunk.enumerated().map {
                    TranslationSession.Request(sourceText: $0.element, clientIdentifier: String($0.offset))
                }
                for r in try await session.translations(from: requests) {
                    if let i = Int(r.clientIdentifier ?? "") { bodyTranslations[chunk[i]] = r.targetText }
                }
            }
        } catch {
            errorMessage = language.t(.translateFailed) + " (\(error.localizedDescription))"
        }
    }

    // MARK: Actions

    /// Korean mode opens the in-app reader (fully translated); English mode opens the browser.
    func open(_ a: Article) {
        markRead(a)
        if language == .ko { reading = a } else { openInBrowser(a) }
    }
    func openInBrowser(_ a: Article) {
        markRead(a)
        if let url = URL(string: a.link) { NSWorkspace.shared.open(url) }
    }
    /// The publisher's page run through Google's web translator (fallback for sites we can't read).
    func openWebTranslation(_ a: Article) {
        markRead(a)
        var c = URLComponents(string: "https://translate.google.com/translate")!
        c.queryItems = [.init(name: "sl", value: "auto"), .init(name: "tl", value: "ko"), .init(name: "u", value: a.link)]
        if let url = c.url { NSWorkspace.shared.open(url) }
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

        if translationReady != true { await checkTranslationAvailability() }
        await summarizeNew()
        await updateBriefing()
        if notifyBigNews && !fetched.isEmpty {
            await Notifier.shared.announce(bigNews(.all), text: { (self.title($0), self.bullets($0).map { "• " + $0 }.joined(separator: "\n")) },
                                           ko: language == .ko)
        }
        if !fetched.isEmpty { await announceBriefingIfMorning() }
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
            // Also redo older cached summaries that predate bullet points.
            $0.date > recent && summaries[$0.link]?.bullets == nil && !LocalHeuristics.isPromotional($0)
        }
        do {
            for start in stride(from: 0, to: pending.count, by: 8) {
                let chunk = Array(pending[start..<min(start + 8, pending.count)])
                let bodies = await fetchBodies(chunk)
                let result = try await ClaudeSummarizer(apiKey: key).summarize(chunk, bodies: bodies)
                summaries.merge(result) { _, new in new }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Full article text for summarizing (fetched in parallel; sites that block us fall back to the excerpt).
    private func fetchBodies(_ chunk: [Article]) async -> [String: String] {
        let cached = articleBodies
        let fetched = await withTaskGroup(of: (String, [ArticleBlock]).self) { group in
            for a in chunk {
                group.addTask {
                    if let c = cached[a.link] { return (a.link, c) }
                    return (a.link, (try? await ArticleExtractor.fetch(a.link)) ?? [])
                }
            }
            var out: [(String, [ArticleBlock])] = []
            for await r in group { out.append(r) }
            return out
        }
        var bodies: [String: String] = [:]
        for (link, blocks) in fetched where !blocks.isEmpty {
            articleBodies[link] = blocks
            bodies[link] = blocks.map(\.text).joined(separator: "\n\n")
        }
        return bodies
    }

    /// When an article is opened in the reader and its summary came from the RSS excerpt only,
    /// re-summarize it from the full body we just fetched.
    func improveSummary(_ a: Article, blocks: [ArticleBlock]) async {
        guard let key = Keychain.load(), !key.isEmpty, !blocks.isEmpty,
              summaries[a.link]?.fromBody != true, !LocalHeuristics.isPromotional(a) else { return }
        let body = blocks.map(\.text).joined(separator: "\n\n")
        if let result = try? await ClaudeSummarizer(apiKey: key).summarize([a], bodies: [a.link: body]) {
            summaries.merge(result) { _, new in new }
            pruneAndSaveSummaries()
        }
    }

    private func pruneAndSaveSummaries() {
        let keep = Set((articles + bookmarks).map(\.link))
        summaries = summaries.filter { keep.contains($0.key) }
        Self.save(summaries, "summaries.json")
    }

    private func persistRead() {
        UserDefaults.standard.set(Array(readLinks.suffix(1000)), forKey: "readLinks")
    }
}
