//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import FactoryKit
import Foundation

enum SeerrKeychain {
    private static var userID: String {
        if case let .signedIn(id) = Defaults[.lastSignedInUserID] {
            id
        } else {
            "default"
        }
    }

    private static var key: String {
        "seerr.session.\(userID)"
    }

    private static var legacyAPIKey: String {
        "seerr.apiKey.\(userID)"
    }

    static var session: SeerrSession? {
        Container.shared.keychainService().delete(legacyAPIKey)
        guard let encoded = Container.shared.keychainService().get(key),
              let data = Data(base64Encoded: encoded)
        else { return nil }
        return try? JSONDecoder().decode(SeerrSession.self, from: data)
    }

    @discardableResult
    static func save(session: SeerrSession) -> Bool {
        guard let data = try? JSONEncoder().encode(session) else { return false }
        return Container.shared.keychainService().set(data.base64EncodedString(), forKey: key)
    }

    @discardableResult
    static func clear() -> Bool {
        let keychain = Container.shared.keychainService()
        let didDeleteSession = keychain.delete(key)
        _ = keychain.delete(legacyAPIKey)
        return didDeleteSession
    }
}
