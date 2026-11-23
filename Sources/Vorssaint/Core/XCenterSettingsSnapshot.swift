// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The first private sync category has an explicit allowlist. File access,
/// executable paths, files, snippets, and credentials are local to each Mac.
enum XCenterSettingsSnapshot {
    struct Snapshot: Codable, Equatable, Sendable {
        let version: Int
        let mouseProfiles: [String: String]
    }

    static let maximumProfiles = 256
    static let maximumBodyBytes = 60_000

    static func snapshot(from defaults: UserDefaults = .standard) -> Snapshot {
        let profiles = defaults.dictionary(forKey: DefaultsKey.scrollDirectionProfiles) as? [String: String] ?? [:]
        return Snapshot(version: 1, mouseProfiles: validProfiles(profiles))
    }

    static func validated(_ snapshot: Snapshot) -> Snapshot? {
        guard snapshot.version == 1, snapshot.mouseProfiles.count <= maximumProfiles,
              validProfiles(snapshot.mouseProfiles) == snapshot.mouseProfiles else { return nil }
        return snapshot
    }

    private static func validProfiles(_ profiles: [String: String]) -> [String: String] {
        Dictionary(uniqueKeysWithValues: profiles.keys.sorted().lazy.prefix(maximumProfiles).compactMap { id in
            guard id.utf8.count <= 120, id.contains("."),
                  id.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0)
                      || (97...122).contains($0) || $0 == 46 || $0 == 45 }),
                  let raw = profiles[id], raw.utf8.count <= 64,
                  let profile = MouseScrollDirectionProfile(storage: raw) else { return nil }
            return (id, profile.storage)
        })
    }
}
