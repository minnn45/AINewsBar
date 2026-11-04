import AppKit
import SwiftUI

/// Popover UI state plus keyboard shortcuts.
///
/// Keys are caught with an AppKit local event monitor rather than SwiftUI's `onKeyPress`, which only fires
/// when a focusable view holds focus (unreliable in a menu bar popover). Keys are matched by physical key
/// code so shortcuts also work while the Korean input source is active (j → ㅓ, etc.).
@MainActor
final class UIModel: ObservableObject {
    @Published var tab: Tab = .today { didSet { store?.selectedLink = nil } }
    @Published var category: NewsCategory = .all { didSet { store?.selectedLink = nil } }
    @Published var showSettings = false
    @Published var searching = false
    /// Debounced search text (the field itself keeps the live text).
    @Published var query = "" { didSet { store?.selectedLink = nil } }
    /// Bumped to ask the search field to take focus.
    @Published var focusSearchToken = 0

    weak var store: NewsStore?
    private var monitor: Any?

    var queryActive: Bool { searching && !query.trimmingCharacters(in: .whitespaces).isEmpty }

    func attach(_ store: NewsStore) {
        self.store = store
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return MainActor.assumeIsolated { self.handle(event) } ? nil : event
        }
    }

    // MARK: Search

    func openSearch() {
        withAnimation(.easeInOut(duration: 0.15)) {
            showSettings = false
            store?.reading = nil
            searching = true
        }
        focusSearchToken += 1
    }

    func closeSearch() {
        withAnimation(.easeInOut(duration: 0.15)) {
            searching = false
            query = ""
        }
        NSApp.keyWindow?.makeFirstResponder(nil)
    }

    // MARK: Navigation

    /// Stories in on-screen order, for ↑/↓ navigation.
    var navigable: [Article] {
        guard let store else { return [] }
        if searching { return queryActive ? store.search(query, category: category) : [] }
        switch tab {
        case .today: return store.bigNews(category) + store.today(category)
        case .past: return store.pastDays(category).flatMap { $0.groups.flatMap(\.articles) }
        case .saved: return store.saved(category)
        }
    }

    private func move(_ step: Int) {
        guard let store else { return }
        let list = navigable
        guard !list.isEmpty else { return }
        let current = list.firstIndex { $0.link == store.selectedLink }
        let next = current.map { min(max($0 + step, 0), list.count - 1) } ?? (step > 0 ? 0 : list.count - 1)
        store.selectedLink = list[next].link
    }

    private var selectedArticle: Article? {
        guard let link = store?.selectedLink else { return nil }
        return navigable.first { $0.link == link } ?? store?.article(link: link)
    }

    func openSelectedOrFirst() {
        guard let store, let a = selectedArticle ?? navigable.first else { return }
        store.selectedLink = a.link
        NSApp.keyWindow?.makeFirstResponder(nil)
        withAnimation(.easeInOut(duration: 0.18)) { store.open(a) }
    }

    // MARK: Key handling

    private enum Key {
        static let `return`: UInt16 = 36, enter: UInt16 = 76, space: UInt16 = 49, escape: UInt16 = 53
        static let left: UInt16 = 123, right: UInt16 = 124, down: UInt16 = 125, up: UInt16 = 126
        static let j: UInt16 = 38, k: UInt16 = 40, b: UInt16 = 11, o: UInt16 = 31, r: UInt16 = 15
        static let f: UInt16 = 3, slash: UInt16 = 44, one: UInt16 = 18, two: UInt16 = 19, three: UInt16 = 20
    }

    /// Returns true when the key was used (and should not reach the focused control).
    private func handle(_ event: NSEvent) -> Bool {
        guard let store, event.window != nil else { return false }
        let mods = event.modifierFlags.intersection([.command, .control, .option])
        let code = event.keyCode
        let editing = (event.window?.firstResponder as? NSTextView)?.isFieldEditor == true

        if mods == .command {
            switch code {
            case Key.f: openSearch(); return true
            case Key.one, Key.two, Key.three:
                guard !showSettings else { return false }
                if searching { closeSearch() }
                store.reading = nil
                withAnimation(.easeInOut(duration: 0.15)) {
                    tab = code == Key.one ? .today : code == Key.two ? .past : .saved
                }
                return true
            default: return false   // ⌘C / ⌘V / ⌘A etc. go to the text field
            }
        }
        guard mods.isEmpty else { return false }

        if code == Key.escape {
            if store.reading != nil { withAnimation(.easeInOut(duration: 0.18)) { store.reading = nil }; return true }
            if showSettings { withAnimation { showSettings = false }; return true }
            if searching { closeSearch(); return true }
            return false
        }

        // Typing in the search field (or the API-key field): only ↓ leaves it; everything else is text.
        if editing {
            guard searching, code == Key.down else { return false }
            event.window?.makeFirstResponder(nil)
            store.selectedLink = navigable.first?.link
            return true
        }
        if showSettings { return false }

        if let reading = store.reading {
            switch code {
            case Key.left, Key.right:
                let list = navigable
                guard let i = list.firstIndex(where: { $0.link == reading.link }) else { return true }
                let j = i + (code == Key.right ? 1 : -1)
                if list.indices.contains(j) {
                    store.selectedLink = list[j].link
                    store.open(list[j])
                }
                return true
            case Key.b: store.toggleBookmark(reading); return true
            case Key.o: store.openInBrowser(reading); return true
            default: return false   // let ↑/↓/space scroll the article
            }
        }

        switch code {
        case Key.down, Key.j: move(1)
        case Key.up, Key.k: move(-1)
        case Key.return, Key.enter, Key.space: openSelectedOrFirst()
        case Key.slash: openSearch()
        case Key.r: Task { await store.refresh() }
        case Key.b:
            guard let a = selectedArticle else { return false }
            store.toggleBookmark(a)
        case Key.o:
            guard let a = selectedArticle else { return false }
            store.openInBrowser(a)
        default: return false
        }
        return true
    }
}

/// Search field with its own text state, so typing doesn't redraw the whole popover on every keystroke.
struct SearchBar: View {
    @ObservedObject var ui: UIModel
    let placeholder: String
    let closeLabel: String
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass").font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(Pastel.subInk)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .foregroundStyle(Pastel.ink)
                .focused($focused)
                .onSubmit {
                    ui.query = text   // don't wait for the debounce
                    ui.openSelectedOrFirst()
                }
            if !text.isEmpty {
                Button { text = ""; ui.query = ""; focused = true } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 12)).foregroundStyle(Pastel.subInk)
                }
                .buttonStyle(.plain)
            }
            Button(closeLabel) { ui.closeSearch() }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(Pastel.ink.opacity(0.6))
        }
        .padding(.horizontal, 11).padding(.vertical, 7)
        .background(Capsule().fill(Color.white.opacity(0.9)))
        .overlay(Capsule().stroke(Pastel.lavender.opacity(0.9), lineWidth: 0.8))
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .onAppear { text = ui.query; focused = true }
        .onChange(of: ui.focusSearchToken) { focused = true }
        // Search runs 150 ms after typing stops.
        .task(id: text) {
            try? await Task.sleep(for: .milliseconds(150))
            if !Task.isCancelled, ui.query != text { ui.query = text }
        }
    }
}
