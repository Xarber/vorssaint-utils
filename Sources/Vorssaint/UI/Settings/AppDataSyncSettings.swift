// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct AppDataSyncSettings: View {
    let reviewRestore: ([String: Any]) -> Void
    @ObservedObject private var account = XCenterSyncSession.shared
    @State private var checking = true
    @State private var confirmSave = false
    @State private var confirmDelete = false

    var body: some View {
        Section("App Data Sync") {
            Text("Save the same data as Export All Data to your private X-Center ID account. Restore it on another Mac when you’re ready.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if checking {
                ProgressView().controlSize(.small).accessibilityLabel("Checking X-Center ID")
            } else if account.connected {
                Label("Connected to X-Center ID", systemImage: "checkmark.circle")
                FlowLayoutLite(spacing: 10) {
                    Button { confirmSave = true } label: {
                        Label("Back Up Now", systemImage: "icloud.and.arrow.up")
                    }
                    Button { account.loadBackup(reviewRestore) } label: {
                        Label("Restore Cloud Backup", systemImage: "icloud.and.arrow.down")
                    }
                    Button("Sign Out", action: account.signOut)
                    Button("Delete Cloud Backup", role: .destructive) { confirmDelete = true }
                }
                .disabled(account.working)
            } else if account.working {
                Button("Cancel Sign-In", action: account.cancel)
            } else if account.available {
                Button("Sign In with X-Center ID", action: account.signIn)
            } else {
                Text("X-Center ID sync is unavailable.").foregroundStyle(.secondary)
            }
            if !account.message.isEmpty {
                Text(account.message).font(.caption).foregroundStyle(.secondary)
            }
        }
        .task {
            await account.checkAvailability()
            checking = false
        }
        .alert("Back Up App Data?", isPresented: $confirmSave) {
            Button("Cancel", role: .cancel) {}
            Button("Back Up Now", action: account.upload)
        } message: {
            Text("This replaces the previous cloud backup for this account with the data from this Mac.")
        }
        .alert("Delete Cloud Backup?", isPresented: $confirmDelete) {
            Button("Cancel", role: .cancel) {}
            Button("Delete Cloud Backup", role: .destructive, action: account.deleteBackup)
        } message: {
            Text("This permanently removes the saved cloud backup. Data on your Macs stays in place.")
        }
    }
}
