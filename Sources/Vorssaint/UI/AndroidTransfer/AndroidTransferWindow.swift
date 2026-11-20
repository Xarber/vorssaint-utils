// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

#if VORSSAINT_DEVELOPMENT
import AppKit
import Darwin
import SwiftUI

/// Local Developer build for validating the MTP helper on real devices.
final class AndroidTransferWindow: NSObject, NSWindowDelegate {
    static let shared = AndroidTransferWindow()
    static var available: Bool { helper.map { FileManager.default.isExecutableFile(atPath: $0.path) } == true }

    private static var helper: URL? { Bundle.main.url(forAuxiliaryExecutable: "vorssaint-mtp") }
    private var window: NSWindow?
    private var browser: AndroidTransferBrowser?

    func show() {
        guard let helper = Self.helper, Self.available else { return }
        if window == nil {
            let browser = AndroidTransferBrowser(helper: helper)
            let host = NSHostingController(rootView: AndroidTransferView(browser: browser))
            let window = NSWindow(contentViewController: host)
            window.title = "Android File Transfer"
            window.setContentSize(NSSize(width: 620, height: 440))
            window.isReleasedWhenClosed = false
            window.delegate = self
            self.browser = browser
            self.window = window
            window.center()
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) { browser?.cancel() }
}

private struct AndroidTransferEntry: Identifiable {
    let id: String
    let name: String
    var folder = false
    var size: UInt64?

    init?(_ line: Substring) {
        let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
        guard fields.count == 3 || fields.count == 5,
              ["device", "storage", "item"].contains(fields[0]) else { return nil }
        id = String(fields[1])
        var bytes: [UInt8] = []
        var hex = fields.last!
        guard hex.count.isMultiple(of: 2), hex.count <= 8_192 else { return nil }
        while !hex.isEmpty {
            guard let byte = UInt8(hex.prefix(2), radix: 16) else { return nil }
            bytes.append(byte)
            hex = hex.dropFirst(2)
        }
        let title = String(decoding: bytes, as: UTF8.self)
        name = title.isEmpty ? id : title
        if fields.count == 5 {
            folder = fields[2] == "folder"
            size = UInt64(fields[3])
        } else { folder = true }
    }

    var safeFilename: Bool {
        !name.isEmpty && name != "." && name != ".."
            && name.rangeOfCharacter(from: CharacterSet(charactersIn: "/:\\").union(.controlCharacters)) == nil
    }
}

private final class AndroidTransferBrowser: ObservableObject {
    @Published private(set) var entries: [AndroidTransferEntry] = []
    @Published var selection = Set<String>()
    @Published private(set) var moveCount = 0
    @Published private(set) var folders: [AndroidTransferEntry] = []
    @Published private(set) var storage: AndroidTransferEntry?
    @Published private(set) var device: AndroidTransferEntry?
    @Published private(set) var busy = false
    @Published private(set) var message = ""
    @Published private(set) var progress: Double?
    private let helper: URL
    private var process: Process?
    private var pendingMove: (ids: [AndroidTransferEntry], parent: String, storage: String)?
    private var parentID: String { folders.last?.id ?? String(UInt32.max) }
    var selectedFiles: [AndroidTransferEntry] {
        entries.filter { selection.contains($0.id) && !$0.folder && $0.safeFilename }
    }
    private var cancelled = false

    init(helper: URL) { self.helper = helper }

    func refresh() {
        let arguments: [String]
        if let storage, let device {
            arguments = ["list", device.id, storage.id, parentID]
        } else if let device {
            arguments = ["storages", device.id]
        } else { arguments = ["devices"] }
        run(arguments, preserveMessage: true) { [weak self] data in
            self?.entries = String(decoding: data, as: UTF8.self).split(separator: "\n")
                .compactMap(AndroidTransferEntry.init)
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
    }

    func open(_ entry: AndroidTransferEntry) {
        guard !busy, entry.folder else { return }
        if device == nil { device = entry }
        else if storage == nil { storage = entry }
        else { folders.append(entry) }
        entries = []
        selection.removeAll()
        refresh()
    }

    func back() {
        guard !busy else { return }
        if !folders.isEmpty { folders.removeLast() }
        else if storage != nil { storage = nil; cancelMove() }
        else { device = nil }
        entries = []
        selection.removeAll()
        refresh()
    }

    func download(_ files: [AndroidTransferEntry]) {
        guard let device, !files.isEmpty, files.allSatisfy(\.safeFilename) else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Save Copies"
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        let directory = folder.appendingPathComponent(".vorssaint-\(UUID().uuidString)", isDirectory: true)
        guard PrivateFileStore.createDirectory(at: directory, container: directory) else {
            message = "Couldn’t prepare the destination."
            return
        }
        let jobs = files.enumerated().map { index, file in
            let temporary = directory.appendingPathComponent(String(index))
            let destination = folder.appendingPathComponent(file.name)
            return Job(arguments: ["get", device.id, file.id, temporary.path]) {
                temporary.withUnsafeFileSystemRepresentation { source in
                    destination.withUnsafeFileSystemRepresentation { target in
                        renamex_np(source, target, UInt32(RENAME_EXCL)) == 0
                    }
                }
            }
        }
        runBatch(jobs) { [weak self] completed, outcome in
            try? FileManager.default.removeItem(at: directory)
            self?.showBatchResult(completed, total: files.count, outcome: outcome)
            if outcome == .success { NSWorkspace.shared.activateFileViewerSelecting([folder]) }
        }
    }

    func upload() {
        guard let device, let storage else { return }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        let jobs = panel.urls.map { Job(arguments: ["put", device.id, storage.id, parentID,
                                                    $0.path, $0.lastPathComponent]) }
        performRemote(jobs)
    }

    func rename() {
        guard let device, let storage, selectedFiles.count == 1, let file = selectedFiles.first else { return }
        let field = NSTextField(string: file.name)
        field.frame.size.width = 280
        let alert = NSAlert()
        alert.messageText = "Rename file on Android"
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn, field.stringValue != file.name else { return }
        performRemote([Job(arguments: ["rename", device.id, file.id, storage.id, parentID,
                                       file.name, field.stringValue])])
    }

    func deleteSelection() {
        guard let device, let storage, !selectedFiles.isEmpty else { return }
        let files = selectedFiles
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Permanently delete selected files?"
        alert.informativeText = "Android File Transfer can’t restore these files from the Trash."
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Delete")
        guard alert.runModal() == .alertSecondButtonReturn else { return }
        performRemote(files.map { Job(arguments: ["delete", device.id, $0.id, storage.id, parentID, $0.name]) })
    }

    func selectForMove() {
        guard let storage, !selectedFiles.isEmpty else { return }
        pendingMove = (selectedFiles, parentID, storage.id)
        moveCount = selectedFiles.count
    }

    func moveHere() {
        guard let device, let pendingMove, pendingMove.storage == storage?.id, pendingMove.parent != parentID else { return }
        cancelMove()
        performRemote(pendingMove.ids.map { Job(arguments: [
            "move", device.id, $0.id, pendingMove.storage, pendingMove.parent, $0.name, parentID
        ]) })
    }

    func cancelMove() {
        pendingMove = nil
        moveCount = 0
    }

    var canMoveHere: Bool { pendingMove.map { $0.parent != parentID && $0.storage == storage?.id } == true }

    private struct Job {
        let arguments: [String]
        var publish: () -> Bool = { true }
    }

    private enum BatchOutcome { case success, failed, cancelled }

    private func performRemote(_ jobs: [Job]) {
        runBatch(jobs) { [weak self] completed, outcome in
            self?.selection.removeAll()
            self?.showBatchResult(completed, total: jobs.count, outcome: outcome)
            self?.refresh()
        }
    }

    private func showBatchResult(_ completed: Int, total: Int, outcome: BatchOutcome) {
        switch outcome {
        case .success: message = "Completed \(completed) of \(total)."
        case .failed: message = "Stopped after \(completed) of \(total). Check the connection and destination names."
        case .cancelled: message = "Cancelled after \(completed) of \(total)."
        }
    }

    private func runBatch(_ jobs: [Job], completion: @escaping (Int, BatchOutcome) -> Void) {
        func next(_ remaining: ArraySlice<Job>, completed: Int) {
            guard let job = remaining.first else { completion(completed, .success); return }
            run(job.arguments, onFailure: { completion(completed, $0) }) { _ in
                guard job.publish() else { completion(completed, .failed); return }
                next(remaining.dropFirst(), completed: completed + 1)
            }
        }
        next(jobs[...], completed: 0)
    }

    func cancel() {
        guard let process, busy else { return }
        cancelled = true
        if process.isRunning { process.interrupt() }
    }

    private func run(_ arguments: [String], preserveMessage: Bool = false,
                     onFailure: ((BatchOutcome) -> Void)? = nil, completion: @escaping (Data) -> Void) {
        guard !busy else { onFailure?(.failed); return }
        let process = Process()
        process.executableURL = helper
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        let progressOutput = Pipe()
        process.standardError = progressOutput
        let progressHandle = progressOutput.fileHandleForReading
        progressHandle.readabilityHandler = { [weak self, weak process] handle in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil; return }
            guard let line = String(decoding: data, as: UTF8.self).split(separator: "\n").last else { return }
            let columns = line.split(separator: "\t")
            guard columns.count == 3, columns[0] == "progress",
                  let completed = UInt64(columns[1]), let total = UInt64(columns[2]), total > 0 else { return }
            DispatchQueue.main.async { [weak self, weak process] in
                guard let self, let process, self.process === process else { return }
                self.progress = min(1, Double(completed) / Double(total))
            }
        }
        do { try process.run() }
        catch {
            progressHandle.readabilityHandler = nil
            message = "Couldn’t start Android File Transfer."
            onFailure?(.failed)
            return
        }
        self.process = process
        cancelled = false
        busy = true
        if !preserveMessage { message = "" }
        progress = nil
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let status = process.terminationStatus
            progressHandle.readabilityHandler = nil
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.busy = false
                self.process = nil
                if self.cancelled {
                    self.message = "Cancelled."
                    onFailure?(.cancelled)
                    return
                }
                guard status == 0 else {
                    self.message = "Android File Transfer couldn’t complete. Check USB File Transfer mode and try again."
                    onFailure?(.failed)
                    return
                }
                completion(data)
            }
        }
    }
}

private struct AndroidTransferView: View {
    @ObservedObject var browser: AndroidTransferBrowser

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button(action: browser.back) { Label("Back", systemImage: "chevron.left") }
                    .disabled(browser.device == nil)
                Button(action: browser.refresh) { Label("Refresh", systemImage: "arrow.clockwise") }
                Spacer()
                if browser.storage != nil {
                    Button(action: browser.upload) { Label("Copy to Android", systemImage: "arrow.up") }
                }
            }
            .disabled(browser.busy)
            if browser.entries.isEmpty {
                Text(browser.device == nil
                     ? "Connect an unlocked Android device and choose File Transfer in its USB options."
                     : "This location is empty or unavailable.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(browser.entries, selection: $browser.selection) { entry in
                    HStack {
                        Label(entry.name, systemImage: entry.folder ? "folder" : "doc")
                            .lineLimit(1).truncationMode(.middle)
                        Spacer()
                        if entry.folder {
                            Button("Open") { browser.open(entry) }
                        } else {
                            Button("Save a Copy") { browser.download([entry]) }
                                .disabled(!entry.safeFilename)
                        }
                    }
                }
                .disabled(browser.busy)
            }
            if !browser.busy, browser.storage != nil {
                HStack {
                    Button("Save Copies") { browser.download(browser.selectedFiles) }
                        .disabled(browser.selectedFiles.isEmpty)
                    Menu("Manage Files") {
                        Button("Rename…", action: browser.rename).disabled(browser.selectedFiles.count != 1)
                        Button("Select for Move", action: browser.selectForMove).disabled(browser.selectedFiles.isEmpty)
                        Button("Delete…", role: .destructive, action: browser.deleteSelection)
                            .disabled(browser.selectedFiles.isEmpty)
                    }
                    Spacer()
                    if browser.moveCount > 0 {
                        Button("Cancel Move", action: browser.cancelMove)
                        Button("Move Here", action: browser.moveHere).disabled(!browser.canMoveHere)
                    }
                }
            }
            if browser.busy {
                HStack {
                    if let progress = browser.progress {
                        ProgressView(value: progress).frame(maxWidth: 180)
                    } else {
                        ProgressView().controlSize(.small)
                    }
                    Text("Working…")
                    Spacer()
                    Button("Cancel", action: browser.cancel)
                }
            } else if !browser.message.isEmpty {
                Text(browser.message).foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(minWidth: 500, minHeight: 340)
        .onAppear(perform: browser.refresh)
    }
}
#endif
