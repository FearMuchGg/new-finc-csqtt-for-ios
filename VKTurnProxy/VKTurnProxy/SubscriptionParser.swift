//
//  SubscriptionParser.swift
//  CSQTT iOS
//
//  Turns whatever a subscription URL answers into a list of servers.
//
//  Three shapes exist in practice:
//
//   1. CSQTT's own endpoints (`/api/sub/<uuid>`, `/<uuid>/json`) — JSON, one
//      object for a client or an array for a group.
//   2. A plain list (or a base64 blob of one) of `csqtt://` / `wdtt://` links —
//      the format most panels use.
//   3. An HTML landing page — turnplus.xyz is one: the page carries a "Серверы
//      и ключи" section with `wdtt://host:ports:password:hash` links, each
//      preceded by its display name.
//
//  The parser is Foundation-only and deterministic: the same bytes always give
//  the same servers, so the merge in ServerStore can rely on `remoteKey`.
//

import Foundation

enum SubscriptionParser {

    static func parse(data: Data,
                      contentType: String?,
                      baseURL: URL) throws -> [SubscriptionServer] {
        let ct = (contentType ?? "").lowercased()

        if ct.contains("json") || looksLikeJSON(data) {
            if let servers = try? parseJSON(data), !servers.isEmpty {
                return dedupe(servers)
            }
        }

        if let text = String(data: data, encoding: .utf8) {
            let direct = parseText(text)
            if !direct.isEmpty { return dedupe(direct) }

            if let decoded = decodeBase64(text),
               let plain = String(data: decoded, encoding: .utf8) {
                let fromBase64 = parseText(plain)
                if !fromBase64.isEmpty { return dedupe(fromBase64) }
            }

            let fromHTML = parseHTML(text)
            if !fromHTML.isEmpty { return dedupe(fromHTML) }
        }

        // Some panels answer a raw base64 body without a text content type.
        if let decoded = decodeBase64(data.base64EncodedString()),
           let plain = String(data: decoded, encoding: .utf8) {
            let servers = parseText(plain)
            if !servers.isEmpty { return dedupe(servers) }
        }

        throw SubscriptionError.malformed("no server links found at \(baseURL.host ?? "the subscription")")
    }

    // MARK: - JSON

    private static func looksLikeJSON(_ data: Data) -> Bool {
        guard let first = String(data: data.prefix(64), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines).first else { return false }
        return first == "{" || first == "["
    }

    private static func parseJSON(_ data: Data) throws -> [SubscriptionServer] {
        let object = try JSONSerialization.jsonObject(with: data)
        return servers(fromJSON: object)
    }

    private static func servers(fromJSON object: Any) -> [SubscriptionServer] {
        if let string = object as? String { return parseText(string) }
        if let array = object as? [Any] { return array.flatMap { servers(fromJSON: $0) } }
        guard let dict = object as? [String: Any] else { return [] }

        for key in ["servers", "data", "items", "list"] {
            if let array = dict[key] as? [Any] {
                let nested = array.flatMap { servers(fromJSON: $0) }
                if !nested.isEmpty { return nested }
            }
        }
        if let link = dict["link"] as? String, !link.isEmpty {
            let rawName = (dict["name"] as? String) ?? ""
            return [SubscriptionServer(name: rawName.isEmpty ? host(from: link) : rawName, link: link)]
        }
        return []
    }

    // MARK: - Text / HTML

    private static let linkPattern = #"(?i)(wdtt|csqtt|vkturnproxy|freeturn)://[^\s"'<>\\]+"#

    private static func parseText(_ text: String) -> [SubscriptionServer] {
        extractLinks(text).map { SubscriptionServer(name: host(from: $0), link: $0) }
    }

    private static func parseHTML(_ html: String) -> [SubscriptionServer] {
        let decoded = html.replacingOccurrences(of: "&amp;", with: "&")
        guard let regex = try? NSRegularExpression(pattern: linkPattern) else { return [] }
        let ns = decoded as NSString
        let matches = regex.matches(in: decoded, range: NSRange(location: 0, length: ns.length))
        var out: [SubscriptionServer] = []
        for match in matches {
            let link = cleanLink(ns.substring(with: match.range))
            guard !link.isEmpty else { continue }
            let name = name(before: match.range.location, in: decoded) ?? host(from: link)
            out.append(SubscriptionServer(name: name, link: link))
        }
        return out
    }

    static func extractLinks(_ text: String) -> [String] {
        let decoded = text.replacingOccurrences(of: "&amp;", with: "&")
        guard let regex = try? NSRegularExpression(pattern: linkPattern) else { return [] }
        let ns = decoded as NSString
        return regex.matches(in: decoded, range: NSRange(location: 0, length: ns.length))
            .map { cleanLink(ns.substring(with: $0.range)) }
            .filter { !$0.isEmpty }
    }

    private static func cleanLink(_ raw: String) -> String {
        var link = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while let last = link.last, ".,);]}\"'".contains(last) {
            link.removeLast()
        }
        return link
    }

    /// The display name turnplus puts in a `<div>` right before each link.
    /// The nearest `>text<` is often the "Копировать" button, so known chrome
    /// words are skipped and the search continues backwards.
    private static func name(before location: Int, in text: String) -> String? {
        let ns = text as NSString
        let start = max(0, location - 800)
        guard location > start else { return nil }
        let prefix = ns.substring(with: NSRange(location: start, length: location - start))
        guard let regex = try? NSRegularExpression(pattern: #">([^<>]{2,60})<"#) else { return nil }
        let matches = regex.matches(in: prefix, range: NSRange(location: 0, length: (prefix as NSString).length))
        let junk: Set<String> = [
            "Копировать", "Скопировать", "Серверы и ключи", "Ссылка подписки",
            "Скачать", "Подписка", "Тариф", "Трафик", "Устройства", "Как подключить",
            "Android", "iPhone", "ПК", "Работает", "Скопировать QR-код",
        ]
        for match in matches.reversed() {
            let candidate = (prefix as NSString)
                .substring(with: match.range(at: 1))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if candidate.isEmpty || junk.contains(candidate) { continue }
            if candidate.contains("://") || candidate.count > 50 { continue }
            return candidate
        }
        return nil
    }

    private static func host(from link: String) -> String {
        if let url = URL(string: link), let host = url.host, !host.isEmpty { return host }
        guard let schemeEnd = link.range(of: "://") else { return link }
        let rest = link[schemeEnd.upperBound...]
        return String(rest.split(separator: ":").first ?? "Server")
    }

    private static func decodeBase64(_ raw: String) -> Data? {
        let cleaned = raw
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        guard !cleaned.isEmpty else { return nil }
        var padded = cleaned
        while padded.count % 4 != 0 { padded += "=" }
        return Data(base64Encoded: padded)
    }

    private static func dedupe(_ servers: [SubscriptionServer]) -> [SubscriptionServer] {
        var seen = Set<String>()
        var out: [SubscriptionServer] = []
        for server in servers where seen.insert(server.remoteKey).inserted {
            out.append(server)
        }
        return out
    }
}
