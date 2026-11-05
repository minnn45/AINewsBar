import SwiftUI

/// A ScrollView that keeps the keyboard-selected story in view.
struct SelectionScroll<Content: View>: View {
    @EnvironmentObject var store: NewsStore
    @ViewBuilder let content: Content

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView { content }
                .onChange(of: store.selectedLink) {
                    guard let link = store.selectedLink else { return }
                    withAnimation(.easeInOut(duration: 0.15)) { proxy.scrollTo(link) }
                }
        }
    }
}

// MARK: - Search results

struct SearchList: View {
    @EnvironmentObject var store: NewsStore
    let query: String
    let category: NewsCategory

    var body: some View {
        let q = query.trimmingCharacters(in: .whitespaces)
        let results = store.search(q, category: category)
        let lang = store.language
        if q.isEmpty {
            EmptyState(symbol: "magnifyingglass", text: lang == .ko
                       ? "제목·요약·본문 발췌에서 찾아요.\n영어와 한국어 모두 검색돼요.\n↓ 로 결과로 이동, ↵ 로 열기"
                       : "Searches titles, key points and excerpts.\n↓ to jump to results, ↵ to open")
        } else if results.isEmpty {
            EmptyState(symbol: "questionmark.circle", text: lang.t(.noResults))
        } else {
            SelectionScroll {
                LazyVStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text(lang == .ko ? "검색 결과 \(results.count)건" : "\(results.count) results")
                            .font(.system(size: 12, weight: .bold)).foregroundStyle(Pastel.ink)
                        Spacer()
                        Text("↑↓ · ↵").font(.system(size: 11)).foregroundStyle(Pastel.subInk)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 6)
                    ForEach(results) { ArticleCard(article: $0, showCategory: true) }
                }
            }
        }
    }
}

// MARK: - Saved

struct SavedList: View {
    @EnvironmentObject var store: NewsStore
    let category: NewsCategory

    var body: some View {
        let items = store.saved(category)
        if items.isEmpty {
            EmptyState(symbol: "bookmark", text: store.language.t(.emptySaved))
        } else {
            SelectionScroll {
                LazyVStack(alignment: .leading, spacing: 0) {
                    SectionTitle(title: store.language.t(.saved), count: items.count,
                                 symbol: "bookmark.fill", symbolColor: Pastel.accent)
                    ForEach(items) { ArticleCard(article: $0, showCategory: true) }
                }
            }
        }
    }
}

// MARK: - Daily briefing

struct BriefingCard: View {
    @EnvironmentObject var store: NewsStore
    @AppStorage("briefingExpanded") private var expanded = true

    var body: some View {
        if let b = store.currentBriefing() {
            let lang = store.language
            VStack(alignment: .leading, spacing: 8) {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { expanded.toggle() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "sun.horizon.fill").font(.system(size: 11))
                            .foregroundStyle(Pastel.gold)
                        Text(lang.t(.briefing))
                            .font(.system(size: 12.5, weight: .bold))
                            .foregroundStyle(Pastel.ink)
                        if b.byClaude {
                            Image(systemName: "wand.and.stars").font(.system(size: 9.5))
                                .foregroundStyle(Pastel.subInk)
                        }
                        Spacer()
                        if store.isBriefing { ProgressView().controlSize(.mini) }
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9.5, weight: .bold))
                            .rotationEffect(.degrees(expanded ? 0 : -90))
                            .foregroundStyle(Pastel.subInk)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Text(b.headline)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Pastel.ink)
                    .fixedSize(horizontal: false, vertical: true)

                if expanded {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(b.points.enumerated()), id: \.offset) { _, p in
                            BriefingPoint(text: p.text, article: p.link.flatMap(store.article(link:)))
                        }
                    }
                    if !b.byClaude && !store.hasAPIKey {
                        Text(lang.t(.briefingNeedsKey))
                            .font(.system(size: 10.5)).foregroundStyle(Pastel.subInk)
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(Pastel.sky.opacity(0.7)))
        }
    }
}

private struct BriefingPoint: View {
    @EnvironmentObject var store: NewsStore
    let text: String
    let article: Article?
    @State private var hover = false

    var body: some View {
        Button {
            if let article { withAnimation(.easeInOut(duration: 0.18)) { store.open(article) } }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Circle().fill(Pastel.ink.opacity(0.45)).frame(width: 4.5, height: 4.5)
                    .alignmentGuide(.firstTextBaseline) { $0[.bottom] + 12 * 0.28 }
                Text(text)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Pastel.body)
                    .underline(hover && article != nil, color: Pastel.ink.opacity(0.4))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(article == nil)
        .onHover { hover = $0 }
    }
}

// MARK: - Shortcuts

struct ShortcutsTable: View {
    @EnvironmentObject var store: NewsStore

    var body: some View {
        let ko = store.language == .ko
        let rows: [(String, String)] = [
            ("↑ ↓  /  j k", ko ? "기사 이동" : "Move between stories"),
            ("↵", ko ? "열기 (한국어: 앱에서 읽기)" : "Open"),
            ("B", ko ? "저장 / 저장 해제" : "Save / unsave"),
            ("O", ko ? "원문을 브라우저에서 열기" : "Open original in browser"),
            ("← →", ko ? "읽는 중: 이전·다음 기사" : "In reader: previous / next"),
            ("⌘F  /  /", ko ? "검색" : "Search"),
            ("⌘1 ⌘2 ⌘3", ko ? "오늘 · 지난 뉴스 · 저장됨" : "Today · Past · Saved"),
            ("R", ko ? "새로고침" : "Refresh"),
            ("Esc", ko ? "뒤로 / 검색 닫기" : "Back / close search"),
        ]
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 5) {
            ForEach(rows, id: \.0) { key, label in
                GridRow {
                    Text(key)
                        .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(Pastel.ink.opacity(0.8))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 5).fill(Pastel.fill))
                    Text(label).font(.system(size: 11.5)).foregroundStyle(Pastel.subInk)
                }
            }
        }
    }
}
