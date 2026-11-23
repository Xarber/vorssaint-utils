// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct MouseProfileSyncSettings: View {
    @ObservedObject private var account = XCenterSyncSession.shared
    @State private var checking = true
    @State private var confirmation: Action?

    private enum Action {
        case upload, download, remove

        var title: String {
            switch self {
            case .upload: return "Save Current Profiles"
            case .download: return "Import Saved Profiles"
            case .remove: return "Remove Cloud Profiles"
            }
        }

        var detail: String {
            switch self {
            case .upload: return "Replace the saved mouse profiles for this account with profiles from this Mac."
            case .download: return "Import saved profiles and update matching apps on this Mac."
            case .remove: return "Permanently remove the saved profiles from this account. Local profiles stay on your Macs."
            }
        }
    }

    var body: some View {
        SettingsCard(title: "Mouse Profile Sync") {
            if checking {
                ProgressView().controlSize(.small).accessibilityLabel("Checking X-Center ID")
            } else if account.connected {
                Label("Connected to X-Center ID", systemImage: "checkmark.circle")
                HStack {
                    Button(Action.upload.title) { confirmation = .upload }
                    Button(Action.download.title) { confirmation = .download }
                }
                .disabled(account.working)
                HStack {
                    Button(Action.remove.title, role: .destructive) { confirmation = .remove }
                    Button("Sign Out", action: account.signOut)
                }
                .disabled(account.working)
            } else if account.working {
                Button("Cancel Sign-In", action: account.cancel)
            } else if account.available {
                Button("Sign In with X-Center ID", action: account.signIn)
            } else {
                Text("X-Center ID sync is unavailable.").foregroundStyle(.secondary)
            }
            Text("Choose when to save or import per-app mouse profiles. File access and device settings stay on this Mac.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if !account.message.isEmpty {
                Text(account.message).font(.caption).foregroundStyle(.secondary)
            }
        }
        .task {
            await account.checkAvailability()
            checking = false
        }
        .confirmationDialog(confirmation?.title ?? "Mouse Profile Sync", isPresented: Binding(
            get: { confirmation != nil },
            set: { if !$0 { confirmation = nil } }
        ), titleVisibility: .visible, presenting: confirmation) { action in
            Button(action.title, role: action == .remove ? .destructive : nil) {
                switch action {
                case .upload: account.upload()
                case .download: account.importProfiles()
                case .remove: account.deleteUploadedProfiles()
                }
            }
        } message: { action in
            Text(action.detail)
        }
    }
}
