// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

#if VORSSAINT_DEVELOPMENT
import AppKit
import SwiftUI

final class LocalSendWindow: NSObject, NSWindowDelegate {
    static let shared = LocalSendWindow()
    private static var helper: URL? { Bundle.main.url(forAuxiliaryExecutable: "vorssaint-localsend") }
    static var available: Bool { helper.map { FileManager.default.isExecutableFile(atPath: $0.path) } == true }
    private var window: NSWindow?
    private var session: LocalSendSession?

    func show(_ files: [URL] = []) {
        guard Self.available, let helper = Self.helper else { return }
        if let window, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            return
        }
        let session = LocalSendSession(helper: helper, files: files)
        let host = NSHostingController(rootView: LocalSendView(session: session))
        let window = NSWindow(contentViewController: host)
        window.title = "LocalSend"
        window.setContentSize(NSSize(width: 440, height: 360))
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        self.session = session
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) { session?.stop() }
}

private final class LocalSendSession: ObservableObject {
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
    let files: [URL]
    private let helper: URL
    private var process: Process?
    private var input: FileHandle?
    private var readBuffer = Data()

    init(helper: URL, files: [URL]) {
        self.helper = helper
        self.files = files.filter(\.isFileURL)
    }

    func chooseReceiveFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.prompt = "Start Receiving"
        guard panel.runModal() == .OK, let directory = panel.url else { return }
        start(receiveFolder: directory)
    }

    func start(receiveFolder: URL? = nil) {
        guard !active else { return }
        let process = Process()
        process.executableURL = helper
        if let receiveFolder { process.arguments = [receiveFolder.path] }
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
                self.stop()
                self.message = "LocalSend closed. Check whether another app is using its port."
            }
        }
        do { try process.run() }
        catch {
            events.fileHandleForReading.readabilityHandler = nil
            message = "Couldn’t start LocalSend."
            return
        }
        self.process = process
        input = commands.fileHandleForWriting
        active = true
        message = "Starting LocalSend…"
    }

    func stop() {
        let running = process
        process = nil
        try? input?.close()
        input = nil
        if let running, running.isRunning { running.interrupt() }
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
        catch { stop(); message = "LocalSend lost its connection." }
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
            case "offer": offer = try? JSONDecoder().decode(Offer.self, from: line)
            case "offerEnded": if (event["id"] as? String) == offer?.id { offer = nil }
            case "sendComplete": sending = false; message = "Files sent."
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
        if readBuffer.count > 1_000_000 { stop() }
    }
}

private struct LocalSendView: View {
    @ObservedObject var session: LocalSendSession

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let offer = session.offer {
                Text(offer.name).font(.headline)
                List(Array(offer.files.enumerated()), id: \.offset) { item in
                    Label(item.element, systemImage: "doc")
                }
                HStack {
                    Button("Decline") { session.confirm(false) }
                    Button("Accept Files") { session.confirm(true) }
                }
            } else if !session.active {
                if session.files.isEmpty {
                    Button("Choose Receive Folder…", action: session.chooseReceiveFolder)
                } else if session.files.count <= 64 {
                    Button("Find Nearby Devices") { session.start() }
                } else {
                    Text("Select up to 64 files.")
                }
            } else if !session.files.isEmpty {
                List(session.peers) { peer in
                    HStack {
                        Label(peer.name, systemImage: "desktopcomputer")
                        Spacer()
                        Button("Send") { session.send(peer) }.disabled(session.sending)
                    }
                }
                if session.sending {
                    Button("Cancel Transfer", action: session.cancelSend)
                } else {
                    Button("Refresh Devices", action: session.refresh)
                }
            }
            Text(session.message).foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(minWidth: 380, minHeight: 320)
    }
}
#endif
