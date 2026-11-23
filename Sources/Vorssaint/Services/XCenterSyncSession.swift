// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import CryptoKit
import Foundation
import Security

@MainActor
final class XCenterSyncSession: ObservableObject {
    static let shared = XCenterSyncSession()
    @Published private(set) var connected = false
    @Published private(set) var working = false
    @Published private(set) var message = ""
    @Published private(set) var available = false
    private var session: String?
    private var operation: Task<Void, Never>?
    private var expiry: Task<Void, Never>?
    private let store = XCenterSettingsStore()

    private static let origin = URL(string: "https://vorssaint.xcenter.it/auth/xcenter/")!

    private struct Status: Decodable { let enabled: Bool }
    private struct Start: Encodable { let challenge: String }
    private struct Transaction: Decodable { let transaction: String; let url: URL }
    private struct Proof: Encodable { let transaction: String; let proof: String }
    private struct Pickup: Decodable { let session: String; let expiresIn: Int }
    private enum Failure: Error { case unavailable, invalidResponse, expired, rejected, browser }

    private init() {}

    func checkAvailability() async {
        guard let result = try? await Self.request("status", method: "GET", body: nil),
              (200...299).contains(result.status) else { return }
        available = (try? JSONDecoder().decode(Status.self, from: result.data).enabled) == true
    }

    func signIn() {
        guard !connected, !working, available else { return }
        run { [self] in
            let proof = try Self.generateProof()
            let challenge = SHA256.hash(data: Data(proof.utf8)).map { String(format: "%02x", $0) }.joined()
            let start = try await Self.post("start", Start(challenge: challenge))
            guard start.status == 201 else { throw Failure.unavailable }
            let transaction = try JSONDecoder().decode(Transaction.self, from: start.data)
            guard Self.isHexKey(transaction.transaction),
                  transaction.url.scheme == Self.origin.scheme,
                  transaction.url.host == Self.origin.host, transaction.url.port == nil,
                  transaction.url.path == "/auth/xcenter/browser",
                  transaction.url.user == nil, transaction.url.password == nil,
                  transaction.url.fragment == nil else { throw Failure.invalidResponse }
            let request = Proof(transaction: transaction.transaction, proof: proof)
            do {
                try Task.checkCancellation()
                guard NSWorkspace.shared.open(transaction.url) else { throw Failure.browser }
                message = "Finish signing in in your browser."
                let deadline = ContinuousClock.now + .seconds(285)
                while ContinuousClock.now < deadline {
                    try await Task.sleep(for: .seconds(2))
                    let response = try await Self.post("pickup", request)
                    switch response.status {
                    case 202: continue
                    case 403: throw Failure.rejected
                    case 200:
                        let pickup = try JSONDecoder().decode(Pickup.self, from: response.data)
                        guard Self.isHexKey(pickup.session), (1...1800).contains(pickup.expiresIn) else {
                            throw Failure.invalidResponse
                        }
                        setSession(pickup)
                        message = "Connected to X-Center ID."
                        return
                    default: throw Failure.expired
                    }
                }
                throw Failure.expired
            } catch {
                Task { _ = try? await Self.post("cancel", request) }
                throw error
            }
        }
    }

    func cancel() { operation?.cancel() }

    func signOut() {
        let token = session
        clearSession()
        message = "Signed out. Your local data is still on this Mac."
        if let token {
            Task { _ = try? await Self.request("signout", method: "POST", body: nil, session: token) }
        }
    }

    func upload() {
        guard let session, !working else { return }
        run { [self] in
            ScratchpadService.shared.prepareForSettingsBackup()
            let backup = try SettingsBackup.backupData(format: .binary)
            let revision = try await store.revision(accessToken: session) ?? "0"
            try Task.checkCancellation()
            _ = try await store.save(backup, replacing: revision, accessToken: session)
            message = "App data backed up to X-Center ID."
        }
    }

    func loadBackup(_ review: @escaping @MainActor ([String: Any]) -> Void) {
        guard let session, !working else { return }
        run { [self] in
            guard let record = try await store.fetch(accessToken: session) else {
                message = "There is no cloud backup for this account."
                return
            }
            try Task.checkCancellation()
            guard let settings = SettingsBackup.decodeSettings(record.archive), !settings.isEmpty else {
                throw Failure.invalidResponse
            }
            review(settings)
        }
    }

    func deleteBackup() {
        guard let session, !working else { return }
        run { [self] in
            if let revision = try await store.revision(accessToken: session) {
                try Task.checkCancellation()
                try await store.delete(revision: revision, accessToken: session)
            }
            message = "Cloud backup removed."
        }
    }

    private func setSession(_ pickup: Pickup) {
        expiry?.cancel()
        session = pickup.session
        connected = true
        expiry = Task {
            do { try await Task.sleep(for: .seconds(pickup.expiresIn)) }
            catch { return }
            clearSession()
            message = "Your X-Center ID session expired. Sign in again to sync."
        }
    }

    private func clearSession() {
        expiry?.cancel()
        expiry = nil
        session = nil
        connected = false
    }

    private func run(_ work: @escaping @MainActor () async throws -> Void) {
        working = true
        operation = Task {
            defer { working = false; operation = nil }
            do { try await work() }
            catch is CancellationError { message = "Cancelled." }
            catch XCenterSettingsStore.Failure.notAuthorized {
                clearSession()
                message = "Check your account permissions and sign in again."
            } catch XCenterSettingsStore.Failure.conflict {
                message = "The cloud backup changed. Try again to use the latest revision."
            } catch XCenterSettingsStore.Failure.tooLarge {
                message = "This backup exceeds the available cloud space. You can still export it to a file."
            } catch Failure.rejected {
                message = "Sign-in was declined or the storage permission is unavailable."
            } catch {
                message = "X-Center ID couldn’t complete the request."
            }
        }
    }

    private static func generateProof() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let result = bytes.withUnsafeMutableBytes {
            SecRandomCopyBytes(kSecRandomDefault, $0.count, $0.baseAddress!)
        }
        guard result == errSecSuccess else { throw Failure.unavailable }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    private static func isHexKey(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }

    private static func post<Body: Encodable>(_ path: String, _ body: Body) async throws -> (data: Data, status: Int) {
        try await request(path, method: "POST", body: JSONEncoder().encode(body))
    }

    private static func request(_ path: String, method: String, body: Data?, session: String? = nil) async throws
        -> (data: Data, status: Int) {
        var request = URLRequest(url: origin.appendingPathComponent(path), cachePolicy: .reloadIgnoringLocalCacheData,
                                 timeoutInterval: 12)
        request.httpMethod = method
        request.httpBody = body
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        if let session { request.setValue("Bearer " + session, forHTTPHeaderField: "Authorization") }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        let connection = URLSession(configuration: configuration, delegate: DenyRedirects(), delegateQueue: nil)
        defer { connection.finishTasksAndInvalidate() }
        let (data, response) = try await connection.data(for: request)
        guard let response = response as? HTTPURLResponse, data.count < 4096 else { throw Failure.invalidResponse }
        return (data, response.statusCode)
    }

    private final class DenyRedirects: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
            completionHandler(nil)
        }
    }
}
