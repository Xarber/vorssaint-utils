// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// Opens the system share sheet for shelf files, from the tile menu and from
/// the panel's own button. It holds the picker while the sheet is up, brings
/// the app forward only once a target has actually been chosen (the shelf
/// panel never activates on its own, so a share window would otherwise open
/// behind whatever is in front), and lets the picker go afterwards.
final class ShelfSharePresenter: NSObject, NSSharingServicePickerDelegate {
    private var picker: NSSharingServicePicker?
    private var completion: ((Bool) -> Void)?

    /// The system's own share menu: AirDrop alongside every other place the
    /// Mac can send files to, kept current by macOS rather than by a list
    /// written here.
    func shareMenuItem(for urls: [URL], title: String) -> NSMenuItem {
        let item = makePicker(for: urls).standardShareMenuItem
        item.title = title
        return item
    }

    /// `completion` reports whether a target was chosen once the sheet
    /// closes. It never runs when there was no window to show the sheet
    /// from, which the result reports as false.
    @discardableResult
    func present(for urls: [URL], from view: NSView, completion: ((Bool) -> Void)? = nil) -> Bool {
        guard view.window != nil else { return false }
        let picker = makePicker(for: urls)
        self.completion = completion
        picker.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
        return true
    }

#if VORSSAINT_DEVELOPMENT
    func sharingServicePicker(_ picker: NSSharingServicePicker, sharingServicesForItems items: [Any],
                              proposedSharingServices proposed: [NSSharingService]) -> [NSSharingService] {
        let files = items.compactMap { $0 as? URL }.filter(\.isFileURL)
        guard LocalSendWindow.available, !files.isEmpty, files.count == items.count,
              let icon = NSImage(systemSymbolName: "point.3.connected.trianglepath.dotted",
                                 accessibilityDescription: "LocalSend") else { return proposed }
        let localSend = NSSharingService(title: "LocalSend", image: icon, alternateImage: nil) {
            DispatchQueue.main.async { LocalSendWindow.shared.show(files) }
        }
        return proposed + [localSend]
    }
#endif

    func sharingServicePicker(_ sharingServicePicker: NSSharingServicePicker,
                              didChoose service: NSSharingService?) {
        // A late answer from a menu that was already replaced must not take
        // the newer one's completion.
        guard sharingServicePicker === picker else { return }
        picker = nil
        let completion = self.completion
        self.completion = nil
        if service != nil { NSApp.activate(ignoringOtherApps: true) }
        completion?(service != nil)
    }

    private func makePicker(for urls: [URL]) -> NSSharingServicePicker {
        let picker = NSSharingServicePicker(items: urls)
        picker.delegate = self
        self.picker = picker
        completion = nil
        return picker
    }
}

/// Opens the native recipient picker after the drag callback returns. Temporary
/// files from AppKit promises stay alive until the sharing service finishes.
final class ShelfAirDropPresenter: NSObject, NSSharingServiceDelegate {
    private var pending = false
    private var service: NSSharingService?
    private var stagingDirectory: URL?
    private static let maximumPromisedFiles = 64

    var isAvailable: Bool { !pending && service == nil }

    func canOffer(_ pasteboard: NSPasteboard) -> Bool {
        let urls = ShelfService.shared.fileURLs(from: pasteboard)
        if !urls.isEmpty {
            return urls.count >= (pasteboard.pasteboardItems?.count ?? 0)
                && !pasteboard.canReadObject(forClasses: [NSFilePromiseReceiver.self], options: nil)
        }
        let types = Set(NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) })
        guard let items = pasteboard.pasteboardItems, !items.isEmpty else { return false }
        return items.allSatisfy { !types.isDisjoint(with: $0.types) }
            && pasteboard.canReadObject(forClasses: [NSFilePromiseReceiver.self], options: nil)
    }

    func accept(_ pasteboard: NSPasteboard, canContinue: @escaping () -> Bool) -> Bool {
        guard isAvailable, canOffer(pasteboard) else { return false }
        let urls = ShelfService.shared.fileURLs(from: pasteboard)
        if !urls.isEmpty { return share(urls, canContinue: canContinue) }

        let receivers = pasteboard.readObjects(forClasses: [NSFilePromiseReceiver.self], options: nil)
            as? [NSFilePromiseReceiver] ?? []
        guard !receivers.isEmpty, receivers.count <= Self.maximumPromisedFiles else { return false }
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("VorssaintAirDrop-\(UUID().uuidString)", isDirectory: true)
        let staged = root.appendingPathComponent("Files", isDirectory: true)
        guard PrivateFileStore.createDirectory(at: root, container: root) else { return false }
        guard let transfer = ShelfFilePromiseTransfer(temporaryDirectory: root, storeDirectory: staged,
                                                      maximumFiles: Self.maximumPromisedFiles,
                                                      completion: { [weak self] result in
            guard let self else {
                try? FileManager.default.removeItem(at: root)
                return
            }
            guard canContinue(), !result.failed, !result.urls.isEmpty else {
                self.finish()
                if canContinue() { self.reportUnavailable() }
                return
            }
            self.present(result.urls)
        }) else {
            try? FileManager.default.removeItem(at: root)
            return false
        }
        stagingDirectory = root
        pending = true
        guard transfer.receive(receivers) else {
            finish()
            return false
        }
        return true
    }

    func share(_ urls: [URL], canContinue: @escaping () -> Bool) -> Bool {
        guard isAvailable, !urls.isEmpty, urls.allSatisfy(\.isFileURL) else { return false }
        pending = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard canContinue() else { self.finish(); return }
            self.present(urls)
        }
        return true
    }

    private func present(_ urls: [URL]) {
        guard let sharing = NSSharingService(named: .sendViaAirDrop),
              sharing.canPerform(withItems: urls) else {
            finish()
            reportUnavailable()
            return
        }
        pending = false
        service = sharing
        sharing.delegate = self
        NSApp.activate(ignoringOtherApps: true)
        sharing.perform(withItems: urls)
    }

    func sharingService(_ sharingService: NSSharingService, didShareItems items: [Any]) {
        if sharingService === service { finish() }
    }

    func sharingService(_ sharingService: NSSharingService, didFailToShareItems items: [Any], error: any Error) {
        guard sharingService === service else { return }
        finish()
        let underlying = error as NSError
        if underlying.domain != NSCocoaErrorDomain || underlying.code != NSUserCancelledError {
            NSApp.presentError(error)
        }
    }

    private func finish() {
        pending = false
        service = nil
        if let stagingDirectory {
            try? FileManager.default.removeItem(at: stagingDirectory)
            self.stagingDirectory = nil
        }
    }

    private func reportUnavailable() {
        let strings = ShelfPromiseDeliveryStrings.localized(L10n.shared.language)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "AirDrop"
        alert.informativeText = FeatureStrings.notchFiles(L10n.shared.language).airDropUnavailable
        alert.addButton(withTitle: strings.okButton)
        if let window = NSApp.keyWindow { alert.beginSheetModal(for: window) }
        else { NSApp.activate(ignoringOtherApps: true); alert.runModal() }
    }
}
