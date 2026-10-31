import Foundation

/// Rule-based filtering/categorizing, used always (ads) and as fallback when no API key is set.
enum LocalHeuristics {
    private static let promoPatterns = [
        "sponsored", "partner content", "brandvoice", "advertorial", "presented by", "in partnership with",
        "% off", "discount", "coupon", "promo code", "black friday", "cyber monday",
        "prime day", "giveaway", "on sale", "price drop", "save $", "lowest price", "best buy",
        "webinar", "register now", "at techcrunch", "techcrunch disrupt", "founder summit", "tc sessions", "strictlyvc", "early bird", "tickets", "buy now", "gift guide", "best ai gifts",
    ]

    /// Shopping-roundup signals that only make sense in a headline ("deals" in body text is usually news).
    private static let promoTitlePatterns = ["deals", "best ai gadgets", "how to buy", "where to buy"]

    /// Lab-blog categories that are customer case studies / marketing rather than announcements.
    private static let officialPromoCategories: Set<String> = ["startup", "openai on openai", "ai adoption", "customer stories"]

    static func isPromotional(_ a: Article) -> Bool {
        let title = a.title.lowercased()
        if a.source?.official == true {
            let cats = a.rawCategories.map { $0.lowercased() }
            // OpenAI tags real announcements; its untagged posts are customer stories.
            if a.sourceID == "openai" && cats.isEmpty { return true }
            if cats.contains(where: officialPromoCategories.contains) { return true }
            // "X cut wait times 75% with GPT-6", "achieves 954% ROI", "helps Y ... with ChatGPT"
            if title.range(of: "\\d+(\\.\\d+)?\\s?%|\\broi\\b", options: .regularExpression) != nil { return true }
            if title.range(of: "\\b(helps|uses|with|using)\\b.*\\b(gpt|chatgpt|codex|openai|gemini)", options: .regularExpression) != nil
                && title.range(of: "^(introducing|announcing|openai|google|gemini|gpt)", options: .regularExpression) == nil { return true }
        }
        if promoTitlePatterns.contains(where: { title.range(of: "\\b\($0)\\b", options: .regularExpression) != nil }) {
            return true
        }
        let hay = ([a.title, a.excerpt] + a.rawCategories).joined(separator: " ").lowercased()
        return promoPatterns.contains { p in
            if p.count <= 5 { // short words: match whole word only
                return hay.range(of: "\\b\(NSRegularExpression.escapedPattern(for: p))\\b",
                                 options: .regularExpression) != nil
            }
            return hay.contains(p)
        }
    }

    static func category(_ a: Article) -> NewsCategory {
        let t = (a.title + " " + a.excerpt).lowercased()
        func has(_ ws: [String]) -> Bool { ws.contains { t.contains($0) } }
        if has(["regulat", "lawsuit", "court", "senate", "congress", " eu ", "policy", "ban ", "copyright", "government", "safety bill"]) { return .policy }
        if has(["paper", "researchers", "study", "benchmark", "arxiv", "scientists"]) { return .research }
        if has(["gpt", "claude", "gemini", "llama", "model", "open-weight", "open source model", "mistral", "deepseek"]) { return .models }
        if has(["funding", "raises", "valuation", "acquire", "ipo", "revenue", "billion", "startup", "layoff", "investor"]) { return .business }
        return .products
    }

    static func shortSummary(_ a: Article) -> String {
        let s = a.excerpt
        guard !s.isEmpty else { return "" }
        // First two sentences, capped.
        var sentences: [String] = []
        s.enumerateSubstrings(in: s.startIndex..., options: .bySentences) { sub, _, _, stop in
            if let sub { sentences.append(sub.trimmingCharacters(in: .whitespaces)) }
            if sentences.count == 2 { stop = true }
        }
        var out = sentences.joined(separator: " ")
        if out.count > 260 { out = String(out.prefix(257)) + "…" }
        return out.trimmingCharacters(in: .whitespaces)
    }
}

/// Summarizes new articles with the Claude API (raw HTTP – Swift has no official SDK).
struct ClaudeSummarizer {
    let apiKey: String
    var model = "claude-opus-5-5"

    enum SummarizerError: LocalizedError {
        case http(Int, String), refusal, badResponse
        var errorDescription: String? {
            switch self {
            case .http(let code, let body): return "Claude API error \(code): \(body.prefix(160))"
            case .refusal: return "Claude declined to summarize this batch."
            case .badResponse: return "Unexpected response from Claude API."
            }
        }
    }

    func summarize(_ articles: [Article]) async throws -> [String: SummaryInfo] {
        guard !articles.isEmpty else { return [:] }

        let listing = articles.enumerated().map { i, a in
            """
            <article index="\(i)">
            <source>\(a.source?.name ?? a.sourceID)\(a.source?.official == true ? " (official lab blog)" : "")</source>
            <title>\(a.title)</title>
            <excerpt>\(a.excerpt.prefix(1200))</excerpt>
            </article>
            """
        }.joined(separator: "\n")

        let prompt = """
        You are writing the item summaries for a small menu bar AI-news reader. The reader wants to \
        quickly know what actually happened in the AI field — not marketing.

        For each article below, return:
        - summary: 1–2 plain, factual sentences (max ~45 words) saying what happened and why it matters. \
        No hype words, no "In this article", no clickbait.
        - category: one of Models, Research, Business, Policy, Products.
        - major: true only for big AI-field news: a new frontier/flagship model or major product from a \
        leading lab (OpenAI, Google DeepMind, Anthropic, Meta, xAI, etc.), a significant research breakthrough, \
        a major acquisition/funding/IPO, or important regulation. Most items are false.
        - promotional: true if the item is primarily an ad, sponsored/partner content, a shopping deal, \
        an event/ticket/webinar promotion, or a product listicle; false for genuine news or analysis.

        Return one entry per article, using its index.

        \(listing)
        """

        let schema: [String: Any] = [
            "type": "object",
            "properties": [
                "items": [
                    "type": "array",
                    "items": [
                        "type": "object",
                        "properties": [
                            "index": ["type": "integer"],
                            "summary": ["type": "string"],
                            "category": ["type": "string", "enum": ["Models", "Research", "Business", "Policy", "Products"]],
                            "promotional": ["type": "boolean"],
                            "major": ["type": "boolean"],
                        ],
                        "required": ["index", "summary", "category", "promotional", "major"],
                        "additionalProperties": false,
                    ],
                ],
            ],
            "required": ["items"],
            "additionalProperties": false,
        ]

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 16000,
            "fallbacks": "default",
            "output_config": [
                "effort": "low",
                "format": ["type": "json_schema", "schema": schema],
            ],
            "messages": [["role": "user", "content": prompt]],
        ]

        var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        req.httpMethod = "POST"
        req.timeoutInterval = 300
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue("2026-10-21", forHTTPHeaderField: "anthropic-version")
        req.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp) = try await URLSession.shared.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            throw SummarizerError.http(status, String(decoding: data, as: UTF8.self))
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SummarizerError.badResponse
        }
        if json["stop_reason"] as? String == "refusal" { throw SummarizerError.refusal }

        let text = (json["content"] as? [[String: Any]] ?? [])
            .filter { $0["type"] as? String == "text" }
            .compactMap { $0["text"] as? String }
            .joined()
        guard let parsed = try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any],
              let items = parsed["items"] as? [[String: Any]] else {
            throw SummarizerError.badResponse
        }

        var out: [String: SummaryInfo] = [:]
        for item in items {
            guard let idx = item["index"] as? Int, articles.indices.contains(idx),
                  let summary = item["summary"] as? String else { continue }
            let cat = NewsCategory(rawValue: item["category"] as? String ?? "") ?? .products
            out[articles[idx].link] = SummaryInfo(summary: summary, category: cat,
                                                  promotional: item["promotional"] as? Bool ?? false,
                                                  major: item["major"] as? Bool)
        }
        return out
    }
}
