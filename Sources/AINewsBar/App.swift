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

enum Tab { case today, past }

// MARK: - Root

struct ContentView: View {
    @EnvironmentObject var store: NewsStore
    @State private var tab: Tab = .today
    @State private var category: NewsCategory = .all
    @State private var showSettings = false
    @State private var translationConfig: TranslationSession.Configuration?

    private var lang: AppLanguage { store.language }

    var body: some View {
        VStack(spacing: 0) {
            header
            if showSettings {
                SettingsView(isPresented: $showSettings)
            } else {
                tabs
                chips
                Group {
                    switch tab {
                    case .today: TodayList(category: category)
                    case .past: PastList(category: category)
                    }
                }
                .frame(maxHeight: .infinity)
                footer
            }
        }
        .frame(width: 400, height: 600)
        .background(
            LinearGradient(colors: [.white, Pastel.lavender.opacity(0.35), Pastel.mint.opacity(0.30)],
                           startPoint: .top, endPoint: .bottom)
        )
        // On-device English → Korean translation (Apple Translation framework).
        .translationTask(translationConfig) { session in
            await store.translatePending(using: session)
        }
        .onAppear(perform: requestTranslation)
        .onChange(of: store.language) { requestTranslation() }
        .onChange(of: store.untranslated.count) { requestTranslation() }
    }

    private func requestTranslation() {
        guard store.language == .ko, !store.untranslated.isEmpty, !store.isTranslating else { return }
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
            IconButton(system: "arrow.clockwise", spinning: store.isLoading) {
                Task { await store.refresh() }
            }
            IconButton(system: showSettings ? "xmark" : "gearshape") {
                withAnimation(.easeInOut(duration: 0.15)) { showSettings.toggle() }
            }
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

    // MARK: Tabs & chips

    private var tabs: some View {
        HStack(spacing: 4) {
            tabButton(.today, lang.t(.today), "sun.max")
            tabButton(.past, lang.t(.past), "calendar")
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
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
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
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(days.enumerated()), id: \.element.id) { index, day in
                        // Most recent day starts open, older days start folded.
                        let isOpen = touched.contains(day.day) ? !collapsed.contains(day.day) : index == 0
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

        Button { store.open(article) } label: {
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

                    let s = store.summary(article)
                    if !s.isEmpty {
                        Text(s)
                            .font(.system(size: 11.5))
                            .foregroundStyle(Pastel.subInk)
                            .lineSpacing(1.5)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
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
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .contextMenu {
            let ko = store.language == .ko
            Button(ko ? "브라우저에서 열기" : "Open in Browser") { store.open(article) }
            Button(ko ? "링크 복사" : "Copy Link") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(article.link, forType: .string)
            }
            Button(ko ? "읽음으로 표시" : "Mark as Read") { store.markRead(article) }
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
