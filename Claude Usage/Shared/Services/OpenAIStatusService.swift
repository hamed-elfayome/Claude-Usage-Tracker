import Foundation

/// Fetches the public OpenAI service status used by Codex profiles.
///
/// OpenAI's current incident.io page publishes live incidents through its Atom
/// feed. The legacy Statuspage-compatible component endpoint can report stale
/// "operational" values while an incident is still shown on the status page, so
/// it is used only as a fallback.
final class OpenAIStatusService {
    private struct ComponentsResponse: Decodable {
        let components: [Component]

        struct Component: Decodable {
            let name: String
            let status: String
        }
    }

    private struct SummaryResponse: Decodable {
        let incidents: [Incident]

        struct Incident: Decodable {
            let id: String
            let name: String?
            let status: String
            let impact: String?
        }
    }

    private let feedURL = URL(string: "https://status.openai.com/feed.atom")!
    private let summaryURL = URL(string: "https://status.openai.com/api/v2/summary.json")!
    private let componentsURL = URL(string: "https://status.openai.com/api/v2/components.json")!

    func fetchStatus() async throws -> ClaudeStatus {
        async let feedResult = fetchResult(from: feedURL)
        async let summaryResult = fetchResult(from: summaryURL)
        let (feed, summary) = await (feedResult, summaryResult)

        let feedData: Data?
        if case .success(let data) = feed {
            feedData = data
        } else {
            feedData = nil
        }
        let summaryData: Data?
        if case .success(let data) = summary {
            summaryData = data
        } else {
            summaryData = nil
        }

        if let status = Self.status(feedData: feedData, summaryData: summaryData) {
            return status
        }

        // Preserve a useful degraded/operational result if the feed is
        // temporarily unavailable, while avoiding the stale endpoint whenever
        // the live incident feed can be parsed.
        let componentData = try await fetchData(from: componentsURL)
        return try Self.statusFromComponents(componentData)
    }

    /// Resolves the two incident.io sources without performing network I/O.
    /// A decoded summary is authoritative even when it contains no incidents;
    /// the known-stale components endpoint is reserved for total primary-source
    /// failure.
    static func status(feedData: Data?, summaryData: Data?) -> ClaudeStatus? {
        let summary = summaryData.flatMap {
            try? JSONDecoder().decode(SummaryResponse.self, from: $0)
        }

        if let feedData,
           let incidents = try? OpenAIStatusFeedParser.parse(feedData) {
            return status(from: incidents, summaryData: summaryData)
        }

        if let summary {
            return status(from: summary)
        }
        return nil
    }

    private func fetchResult(from url: URL) async -> Result<Data, Error> {
        do {
            return .success(try await fetchData(from: url))
        } catch {
            return .failure(error)
        }
    }

    private func fetchData(from url: URL) async throws -> Data {
        var request = URLRequest(
            url: url,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: 10
        )
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return data
    }

    static func status(
        from incidents: [OpenAIStatusFeedIncident],
        summaryData: Data?
    ) -> ClaudeStatus {
        let summary = summaryData.flatMap {
            try? JSONDecoder().decode(SummaryResponse.self, from: $0)
        }
        let relevant = incidents.filter { incident in
            incident.status.lowercased() != "resolved" && incident.affectsCodex
        }
        guard !relevant.isEmpty else {
            if let summary {
                let active = summary.incidents.filter { $0.status.lowercased() != "resolved" }
                let feedByID = incidents.reduce(into: [String: OpenAIStatusFeedIncident]()) {
                    $0[normalizedIncidentID($1.id)] = $1
                }
                if active.contains(where: { summaryIncident in
                    guard let feedIncident = feedByID[normalizedIncidentID(summaryIncident.id)] else {
                        return true
                    }
                    if feedIncident.status.lowercased() == "resolved"
                        || summaryIncident.name.map(isCodexComponent) == true {
                        return true
                    }
                    // A generic incident with no confidently extracted component
                    // list cannot establish that Codex is unaffected.
                    return feedIncident.affectedComponents.isEmpty
                        && !isCodexComponent(feedIncident.title)
                }) {
                    return status(from: summary)
                }
            }
            return ClaudeStatus(
                indicator: .none,
                description: "All Codex systems operational"
            )
        }

        let impacts: [String: String]
        if let summary {
            impacts = summary.incidents.reduce(into: [:]) { result, incident in
                guard incident.status.lowercased() != "resolved",
                      let impact = incident.impact else { return }
                result[normalizedIncidentID(incident.id)] = impact
            }
        } else {
            impacts = [:]
        }

        let sorted = relevant.sorted {
            severity(for: impacts[normalizedIncidentID($0.id)])
                > severity(for: impacts[normalizedIncidentID($1.id)])
        }
        let primary = sorted[0]
        let worst = severity(for: impacts[normalizedIncidentID(primary.id)])
        let indicator: ClaudeStatus.StatusIndicator = switch worst {
        case 3: .critical
        case 2: .major
        default: .minor
        }
        let additional = sorted.count > 1 ? " +\(sorted.count - 1)" : ""
        let lifecycle = primary.status.replacingOccurrences(of: "_", with: " ").capitalized

        return ClaudeStatus(
            indicator: indicator,
            description: "\(primary.title)\(additional) · \(lifecycle)"
        )
    }

    private static func status(from summary: SummaryResponse) -> ClaudeStatus {
        let active = summary.incidents.filter { $0.status.lowercased() != "resolved" }
        guard !active.isEmpty else {
            return ClaudeStatus(
                indicator: .none,
                description: "All Codex systems operational"
            )
        }

        let namedCodex = active.filter { $0.name.map(isCodexComponent) == true }
        guard !namedCodex.isEmpty else {
            let incident = active.max {
                severity(for: $0.impact) < severity(for: $1.impact)
            } ?? active[0]
            return ClaudeStatus(
                indicator: .unknown,
                description: "\(incident.name ?? "OpenAI incident") · \(lifecycle(incident.status))"
            )
        }

        let sorted = namedCodex.sorted {
            severity(for: $0.impact) > severity(for: $1.impact)
        }
        let primary = sorted[0]
        let indicator: ClaudeStatus.StatusIndicator = switch severity(for: primary.impact) {
        case 3: .critical
        case 2: .major
        default: .minor
        }
        let additional = sorted.count > 1 ? " +\(sorted.count - 1)" : ""
        return ClaudeStatus(
            indicator: indicator,
            description: "\(primary.name ?? "OpenAI Codex incident")\(additional) · \(lifecycle(primary.status))"
        )
    }

    private static func lifecycle(_ status: String) -> String {
        status.replacingOccurrences(of: "_", with: " ").capitalized
    }

    fileprivate static func normalizedIncidentID(_ id: String) -> String {
        URL(string: id)?.lastPathComponent
            ?? id.split(separator: "/").last.map(String.init)
            ?? id
    }

    private static func severity(for impact: String?) -> Int {
        return switch impact?.lowercased() {
        case "critical": 3
        case "major": 2
        default: 1
        }
    }

    static func statusFromComponents(_ data: Data) throws -> ClaudeStatus {
        let response = try JSONDecoder().decode(ComponentsResponse.self, from: data)
        let relevant = response.components.filter { Self.isCodexComponent($0.name) }
        guard !relevant.isEmpty else { return .unknown }

        let affected = relevant.filter { $0.status != "operational" }
        guard !affected.isEmpty else {
            // This endpoint can lag the incident feed. It may corroborate a
            // degradation, but must not assert green when both primary
            // incident sources failed.
            return .unknown
        }

        let severity: [String: Int] = [
            "degraded_performance": 1,
            "under_maintenance": 1,
            "partial_outage": 2,
            "major_outage": 3
        ]
        let worst = affected.map { severity[$0.status] ?? 1 }.max() ?? 1
        let indicator: ClaudeStatus.StatusIndicator = switch worst {
        case 3: .critical
        case 2: .major
        default: .minor
        }
        let names = affected.prefix(2).map(\.name).joined(separator: ", ")
        let suffix = affected.count > 2 ? " +\(affected.count - 2)" : ""
        return ClaudeStatus(
            indicator: indicator,
            description: "\(names)\(suffix) degraded"
        )
    }

    static func isCodexComponent(_ name: String) -> Bool {
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.contains("codex")
            || normalized == "cli"
            || normalized == "vs code extension"
    }
}

struct OpenAIStatusFeedIncident: Equatable {
    let id: String
    let title: String
    let status: String
    let affectedComponents: [String]

    var affectsCodex: Bool {
        OpenAIStatusService.isCodexComponent(title)
            || affectedComponents.contains(where: OpenAIStatusService.isCodexComponent)
    }
}

enum OpenAIStatusFeedParser {
    static func parse(_ data: Data) throws -> [OpenAIStatusFeedIncident] {
        let delegate = Delegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldResolveExternalEntities = false

        guard parser.parse() else {
            throw parser.parserError ?? URLError(.cannotParseResponse)
        }
        guard delegate.failedEntryCount == 0 else {
            throw URLError(.cannotParseResponse)
        }
        return delegate.incidents
    }

    private final class Delegate: NSObject, XMLParserDelegate {
        private struct Entry {
            var id = ""
            var title = ""
            var summary = ""
        }

        private var entry: Entry?
        private var capturedElement: String?
        private var capturedText = ""
        fileprivate var incidents: [OpenAIStatusFeedIncident] = []
        fileprivate var failedEntryCount = 0

        private func localName(_ elementName: String) -> String {
            elementName.split(separator: ":").last.map(String.init) ?? elementName
        }

        func parser(
            _ parser: XMLParser,
            didStartElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?,
            attributes attributeDict: [String: String] = [:]
        ) {
            let elementName = localName(elementName)
            if elementName == "entry" {
                entry = Entry()
            } else if entry != nil,
                      elementName == "id"
                        || elementName == "title"
                        || elementName == "summary"
                        || elementName == "content" {
                capturedElement = elementName
                capturedText = ""
            } else if capturedElement == "summary" || capturedElement == "content" {
                if ["br", "li", "p", "div"].contains(elementName) {
                    capturedText += "\n"
                }
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            guard capturedElement != nil else { return }
            capturedText += string
        }

        func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
            guard capturedElement != nil,
                  let string = String(data: CDATABlock, encoding: .utf8) else { return }
            capturedText += string
        }

        func parser(
            _ parser: XMLParser,
            didEndElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?
        ) {
            let elementName = localName(elementName)
            if elementName == capturedElement {
                switch elementName {
                case "id":
                    entry?.id = capturedText
                case "title":
                    entry?.title = capturedText
                case "summary", "content":
                    entry?.summary = capturedText
                default:
                    break
                }
                capturedElement = nil
                capturedText = ""
            }

            if elementName == "entry", let entry {
                if let incident = Self.makeIncident(from: entry) {
                    incidents.append(incident)
                } else {
                    failedEntryCount += 1
                }
                self.entry = nil
            }
        }

        private static func makeIncident(from entry: Entry) -> OpenAIStatusFeedIncident? {
            guard let status = extractStatus(from: entry.summary) else {
                return nil
            }

            let componentMatches = captures(
                in: entry.summary,
                pattern: #"<li[^>]*>\s*(.*?)\s*</li>"#,
                options: [.caseInsensitive, .dotMatchesLineSeparators]
            )
            var components = componentMatches.map {
                plainText(from: $0).replacingOccurrences(
                    of: #"\s+\([^)]+\)\s*$"#,
                    with: "",
                    options: .regularExpression
                )
            }
            if components.isEmpty {
                components = componentsFromPlainText(entry.summary)
            }

            return OpenAIStatusFeedIncident(
                id: OpenAIStatusService.normalizedIncidentID(entry.id),
                title: plainText(from: entry.title),
                status: status.trimmingCharacters(in: .whitespacesAndNewlines),
                affectedComponents: components.filter { !$0.isEmpty }
            )
        }

        private static func extractStatus(from html: String) -> String? {
            let patterns = [
                #"<(?:b|strong)[^>]*>\s*Status:\s*([^<]+)</(?:b|strong)>"#,
                #"<(?:b|strong)[^>]*>\s*Status:\s*</(?:b|strong)>\s*([^<\r\n]+)"#
            ]
            for pattern in patterns {
                if let value = captures(
                    in: html,
                    pattern: pattern,
                    options: [.caseInsensitive, .dotMatchesLineSeparators]
                ).first {
                    return plainText(from: value)
                }
            }

            return captures(
                in: plainText(from: html, preserveLines: true),
                pattern: #"(?m)(?:^|\n)\s*Status:\s*([^\r\n]+)"#,
                options: [.caseInsensitive]
            ).first?.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        private static func componentsFromPlainText(_ html: String) -> [String] {
            let lines = plainText(from: html, preserveLines: true)
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            guard let marker = lines.firstIndex(where: {
                $0.localizedCaseInsensitiveContains("affected components")
            }) else {
                return []
            }

            let markerLine = lines[marker]
            let inlineComponents: [String]
            if let markerRange = markerLine.range(
                of: "affected components",
                options: .caseInsensitive
            ) {
                let suffix = markerLine[markerRange.upperBound...]
                    .trimmingCharacters(in: CharacterSet(charactersIn: " :-–—\t"))
                inlineComponents = suffix.isEmpty
                    ? []
                    : suffix
                        .components(separatedBy: CharacterSet(charactersIn: ",;"))
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
            } else {
                inlineComponents = []
            }

            let followingComponents = lines.dropFirst(marker + 1)
                .prefix { !$0.localizedCaseInsensitiveContains("status update") }
                .filter { !$0.isEmpty }
                .map {
                    $0.replacingOccurrences(
                        of: #"\s+\([^)]+\)\s*$"#,
                        with: "",
                        options: .regularExpression
                    )
                }
            return inlineComponents + followingComponents
        }

        private static func plainText(from html: String, preserveLines: Bool = false) -> String {
            var text = html
            if preserveLines {
                text = text.replacingOccurrences(
                    of: #"<(?:br|/li|/p|/div)\b[^>]*>"#,
                    with: "\n",
                    options: [.regularExpression, .caseInsensitive]
                )
            }
            text = text.replacingOccurrences(
                of: #"<[^>]+>"#,
                with: "",
                options: .regularExpression
            )
            let entities = [
                "&amp;": "&",
                "&lt;": "<",
                "&gt;": ">",
                "&quot;": "\"",
                "&#39;": "'",
                "&nbsp;": " "
            ]
            for (entity, value) in entities {
                text = text.replacingOccurrences(of: entity, with: value)
            }
            if preserveLines {
                return text
                    .replacingOccurrences(of: #"[ \t]+"#, with: " ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return text
                .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        private static func captures(
            in string: String,
            pattern: String,
            options: NSRegularExpression.Options = [.caseInsensitive]
        ) -> [String] {
            guard let expression = try? NSRegularExpression(
                pattern: pattern,
                options: options
            ) else {
                return []
            }
            let range = NSRange(string.startIndex..., in: string)
            return expression.matches(in: string, range: range).compactMap { match in
                guard match.numberOfRanges > 1,
                      let captureRange = Range(match.range(at: 1), in: string) else {
                    return nil
                }
                return String(string[captureRange])
            }
        }
    }
}
