// ServerStore.swift
//
// Canonical store of named server profiles (Option A architecture). The ACTIVE
// profile is PROJECTED into the flat @AppStorage/UserDefaults keys that
// ContentView's TunnelConfig build + TunnelManager already read — so connect(),
// buildProxyConfig and buildUAPIConfig need no changes.
//
// ServerStore is the ONLY writer of the per-server flat keys. The GLOBAL keys
// (vkLink, VKAuth, forceLegacyCaptcha) are NEVER touched by projection.
//
// The store is instantiated at launch: first-launch migration captures the
// existing single config as "Server1", then load() projects the active server
// onto the flat @AppStorage keys that ContentView / TunnelManager read.

import Foundation

final class ServerStore: ObservableObject {
    static let shared = ServerStore()

    @Published private(set) var servers: [ServerProfile] = []
    @Published private(set) var activeServerId: UUID = UUID()

    private let d = UserDefaults.standard
    private let serversKey = "servers_v1"
    private let activeKey = "activeServerId"

    // The flat per-server keys projected/migrated. GLOBAL keys (vkLink, VKAuth,
    // forceLegacyCaptcha) are deliberately absent from these tables.
    private static let stringKeyPaths: [(String, WritableKeyPath<ServerProfile, String>)] = [
        ("privateKey", \.privateKey), ("peerPublicKey", \.peerPublicKey),
        ("presharedKey", \.presharedKey), ("tunnelAddress", \.tunnelAddress),
        ("peerAddress", \.peerAddress), ("dnsServers", \.dnsServers),
        ("turnServerOverride", \.turnServerOverride), ("wrapKeyHex", \.wrapKeyHex),
        ("obfProfile", \.obfProfile), ("clientID", \.clientID),
        ("wrapAPassword", \.wrapAPassword), ("deviceID", \.deviceID),
        ("csqttPassword", \.csqttPassword), ("csqttDeviceID", \.csqttDeviceID),
    ]
    private static let boolKeyPaths: [(String, WritableKeyPath<ServerProfile, Bool>, Bool)] = [
        ("useUDP", \.useUDP, false), ("useDTLS", \.useDTLS, true),
        ("useSrtp", \.useSrtp, true), ("useWrap", \.useWrap, false),
        ("useWrapA", \.useWrapA, false), ("useWrapS", \.useWrapS, false),
        ("useCsqtt", \.useCsqtt, false),
        ("csqttBoundedWrites", \.csqttBoundedWrites, true),
    ]
    private static let intKeyPaths: [(String, WritableKeyPath<ServerProfile, Int>, Int)] = [
        ("numConnections", \.numConnections, 30),
        ("credPoolCooldownSeconds", \.credPoolCooldownSeconds, 150),
    ]

    private init() { load() }

    var activeServer: ServerProfile {
        servers.first(where: { $0.id == activeServerId }) ?? servers[0]
    }

    // MARK: - Persistence + first-launch migration

    private func load() {
        if let data = d.data(forKey: serversKey),
           let decoded = try? JSONDecoder().decode([ServerProfile].self, from: data),
           !decoded.isEmpty {
            servers = decoded
            if let s = d.string(forKey: activeKey), let id = UUID(uuidString: s),
               decoded.contains(where: { $0.id == id }) {
                activeServerId = id
            } else {
                activeServerId = decoded[0].id
            }
        } else {
            // First launch (or an unreadable store): capture the user's existing
            // single config from the flat keys as "Server1".
            let s = Self.serverFromFlatKeys(name: "Server1")
            servers = [s]
            activeServerId = s.id
            persist()
        }
        seedLegacyWrapADeviceID()
        // Project the active server onto the flat @AppStorage keys so ContentView
        // / TunnelManager always read the active server's config. On first launch
        // this is a no-op (Server1 was built from those very keys).
        projectToFlatKeys(activeServer)
        applyActiveVKLink()
        let s = activeServer
        SharedLogger.shared.log("[AppDebug] servers: \(servers.count) configured, active = \"\(s.serverName)\" [\(s.modeLabel)]")
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(servers) {
            d.set(data, forKey: serversKey)
        }
        d.set(activeServerId.uuidString, forKey: activeKey)
    }

    /// Build 181 migration: the SRTP-WRAP-A device identifier used to be ONE
    /// hidden App-Group value (`wrapADeviceID`) that every configuration shared;
    /// it is now a per-server, user-editable field. Seed that legacy value into
    /// every WRAP-A server that has no device ID yet, so an existing install
    /// keeps the WireGuard peer + tunnel IP the server already minted for it.
    ///
    /// Seeding all of them reproduces the old behaviour exactly (they really did
    /// all send the same ID); the user can now give them distinct ones. Keyed on
    /// "field is empty" rather than a one-shot migration flag, so a server whose
    /// ID was cleared by hand is repaired too — an empty device ID is never
    /// valid for GETCONF.
    private static var legacyWrapADeviceID: String? {
        let v = UserDefaults(suiteName: AppEntitlements.sharedGroup)?.string(forKey: "wrapADeviceID")
        return (v?.isEmpty == false) ? v : nil
    }

    /// The legacy WRAP-A device ID, but only while NO server holds it yet.
    ///
    /// Used when a server is switched INTO SRTP-WRAP-A: on build ≤180 that
    /// server would have connected with the legacy ID, so handing it over keeps
    /// the WireGuard peer the server already minted. Returning nil once some
    /// server owns it is what makes this safe — the ID can be adopted at most
    /// once, so two profiles can never end up sharing one server-side peer.
    /// The caller mints a fresh UUID when this is nil.
    func unclaimedLegacyWrapADeviceID() -> String? {
        guard let legacy = Self.legacyWrapADeviceID else { return nil }
        return servers.contains { $0.deviceID == legacy } ? nil : legacy
    }

    private func seedLegacyWrapADeviceID() {
        guard let legacy = Self.legacyWrapADeviceID else { return }
        var seeded = 0
        for i in servers.indices where servers[i].useWrapA && servers[i].deviceID.isEmpty {
            servers[i].deviceID = legacy
            seeded += 1
        }
        guard seeded > 0 else { return }
        persist()
        SharedLogger.shared.log("[AppDebug] servers: seeded the legacy WRAP-A device ID into \(seeded) server(s)")
    }

    /// Build a ServerProfile from the current flat @AppStorage keys, matching
    /// each key's @AppStorage default when the key was never written.
    static func serverFromFlatKeys(name: String) -> ServerProfile {
        let d = UserDefaults.standard
        var p = ServerProfile()
        p.serverName = name
        for (key, kp) in stringKeyPaths {
            if let v = d.string(forKey: key) { p[keyPath: kp] = v }
        }
        for (key, kp, def) in boolKeyPaths {
            p[keyPath: kp] = d.object(forKey: key) == nil ? def : d.bool(forKey: key)
        }
        for (key, kp, def) in intKeyPaths {
            p[keyPath: kp] = d.object(forKey: key) == nil ? def : d.integer(forKey: key)
        }
        // The flat keys never carried a csqtt generation: what they describe
        // is from before 2.5 could be chosen.
        if p.useCsqtt && p.csqttGeneration.isEmpty { p.csqttGeneration = CsqttGeneration.v219 }
        return p
    }

    // MARK: - Projection (active profile -> flat keys). ONLY writer of these keys.

    /// Write the active profile into the legacy flat keys.
    ///
    /// ⚠️ Nothing in the running app READS these keys any more. Connect,
    /// validation, the backup export and the extension all take their values
    /// from this store; `serverFromFlatKeys` is the single remaining reader and
    /// runs only on the two legacy INPUT paths — a first launch migrating a
    /// pre-173 single config, and a pre-179 backup whose fields `applyConfig`
    /// has just written here. So this projection now exists solely to leave a
    /// coherent configuration behind for a DOWNGRADE to build ≤180.
    ///
    /// It follows that projecting more often is not "safer" — it is pure risk.
    /// A `projectActive()` used to sit here for SettingsView to call on
    /// dismissal; it was never wired up, and by the time anyone noticed,
    /// calling it would have written 20 keys that views were still subscribed
    /// to and popped the pushed screen for no benefit at all (the exact
    /// build-177 trap). Removed in build 196 along with those subscriptions —
    /// do not reintroduce either.
    func projectToFlatKeys(_ p: ServerProfile) {
        for (key, kp) in Self.stringKeyPaths { d.set(p[keyPath: kp], forKey: key) }
        for (key, kp, _) in Self.boolKeyPaths { d.set(p[keyPath: kp], forKey: key) }
        for (key, kp, _) in Self.intKeyPaths { d.set(p[keyPath: kp], forKey: key) }
        d.set("0.0.0.0/0", forKey: "allowedIPs")   // always pinned
        // GLOBAL keys (vkLink, VKAuth, forceLegacyCaptcha) intentionally untouched.
    }

    // MARK: - Mutations (wired to the UI in M2 / link import in M4)

    func activate(_ id: UUID) {
        guard servers.contains(where: { $0.id == id }) else { return }
        activeServerId = id
        persist()
        applyActiveVKLink()
        let s = activeServer
        SharedLogger.shared.log("[AppDebug] active server → \"\(s.serverName)\" [\(s.modeLabel)]")
    }

    /// The tunnel reads `vkLink` from UserDefaults at connect time. A profile
    /// imported from a subscription carries its own hash. 🚨 The global value
    /// is a POOL — one call link per line — so selecting a server must ADD its
    /// link, never replace the pool with it: the other subscriptions' servers
    /// keep their calls available, and a provider that reuses one hash for all
    /// its servers contributes exactly one line.
    private func applyActiveVKLink() {
        mergeVKLinks([activeServer.vkLink])
    }

    private func currentVKLines() -> [String] {
        (d.string(forKey: "vkLink") ?? "")
            .split(whereSeparator: { $0.isNewline })
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    /// Adds links to the global VK pool without disturbing the existing order.
    func mergeVKLinks(_ links: [String]) {
        let incoming = links
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !incoming.isEmpty else { return }
        var lines = currentVKLines()
        var changed = false
        for link in incoming where !lines.contains(link) {
            lines.append(link)
            changed = true
        }
        guard changed else { return }
        d.set(lines.joined(separator: "\n"), forKey: "vkLink")
    }

    /// Removes links that belonged only to profiles that no longer exist.
    /// A link still carried by any remaining profile (manual or another
    /// subscription) stays, so the pool never loses a live call.
    private func pruneVKLinks(_ candidates: [String]) {
        let unique = Set(candidates.filter { !$0.isEmpty })
        guard !unique.isEmpty else { return }
        let stillUsed = Set(servers.compactMap { $0.vkLink.isEmpty ? nil : $0.vkLink })
        let current = currentVKLines()
        let kept = current.filter { !unique.contains($0) || stillUsed.contains($0) }
        guard kept != current else { return }
        d.set(kept.joined(separator: "\n"), forKey: "vkLink")
    }

    func update(_ profile: ServerProfile) {
        guard let i = servers.firstIndex(where: { $0.id == profile.id }) else { return }
        servers[i] = profile
        persist()
    }

    @discardableResult
    func addNew() -> ServerProfile {
        var p = ServerProfile()
        p.serverName = nextDefaultName()
        servers.append(p)
        persist()
        return p
    }

    @discardableResult
    func copy(_ id: UUID) -> ServerProfile? {
        guard var p = servers.first(where: { $0.id == id }) else { return nil }
        p.id = UUID()
        p.serverName = uniqueName(p.serverName + " copy")
        servers.append(p)
        persist()
        return p
    }

    func delete(_ id: UUID) {
        guard servers.count > 1 else { return }   // can't delete the last server
        let wasActive = (id == activeServerId)
        servers.removeAll { $0.id == id }
        if wasActive { activate(servers[0].id) } else { persist() }
    }

    // MARK: - Full-backup import (M3)

    /// Replace the whole set from a backup that carries `servers`. The active
    /// server is picked by name (falling back to the first entry) and projected
    /// onto the flat keys, since an import lands the user back on the main
    /// screen where those keys are read.
    func replaceAll(_ profiles: [ServerProfile], activeName: String?) {
        guard !profiles.isEmpty else { return }
        servers = profiles
        let active = activeName.flatMap { name in profiles.first { $0.serverName == name } }
                     ?? profiles[0]
        activeServerId = active.id
        // A backup from build ≤180 carries no per-server device ID, so give the
        // restored WRAP-A servers this device's legacy one — otherwise the
        // Settings field would read empty while the tunnel quietly connected
        // with the hidden App-Group value, and the NEXT export would persist
        // that emptiness onto a device that has no legacy value to fall back to.
        seedLegacyWrapADeviceID()
        persist()
        projectToFlatKeys(activeServer)   // re-read: seeding may have changed it
        SharedLogger.shared.log("[AppDebug] Backup: restored \(profiles.count) server(s), active = \"\(active.serverName)\" [\(active.modeLabel)]")
    }

    /// Rebuild the set as a single server from the flat @AppStorage keys. Used
    /// when importing a pre-179 backup, whose settings were just written to
    /// those keys — no projection needed, they already hold these values.
    func resetFromFlatKeys(name: String = "Server1") {
        let p = Self.serverFromFlatKeys(name: name)
        servers = [p]
        activeServerId = p.id
        seedLegacyWrapADeviceID()   // same reasoning as replaceAll
        persist()
        SharedLogger.shared.log("[AppDebug] Backup: legacy single-server backup imported as \"\(p.serverName)\" [\(p.modeLabel)]")
    }

    /// M4: import a connection link as a NEW server and make it active.
    @discardableResult
    func addAndActivate(_ profile: ServerProfile) -> ServerProfile {
        var p = profile
        p.serverName = p.serverName.isEmpty ? nextDefaultName() : uniqueName(p.serverName)
        servers.append(p)
        activate(p.id)
        return p
    }

    // MARK: - Subscriptions

    /// Replace one subscription's servers with a freshly parsed set.
    ///
    /// Merge by `remoteKey`, never by name or index: a provider may rename or
    /// reorder servers between refreshes, and matching by position would
    /// silently swap the settings under the user's active profile. The
    /// existing UUID is preserved for a key that survives, so the active
    /// selection and any pushed screen referring to it stay valid.
    ///
    /// Returns true when the ACTIVE server changed (removed, or replaced by a
    /// fallback), so the caller can refresh the Live Activity and the screen.
    @discardableResult
    func replaceSubscriptionServers(_ subscriptionId: UUID,
                                    with incoming: [ServerProfile]) -> Bool {
        var byKey: [String: ServerProfile] = [:]
        for profile in incoming {
            guard let key = profile.remoteKey, !key.isEmpty else { continue }
            byKey[key] = profile
        }

        let others = servers.filter { $0.subscriptionId != subscriptionId }
        let existing = servers.filter { $0.subscriptionId == subscriptionId }
        var existingByKey: [String: ServerProfile] = [:]
        for profile in existing {
            if let key = profile.remoteKey { existingByKey[key] = profile }
        }

        var merged: [ServerProfile] = []
        for (key, var profile) in byKey {
            if let old = existingByKey[key] {
                // Keep the identity the rest of the app already knows.
                profile.id = old.id
            }
            merged.append(profile)
        }
        merged.sort { $0.serverName.localizedCaseInsensitiveCompare($1.serverName) == .orderedAscending }

        let activeWasManaged = servers.first(where: { $0.id == activeServerId })?.subscriptionId == subscriptionId
        let activeSurvives = merged.contains { $0.id == activeServerId }
        let removedLinks = existing.map(\.vkLink).filter { !$0.isEmpty }
        let mergedLinks = merged.map(\.vkLink).filter { !$0.isEmpty }
        servers = others + merged

        var activeChanged = false
        if activeWasManaged && !activeSurvives {
            // The server the user was on vanished from the provider. Falling
            // back to the first fresh one of the same subscription keeps them
            // online; if the subscription is now empty, any other server wins.
            if let next = merged.first ?? servers.first {
                activeServerId = next.id
                activeChanged = true
            }
        }
        persist()
        if activeChanged { projectToFlatKeys(activeServer) }
        // The subscription's calls go into the shared pool; calls of profiles
        // that no longer exist leave it.
        mergeVKLinks(mergedLinks)
        pruneVKLinks(removedLinks)
        applyActiveVKLink()
        SharedLogger.shared.log("[AppDebug] subscription \(subscriptionId.uuidString.prefix(8)): "
            + "\(incoming.count) server(s), \(merged.count) applied")
        return activeChanged
    }

    func removeSubscriptionServers(_ subscriptionId: UUID) {
        let removed = servers.filter { $0.subscriptionId == subscriptionId }
        guard !removed.isEmpty else { return }
        let activeWasManaged = removed.contains { $0.id == activeServerId }
        let removedLinks = removed.map(\.vkLink).filter { !$0.isEmpty }
        servers.removeAll { $0.subscriptionId == subscriptionId }
        if servers.isEmpty {
            // Never leave the app without a profile: an empty set breaks
            // activeServer's `servers[0]` and every screen behind it.
            let fallback = ServerProfile()
            servers = [fallback]
            activeServerId = fallback.id
        } else if activeWasManaged, let first = servers.first {
            activeServerId = first.id
        }
        persist()
        projectToFlatKeys(activeServer)
        pruneVKLinks(removedLinks)
        applyActiveVKLink()
    }

    func servers(for subscriptionId: UUID) -> [ServerProfile] {
        servers.filter { $0.subscriptionId == subscriptionId }
    }

    // MARK: - Naming helpers

    private func nextDefaultName() -> String {
        let names = Set(servers.map { $0.serverName })
        var n = 1
        while names.contains("Server\(n)") { n += 1 }
        return "Server\(n)"
    }

    private func uniqueName(_ base: String) -> String {
        let names = Set(servers.map { $0.serverName })
        if !names.contains(base) { return base }
        var n = 2
        while names.contains("\(base) \(n)") { n += 1 }
        return "\(base) \(n)"
    }
}
