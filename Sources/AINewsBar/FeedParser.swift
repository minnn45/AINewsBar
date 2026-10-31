import Foundation

/// Minimal RSS 2.0 + Atom parser.
final class FeedParser: NSObject, XMLParserDelegate {
    private let sourceID: String
    private var articles: [Article] = []

    private var inItem = false
    private var text = ""
    private var title = "", link = "", desc = "", dateStr = ""
    private var cats: [String] = []

    init(sourceID: String) { self.sourceID = sourceID }

    static func parse(_ data: Data, sourceID: String) -> [Article] {
        let p = FeedParser(sourceID: sourceID)
        let xml = XMLParser(data: data)
        xml.delegate = p
        xml.parse()
        return p.articles
    }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes: [String: String] = [:]) {
        text = ""
        switch name {
        case "item", "entry":
            inItem = true
            title = ""; link = ""; desc = ""; dateStr = ""; cats = []
        case "link" where inItem:
            // Atom: <link rel="alternate" href="..."/>
            if let href = attributes["href"], (attributes["rel"] ?? "alternate") == "alternate", link.isEmpty {
                link = href
            }
        case "category" where inItem:
            if let term = attributes["term"] { cats.append(term) }
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

    func parser(_ parser: XMLParser, foundCDATA block: Data) {
        text += String(decoding: block, as: UTF8.self)
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName qName: String?) {
        guard inItem else { return }
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch name {
        case "title": title = t
        case "link": if link.isEmpty, !t.isEmpty { link = t }
        case "description", "summary": if desc.isEmpty { desc = t }
        case "content", "content:encoded": if desc.isEmpty { desc = t }
        case "pubDate", "published", "updated", "dc:date": if dateStr.isEmpty { dateStr = t }
        case "category": if !t.isEmpty { cats.append(t) }
        case "item", "entry":
            inItem = false
            if !title.isEmpty, !link.isEmpty {
                articles.append(Article(
                    title: title.htmlDecoded,
                    link: link,
                    excerpt: desc.strippingHTML,
                    date: Self.parseDate(dateStr) ?? Date.distantPast,
                    sourceID: sourceID,
                    rawCategories: cats))
            }
        default: break
        }
        text = ""
    }

    private static let rfc822: [DateFormatter] = {
        ["EEE, dd MMM yyyy HH:mm:ss Z", "EEE, dd MMM yyyy HH:mm:ss zzz", "dd MMM yyyy HH:mm:ss Z"].map {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = $0
            return f
        }
    }()

    static func parseDate(_ s: String) -> Date? {
        let iso = ISO8601DateFormatter()
        if let d = iso.date(from: s) { return d }
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: s) { return d }
        for f in rfc822 { if let d = f.date(from: s) { return d } }
        return nil
    }
}

extension String {
    var strippingHTML: String {
        var s = replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        s = s.htmlDecoded
        s = s.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        // Drop boilerplate tails like "The post X appeared first on Y."
        if let r = s.range(of: "The post .* appeared first on .*", options: .regularExpression) {
            s.removeSubrange(r)
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var htmlDecoded: String {
        var s = self
        let map = ["&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'", "&apos;": "'",
                   "&nbsp;": " ", "&#8217;": "’", "&#8216;": "‘", "&#8220;": "“", "&#8221;": "”",
                   "&#8211;": "–", "&#8212;": "—", "&#8230;": "…", "&hellip;": "…", "&rsquo;": "’",
                   "&lsquo;": "‘", "&ldquo;": "“", "&rdquo;": "”", "&mdash;": "—", "&ndash;": "–"]
        for (k, v) in map { s = s.replacingOccurrences(of: k, with: v) }
        // Numeric entities (&#123; / &#x1F;)
        while let r = s.range(of: "&#x?[0-9A-Fa-f]+;", options: .regularExpression) {
            let body = s[r].dropFirst(2).dropLast()
            let code = body.hasPrefix("x") ? UInt32(body.dropFirst(), radix: 16) : UInt32(body)
            s.replaceSubrange(r, with: code.flatMap(Unicode.Scalar.init).map { String(Character($0)) } ?? "")
        }
        return s
    }
}
