import Foundation
import SwiftUI

struct FeedSource: Identifiable, Hashable {
    let id: String
    let name: String
    let url: URL
    let tint: Color
    /// First-party announcements from an AI lab (vs. journalism).
    var official = false

    /// Short label for the round avatar in the feed.
    var initials: String {
        switch id {
        case "openai": return "OA"
        case "deepmind": return "DM"
        case "googleai": return "G"
        case "techcrunch": return "TC"
        case "verge": return "V"
        case "mittr": return "MIT"
        case "ars": return "A"
        case "wired": return "W"
        default: return String(name.prefix(1))
        }
    }

    static let all: [FeedSource] = [
        // Official lab announcements
        .init(id: "openai", name: "OpenAI",
              url: URL(string: "https://openai.com/news/rss.xml")!,
              tint: Pastel.sage, official: true),
        .init(id: "deepmind", name: "Google DeepMind",
              url: URL(string: "https://deepmind.google/blog/rss.xml")!,
              tint: Pastel.aqua, official: true),
        .init(id: "googleai", name: "Google AI",
              url: URL(string: "https://blog.google/technology/ai/rss/")!,
              tint: Pastel.apricot, official: true),
        // News outlets
        .init(id: "techcrunch", name: "TechCrunch",
              url: URL(string: "https://techcrunch.com/category/artificial-intelligence/feed/")!,
              tint: Pastel.mint),
        .init(id: "verge", name: "The Verge",
              url: URL(string: "https://www.theverge.com/rss/ai-artificial-intelligence/index.xml")!,
              tint: Pastel.lavender),
        .init(id: "mittr", name: "MIT Tech Review",
              url: URL(string: "https://www.technologyreview.com/topic/artificial-intelligence/feed")!,
              tint: Pastel.peach),
        .init(id: "ars", name: "Ars Technica",
              url: URL(string: "https://arstechnica.com/ai/feed/")!,
              tint: Pastel.sky),
        .init(id: "wired", name: "WIRED",
              url: URL(string: "https://www.wired.com/feed/tag/ai/latest/rss")!,
              tint: Pastel.rose),
    ]
}

enum NewsCategory: String, CaseIterable, Codable, Identifiable {
    case all = "All"
    case models = "Models"
    case research = "Research"
    case business = "Business"
    case policy = "Policy"
    case products = "Products"
    var id: String { rawValue }

    func name(_ lang: AppLanguage) -> String {
        guard lang == .ko else { return rawValue }
        switch self {
        case .all: return "전체"
        case .models: return "모델"
        case .research: return "연구"
        case .business: return "비즈니스"
        case .policy: return "정책"
        case .products: return "제품·서비스"
        }
    }

    var symbol: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .models: return "cpu"
        case .research: return "flask"
        case .business: return "chart.line.uptrend.xyaxis"
        case .policy: return "building.columns"
        case .products: return "app.badge"
        }
    }
}

enum AppLanguage: String, CaseIterable, Identifiable {
    case en, ko
    var id: String { rawValue }
    var locale: Locale { Locale(identifier: self == .ko ? "ko_KR" : "en_US") }

    enum Key {
        case appTitle, today, past, updating, loading, updated, new, empty, emptyPast, gathering,
             aiOn, basic, markAllRead, quit, translating, translateFailed, offline, stories,
             searchPlaceholder, noResults, saved, emptySaved, bookmark, unbookmark, briefing, briefingNeedsKey,
             notifyBriefing, shortcuts, results,
             back, openOriginal, openTranslatedWeb, fetchingArticle, translatingArticle, articleUnavailable, keyPoints, fullArticle,
             settingsAI, settingsAIBody, keySaved, removeKey, save, sources, sourcesNote, language, launchAtLogin, notifyBig, bigNews, official, outlets
    }

    func t(_ k: Key) -> String {
        let ko = self == .ko
        switch k {
        case .appTitle: return ko ? "AI 뉴스" : "AI News"
        case .today: return ko ? "오늘" : "Today"
        case .past: return ko ? "지난 뉴스" : "Past days"
        case .updating: return ko ? "업데이트 중…" : "Updating…"
        case .loading: return ko ? "최신 소식을 불러오는 중" : "Loading latest stories"
        case .updated: return ko ? "업데이트" : "Updated"
        case .new: return ko ? "새 소식" : "new"
        case .empty: return ko ? "지난 24시간 동안 새 소식이 없어요." : "No new stories in the last 24 hours."
        case .emptyPast: return ko ? "지난 뉴스가 쌓이면 여기에 날짜별로 정리돼요." : "Older stories will collect here, grouped by day."
        case .gathering: return ko ? "최신 AI 뉴스를 모으는 중…" : "Gathering the latest AI news…"
        case .aiOn: return ko ? "AI 요약 사용 중" : "AI summaries on"
        case .basic: return ko ? "기본 요약" : "Basic summaries"
        case .markAllRead: return ko ? "모두 읽음" : "Mark all read"
        case .quit: return ko ? "종료" : "Quit"
        case .translating: return ko ? "번역 중…" : "Translating…"
        case .translateFailed: return ko ? "번역에 실패했어요" : "Translation failed"
        case .offline: return ko ? "뉴스를 불러오지 못했어요. 인터넷 연결을 확인해 주세요." : "Couldn't reach news sources. Check your connection."
        case .stories: return ko ? "개" : "stories"
        case .searchPlaceholder: return ko ? "지난 30일 뉴스 검색" : "Search the last 30 days"
        case .noResults: return ko ? "검색 결과가 없어요." : "No matching stories."
        case .results: return ko ? "건" : "results"
        case .saved: return ko ? "저장됨" : "Saved"
        case .emptySaved: return ko
            ? "기사에서 북마크를 누르거나 B 키를 누르면 여기에 모여요. 저장한 기사는 30일이 지나도 남아요."
            : "Bookmark a story (or press B) to keep it here. Saved stories never expire."
        case .bookmark: return ko ? "저장" : "Save"
        case .unbookmark: return ko ? "저장 해제" : "Remove from Saved"
        case .briefing: return ko ? "오늘의 브리핑" : "Today's briefing"
        case .briefingNeedsKey: return ko
            ? "API 키를 넣으면 Claude가 오늘의 핵심을 정리해 줘요."
            : "Add an API key and Claude will write a briefing of the day."
        case .notifyBriefing: return ko ? "아침 브리핑 알림 (오전 7시 이후)" : "Morning briefing notification (after 7 AM)"
        case .shortcuts: return ko ? "키보드 단축키" : "Keyboard shortcuts"
        case .back: return ko ? "목록" : "Back"
        case .openOriginal: return ko ? "원문 보기" : "Open original"
        case .openTranslatedWeb: return ko ? "웹 번역으로 보기" : "View web translation"
        case .fetchingArticle: return ko ? "기사 본문을 가져오는 중…" : "Fetching the article…"
        case .translatingArticle: return ko ? "본문 번역 중" : "Translating"
        case .articleUnavailable: return ko
            ? "이 사이트는 본문을 앱에서 불러올 수 없어요. 아래 버튼으로 번역된 웹페이지를 열 수 있어요."
            : "This site doesn't allow loading the article in the app."
        case .keyPoints: return ko ? "핵심 요약" : "Key points"
        case .fullArticle: return ko ? "기사 본문" : "Full article"
        case .settingsAI: return ko ? "AI 요약" : "AI summaries"
        case .settingsAIBody: return ko
            ? "키가 없으면 언론사 기사 첫 문장을 보여줘요. Anthropic API 키를 넣으면 Claude가 새 기사마다 짧고 중립적인 요약을 쓰고, 주제를 분류하고, 광고성 글을 숨겨요. 요약은 저장되므로 기사당 한 번만 요청해요."
            : "Without a key, each story shows the first lines from the publisher. Add an Anthropic API key and Claude writes a short, neutral summary of each new story, sorts it into a topic, and hides anything promotional. Summaries are cached, so each story is only summarized once."
        case .keySaved: return ko ? "키체인에 저장됨 — 바꾸려면 붙여넣기" : "Key saved in Keychain — paste to replace"
        case .removeKey: return ko ? "키 삭제" : "Remove key"
        case .save: return ko ? "저장" : "Save"
        case .sources: return ko ? "뉴스 출처" : "Sources"
        case .sourcesNote: return ko
            ? "30분마다, 자정마다, 그리고 Mac이 깨어날 때 업데이트 · 지난 30일 보관"
            : "Updates every 30 min, at midnight, and on wake · keeps 30 days"
        case .language: return ko ? "언어" : "Language"
        case .bigNews: return ko ? "주요 뉴스" : "Big news"
        case .official: return ko ? "공식" : "Official"
        case .outlets: return ko ? "언론사" : "News outlets"
        case .notifyBig: return ko ? "주요 뉴스 알림" : "Notify me about big news"
        case .launchAtLogin: return ko ? "로그인 시 자동 실행" : "Launch at login"
        }
    }
}

struct Article: Identifiable, Hashable, Codable {
    var id: String { link }
    let title: String
    let link: String
    let excerpt: String
    let date: Date
    let sourceID: String
    let rawCategories: [String]

    var source: FeedSource? { FeedSource.all.first { $0.id == sourceID } }
}

/// Cached result of summarizing one article (persisted so we never re-summarize).
struct SummaryInfo: Codable {
    let summary: String
    /// Key points shown under the headline (nil for summaries cached before bullets existed).
    var bullets: [String]?
    let category: NewsCategory
    let promotional: Bool
    /// Claude's judgment that this is major AI news (nil for summaries cached before this existed).
    var major: Bool?
    /// Whether Claude read the full article body (vs. only the RSS excerpt).
    var fromBody: Bool? = nil
}

/// The day's top developments, written by Claude (stored so it survives relaunches).
struct Briefing: Codable {
    struct Point: Codable, Hashable {
        let en: String
        let ko: String
        /// Articles this point is based on.
        let links: [String]
    }
    let generated: Date
    let storyCount: Int
    let headlineEN: String
    let headlineKO: String
    let points: [Point]
}

enum Pastel {
    static let mint     = Color(red: 0.78, green: 0.93, blue: 0.86)
    static let lavender = Color(red: 0.87, green: 0.84, blue: 0.97)
    static let peach    = Color(red: 0.99, green: 0.87, blue: 0.80)
    static let sky      = Color(red: 0.80, green: 0.90, blue: 0.98)
    static let rose     = Color(red: 0.98, green: 0.84, blue: 0.89)
    static let butter   = Color(red: 0.99, green: 0.95, blue: 0.80)
    static let sage     = Color(red: 0.84, green: 0.90, blue: 0.80)
    static let aqua     = Color(red: 0.78, green: 0.92, blue: 0.94)
    static let apricot  = Color(red: 0.99, green: 0.90, blue: 0.74)
    static let gold     = Color(red: 0.96, green: 0.80, blue: 0.45)
    // Neutral frame (clean, Figma-kit style): near-black text, light gray fills, hairline borders.
    static let ink      = Color(red: 0.086, green: 0.094, blue: 0.137)   // #161823
    static let body     = Color(red: 0.29, green: 0.30, blue: 0.34)      // bullet / body text
    static let subInk   = Color(red: 0.54, green: 0.55, blue: 0.58)      // #8A8C93
    static let line     = Color(red: 0.902, green: 0.902, blue: 0.902)   // #E6E6E6
    static let divider  = Color(red: 0.937, green: 0.937, blue: 0.945)   // #EFEFF1
    static let fill     = Color(red: 0.961, green: 0.961, blue: 0.961)   // #F5F5F5
    /// Deeper lavender for the few places that need a clear accent (tab underline, selection, unread dot).
    static let accent   = Color(red: 0.55, green: 0.48, blue: 0.86)
}
