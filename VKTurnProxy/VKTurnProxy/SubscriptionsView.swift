//
//  SubscriptionsView.swift
//  CSQTT iOS
//
//  Management screen: add a subscription URL, see when it was refreshed, how
//  many servers it carries, and the ONE device identity shared by all of them.
//
//  The URL is a bearer token; it is shown masked (host only) and never logged.
//

import SwiftUI

struct SubscriptionsView: View {
    @ObservedObject private var store = SubscriptionStore.shared
    @State private var showAdd = false
    @State private var url = ""
    @State private var name = ""
    /// Chosen "conn" for the subscription being added. nil = Auto.
    @State private var connections: Int? = nil
    @State private var busy = false
    @State private var error: String?

    /// The offered values. Dense at the low end (where a phone actually lives)
    /// and stopping at TunnelConfig.anonConnCap, so no menu entry can promise a
    /// number the tunnel will refuse.
    private var connChoices: [Int] {
        [1, 2, 3, 4, 6, 8, 10, 12, 16, 20, 24, 30, 40, 50, TunnelConfig.anonConnCap]
            .filter { $0 <= TunnelConfig.anonConnCap }
    }

    var body: some View {
        List {
            if store.subscriptions.isEmpty {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("No subscriptions yet")
                            .font(.headline)
                        Text("Add a subscription URL to keep its servers in sync. One subscription uses one device for all of its servers.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }

            ForEach(store.subscriptions) { sub in
                Section {
                    HStack {
                        Text(sub.name)
                        Spacer()
                        Text("\(store.serversCount(sub.id))")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Text(sub.hostLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack {
                        Text("Device")
                            .font(.caption)
                        Spacer()
                        Text(sub.shortIdentity)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }

                    // "conn" for the whole subscription. Choosing a number here
                    // rewrites it on every server the subscription owns, at
                    // once (SubscriptionStore.setNumConnections) — a provider
                    // that ships one link per server is tuned in one place
                    // instead of once per server. "Auto" hands each server back
                    // to its own value on the next refresh.
                    Menu {
                        Button("Auto") { store.setNumConnections(sub.id, nil) }
                        ForEach(connChoices, id: \.self) { n in
                            Button("\(n)") { store.setNumConnections(sub.id, n) }
                        }
                    } label: {
                        HStack {
                            Text("Connections")
                            Spacer()
                            if let value = sub.numConnections {
                                Text("\(value)")
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            } else {
                                Text("Auto")
                                    .foregroundStyle(.secondary)
                            }
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }

                    if let failure = sub.lastError {
                        Text(failure)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    Button {
                        Task { await store.refresh(sub.id) }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .disabled(store.refreshing.contains(sub.id))

                    Button(role: .destructive) {
                        store.resetDevice(sub.id)
                    } label: {
                        Label("Reset device", systemImage: "arrow.triangle.2.circlepath")
                    }

                    Button(role: .destructive) {
                        store.remove(sub.id)
                    } label: {
                        Label("Delete subscription", systemImage: "trash")
                    }
                } header: {
                    Text(sub.name)
                } footer: {
                    Text("Updated \(sub.ageLabel)")
                }
            }
        }
        .navigationTitle("Subscriptions")
        .toolbar {
            Button {
                error = nil
                showAdd = true
            } label: {
                Label("Add", systemImage: "plus")
            }
        }
        .sheet(isPresented: $showAdd) {
            addSheet
        }
    }

    private var addSheet: some View {
        NavigationView {
            Form {
                Section {
                    TextField("Subscription URL", text: $url)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    TextField("Name (optional)", text: $name)
                        .textInputAutocapitalization(.never)

                    // Chosen BEFORE the URL is fetched, then stamped onto every
                    // server the subscription produces and stored on the
                    // subscription itself, so refreshing it later keeps the
                    // number instead of losing it with the old profiles.
                    Menu {
                        Button("Auto") { connections = nil }
                        ForEach(connChoices, id: \.self) { n in
                            Button("\(n)") { connections = n }
                        }
                    } label: {
                        HStack {
                            Text("Connections")
                            Spacer()
                            if let value = connections {
                                Text("\(value)")
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            } else {
                                Text("Auto")
                                    .foregroundStyle(.secondary)
                            }
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                } footer: {
                    Text("The URL is a secret: anyone holding it can pull the servers. It is never logged.")
                    Text("Applies to every server of this subscription. Auto keeps each server's own value.")
                }

                if let error {
                    Section {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Button {
                        Task { await addSubscription() }
                    } label: {
                        if busy {
                            HStack {
                                ProgressView()
                                Text("Checking…")
                            }
                        } else {
                            Text("Check and add")
                        }
                    }
                    .disabled(busy || url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .navigationTitle("Add subscription")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showAdd = false }
                }
            }
        }
    }

    private func addSubscription() async {
        busy = true
        error = nil
        do {
            _ = try await store.add(url: url, name: name, numConnections: connections)
            url = ""
            name = ""
            connections = nil
            showAdd = false
        } catch {
            self.error = error.localizedDescription
        }
        busy = false
    }
}
