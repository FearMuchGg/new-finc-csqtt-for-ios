//
//  Subscription.swift
//  CSQTT iOS
//
//  The model of one subscription: where it lives, when it was last refreshed,
//  and what went wrong last time. The SERVERS it produced are ordinary
//  ServerProfile values with `subscriptionId` set — they live in ServerStore
//  with everything else, so connect(), the picker and the tunnel need no new
//  code paths.
//
//  The URL is a bearer token (anyone holding it can pull the keys), so it is
//  never logged and is masked in the UI. It is stored in UserDefaults for now;
//  moving it to the Keychain is a separate change because the app must stay
//  readable before first unlock only in the ways it already is.
//

import Foundation

struct Subscription: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String = ""
    var url: String = ""
    var lastUpdated: Date? = nil
    var lastError: String? = nil
    var enabled: Bool = true

    /// THE device identity for this whole subscription. Every server it
    /// produces carries this value, so a provider that binds an account to one
    /// device sees one device even when the subscription lists five servers.
    /// Optional so a store written before the field existed decodes.
    var deviceID: String? = nil

    /// Connections ("conn") applied to EVERY server this subscription
    /// produces. `nil` is the "Auto" state: the subscription does not touch a
    /// server's own value (the profile default, or whatever the panel's link
    /// carried), so importing a subscription never silently rewrites a number
    /// the user set elsewhere. A number here wins on every refresh, which is
    /// what a provider that ships one link per server expects: the person
    /// tunes connections once, for the whole subscription.
    ///
    /// Stored on the SUBSCRIPTION, not on each profile, for the same reason
    /// `deviceID` is: a refresh replaces the profiles, and a per-profile value
    /// would be lost the next time the subscription is pulled.
    var numConnections: Int? = nil

    var shortIdentity: String {
        String((deviceID ?? "").prefix(8))
    }

    /// Host shown in the UI — never the full URL, which carries the token.
    var hostLabel: String {
        guard let host = URL(string: url)?.host else { return "—" }
        return host
    }

    var isStale: Bool {
        guard let lastUpdated else { return true }
        return Date().timeIntervalSince(lastUpdated) > 6 * 60 * 60
    }

    var ageLabel: String {
        guard let lastUpdated else { return "never" }
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f.localizedString(for: lastUpdated, relativeTo: Date())
    }
}

/// One parsed server from a subscription, before it becomes a ServerProfile.
struct SubscriptionServer: Equatable {
    var name: String
    var link: String
    /// Stable identity inside the subscription: the normalized link. A provider
    /// that re-issues the same server with a new password IS a new server —
    /// merging it with the old one would silently rewrite a live profile.
    var remoteKey: String

    init(name: String, link: String) {
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.link = link.trimmingCharacters(in: .whitespacesAndNewlines)
        self.remoteKey = Self.remoteKey(for: link)
    }

    static func remoteKey(for link: String) -> String {
        link.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

enum SubscriptionError: LocalizedError {
    case badURL
    case insecureURL
    case http(Int)
    case empty
    case malformed(String)

    var errorDescription: String? {
        switch self {
        case .badURL: return "The subscription link is not a valid URL."
        case .insecureURL: return "The subscription must use HTTPS."
        case .http(let code): return "The subscription server answered HTTP \(code)."
        case .empty: return "The subscription contains no servers."
        case .malformed(let why): return "The subscription could not be read: \(why)"
        }
    }
}
