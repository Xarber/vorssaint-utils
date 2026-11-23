// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

#if VORSSAINT_DEVELOPMENT
import AppKit
import SwiftUI

final class LocalSendSession: ObservableObject {
    static let shared = LocalSendSession()
    private static let folderKey = "localSendReceiveFolderBookmark"
    private static var helper: URL? { Bundle.main.url(forAuxiliaryExecutable: "vorssaint-localsend") }
    static var available: Bool { helper.map { FileManager.default.isExecutableFile(atPath: $0.path) } == true }

    static func syncFeature() { shared.syncFeature() }

    func syncFeature() {
        guard AppFeature.localSend.isAvailable, Self.available else {
            stop()
            files = []
            return
        }
        if process == nil, retry == nil { start(receiveFolder: receiveFolder) }
    }

    @Published private(set) var receiveFolder: URL?
    private var scopedFolder: URL?

    private init() {
        guard let data = UserDefaults.standard.data(forKey: Self.folderKey) else { return }
        var stale = false
        receiveFolder = try? URL(resolvingBookmarkData: data, options: [.withSecurityScope, .withoutUI],
                                 relativeTo: nil, bookmarkDataIsStale: &stale)
        if stale { receiveFolder = nil }
    }

    struct Peer: Identifiable, Decodable { let id: String; let name: String }
    struct Offer: Decodable {
        let id: String
        let name: String
        let files: [String]
    }

    @Published private(set) var peers: [Peer] = []
    @Published private(set) var offer: Offer?
    @Published private(set) var message = ""
    @Published private(set) var active = false
    @Published private(set) var sending = false
    @Published private(set) var files: [URL] = []
    private var process: Process?
    private var input: FileHandle?
    private var readBuffer = Data()
    private var retry: DispatchWorkItem?

    func stage(_ urls: [URL]) -> Bool {
        guard NearbyFeatureLifecycle.canStage(urls), !sending else { return false }
        files = urls
        if active { refresh() }
        else if AppFeature.localSend.isAvailable && Self.available { syncFeature() }
        return true
    }

    func clearStagedFiles() { if !sending { files = [] } }

    func chooseReceiveFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.prompt = "Start Receiving"
        guard panel.runModal() == .OK, let directory = panel.url else { return }
        guard let bookmark = try? directory.bookmarkData(options: .withSecurityScope,
                                                         includingResourceValuesForKeys: nil, relativeTo: nil) else {
            message = "Couldn’t remember the receive folder."
            return
        }
        UserDefaults.standard.set(bookmark, forKey: Self.folderKey)
        receiveFolder = directory
        Notifier.requestPermission()
        restartForFolderChange()
    }

    func forgetReceiveFolder() {
        UserDefaults.standard.removeObject(forKey: Self.folderKey)
        receiveFolder = nil
        restartForFolderChange()
    }

    private func restartForFolderChange() {
        stop()
        syncFeature()
    }

    private func start(receiveFolder: URL?) {
        guard !active, let helper = Self.helper else { return }
        let process = Process()
        process.executableURL = helper
        if let receiveFolder {
            if receiveFolder.startAccessingSecurityScopedResource() { scopedFolder = receiveFolder }
            process.arguments = [receiveFolder.path]
        }
        let commands = Pipe()
        let events = Pipe()
        process.standardInput = commands
        process.standardOutput = events
        process.standardError = FileHandle.nullDevice
        events.fileHandleForReading.readabilityHandler = { [weak self, weak process] handle in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil; return }
            DispatchQueue.main.async { [weak self, weak process] in
                guard let self, let process, process === self.process else { return }
                self.consume(data)
            }
        }
        process.terminationHandler = { [weak self] process in
            DispatchQueue.main.async { [weak self] in
                guard let self, self.process === process else { return }
                self.process = nil
                let wasActive = self.active
                self.resetConnection()
                if wasActive {
                    self.message = "LocalSend disconnected. Retrying…"
                    self.scheduleRetry()
                } else {
                    self.syncFeature()
                }
            }
        }
        do { try process.run() }
        catch {
            events.fileHandleForReading.readabilityHandler = nil
            scopedFolder?.stopAccessingSecurityScopedResource()
            scopedFolder = nil
            message = "Couldn’t start LocalSend."
            scheduleRetry()
            return
        }
        self.process = process
        input = commands.fileHandleForWriting
        active = true
        message = "Starting LocalSend…"
    }

    private func stop() {
        retry?.cancel()
        retry = nil
        resetConnection()
        if let process, process.isRunning { process.terminate() }
    }

    private func scheduleRetry() {
        guard AppFeature.localSend.isAvailable, Self.available, retry == nil else { return }
        let retry = DispatchWorkItem { [weak self] in
            self?.retry = nil
            self?.syncFeature()
        }
        self.retry = retry
        DispatchQueue.main.asyncAfter(deadline: .now() + 15, execute: retry)
    }

    private func resetConnection() {
        try? input?.close()
        input = nil
        scopedFolder?.stopAccessingSecurityScopedResource()
        scopedFolder = nil
        active = false
        sending = false
        offer = nil
        peers = []
        readBuffer.removeAll()
    }

    func refresh() { command(["kind": "refresh"]) }

    func send(_ peer: Peer) {
        guard !files.isEmpty, files.count <= 64, !sending else { return }
        sending = true
        message = "Waiting for \(peer.name)…"
        command(["kind": "send", "id": peer.id, "paths": files.map(\.path)])
    }

    func confirm(_ accept: Bool) {
        guard let offer else { return }
        command(["kind": accept ? "accept" : "decline", "id": offer.id])
        if accept { message = "Receiving files…" }
        self.offer = nil
    }

    func cancelSend() { command(["kind":"cancelSend"]) }

    private func command(_ object: [String: Any]) {
        guard let input, let payload = try? JSONSerialization.data(withJSONObject: object) else { return }
        do { try input.write(contentsOf: payload + Data([10])) }
        catch { process?.terminate(); message = "LocalSend lost its connection." }
    }

    private func consume(_ data: Data) {
        readBuffer.append(data)
        while let boundary = readBuffer.firstIndex(of: 10) {
            let line = Data(readBuffer[..<boundary])
            readBuffer.removeSubrange(...boundary)
            guard let event = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  let kind = event["kind"] as? String else { continue }
            switch kind {
            case "ready": message = files.isEmpty ? "Waiting for nearby devices to send files." : "Choose a nearby device."
            case "peers":
                if let list = event["peers"], let bytes = try? JSONSerialization.data(withJSONObject: list),
                   let peers = try? JSONDecoder().decode([Peer].self, from: bytes) {
                    self.peers = peers.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                }
            case "offer":
                guard let newOffer = try? JSONDecoder().decode(Offer.self, from: line) else { continue }
                if offer?.id != newOffer.id {
                    Notifier.post(title: "Incoming LocalSend transfer",
                                  body: "Review the request in the island or Shelf settings.")
                }
                offer = newOffer
            case "offerEnded": if (event["id"] as? String) == offer?.id { offer = nil }
            case "sendComplete": sending = false; files = []; message = "Files sent."
            case "sendFailed": sending = false; message = "The transfer ended before all files were sent."
            case "receiveComplete": message = "File saved."
            case "receiveFailed": message = "A file couldn’t be saved. Check free space and existing filenames."
            case "progress":
                if let completed = event["completed"] as? Int, let total = event["total"] as? Int {
                    message = "Sent \(completed) of \(total)."
                }
            case "error": message = "LocalSend couldn’t complete the operation."
            default: break
            }
        }
        if readBuffer.count > 1_000_000 { process?.terminate() }
    }
}

struct NearbyTransferControls: View {
    @ObservedObject var session = LocalSendSession.shared
    var compact = false
    var showsSender = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let offer = session.offer {
                Text(offer.name).font(.headline).lineLimit(1)
                ScrollView {
                    ForEach(Array(offer.files.enumerated()), id: \.offset) { item in
                        Label(item.element, systemImage: "doc").lineLimit(1)
                    }
                }.frame(maxHeight: compact ? 38 : 80)
                HStack {
                    Button("Decline") { session.confirm(false) }
                    Button("Accept Files") { session.confirm(true) }
                }
            } else if showsSender, !session.files.isEmpty, AppFeature.localSend.isAvailable, LocalSendSession.available {
                if session.peers.isEmpty {
                    Label("Finding nearby devices…", systemImage: "dot.radiowaves.left.and.right")
                } else {
                    ScrollView {
                        ForEach(session.peers) { peer in
                            Button { session.send(peer) } label: {
                                HStack {
                                    Label(peer.name, systemImage: "desktopcomputer").lineLimit(1)
                                    Spacer()
                                    Text("LocalSend").font(.caption).foregroundStyle(.secondary)
                                }
                            }.disabled(session.sending)
                        }
                    }.frame(maxHeight: compact ? 70 : 135)
                }
                HStack {
                    Button("Refresh", action: session.refresh).disabled(session.sending)
                    if session.sending {
                        Button("Cancel Transfer", action: session.cancelSend)
                    } else {
                        Button("Clear", action: session.clearStagedFiles)
                    }
                }
            }
            if !session.message.isEmpty {
                Text(session.message).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct TransferFeatureSettings: View {
    @ObservedObject private var features = FeatureRuntime.shared
    @ObservedObject private var localSend = LocalSendSession.shared

    var body: some View {
        Section("Nearby Transfer") {
            if AppFeature.localSend.isAvailable {
                if LocalSendSession.available {
                    Button(localSend.receiveFolder?.lastPathComponent ?? "Choose LocalSend Receive Folder…",
                           action: localSend.chooseReceiveFolder)
                    if localSend.receiveFolder != nil {
                        Button("Stop Receiving", action: localSend.forgetReceiveFolder)
                    }
                    NearbyTransferControls(session: localSend, showsSender: false)
                } else {
                    Text("This build needs the LocalSend helper.")
                }
            }
            if AppFeature.quickShare.isAvailable {
                Text(QuickShareCompanion.available ? "NearDrop supplies Quick Share in the native Share menu."
                     : "Install NearDrop to use Quick Share.")
            }
            if AppFeature.androidTransfer.isAvailable {
                AndroidTransferSettings()
            }
        }
    }
}
#endif
