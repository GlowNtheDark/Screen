//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import JellyfinAPI
import Pulse

final class UserSession {

    let id = UUID()

    let server: ServerState
    let user: UserState
    let accessToken: String

    lazy var client: JellyfinClient = JellyfinClient(
        configuration: .screenConfiguration(
            url: server.effectiveServerURL,
            accessToken: accessToken
        ),
        sessionConfiguration: .screen,
        sessionDelegate: URLSessionProxyDelegate(logger: NetworkLogger.screen())
    )

    @MainActor
    lazy var serverConnectionManager = ServerConnectionManager()

    @MainActor
    private var storedItemStateStore: ItemStateStore?

    @MainActor
    var itemStateStore: ItemStateStore {
        if let storedItemStateStore {
            return storedItemStateStore
        }

        let store = ItemStateStore(userSessionID: id)
        storedItemStateStore = store
        return store
    }

    lazy var serverSocketManager = ServerSocketManager()

    @MainActor
    private lazy var services: [any UserSessionService] = [
        serverConnectionManager,
        serverSocketManager,
    ]

    init(
        server: ServerState,
        user: UserState,
        accessToken: String
    ) {
        self.server = server
        self.user = user
        self.accessToken = accessToken
    }

    @MainActor
    func willStart() async {
        for service in services {
            await service.willStart(userSession: self)
        }
    }

    @MainActor
    func didStart() {
        for service in services {
            service.didStart(userSession: self)
        }
    }

    @MainActor
    func willStop() {
        storedItemStateStore?.reset()

        for service in services.reversed() {
            service.willStop(userSession: self)
        }
    }
}
