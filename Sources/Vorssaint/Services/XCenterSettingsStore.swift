// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Private app record adapter. A validated, app-scoped user session supplies
/// the token. It is deliberately independent of browser sign-in and storage.
struct XCenterSettingsStore: Sendable {
    struct Record: Sendable {
        let archive: Data
        let revision: String
    }

    enum Failure: Error {
        case invalidResponse, notAuthorized, conflict, tooLarge
    }

    private struct Payload: Codable {
        let archive: Data
    }

    static let maximumArchiveBytes = 6 * 1024 * 1024
    private static let maximumEnvelopeBytes = (maximumArchiveBytes / 3) * 4 + 1024

    private let recordURL = URL(string: "https://vorssaint.xcenter.it/auth/xcenter/backup")!

    func fetch(accessToken: String) async throws -> Record? {
        try await exchange(method: "GET", accessToken: accessToken)
    }

    func revision(accessToken: String) async throws -> String? {
        try await exchange(method: "HEAD", accessToken: accessToken)?.revision
    }

    func save(_ archive: Data, replacing revision: String,
              accessToken: String) async throws -> Record {
        guard archive.count <= Self.maximumArchiveBytes else { throw Failure.tooLarge }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        let bytes = try encoder.encode(Payload(archive: archive))
        guard let record = try await exchange(method: "PUT", accessToken: accessToken, revision: revision, body: bytes) else {
            throw Failure.invalidResponse
        }
        return record
    }

    func delete(revision: String, accessToken: String) async throws {
        _ = try await exchange(method: "DELETE", accessToken: accessToken, revision: revision)
    }

    private func exchange(method: String, accessToken: String, revision: String? = nil, body: Data? = nil) async throws -> Record? {
        guard !accessToken.isEmpty else { throw Failure.notAuthorized }
        var request = URLRequest(url: recordURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 90)
        request.httpMethod = method
        request.setValue("Bearer " + accessToken, forHTTPHeaderField: "Authorization")
        if let revision {
            guard !revision.isEmpty, revision.utf8.count <= 64,
                  revision.utf8.allSatisfy({ (48...57).contains($0) }) else { throw Failure.invalidResponse }
            request.setValue("\"\(revision)\"", forHTTPHeaderField: "If-Match")
        }
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        let session = URLSession(configuration: config, delegate: DenyRedirects(), delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw Failure.invalidResponse }
        switch response.statusCode {
        case 401, 403: throw Failure.notAuthorized
        case 204 where method == "DELETE": return nil
        case 404 where method == "GET" || method == "HEAD": return nil
        case 409, 412: throw Failure.conflict
        case 413, 507: throw Failure.tooLarge
        case 200, 201: break
        default: throw Failure.invalidResponse
        }
        guard let etag = response.value(forHTTPHeaderField: "ETag"), etag.count > 2, etag.count <= 66,
              etag.first == "\"", etag.last == "\"" else { throw Failure.invalidResponse }
        let revision = String(etag.dropFirst().dropLast())
        guard revision.utf8.allSatisfy({ (48...57).contains($0) }) else { throw Failure.invalidResponse }
        if method == "HEAD" { return Record(archive: Data(), revision: revision) }
        guard data.count <= Self.maximumEnvelopeBytes,
              let payload = try? JSONDecoder().decode(Payload.self, from: data),
              payload.archive.count <= Self.maximumArchiveBytes else { throw Failure.invalidResponse }
        return Record(archive: payload.archive, revision: revision)
    }

    private final class DenyRedirects: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
            completionHandler(nil)
        }
    }
}
