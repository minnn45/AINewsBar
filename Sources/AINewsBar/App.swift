import SwiftUI
import AppKit
import Translation

@main
struct AINewsBarApp: App {
    @StateObject private var store = NewsStore()

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
    @State private var tab: Tab = .today
    @State private var category: NewsCategory = .all
    @State private var showSettings = false
    @State private var translationConfig: TranslationSession.Configuration?
    @State private var searching = false
    @State private var query = ""
    @FocusState private var searchFocused: Bool
    @FocusState private var rootFocused: Bool

    private var lang: AppLanguage { store.language }
    private var queryActive: Bool { searching && !query.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            header
            if showSettings {
                SettingsView(isPresented: $showSettings)
            } else if let article = store.reading {
                ArticleReader(article: article)
                    .id(article.link)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                if searching { searchBar } else { tabs }
                chips
                if lang == .ko && store.translationReady == false { LanguagePackBanner() }
                Group {
                    if searching {
                        SearchList(query: query, category: category)
                    } else {
                        switch tab {
                        case .today: TodayList(category: category)
                        case .past: PastList(category: category)
                        case .saved: SavedList(category: category)
                        }
                    }
                }
                .frame(maxHeight: .infinity)
                footer
            }
        }
        .frame(width: 400, height: 600)
        // Keyboard navigation: the whole popover takes key presses.
        .focusable()
        .focused($rootFocused)
        .focusEffectDisabled()
        .onKeyPress(phases: .down, action: handleKey)
        .onChange(of: tab) { store.selectedLink = nil }
        .onChange(of: category) { store.selectedLink = nil }
        .onChange(of: query) { store.selectedLink = nil }
        .background(
            LinearGradient(colors: [.white, Pastel.lavender.opacity(0.35), Pastel.mint.opacity(0.30)],
                           startPoint: .top, endPoint: .bottom)
        )
        // On-device English → Korean translation (Apple Translation framework).
        .translationTask(translationConfig) { session in
            await store.translatePending(using: session)
        }
        .onAppear {
            rootFocused = true
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
                Circle().fill(LinearGradient(colors: [Pastel.lavender, Pastel.sky],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                Image(systemName: "sparkles").font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Pastel.ink.opacity(0.75))
            }
            .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 1) {
                Text(lang.t(.appTitle)).font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(Pastel.ink)
                Text(subtitle).font(.system(size: 10.5)).foregroundStyle(Pastel.subInk)
            }
            Spacer()
            LanguageToggle()
            IconButton(system: searching ? "magnifyingglass.circle.fill" : "magnifyingglass") {
                searching ? closeSearch() : openSearch()
            }
            .help(lang == .ko ? "검색 (⌘F)" : "Search (⌘F)")
            IconButton(system: "arrow.clockwise", spinning: store.isLoading) {
                Task { await store.refresh() }
            }
            IconButton(system: showSettings ? "xmark" : "gearshape") {
                withAnimation(.easeInOut(duration: 0.15)) { showSettings.toggle() }
            }
        }
        .onChange(of: store.language) {
            // The reader is the Korean-mode way of opening stories; English goes back to the list.
            if store.language == .en { withAnimation(.easeInOut(duration: 0.15)) { store.reading = nil } }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    private var subtitle: String {
        if store.isLoading { return lang.t(.updating) }
        if store.isTranslating { return lang.t(.translating) }
        guard let d = store.lastUpdated else { return lang.t(.loading) }
        let time = d.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(lang.locale))
        let unread = store.unreadCount
        return "\(lang.t(.updated)) \(time)" + (unread > 0 ? " · \(unread) \(lang.t(.new))" : "")
    }

    // MARK: Search

    private var searchBar: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass").font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(Pastel.subInk)
            TextField(lang.t(.searchPlaceholder), text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .foregroundStyle(Pastel.ink)
                .focused($searchFocused)
                .onSubmit { openSelectedOrFirst() }
            if queryActive {
                Text("\(navigable.count)\(lang == .ko ? "" : " ")\(lang.t(.results))")
                    .font(.system(size: 10.5, design: .rounded)).foregroundStyle(Pastel.subInk)
            }
            Button(action: closeSearch) {
                Image(systemName: "xmark.circle.fill").font(.system(size: 12)).foregroundStyle(Pastel.subInk)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 11).padding(.vertical, 7)
        .background(Capsule().fill(Color.white.opacity(0.9)))
        .overlay(Capsule().stroke(Pastel.lavender.opacity(0.9), lineWidth: 0.8))
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private func openSearch() {
        withAnimation(.easeInOut(duration: 0.15)) {
            showSettings = false
            store.reading = nil
            searching = true
        }
        DispatchQueue.main.async { searchFocused = true }
    }

    private func closeSearch() {
        withAnimation(.easeInOut(duration: 0.15)) { searching = false; query = "" }
        searchFocused = false
        rootFocused = true
    }

    // MARK: Keyboard

    /// Stories in on-screen order, for ↑/↓ navigation.
    private var navigable: [Article] {
        if searching { return queryActive ? store.search(query, category: category) : [] }
        switch tab {
        case .today: return store.bigNews(category) + store.today(category)
        case .past: return store.pastDays(category).flatMap { $0.groups.flatMap(\.articles) }
        case .saved: return store.saved(category)
        }
    }

    private func move(_ step: Int) {
        let list = navigable
        guard !list.isEmpty else { return }
        let current = list.firstIndex { $0.link == store.selectedLink }
        let next = current.map { min(max($0 + step, 0), list.count - 1) } ?? (step > 0 ? 0 : list.count - 1)
        store.selectedLink = list[next].link
    }

    private var selectedArticle: Article? {
        guard let link = store.selectedLink else { return nil }
        return navigable.first { $0.link == link }
    }

    private func openSelectedOrFirst() {
        guard let a = selectedArticle ?? navigable.first else { return }
        store.selectedLink = a.link
        searchFocused = false
        rootFocused = true
        withAnimation(.easeInOut(duration: 0.18)) { store.open(a) }
    }

    private func handleKey(_ press: KeyPress) -> KeyPress.Result {
        if press.modifiers.contains(.command) {
            if press.characters == "f" { openSearch(); return .handled }
            return .ignored
        }
        if press.key == .escape {
            if store.reading != nil { withAnimation(.easeInOut(duration: 0.18)) { store.reading = nil }; return .handled }
            if showSettings { withAnimation { showSettings = false }; return .handled }
            if searching { if query.isEmpty { closeSearch() } else { query = "" }; return .handled }
            return .ignored
        }
        // While typing a search, only ↓ / ↵ leave the field; everything else is text.
        if searchFocused {
            if press.key == .downArrow {
                searchFocused = false; rootFocused = true
                if let first = navigable.first { store.selectedLink = first.link }
                return .handled
            }
            return .ignored
        }
        if showSettings { return .ignored }

        if let reading = store.reading {
            switch press.key {
            case .leftArrow, .rightArrow:
                let list = navigable
                guard let i = list.firstIndex(where: { $0.link == reading.link }) else { return .ignored }
                let j = i + (press.key == .rightArrow ? 1 : -1)
                guard list.indices.contains(j) else { return .handled }
                store.selectedLink = list[j].link
                store.open(list[j])
                return .handled
            default:
                switch press.characters {
                case "b": store.toggleBookmark(reading); return .handled
                case "o": store.openInBrowser(reading); return .handled
                default: return .ignored
                }
            }
        }

        switch press.key {
        case .downArrow: move(1); return .handled
        case .upArrow: move(-1); return .handled
        case .return, .space: openSelectedOrFirst(); return .handled
        default: break
        }
        switch press.characters {
        case "j": move(1)
        case "k": move(-1)
        case "/": openSearch()
        case "r": Task { await store.refresh() }
        case "b": if let a = selectedArticle { store.toggleBookmark(a) } else { return .ignored }
        case "o": if let a = selectedArticle { store.openInBrowser(a) } else { return .ignored }
        default: return .ignored
        }
        return .handled
    }

    // MARK: Tabs & chips

    private var tabs: some View {
        HStack(spacing: 4) {
            tabButton(.today, lang.t(.today), "sun.max").keyboardShortcut("1", modifiers: .command)
            tabButton(.past, lang.t(.past), "calendar").keyboardShortcut("2", modifiers: .command)
            tabButton(.saved, lang.t(.saved), "bookmark").keyboardShortcut("3", modifiers: .command)
        }
        .padding(3)
        .background(Capsule().fill(Color.white.opacity(0.75)))
        .overlay(Capsule().stroke(Pastel.lavender.opacity(0.8), lineWidth: 0.6))
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private func tabButton(_ t: Tab, _ label: String, _ symbol: String) -> some View {
        Button { withAnimation(.easeInOut(duration: 0.15)) { tab = t } } label: {
            Label(label, systemImage: symbol)
                .font(.system(size: 12, weight: tab == t ? .semibold : .regular, design: .rounded))
                .foregroundStyle(Pastel.ink.opacity(tab == t ? 1 : 0.6))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
                .background(Capsule().fill(tab == t ? Pastel.lavender : .clear))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(NewsCategory.allCases) { c in
                    Button { category = c } label: {
                        Text(c.name(lang))
                            .font(.system(size: 11.5, weight: category == c ? .semibold : .regular, design: .rounded))
                            .foregroundStyle(Pastel.ink.opacity(category == c ? 1 : 0.7))
                            .padding(.horizontal, 11).padding(.vertical, 5)
                            .background(Capsule().fill(category == c ? Pastel.mint : Color.white.opacity(0.8)))
                            .overlay(Capsule().stroke(Pastel.mint.opacity(0.9), lineWidth: 0.6))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.bottom, 8)
    }

    // MARK: Footer

    private var footer: some View {
        VStack(spacing: 0) {
            if let err = store.errorMessage {
                Text(err).font(.system(size: 10.5)).foregroundStyle(Color(red: 0.75, green: 0.35, blue: 0.4))
                    .lineLimit(2).padding(.horizontal, 16).padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Pastel.rose.opacity(0.4))
            }
            HStack {
                Label(store.hasAPIKey ? lang.t(.aiOn) : lang.t(.basic),
                      systemImage: store.hasAPIKey ? "wand.and.stars" : "text.alignleft")
                    .font(.system(size: 10.5)).foregroundStyle(Pastel.subInk)
                Spacer()
                Button(lang.t(.markAllRead)) { store.markAllRead() }
                    .buttonStyle(.plain).font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(Pastel.ink.opacity(0.7))
                Text("·").foregroundStyle(Pastel.subInk)
                Button(lang.t(.quit)) { NSApp.terminate(nil) }
                    .buttonStyle(.plain).font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(Pastel.ink.opacity(0.7))
            }
            .padding(.horizontal, 16).padding(.vertical, 9)
            .background(Color.white.opacity(0.85))
        }
    }
}

// MARK: - Language toggle

struct LanguageToggle: View {
    @EnvironmentObject var store: NewsStore

    var body: some View {
        HStack(spacing: 0) {
            option(.en, "EN")
            option(.ko, "한")
        }
        .padding(2)
        .background(Capsule().fill(Color.white.opacity(0.8)))
        .overlay(Capsule().stroke(Pastel.lavender, lineWidth: 0.6))
        .help(store.language == .ko ? "언어 전환" : "Switch language")
    }

    private func option(_ l: AppLanguage, _ label: String) -> some View {
        Button { store.language = l } label: {
            Text(label)
                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                .foregroundStyle(Pastel.ink.opacity(store.language == l ? 1 : 0.5))
                .frame(width: 24, height: 20)
                .background(Capsule().fill(store.language == l ? Pastel.peach : .clear))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
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
                LazyVStack(alignment: .leading, spacing: 8) {
                    if category == .all { BriefingCard() }
                    if !big.isEmpty {
                        HStack(spacing: 5) {
                            Image(systemName: "star.fill").font(.system(size: 10))
                                .foregroundStyle(Pastel.gold)
                            Text(store.language.t(.bigNews))
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(Pastel.ink)
                        }
                        .padding(.leading, 4)
                        ForEach(big) { ArticleCard(article: $0, showCategory: true, featured: true) }

                        if !items.isEmpty {
                            HStack(spacing: 5) {
                                Image(systemName: "newspaper").font(.system(size: 10))
                                Text(store.language.t(.today))
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                            }
                            .foregroundStyle(Pastel.subInk)
                            .padding(.leading, 4).padding(.top, 6)
                        }
                    }
                    ForEach(items) { ArticleCard(article: $0, showCategory: true) }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
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
                LazyVStack(alignment: .leading, spacing: 10) {
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
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
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
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .rotationEffect(.degrees(isOpen ? 90 : 0))
                    .foregroundStyle(Pastel.subInk)
                Text(dayTitle(day.day))
                    .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(Pastel.ink)
                Spacer()
                Text("\(day.count) \(lang.t(.stories))")
                    .font(.system(size: 10.5, design: .rounded)).foregroundStyle(Pastel.subInk)
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(Capsule().fill(Pastel.butter))
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 10).fill(Pastel.lavender.opacity(0.45)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.top, 2)
    }

    private func groupHeader(_ c: NewsCategory, count: Int) -> some View {
        HStack(spacing: 5) {
            Image(systemName: c.symbol).font(.system(size: 10))
            Text(c.name(lang)).font(.system(size: 11, weight: .semibold, design: .rounded))
            Text("\(count)").font(.system(size: 10)).foregroundStyle(Pastel.subInk.opacity(0.8))
        }
        .foregroundStyle(Pastel.subInk)
        .padding(.leading, 6).padding(.top, 2)
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

// MARK: - Card

struct ArticleCard: View {
    @EnvironmentObject var store: NewsStore
    let article: Article
    let showCategory: Bool
    var featured = false
    @State private var hovering = false

    var body: some View {
        let unread = !store.readLinks.contains(article.link)
        let tint = article.source?.tint ?? Pastel.butter
        let big = store.isBig(article)
        let selected = store.selectedLink == article.link
        let saved = store.isBookmarked(article)

        Button { withAnimation(.easeInOut(duration: 0.18)) { store.open(article) } } label: {
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 2).fill(tint).frame(width: 4)

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Text(article.source?.name ?? "")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(Pastel.ink.opacity(0.75))
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(Capsule().fill(tint.opacity(0.7)))
                        if article.source?.official == true {
                            Label(store.language.t(.official), systemImage: "checkmark.seal.fill")
                                .labelStyle(.titleAndIcon)
                                .font(.system(size: 9.5, weight: .medium, design: .rounded))
                                .foregroundStyle(Pastel.ink.opacity(0.6))
                        }
                        if big && !featured {
                            Image(systemName: "star.fill").font(.system(size: 9)).foregroundStyle(Pastel.gold)
                        }
                        if showCategory {
                            Text(store.category(article).name(store.language))
                                .font(.system(size: 10, design: .rounded)).foregroundStyle(Pastel.subInk)
                        }
                        Spacer()
                        if saved {
                            Image(systemName: "bookmark.fill").font(.system(size: 9.5))
                                .foregroundStyle(Color(red: 0.55, green: 0.48, blue: 0.85))
                        }
                        Text(article.date, format: .relative(presentation: .named))
                            .font(.system(size: 10)).foregroundStyle(Pastel.subInk)
                        if unread {
                            Circle().fill(Color(red: 0.62, green: 0.55, blue: 0.92)).frame(width: 6, height: 6)
                        }
                    }

                    Text(store.title(article))
                        .font(.system(size: featured ? 14 : 13, weight: unread || featured ? .semibold : .medium))
                        .foregroundStyle(Pastel.ink.opacity(unread ? 1 : 0.7))
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    let points = store.bullets(article)
                    if !points.isEmpty {
                        BulletList(points: points, dot: tint, size: 11.5, color: Pastel.subInk)
                            .padding(.top, 1)
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(featured
                          ? AnyShapeStyle(LinearGradient(colors: [.white, Pastel.butter.opacity(0.55)],
                                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                          : AnyShapeStyle(Color.white.opacity(hovering ? 1 : 0.88)))
                    .shadow(color: (featured ? Pastel.gold : Pastel.lavender).opacity(hovering ? 0.7 : 0.35),
                            radius: hovering ? 6 : 3, y: 1)
            )
            .overlay(RoundedRectangle(cornerRadius: 12)
                .stroke(featured ? Pastel.gold.opacity(0.7) : tint.opacity(0.6), lineWidth: featured ? 1 : 0.6))
            .overlay(RoundedRectangle(cornerRadius: 12)
                .stroke(Color(red: 0.62, green: 0.55, blue: 0.92), lineWidth: selected ? 2 : 0))
        }
        .id(article.link)
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .contextMenu {
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
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Pastel.ink)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                    keyPoints
                    bodySection
                }
                .textSelection(.enabled)
                .padding(.horizontal, 20)
                .padding(.top, 6)
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
        HStack {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) { store.reading = nil }
            } label: {
                Label(lang.t(.back), systemImage: "chevron.left")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(Pastel.ink.opacity(0.75))
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Capsule().fill(Color.white.opacity(0.8)))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            Spacer()
            let saved = store.isBookmarked(article)
            Button { store.toggleBookmark(article) } label: {
                Label(saved ? lang.t(.unbookmark) : lang.t(.bookmark), systemImage: saved ? "bookmark.fill" : "bookmark")
                    .font(.system(size: 11.5, weight: .medium, design: .rounded))
                    .foregroundStyle(Pastel.ink.opacity(0.75))
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Capsule().fill(saved ? Pastel.lavender : Color.white.opacity(0.8)))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .help(lang == .ko ? "저장 (B) · ←/→ 이전·다음 기사" : "Save (B) · ←/→ previous/next story")
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 6)
    }

    private var meta: some View {
        HStack(spacing: 6) {
            Text(article.source?.name ?? "")
                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                .foregroundStyle(Pastel.ink.opacity(0.75))
                .padding(.horizontal, 8).padding(.vertical, 2)
                .background(Capsule().fill(tint.opacity(0.75)))
            if article.source?.official == true {
                Label(lang.t(.official), systemImage: "checkmark.seal.fill")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(Pastel.ink.opacity(0.6))
            }
            Text(store.category(article).name(lang))
                .font(.system(size: 10.5, design: .rounded)).foregroundStyle(Pastel.subInk)
            Spacer()
            Text(article.date.formatted(.dateTime.month(.abbreviated).day().hour().minute().locale(lang.locale)))
                .font(.system(size: 10.5)).foregroundStyle(Pastel.subInk)
        }
    }

    @ViewBuilder private var keyPoints: some View {
        let points = store.bullets(article)
        if !points.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Label(lang.t(.keyPoints), systemImage: "list.bullet")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(Pastel.ink.opacity(0.7))
                BulletList(points: points, dot: tint, size: 12.5, color: Pastel.ink.opacity(0.85), spacing: 6)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(tint.opacity(0.28)))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(tint.opacity(0.8), lineWidth: 0.6))
        }
    }

    @ViewBuilder private var bodySection: some View {
        HStack(spacing: 8) {
            Text(lang.t(.fullArticle))
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(Pastel.subInk)
            Rectangle().fill(Pastel.lavender).frame(height: 0.8)
        }
        .padding(.top, 4)

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
                .font(.system(size: 14.5, weight: .semibold))
                .foregroundStyle(Pastel.ink)
                .padding(.top, 6)
                .fixedSize(horizontal: false, vertical: true)
        case .paragraph:
            Text(b.text)
                .font(.system(size: 13.5))
                .foregroundStyle(Pastel.ink.opacity(0.9))
                .lineSpacing(5)
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
                .buttonStyle(PastelButton(fill: failed ? Pastel.mint : Pastel.lavender))
            }
            Spacer()
            Button { store.openInBrowser(article) } label: {
                Label(lang.t(.openOriginal), systemImage: "arrow.up.right.square")
            }
            .buttonStyle(PastelButton(fill: Pastel.sky))
        }
        .padding(.horizontal, 16).padding(.vertical, 9)
        .background(Color.white.opacity(0.85))
    }
}

// MARK: - Korean language pack

/// Shown in Korean mode until Apple's on-device English→Korean pack is installed.
struct LanguagePackBanner: View {
    @EnvironmentObject var store: NewsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("한국어 번역 언어팩이 필요해요", systemImage: "character.bubble")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(Pastel.ink)
            Text("제목·요약·기사 본문을 Mac에서 바로 번역하려면 영어→한국어 언어팩(무료)을 한 번 내려받아야 해요.")
                .font(.system(size: 11)).foregroundStyle(Pastel.subInk)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button("언어팩 다운로드") { store.downloadKoreanPack() }
                    .buttonStyle(PastelButton(fill: Pastel.mint))
                Button("시스템 설정에서 받기") { store.openTranslationSettings() }
                    .buttonStyle(PastelButton(fill: Pastel.lavender))
            }
            Text("시스템 설정 → 일반 → 언어 및 지역 → 번역 언어에서 ‘한국어’를 받아도 돼요.")
                .font(.system(size: 10)).foregroundStyle(Pastel.subInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Pastel.butter.opacity(0.8)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Pastel.gold.opacity(0.6), lineWidth: 0.6))
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
            Text(lang.t(.settingsAI)).font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(Pastel.ink)
            Text(lang.t(.settingsAIBody))
                .font(.system(size: 11.5)).foregroundStyle(Pastel.subInk)
                .fixedSize(horizontal: false, vertical: true)

            SecureField(store.hasAPIKey ? lang.t(.keySaved) : "sk-ant-…", text: $key)
                .textFieldStyle(.plain)
                .font(.system(size: 12, design: .monospaced))
                .padding(9)
                .background(RoundedRectangle(cornerRadius: 8).fill(.white))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Pastel.lavender, lineWidth: 1))

            HStack {
                if store.hasAPIKey {
                    Button(lang.t(.removeKey)) { store.setAPIKey(""); key = "" }
                        .buttonStyle(PastelButton(fill: Pastel.rose))
                }
                Spacer()
                Button(lang.t(.save)) {
                    store.setAPIKey(key); key = ""; isPresented = false
                }
                .buttonStyle(PastelButton(fill: Pastel.mint))
                .disabled(key.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            Divider().padding(.vertical, 4)

            Toggle(isOn: Binding(get: { store.launchAtLogin }, set: { store.setLaunchAtLogin($0) })) {
                Text(lang.t(.launchAtLogin)).font(.system(size: 12.5, weight: .medium, design: .rounded))
                    .foregroundStyle(Pastel.ink)
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .tint(Pastel.mint)

            Toggle(isOn: Binding(get: { store.notifyBigNews }, set: { store.setNotifyBigNews($0) })) {
                Label(lang.t(.notifyBig), systemImage: "bell.badge")
                    .font(.system(size: 12.5, weight: .medium, design: .rounded))
                    .foregroundStyle(Pastel.ink)
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .tint(Pastel.mint)

            Toggle(isOn: Binding(get: { store.notifyBriefing }, set: { store.setNotifyBriefing($0) })) {
                Label(lang.t(.notifyBriefing), systemImage: "sun.horizon")
                    .font(.system(size: 12.5, weight: .medium, design: .rounded))
                    .foregroundStyle(Pastel.ink)
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .tint(Pastel.mint)

            Divider().padding(.vertical, 4)

            Text(lang.t(.shortcuts)).font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(Pastel.ink)
            ShortcutsTable()

            Divider().padding(.vertical, 4)

            Text(lang.t(.sources)).font(.system(size: 13, weight: .semibold, design: .rounded))
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
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Pastel.ink.opacity(0.7))
                .rotationEffect(.degrees(spinning ? 360 : 0))
                .animation(spinning ? .linear(duration: 1).repeatForever(autoreverses: false) : .default,
                           value: spinning)
                .frame(width: 28, height: 28)
                .background(Circle().fill(hover ? Pastel.lavender.opacity(0.6) : Color.white.opacity(0.7)))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

struct PastelButton: ButtonStyle {
    let fill: Color
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .foregroundStyle(Pastel.ink)
            .padding(.horizontal, 14).padding(.vertical, 6)
            .background(Capsule().fill(fill.opacity(configuration.isPressed ? 1 : 0.8)))
    }
}
