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
    @State private var busy = false
    @State private var error: String?

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
                } footer: {
                    Text("The URL is a secret: anyone holding it can pull the servers. It is never logged.")
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
            _ = try await store.add(url: url, name: name)
            url = ""
            name = ""
            showAdd = false
        } catch {
            self.error = error.localizedDescription
        }
        busy = false
    }
}
