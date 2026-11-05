import SwiftUI
import AppKit
import Translation

@main
struct AINewsBarApp: App {
    @StateObject private var store = NewsStore()

    init() {
        // Debug: `AINewsBar --snapshot out.png [ko] [reader]` renders the popover offscreen and quits.
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count {
            Snapshot.schedule(path: args[i + 1], ko: args.contains("ko"), reader: args.contains("reader"),
                              height: args.contains("tall") ? 1500 : 600)
        }
    }

    var body: some Scene {
        MenuBarExtra {
            ContentView()
                .environmentObject(store)
                .environment(\.colorScheme, .light)
                .environment(\.locale, store.language.locale)
        } label: {
            Image(systemName: store.unreadCount > 0 ? "sparkles.rectangle.stack.fill" : "sparkles.rectangle.stack")
        }
        .menuBarExtraStyle(.window)
    }
}

enum Tab { case today, past, saved }

// MARK: - Root

struct ContentView: View {
    @EnvironmentObject var store: NewsStore
    @StateObject private var ui = UIModel()
    @State private var translationConfig: TranslationSession.Configuration?

    private var lang: AppLanguage { store.language }

    var body: some View {
        VStack(spacing: 0) {
            header
            if ui.showSettings {
                SettingsView(isPresented: $ui.showSettings)
            } else if let article = store.reading {
                ArticleReader(article: article)
                    .id(article.link)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                if ui.searching {
                    SearchBar(ui: ui, placeholder: lang.t(.searchPlaceholder), closeLabel: lang == .ko ? "닫기" : "Close")
                } else {
                    searchPlaceholder
                    tabs
                }
                chips
                if lang == .ko && store.translationReady == false { LanguagePackBanner() }
                Group {
                    if ui.searching {
                        SearchList(query: ui.query, category: ui.category)
                    } else {
                        switch ui.tab {
                        case .today: TodayList(category: ui.category)
                        case .past: PastList(category: ui.category)
                        case .saved: SavedList(category: ui.category)
                        }
                    }
                }
                .frame(maxHeight: .infinity)
                footer
            }
        }
        .frame(width: 400, height: Snapshot.height)
        .background(Color.white)
        // On-device English → Korean translation (Apple Translation framework).
        .translationTask(translationConfig) { session in
            await store.translatePending(using: session)
        }
        .onAppear {
            ui.attach(store)   // keyboard shortcuts
            requestTranslation()
            // Pick up a pack the user installed from System Settings since we last checked.
            if store.translationReady != true { Task { await store.checkTranslationAvailability() } }
        }
        .onChange(of: store.language) {
            if store.translationReady != true { Task { await store.checkTranslationAvailability() } }
            requestTranslation()
        }
        .onChange(of: store.translationReady) { requestTranslation() }
        .onChange(of: store.untranslated.count) { requestTranslation() }
    }

    private func requestTranslation() {
        guard store.language == .ko, store.translationReady == true,
              !store.untranslated.isEmpty, !store.isTranslating else { return }
        if translationConfig == nil {
            translationConfig = .init(source: Locale.Language(identifier: "en"),
                                      target: Locale.Language(identifier: "ko"))
        } else {
            translationConfig?.invalidate()
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(Pastel.lavender)
                Image(systemName: "sparkles").font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Pastel.ink.opacity(0.8))
            }
            .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 1) {
                Text(lang.t(.appTitle)).font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Pastel.ink)
                Text(subtitle).font(.system(size: 11)).foregroundStyle(Pastel.subInk)
            }
            Spacer()
            LanguageToggle()
            IconButton(system: "arrow.clockwise", spinning: store.isLoading) {
                Task { await store.refresh() }
            }
            .help(lang == .ko ? "새로고침 (R)" : "Refresh (R)")
            IconButton(system: ui.showSettings ? "xmark" : "gearshape") {
                withAnimation(.easeInOut(duration: 0.15)) { ui.showSettings.toggle() }
            }
        }
        .onChange(of: store.language) {
            // The reader is the Korean-mode way of opening stories; English goes back to the list.
            if store.language == .en { withAnimation(.easeInOut(duration: 0.15)) { store.reading = nil } }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }

    private var subtitle: String {
        if store.isLoading { return lang.t(.updating) }
        if store.isTranslating { return lang.t(.translating) }
        guard let d = store.lastUpdated else { return lang.t(.loading) }
        let time = d.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(lang.locale))
        let unread = store.unreadCount
        return "\(lang.t(.updated)) \(time)" + (unread > 0 ? " · \(unread) \(lang.t(.new))" : "")
    }

    // MARK: Search field, tabs & chips

    /// Looks like the search field; clicking it (or ⌘F) switches to the real one.
    private var searchPlaceholder: some View {
        Button { ui.openSearch() } label: {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Pastel.subInk)
                Text(lang.t(.searchPlaceholder)).font(.system(size: 13)).foregroundStyle(Pastel.subInk)
                Spacer()
                Text("⌘F").font(.system(size: 10.5, weight: .medium)).foregroundStyle(Pastel.subInk.opacity(0.8))
            }
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(RoundedRectangle(cornerRadius: 8).fill(Pastel.fill))
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.bottom, 4)
    }

    /// Text tabs with an underline, like a feed's 팔로잉 / 추천 / 즐겨찾기 tabs.
    private var tabs: some View {
        HStack(spacing: 0) {
            tabButton(.today, lang.t(.today))
            tabButton(.past, lang.t(.past))
            tabButton(.saved, lang.t(.saved))
        }
        .padding(.horizontal, 16)
        .overlay(alignment: .bottom) { Rectangle().fill(Pastel.divider).frame(height: 1) }
        .padding(.bottom, 10)
    }

    private func tabButton(_ t: Tab, _ label: String) -> some View {
        let active = ui.tab == t
        return Button { withAnimation(.easeInOut(duration: 0.15)) { ui.tab = t } } label: {
            VStack(spacing: 7) {
                Text(label)
                    .font(.system(size: 13.5, weight: active ? .bold : .medium))
                    .foregroundStyle(active ? Pastel.ink : Pastel.subInk)
                Rectangle().fill(active ? Pastel.accent : .clear)
                    .frame(width: 36, height: 2)
            }
            .padding(.top, 8)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Outlined pills with icons; the selected one is filled with a pastel.
    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(NewsCategory.allCases) { c in
                    let active = ui.category == c
                    Button { ui.category = c } label: {
                        HStack(spacing: 4) {
                            Image(systemName: c.symbol).font(.system(size: 10.5, weight: .medium))
                            Text(c.name(lang)).font(.system(size: 12, weight: active ? .semibold : .regular))
                        }
                        .foregroundStyle(active ? Pastel.ink : Pastel.ink.opacity(0.75))
                        .padding(.horizontal, 10)
                        .frame(height: 28)
                        .background(RoundedRectangle(cornerRadius: 8).fill(active ? Pastel.mint : Color.white))
                        .overlay(RoundedRectangle(cornerRadius: 8)
                            .stroke(active ? Pastel.mint.mix(with: Pastel.ink, by: 0.15) : Pastel.line, lineWidth: 1))
                        .contentShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 1)
        }
        .padding(.bottom, 6)
    }

    // MARK: Footer

    private var footer: some View {
        VStack(spacing: 0) {
            if let err = store.errorMessage {
                Text(err).font(.system(size: 11)).foregroundStyle(Color(red: 0.72, green: 0.3, blue: 0.36))
                    .lineLimit(2).padding(.horizontal, 16).padding(.vertical, 7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Pastel.rose.opacity(0.45))
            }
            HStack(spacing: 10) {
                Label(store.hasAPIKey ? lang.t(.aiOn) : lang.t(.basic),
                      systemImage: store.hasAPIKey ? "wand.and.stars" : "text.alignleft")
                    .font(.system(size: 11)).foregroundStyle(Pastel.subInk)
                Spacer()
                Button(lang.t(.markAllRead)) { store.markAllRead() }
                    .buttonStyle(.plain).font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Pastel.ink.opacity(0.75))
                Button(lang.t(.quit)) { NSApp.terminate(nil) }
                    .buttonStyle(.plain).font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Pastel.ink.opacity(0.75))
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .overlay(alignment: .top) { Rectangle().fill(Pastel.divider).frame(height: 1) }
        }
    }
}

// MARK: - Language toggle

/// Segmented control: gray track, white selected segment.
struct LanguageToggle: View {
    @EnvironmentObject var store: NewsStore

    var body: some View {
        HStack(spacing: 0) {
            option(.en, "EN")
            option(.ko, "한")
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 7).fill(Pastel.fill))
        .help(store.language == .ko ? "언어 전환" : "Switch language")
    }

    private func option(_ l: AppLanguage, _ label: String) -> some View {
        let active = store.language == l
        return Button { store.language = l } label: {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(active ? Pastel.ink : Pastel.subInk)
                .frame(width: 26, height: 22)
                .background(RoundedRectangle(cornerRadius: 5).fill(active ? Pastel.peach : .clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Bold section title, like "제목 ›" in a mobile kit.
struct SectionTitle: View {
    let title: String
    var count: Int? = nil
    var symbol: String? = nil
    var symbolColor: Color = Pastel.subInk

    var body: some View {
        HStack(spacing: 6) {
            if let symbol {
                Image(systemName: symbol).font(.system(size: 11, weight: .semibold)).foregroundStyle(symbolColor)
            }
            Text(title).font(.system(size: 15, weight: .bold)).foregroundStyle(Pastel.ink)
            if let count {
                Text("\(count)").font(.system(size: 12, weight: .medium)).foregroundStyle(Pastel.subInk)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 2)
    }
}

// MARK: - Today

struct TodayList: View {
    @EnvironmentObject var store: NewsStore
    let category: NewsCategory

    var body: some View {
        let big = store.bigNews(category)
        let items = store.today(category)
        if items.isEmpty && big.isEmpty {
            EmptyState(symbol: store.isLoading ? "hourglass" : "tray",
                       text: store.isLoading ? store.language.t(.gathering) : store.language.t(.empty))
        } else {
            SelectionScroll {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if category == .all { BriefingCard().padding(.horizontal, 16).padding(.top, 4) }
                    if !big.isEmpty {
                        SectionTitle(title: store.language.t(.bigNews), count: big.count,
                                     symbol: "star.fill", symbolColor: Pastel.gold)
                        VStack(spacing: 8) {
                            ForEach(big) { ArticleCard(article: $0, showCategory: true, featured: true) }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                    }
                    if !items.isEmpty {
                        if !big.isEmpty || category == .all {
                            SectionTitle(title: store.language.t(.today), count: items.count)
                        }
                        ForEach(items) { ArticleCard(article: $0, showCategory: true) }
                    }
                }
                .padding(.bottom, 8)
            }
        }
    }
}

// MARK: - Past days (grouped by day, then by topic)

struct PastList: View {
    @EnvironmentObject var store: NewsStore
    let category: NewsCategory
    @State private var collapsed: Set<Date> = []
    @State private var touched: Set<Date> = []

    private var lang: AppLanguage { store.language }

    var body: some View {
        let days = store.pastDays(category)
        if days.isEmpty {
            EmptyState(symbol: "calendar", text: lang.t(.emptyPast))
        } else {
            SelectionScroll {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(days.enumerated()), id: \.element.id) { index, day in
                        // Most recent day starts open, older days start folded; keyboard selection opens its day.
                        let holdsSelection = day.groups.contains { $0.articles.contains { $0.link == store.selectedLink } }
                        let isOpen = holdsSelection || (touched.contains(day.day) ? !collapsed.contains(day.day) : index == 0)
                        dayHeader(day, isOpen: isOpen)
                        if isOpen {
                            ForEach(day.groups, id: \.category) { group in
                                groupHeader(group.category, count: group.articles.count)
                                ForEach(group.articles) { ArticleCard(article: $0, showCategory: false) }
                            }
                        }
                    }
                }
                .padding(.bottom, 8)
            }
        }
    }

    private func dayHeader(_ day: DayGroup, isOpen: Bool) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                touched.insert(day.day)
                if isOpen { collapsed.insert(day.day) } else { collapsed.remove(day.day) }
            }
        } label: {
            HStack(spacing: 8) {
                Text(dayTitle(day.day))
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Pastel.ink)
                Text("\(day.count)").font(.system(size: 12, weight: .medium)).foregroundStyle(Pastel.subInk)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 9.5, weight: .bold))
                    .rotationEffect(.degrees(isOpen ? 90 : 0))
                    .foregroundStyle(Pastel.ink.opacity(0.7))
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(Pastel.fill))
            }
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func groupHeader(_ c: NewsCategory, count: Int) -> some View {
        HStack(spacing: 5) {
            Image(systemName: c.symbol).font(.system(size: 10, weight: .medium))
            Text(c.name(lang)).font(.system(size: 11.5, weight: .semibold))
            Text("\(count)").font(.system(size: 11))
        }
        .foregroundStyle(Pastel.subInk)
        .padding(.horizontal, 6).padding(.vertical, 3)
        .background(RoundedRectangle(cornerRadius: 6).fill(Pastel.fill))
        .padding(.horizontal, 16).padding(.top, 6).padding(.bottom, 2)
    }

    private func dayTitle(_ d: Date) -> String {
        let date = d.formatted(.dateTime.month(.abbreviated).day().weekday(.wide).locale(lang.locale))
        if Calendar.current.isDateInYesterday(d) { return (lang == .ko ? "어제 · " : "Yesterday · ") + date }
        return date
    }
}

struct EmptyState: View {
    let symbol: String
    let text: String
    var body: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: symbol).font(.system(size: 26)).foregroundStyle(Pastel.subInk.opacity(0.6))
            Text(text).font(.system(size: 12)).foregroundStyle(Pastel.subInk).multilineTextAlignment(.center)
            Spacer()
        }
        .padding(.horizontal, 30)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Feed row

/// One story in the feed: avatar + source + time, headline, key points, and an action row.
/// Featured (Big news) stories sit in a pastel banner; the rest are flat rows split by hairlines.
struct ArticleCard: View {
    @EnvironmentObject var store: NewsStore
    let article: Article
    let showCategory: Bool
    var featured = false
    @State private var hovering = false

    var body: some View {
        let unread = !store.readLinks.contains(article.link)
        let tint = article.source?.tint ?? Pastel.butter
        let selected = store.selectedLink == article.link
        let lang = store.language

        VStack(alignment: .leading, spacing: 8) {
            // Byline
            HStack(spacing: 9) {
                SourceAvatar(source: article.source, size: 30)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Text(article.source?.name ?? "")
                            .font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Pastel.ink)
                        if article.source?.official == true {
                            Image(systemName: "checkmark.seal.fill").font(.system(size: 10))
                                .foregroundStyle(Pastel.accent)
                                .help(lang.t(.official))
                        }
                        if store.isBig(article) && !featured {
                            Image(systemName: "star.fill").font(.system(size: 9)).foregroundStyle(Pastel.gold)
                        }
                    }
                    HStack(spacing: 4) {
                        Text(article.date, format: .relative(presentation: .named))
                        if showCategory {
                            Text("·")
                            Text(store.category(article).name(lang))
                        }
                    }
                    .font(.system(size: 11)).foregroundStyle(Pastel.subInk)
                }
                Spacer()
                if unread { Circle().fill(Pastel.accent).frame(width: 7, height: 7) }
                moreMenu
            }

            // Headline + key points (the tappable part)
            Button { withAnimation(.easeInOut(duration: 0.18)) { store.open(article) } } label: {
                VStack(alignment: .leading, spacing: 6) {
                    Text(store.title(article))
                        .font(.system(size: featured ? 15 : 14, weight: .semibold))
                        .foregroundStyle(Pastel.ink.opacity(unread ? 1 : 0.6))
                        .lineSpacing(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    let points = store.bullets(article)
                    if !points.isEmpty {
                        BulletList(points: points, dot: tint, size: 12.5, color: Pastel.body.opacity(unread ? 1 : 0.75))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            actions
        }
        .padding(.horizontal, featured ? 14 : 16)
        .padding(.vertical, featured ? 12 : 13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(background(selected: selected, tint: tint))
        .overlay(alignment: .bottom) {
            if !featured { Rectangle().fill(Pastel.divider).frame(height: 1).padding(.horizontal, 16) }
        }
        .onHover { hovering = $0 }
        .id(article.link)
        .contextMenu { menuItems }
    }

    @ViewBuilder private func background(selected: Bool, tint: Color) -> some View {
        if featured {
            RoundedRectangle(cornerRadius: 10)
                .fill(Pastel.butter.opacity(hovering ? 0.85 : 0.6))
                .overlay(RoundedRectangle(cornerRadius: 10)
                    .stroke(Pastel.accent, lineWidth: selected ? 1.5 : 0))
        } else {
            Rectangle().fill(selected ? Pastel.lavender.opacity(0.35) : hovering ? Pastel.fill.opacity(0.7) : .white)
        }
    }

    /// 저장 · 원문 — like the 좋아요 / 댓글 row of a feed.
    private var actions: some View {
        let lang = store.language
        let saved = store.isBookmarked(article)
        return HStack(spacing: 16) {
            ActionButton(symbol: saved ? "bookmark.fill" : "bookmark",
                         label: saved ? lang.t(.saved) : lang.t(.bookmark),
                         tint: saved ? Pastel.accent : Pastel.ink.opacity(0.75)) {
                store.toggleBookmark(article)
            }
            ActionButton(symbol: "arrow.up.right.square", label: lang.t(.openOriginal),
                         tint: Pastel.ink.opacity(0.75)) {
                store.openInBrowser(article)
            }
            if lang == .ko {
                ActionButton(symbol: "text.book.closed", label: "한국어로 읽기", tint: Pastel.ink.opacity(0.75)) {
                    withAnimation(.easeInOut(duration: 0.18)) { store.open(article) }
                }
            }
            Spacer()
        }
        .padding(.top, 1)
    }

    private var moreMenu: some View {
        Menu { menuItems } label: {
            Image(systemName: "ellipsis").font(.system(size: 13, weight: .bold))
                .foregroundStyle(Pastel.ink.opacity(0.7))
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    @ViewBuilder private var menuItems: some View {
        let ko = store.language == .ko
        if ko {
            Button("앱에서 한국어로 읽기") { withAnimation { store.open(article) } }
            Button("웹 번역으로 열기") { store.openWebTranslation(article) }
        }
        Button(ko ? "원문을 브라우저에서 열기" : "Open in Browser") { store.openInBrowser(article) }
        Button(ko ? "링크 복사" : "Copy Link") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(article.link, forType: .string)
        }
        Button(store.isBookmarked(article) ? store.language.t(.unbookmark) : store.language.t(.bookmark)) {
            store.toggleBookmark(article)
        }
        Button(ko ? "읽음으로 표시" : "Mark as Read") { store.markRead(article) }
    }
}

/// Round pastel avatar with the source's initials (stands in for a profile photo).
struct SourceAvatar: View {
    let source: FeedSource?
    var size: CGFloat = 30

    var body: some View {
        let tint = source?.tint ?? Pastel.butter
        let initials = source?.initials ?? "?"
        Text(initials)
            .font(.system(size: size * (initials.count > 2 ? 0.3 : 0.37), weight: .bold))
            .foregroundStyle(tint.mix(with: Pastel.ink, by: 0.62))
            .frame(width: size, height: size)
            .background(Circle().fill(tint))
            .overlay(Circle().stroke(Color.black.opacity(0.04), lineWidth: 1))
    }
}

struct ActionButton: View {
    let symbol: String
    let label: String
    var tint: Color = Pastel.ink.opacity(0.75)
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 12, weight: .medium))
                Text(label).font(.system(size: 11.5, weight: .medium))
            }
            .foregroundStyle(hover ? Pastel.ink : tint)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

// MARK: - Bullets

struct BulletList: View {
    let points: [String]
    let dot: Color
    var size: CGFloat = 11.5
    var color: Color = Pastel.subInk
    var spacing: CGFloat = 3

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            ForEach(Array(points.enumerated()), id: \.offset) { _, p in
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Circle().fill(dot.mix(with: Pastel.ink, by: 0.35))
                        .frame(width: 4.5, height: 4.5)
                        .alignmentGuide(.firstTextBaseline) { $0[.bottom] + size * 0.28 }
                    Text(p)
                        .font(.system(size: size))
                        .foregroundStyle(color)
                        .lineSpacing(1.5)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

// MARK: - Reader (Korean mode: everything, including the article body, in Korean)

struct ArticleReader: View {
    @EnvironmentObject var store: NewsStore
    let article: Article
    @State private var blocks: [ArticleBlock]?
    @State private var failed = false
    @State private var config: TranslationSession.Configuration?

    private var lang: AppLanguage { store.language }
    private var tint: Color { article.source?.tint ?? Pastel.butter }

    /// Body text in the reader's language. In Korean, show blocks in order only once translated,
    /// so the page never mixes languages mid-article.
    private var visible: [ArticleBlock] {
        guard let blocks else { return [] }
        guard lang == .ko else { return blocks }
        var out: [ArticleBlock] = []
        for b in blocks {
            guard let t = store.bodyTranslations[b.text] else { break }
            out.append(ArticleBlock(kind: b.kind, text: t))
        }
        return out
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    meta
                    Text(store.title(article))
                        .font(.system(size: 19, weight: .bold))
                        .foregroundStyle(Pastel.ink)
                        .lineSpacing(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                    keyPoints
                    bodySection
                }
                .textSelection(.enabled)
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 20)
            }
            bottomBar
        }
        .task(id: article.link) { await load() }
        .translationTask(config) { session in
            if let blocks { await store.translateBody(blocks, using: session) }
        }
        .onChange(of: store.language) { requestTranslation() }
        .onChange(of: store.translationReady) { requestTranslation() }
    }

    private func load() async {
        do {
            let b = try await store.articleBody(article)
            blocks = b
            failed = b.isEmpty
            // Upgrade an excerpt-based summary to one written from the full text.
            if !b.isEmpty { Task { await store.improveSummary(article, blocks: b) } }
        } catch {
            blocks = []
            failed = true
        }
        requestTranslation()
    }

    private func requestTranslation() {
        guard lang == .ko, store.translationReady == true, let blocks, !blocks.isEmpty,
              blocks.contains(where: { store.bodyTranslations[$0.text] == nil }) else { return }
        if config == nil {
            config = .init(source: Locale.Language(identifier: "en"), target: Locale.Language(identifier: "ko"))
        } else {
            config?.invalidate()
        }
    }

    // MARK: Pieces

    private var topBar: some View {
        HStack(spacing: 4) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) { store.reading = nil }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left").font(.system(size: 12, weight: .semibold))
                    Text(lang.t(.back)).font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(Pastel.ink)
                .padding(.horizontal, 6).frame(height: 28)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Spacer()
            let saved = store.isBookmarked(article)
            IconButton(system: saved ? "bookmark.fill" : "bookmark") { store.toggleBookmark(article) }
                .help(lang == .ko ? "저장 (B) · ←/→ 이전·다음 기사" : "Save (B) · ←/→ previous/next story")
            IconButton(system: "square.and.arrow.up") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString("\(store.title(article))\n\(article.link)", forType: .string)
            }
            .help(lang == .ko ? "제목과 링크 복사" : "Copy title and link")
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 6)
        .overlay(alignment: .bottom) { Rectangle().fill(Pastel.divider).frame(height: 1) }
    }

    private var meta: some View {
        HStack(spacing: 9) {
            SourceAvatar(source: article.source, size: 32)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(article.source?.name ?? "").font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Pastel.ink)
                    if article.source?.official == true {
                        Image(systemName: "checkmark.seal.fill").font(.system(size: 10.5))
                            .foregroundStyle(Pastel.accent)
                    }
                }
                Text(article.date.formatted(.dateTime.month(.abbreviated).day().hour().minute().locale(lang.locale))
                     + " · " + store.category(article).name(lang))
                    .font(.system(size: 11)).foregroundStyle(Pastel.subInk)
            }
            Spacer()
        }
    }

    @ViewBuilder private var keyPoints: some View {
        let points = store.bullets(article)
        if !points.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(lang.t(.keyPoints))
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Pastel.ink)
                BulletList(points: points, dot: tint, size: 13, color: Pastel.body, spacing: 6)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(tint.opacity(0.4)))
        }
    }

    @ViewBuilder private var bodySection: some View {
        HStack(spacing: 8) {
            Text(lang.t(.fullArticle))
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Pastel.ink)
            Rectangle().fill(Pastel.divider).frame(height: 1)
        }
        .padding(.top, 6)

        if lang == .ko && store.translationReady == false {
            LanguagePackBanner()
        } else if failed {
            Text(lang.t(.articleUnavailable))
                .font(.system(size: 12)).foregroundStyle(Pastel.subInk)
                .fixedSize(horizontal: false, vertical: true)
        } else if blocks == nil {
            progress(lang.t(.fetchingArticle))
        } else {
            let shown = visible
            VStack(alignment: .leading, spacing: 13) {
                ForEach(Array(shown.enumerated()), id: \.offset) { _, b in blockView(b) }
            }
            if let blocks, shown.count < blocks.count {
                progress("\(lang.t(.translatingArticle)) \(shown.count)/\(blocks.count)…")
            }
        }
    }

    @ViewBuilder private func blockView(_ b: ArticleBlock) -> some View {
        switch b.kind {
        case .heading:
            Text(b.text)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Pastel.ink)
                .padding(.top, 6)
                .fixedSize(horizontal: false, vertical: true)
        case .paragraph:
            Text(b.text)
                .font(.system(size: 14))
                .foregroundStyle(Pastel.ink.opacity(0.88))
                .lineSpacing(6)
                .fixedSize(horizontal: false, vertical: true)
        case .bullet:
            BulletList(points: [b.text], dot: tint, size: 13.5, color: Pastel.ink.opacity(0.9))
                .padding(.leading, 4)
        case .quote:
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 1.5).fill(tint).frame(width: 3)
                Text(b.text)
                    .font(.system(size: 13.5).italic())
                    .foregroundStyle(Pastel.ink.opacity(0.75))
                    .lineSpacing(5)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func progress(_ text: String) -> some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text(text).font(.system(size: 11.5)).foregroundStyle(Pastel.subInk)
        }
        .padding(.vertical, 6)
    }

    private var bottomBar: some View {
        HStack(spacing: 8) {
            if lang == .ko {
                Button { store.openWebTranslation(article) } label: {
                    Label(lang.t(.openTranslatedWeb), systemImage: "globe")
                }
                .buttonStyle(PastelButton(fill: failed ? Pastel.mint : nil))
            }
            Spacer()
            Button { store.openInBrowser(article) } label: {
                Label(lang.t(.openOriginal), systemImage: "arrow.up.right.square")
            }
            .buttonStyle(PastelButton(fill: Pastel.lavender))
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .overlay(alignment: .top) { Rectangle().fill(Pastel.divider).frame(height: 1) }
    }
}

// MARK: - Korean language pack

/// Shown in Korean mode until Apple's on-device English→Korean pack is installed.
struct LanguagePackBanner: View {
    @EnvironmentObject var store: NewsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("한국어 번역 언어팩이 필요해요", systemImage: "character.bubble")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Pastel.ink)
            Text("제목·요약·기사 본문을 Mac에서 바로 번역하려면 영어→한국어 언어팩(무료)을 한 번 내려받아야 해요.")
                .font(.system(size: 11)).foregroundStyle(Pastel.subInk)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button("언어팩 다운로드") { store.downloadKoreanPack() }
                    .buttonStyle(PastelButton(fill: Pastel.mint))
                Button("시스템 설정에서 받기") { store.openTranslationSettings() }
                    .buttonStyle(PastelButton(fill: nil))
            }
            Text("시스템 설정 → 일반 → 언어 및 지역 → 번역 언어에서 ‘한국어’를 받아도 돼요.")
                .font(.system(size: 10)).foregroundStyle(Pastel.subInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Pastel.butter.opacity(0.75)))
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }
}

/// A normal window (unlike the menu bar popover, it can present the system download prompt).
@MainActor
enum LanguagePackWindow {
    private static var window: NSWindow?

    static func show(store: NewsStore) {
        if let window { window.makeKeyAndOrderFront(nil); NSApp.activate(); return }
        let view = LanguagePackView { Task { await store.checkTranslationAvailability() }; close() }
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 360, height: 150),
                         styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.title = "한국어 언어팩"
        w.isReleasedWhenClosed = false
        w.contentView = NSHostingView(rootView: view)
        w.center()
        window = w
        NSApp.activate()
        w.makeKeyAndOrderFront(nil)
    }

    static func close() {
        window?.close()
        window = nil
    }
}

struct LanguagePackView: View {
    let done: () -> Void
    @State private var config = TranslationSession.Configuration(
        source: Locale.Language(identifier: "en"), target: Locale.Language(identifier: "ko"))
    @State private var failed = false

    var body: some View {
        VStack(spacing: 12) {
            if failed {
                Text("다운로드하지 못했어요. 시스템 설정 → 일반 → 언어 및 지역 → 번역 언어에서 ‘한국어’를 받아 주세요.")
                    .font(.system(size: 12)).multilineTextAlignment(.center)
                Button("시스템 설정 열기") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.Localization-Settings.extension") {
                        NSWorkspace.shared.open(url)
                    }
                    done()
                }
            } else {
                ProgressView().controlSize(.small)
                Text("다운로드 창이 뜨면 ‘다운로드’를 눌러 주세요.").font(.system(size: 12))
            }
        }
        .padding(20)
        .frame(width: 360, height: 150)
        .translationTask(config) { session in
            do {
                try await session.prepareTranslation()
                done()
            } catch {
                failed = true
            }
        }
    }
}

// MARK: - Settings

struct SettingsView: View {
    @EnvironmentObject var store: NewsStore
    @Binding var isPresented: Bool
    @State private var key = ""

    private var lang: AppLanguage { store.language }

    var body: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: 14) {
            Text(lang.t(.settingsAI)).font(.system(size: 14, weight: .bold))
                .foregroundStyle(Pastel.ink)
            Text(lang.t(.settingsAIBody))
                .font(.system(size: 11.5)).foregroundStyle(Pastel.subInk)
                .fixedSize(horizontal: false, vertical: true)

            SecureField(store.hasAPIKey ? lang.t(.keySaved) : "sk-ant-…", text: $key)
                .textFieldStyle(.plain)
                .font(.system(size: 12, design: .monospaced))
                .padding(9)
                .background(RoundedRectangle(cornerRadius: 8).fill(Pastel.fill))

            HStack {
                if store.hasAPIKey {
                    Button(lang.t(.removeKey)) { store.setAPIKey(""); key = "" }
                        .buttonStyle(PastelButton(fill: nil))
                }
                Spacer()
                Button(lang.t(.save)) {
                    store.setAPIKey(key); key = ""; isPresented = false
                }
                .buttonStyle(PastelButton(fill: Pastel.mint))
                .disabled(key.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            Rectangle().fill(Pastel.divider).frame(height: 1).padding(.vertical, 4)

            Toggle(isOn: Binding(get: { store.launchAtLogin }, set: { store.setLaunchAtLogin($0) })) {
                Text(lang.t(.launchAtLogin)).font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Pastel.ink)
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .tint(Pastel.mint)

            Toggle(isOn: Binding(get: { store.notifyBigNews }, set: { store.setNotifyBigNews($0) })) {
                Label(lang.t(.notifyBig), systemImage: "bell.badge")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Pastel.ink)
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .tint(Pastel.mint)

            Toggle(isOn: Binding(get: { store.notifyBriefing }, set: { store.setNotifyBriefing($0) })) {
                Label(lang.t(.notifyBriefing), systemImage: "sun.horizon")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Pastel.ink)
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .tint(Pastel.mint)

            Rectangle().fill(Pastel.divider).frame(height: 1).padding(.vertical, 4)

            Text(lang.t(.shortcuts)).font(.system(size: 14, weight: .bold))
                .foregroundStyle(Pastel.ink)
            ShortcutsTable()

            Rectangle().fill(Pastel.divider).frame(height: 1).padding(.vertical, 4)

            Text(lang.t(.sources)).font(.system(size: 14, weight: .bold))
                .foregroundStyle(Pastel.ink)
            ForEach([true, false], id: \.self) { official in
                Text(official ? lang.t(.official) : lang.t(.outlets))
                    .font(.system(size: 10.5, weight: .medium)).foregroundStyle(Pastel.subInk)
                FlowRow(FeedSource.all.filter { $0.official == official })
            }
            Text(lang.t(.sourcesNote))
                .font(.system(size: 10.5)).foregroundStyle(Pastel.subInk)
        }
        .padding(18)
        }
    }
}

// MARK: - Small components

struct FlowRow: View {
    let sources: [FeedSource]
    init(_ sources: [FeedSource]) { self.sources = sources }
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), alignment: .leading)], alignment: .leading, spacing: 6) {
            ForEach(sources) { s in
                HStack(spacing: 6) {
                    Circle().fill(s.tint).frame(width: 9, height: 9)
                    Text(s.name).font(.system(size: 11.5)).foregroundStyle(Pastel.ink.opacity(0.8)).lineLimit(1)
                }
            }
        }
    }
}

struct IconButton: View {
    let system: String
    var spinning = false
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 13.5, weight: .medium))
                .foregroundStyle(Pastel.ink.opacity(0.85))
                .rotationEffect(.degrees(spinning ? 360 : 0))
                .animation(spinning ? .linear(duration: 1).repeatForever(autoreverses: false) : .default,
                           value: spinning)
                .frame(width: 28, height: 28)
                .background(RoundedRectangle(cornerRadius: 7).fill(hover ? Pastel.fill : .clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

/// Filled pastel button (primary) — or outlined white when `fill` is nil (secondary).
struct PastelButton: ButtonStyle {
    var fill: Color? = Pastel.mint
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Pastel.ink)
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(RoundedRectangle(cornerRadius: 8)
                .fill(fill.map { $0.opacity(configuration.isPressed ? 1 : 0.85) } ?? (configuration.isPressed ? Pastel.fill : .white)))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(fill == nil ? Pastel.line : .clear, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Debug snapshot

@MainActor
enum Snapshot {
    /// Popover height; only the debug snapshot changes it.
    nonisolated(unsafe) static var height: CGFloat = 600

    static func schedule(path: String, ko: Bool, reader: Bool, height: CGFloat) {
        self.height = height
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            guard let store = NewsStore.shared else { return }
            let savedLanguage = UserDefaults.standard.string(forKey: "language")
            store.language = ko ? .ko : .en
            while store.isLoading || store.articles.isEmpty { try? await Task.sleep(for: .milliseconds(300)) }
            if reader { store.reading = store.bigNews(.all).first ?? store.today(.all).first }
            let view = ContentView().environmentObject(store)
                .environment(\.colorScheme, .light).environment(\.locale, store.language.locale)
            let host = NSHostingView(rootView: view)
            host.frame = NSRect(x: 0, y: 0, width: 400, height: height)
            let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = host
            window.setFrameOrigin(NSPoint(x: -5000, y: -5000))
            window.orderFrontRegardless()
            try? await Task.sleep(for: .seconds(reader ? 6 : 2))
            host.layoutSubtreeIfNeeded()
            if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
                host.cacheDisplay(in: host.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
            }
            UserDefaults.standard.set(savedLanguage, forKey: "language")   // don't change the user's setting
            exit(0)
        }
    }
}
