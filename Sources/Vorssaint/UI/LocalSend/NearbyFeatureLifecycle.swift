// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

enum NearbyFeatureLifecycle {
    static var hasQuickShare: Bool {
#if VORSSAINT_DEVELOPMENT
        AppFeature.quickShare.isAvailable && QuickShareCompanion.available
#else
        false
#endif
    }

    static func canStage(_ files: [URL]) -> Bool {
#if VORSSAINT_DEVELOPMENT
        (hasQuickShare || (AppFeature.localSend.isAvailable && LocalSendSession.available))
            && !files.isEmpty && files.count <= 64 && files.allSatisfy(\.isFileURL)
#else
        false
#endif
    }

    static func syncLocalSend() {
#if VORSSAINT_DEVELOPMENT
        LocalSendSession.syncFeature()
#endif
    }

    static func syncAndroidTransfer() {
#if VORSSAINT_DEVELOPMENT
        AndroidUSBFeature.sync()
#endif
    }

    static func syncQuickShare() {
#if VORSSAINT_DEVELOPMENT
        QuickShareCompanion.syncFeature()
#endif
    }
}

#if VORSSAINT_DEVELOPMENT
enum QuickShareCompanion {
    private static let identifier = "me.grishka.NearDrop"
    private static var appURL: URL? { NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier) }
    static var available: Bool { appURL != nil }
    private static var startedApp: NSRunningApplication?
    private static var launching = false
    private static var terminationObserver: NSObjectProtocol?
    private static var retry: DispatchWorkItem?

    static func syncFeature() {
        guard AppFeature.quickShare.isAvailable else {
            retry?.cancel()
            retry = nil
            if let terminationObserver {
                NSWorkspace.shared.notificationCenter.removeObserver(terminationObserver)
            }
            terminationObserver = nil
            startedApp?.terminate()
            startedApp = nil
            return
        }
        if terminationObserver == nil {
            terminationObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
            ) { notification in
                guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                      app.bundleIdentifier == identifier else { return }
                if startedApp?.processIdentifier == app.processIdentifier { startedApp = nil }
                scheduleRetry()
            }
        }
        guard !launching, NSRunningApplication.runningApplications(withBundleIdentifier: identifier).isEmpty,
              let appURL else { return }
        launching = true
        let options = NSWorkspace.OpenConfiguration()
        options.activates = false
        NSWorkspace.shared.openApplication(at: appURL, configuration: options) { app, _ in
            DispatchQueue.main.async {
                launching = false
                if AppFeature.quickShare.isAvailable {
                    startedApp = app
                    if app == nil { scheduleRetry() }
                } else { app?.terminate() }
            }
        }
    }

    private static func scheduleRetry() {
        guard AppFeature.quickShare.isAvailable, available, retry == nil else { return }
        let work = DispatchWorkItem {
            retry = nil
            syncFeature()
        }
        retry = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 15, execute: work)
    }
}
#endif
