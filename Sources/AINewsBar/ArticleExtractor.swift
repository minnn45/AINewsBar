import Foundation

/// One readable piece of an article body.
struct ArticleBlock: Hashable {
    enum Kind { case heading, paragraph, bullet, quote }
    let kind: Kind
    let text: String
}

/// Pulls the readable body text out of a news article's HTML (no WebKit, no dependencies).
enum ArticleExtractor {
    static let userAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"

    static func fetch(_ link: String) async throws -> [ArticleBlock] {
        guard let url = URL(string: link) else { throw URLError(.badURL) }
        var req = URLRequest(url: url, timeoutInterval: 20)
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        req.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        req.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        let (data, resp) = try await URLSession.shared.data(for: req)
        if let code = (resp as? HTTPURLResponse)?.statusCode, code >= 400 { throw URLError(.badServerResponse) }
        let html = String(decoding: data, as: UTF8.self)
        return await Task.detached(priority: .userInitiated) { extract(html) }.value
    }

    private static let junkContainers = ["script", "style", "noscript", "svg", "template", "iframe", "nav",
                                         "header", "footer", "aside", "form", "button", "figure", "select"]
    private static let boilerplate = [
        "subscribe", "newsletter", "sign up", "sign in", "log in", "cookie", "all rights reserved",
        "©", "advertisement", "related:", "read more", "follow us", "share this", "privacy policy",
        "terms of service", "this story originally appeared", "techcrunch event", "affiliate commission",
        "contact the author", "send tips", "we may earn", "click here", "native ad", "special offers",
        "get the latest updates",
    ]

    /// Phrases that mark a block as an ad/promo no matter how long it is.
    private static let alwaysJunk = ["native ad", "second free", "special offers", "your browser does not support",
                                     "techcrunch event", "sign up for", "subscribe to"]
    /// Headings that introduce link lists rather than article content.
    private static let linkListHeadings: Set<String> = ["related", "more from", "read more", "most popular",
                                                        "recommended", "more stories", "related stories", "related articles"]

    static func extract(_ rawHTML: String) -> [ArticleBlock] {
        var html = rawHTML
        for tag in junkContainers {
            html = html.replacingOccurrences(of: "<\(tag)\\b[^>]*>[\\s\\S]*?</\(tag)>", with: " ",
                                             options: [.regularExpression, .caseInsensitive])
        }
        html = html.replacingOccurrences(of: "<!--[\\s\\S]*?-->", with: " ", options: .regularExpression)

        // Prefer the <article> (or <main>) region when the page has one with real text in it.
        // Try the tightest region first: up to the first </article> (related-story cards are often
        // separate <article>s further down), then the whole article span, then <main>.
        var candidates: [String] = []
        for (tag, backwards) in [("article", false), ("article", true), ("main", true)] {
            guard let start = html.range(of: "<\(tag)\\b", options: [.regularExpression, .caseInsensitive]) else { continue }
            let end = backwards
                ? html.range(of: "</\(tag)>", options: [.caseInsensitive, .backwards])
                : html.range(of: "</\(tag)>", options: .caseInsensitive, range: start.upperBound..<html.endIndex)
            if let end, start.lowerBound < end.lowerBound {
                candidates.append(String(html[start.lowerBound..<end.upperBound]))
            }
        }
        candidates.append(html)

        for region in candidates {
            let blocks = blocks(in: region)
            if blocks.filter({ $0.kind == .paragraph }).count >= 4 { return blocks }
        }
        return []
    }

    private static let blockRegex = try! NSRegularExpression(
        pattern: "<(p|h2|h3|li|blockquote)\\b[^>]*>([\\s\\S]*?)</\\1>", options: .caseInsensitive)

    private static let widgetClass = try! NSRegularExpression(
        pattern: "class=\"[^\"]*(deepdive|related|recirc|popular|teaser|promo|newsletter|sidebar)", options: .caseInsensitive)

    private static func blocks(in region: String) -> [ArticleBlock] {
        let ns = region as NSString
        var out: [ArticleBlock] = []
        var seen = Set<String>()
        var skippingLinks = false
        for m in blockRegex.matches(in: region, range: NSRange(location: 0, length: ns.length)) {
            let tag = ns.substring(with: m.range(at: 1)).lowercased()
            // Skip teaser cards (related / popular / newsletter widgets): look at the wrappers opened right
            // before this block (anything after the last closing tag) plus the block's own opening tag.
            let ctxStart = max(0, m.range.location - 300)
            var context = ns.substring(with: NSRange(location: ctxStart, length: m.range.location - ctxStart))
            if let close = context.range(of: "</", options: .backwards) { context = String(context[close.upperBound...]) }
            context += ns.substring(with: NSRange(location: m.range.location, length: min(160, m.range.length)))
            if widgetClass.firstMatch(in: context, range: NSRange(location: 0, length: (context as NSString).length)) != nil { continue }
            let inner = ns.substring(with: m.range(at: 2))
            // A <li> holding nested paragraphs/lists is a wrapper, not content.
            if tag == "li", inner.range(of: "<(p|ul|ol|li)\\b", options: [.regularExpression, .caseInsensitive]) != nil { continue }
            let text = inner.strippingHTML
            guard !text.isEmpty, seen.insert(text).inserted else { continue }
            let lower = text.lowercased()
            let words = text.split(separator: " ").count
            if alwaysJunk.contains(where: lower.contains) { continue }
            if (tag == "h2" || tag == "h3"), linkListHeadings.contains(lower.trimmingCharacters(in: .punctuationCharacters)) {
                skippingLinks = true; continue
            }
            if skippingLinks {
                if tag == "p" && words >= 15 { skippingLinks = false } else { continue }
            }

            let kind: ArticleBlock.Kind
            switch tag {
            case "h2", "h3":
                guard words <= 18, text.count >= 3, !boilerplate.contains(where: lower.contains) else { continue }
                kind = .heading
            case "li":
                guard words >= 6, text.count <= 400, !boilerplate.contains(where: lower.contains) else { continue }
                kind = .bullet
            case "blockquote":
                guard words >= 6 else { continue }
                kind = .quote
            default:
                guard words >= 8 else { continue }
                // Short lines with boilerplate words are site chrome; long paragraphs that merely mention them are content.
                if words < 30, boilerplate.contains(where: lower.contains) { continue }
                kind = .paragraph
            }
            out.append(ArticleBlock(kind: kind, text: text))
        }
        // Drop headings/bullets that trail after the last real paragraph (usually "More from…" lists).
        if let last = out.lastIndex(where: { $0.kind == .paragraph }) { out = Array(out[...last]) }
        // Drop leading list items/headings before the first paragraph (menus, tags).
        if let first = out.firstIndex(where: { $0.kind == .paragraph }) {
            out = out.enumerated().filter { $0.offset >= first || $0.element.kind == .quote }.map(\.element)
        }
        return Array(out.prefix(80))
    }
}
