//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Combine
import Defaults
import FactoryKit
import Foundation
import Get
import JellyfinAPI
import KeychainSwift
import Logging

extension Container {

    var userSessionManager: Factory<UserSessionManager> {
        self { UserSessionManager() }
            .singleton
    }

    var currentUserSession: Factory<UserSession?> {
        self { self.userSessionManager().currentSession }
            .cached
    }
}

final class UserSessionManager: ObservableObject {

    enum State: Equatable {
        case initial
        case signedOut
        case signedIn
    }

    enum SignOutReason {
        case backgroundTimeout
        case explicit
    }

    enum AuthenticationError: Error {
        case missingAuthenticationAction
    }

    @Injected(\.keychainService)
    private var keychain: KeychainSwift

    @Published
    private(set) var state: State = .initial

    @Published
    private(set) var currentSession: UserSession?

    @Published
    private(set) var pendingDeepLink: DeepLink?

    let routePublisher = PassthroughSubject<NavigationRoute, Never>()

    var cancellables = Set<AnyCancellable>()

    let logger = Logger.screen()

    private(set) var mediaPlayerManager: MediaPlayerManager?

    @MainActor
    var hasActivePlayback: Bool {
        guard let mediaPlayerManager else { return false }
        return mediaPlayerManager.state != .stopped
    }

    init() {
        setupObservations()
    }

    @MainActor
    func start() async {
        guard state == .initial else { return }

        do {
            if Defaults[.signOutOnClose] {
                Defaults[.lastSignedInUserID] = .signedOut
            }

            let restoredSession = try await resolveStoredSession()
            await updateCurrentSession(with: restoredSession)
        } catch {
            logger.error(
                "Unable to restore launch session",
                metadata: ["error": .string(error.localizedDescription)]
            )

            await updateCurrentSession(with: nil)
        }
    }

    @MainActor
    private func refreshCurrentSession() async {
        do {
            let restoredSession = try await resolveStoredSession()
            await updateCurrentSession(with: restoredSession)
        } catch {
            logger.error(
                "Unable to refresh current user session",
                metadata: ["error": .string(error.localizedDescription)]
            )

            if shouldInvalidateCurrentSession(for: error) {
                await updateCurrentSession(with: nil)
            }
        }
    }

    @MainActor
    func signIn(userID: String, serverID: String? = nil) async throws {
        Defaults[.lastSignedInUserID] = .signedIn(userID: userID)
        let signedInSession: UserSession?
        do {
            signedInSession = try await resolveStoredSession(userID: userID, serverID: serverID)
        } catch {
            if shouldInvalidateCurrentSession(for: error) {
                await updateCurrentSession(with: nil)
            }

            throw error
        }

        await updateCurrentSession(with: signedInSession)

        Task {
            await refreshServerInformationIfNeeded(reason: .explicitSignIn)
        }
    }

    @MainActor
    func signOut(reason: SignOutReason) async {
        guard currentSession != nil else { return }

        Defaults[.lastSignedInUserID] = .signedOut
        await refreshCurrentSession()

        logger.info(
            "Signed out current user",
            metadata: ["reason": .string(String(describing: reason))]
        )
    }

    @MainActor
    private func stopActivePlayback() async {
        await mediaPlayerManager?.stop()
        self.mediaPlayerManager = nil
    }

    @MainActor
    func scheduleServerConnectionResolution() {
        currentSession?.serverConnectionManager.scheduleConnectionResolution()
    }

    @MainActor
    func handleOpenURL(
        _ url: URL,
        authenticationAction: LocalUserAuthenticationAction
    ) async {
        guard let deepLink = DeepLink(url) else { return }

        do {
            let deepLinkSession = try session(for: deepLink)
            let currentSession = currentSession
            let isSameUserSession = currentSession?.server.id == deepLinkSession.server.id && currentSession?.user.id == deepLinkSession
                .user.id

            if !isSameUserSession {
                try await authenticate(
                    user: deepLinkSession.user,
                    authenticationAction: authenticationAction
                )

                if hasActivePlayback {
                    await stopActivePlayback()
                }

                try await signIn(userID: deepLinkSession.user.id)
            }

            pendingDeepLink = deepLink
        } catch {
            logger.error(
                "Failed to process deep link",
                metadata: ["error": .string(error.localizedDescription)]
            )
        }
    }

    @MainActor
    func consumePendingDeepLink() -> DeepLink? {
        defer {
            pendingDeepLink = nil
        }

        return pendingDeepLink
    }

    @MainActor
    func appDidEnterBackground() {
        Defaults[.backgroundTimeStamp] = Date.now
    }

    @MainActor
    func appWillEnterForeground() async {
        await refreshCurrentSession()

        Task {
            await refreshServerInformationIfNeeded(reason: .stale)
        }

        guard currentSession != nil else { return }
        guard Defaults[.signOutOnBackground] else { return }
        guard !hasActivePlayback else { return }

        let backgroundedInterval = Date.now.timeIntervalSince(Defaults[.backgroundTimeStamp])
        if backgroundedInterval > Defaults[.backgroundSignOutInterval] {
            await signOut(reason: .backgroundTimeout)
        }
    }

    private enum ServerInformationRefreshReason {
        case explicitSignIn
        case stale
    }

    private func session(for deepLink: DeepLink) throws -> (server: ServerState, user: UserState) {
        guard let server = StoredValues[.Server.servers].first(where: { $0.id == deepLink.serverID }) else {
            throw DeepLinkError.missingServer(deepLink.serverID)
        }

        guard let user = StoredValues[.User.users].first(where: { $0.id == deepLink.userID && $0.serverID == server.id }) else {
            throw DeepLinkError.missingUser(deepLink.userID)
        }

        return (server, user)
    }

    private func authenticate(
        user: UserState,
        authenticationAction: LocalUserAuthenticationAction
    ) async throws {
        guard user.accessPolicy != .none else { return }

        let evaluatedPolicy = try await authenticationAction(
            policy: user.accessPolicy,
            reason: user.accessPolicy.authenticateReason(user: user)
        )

        guard let pinPolicy = evaluatedPolicy as? PinEvaluatedUserAccessPolicy else { return }

        if let storedPin = keychain.get("\(user.id)-pin") {
            guard pinPolicy.pin == storedPin else {
                throw ErrorMessage(L10n.incorrectPinForUser(user.username))
            }
        }
    }

    @MainActor
    private func refreshServerInformationIfNeeded(reason: ServerInformationRefreshReason) async {
        guard let currentSession else { return }

        switch reason {
        case .explicitSignIn:
            break
        case .stale:
            guard Defaults[.lastServerInformationRefreshDate].isStale(with: .hours(24)) else { return }
        }

        do {
            try await currentSession.server.updateServerInfo()
            try await currentSession.user.updateUserData(server: currentSession.server)

            Defaults[.lastServerInformationRefreshDate] = Date.now
        } catch {
            logger.error(
                "Unable to refresh server and user information",
                metadata: ["error": .string(error.localizedDescription)]
            )
        }
    }

    private func setupObservations() {
        Notifications[.applicationDidEnterBackground]
            .publisher
            .sink { [weak self] in
                Task { @MainActor in
                    self?.appDidEnterBackground()
                }
            }
            .store(in: &cancellables)

        Notifications[.applicationWillEnterForeground]
            .publisher
            .sink { [weak self] in
                Task { @MainActor in
                    await self?.appWillEnterForeground()
                }
            }
            .store(in: &cancellables)

        Container.shared.mediaPlayerManagerPublisher()
            .sink { [weak self] manager in
                Task { @MainActor in
                    self?.mediaPlayerManager = manager
                }
            }
            .store(in: &cancellables)

        observeSocketCommands()
    }

    @MainActor
    private func updateCurrentSession(with newSession: UserSession?) async {
        let previousSession = currentSession

        previousSession?.willStop()
        await newSession?.willStart()

        currentSession = newSession
        Container.shared.currentUserSession.reset()

        if let newSession {
            Defaults[.selectUserLastUsedUserID] = newSession.user.id
            Defaults[.selectUserLastUsedServerID] = newSession.server.id
        }

        if previousSession?.server.id != newSession?.server.id || previousSession?.user.id != newSession?.user.id {
            Container.shared.mediaPlayerManager.reset()
        }

        if newSession == nil {
            #if os(tvOS)
            ScreenTopShelfSnapshotWriter.clear()
            #endif
            state = .signedOut
        } else {
            state = .signedIn
        }

        newSession?.didStart()
    }

    private func resolveStoredSession(
        userID requestedUserID: String? = nil,
        serverID requestedServerID: String? = nil
    ) async throws -> UserSession? {
        let userID: String
        if let requestedUserID {
            userID = requestedUserID
        } else {
            guard case let .signedIn(storedUserID) = Defaults[.lastSignedInUserID] else { return nil }
            userID = storedUserID
        }

        guard let user = StoredValues[.User.users].first(where: {
            $0.id == userID && (requestedServerID == nil || $0.serverID == requestedServerID)
        }) else {
            Defaults[.lastSignedInUserID] = .signedOut
            throw UserSessionError.invalidStoredSession(userID: userID)
        }

        guard let server = StoredValues[.Server.servers].first(where: { $0.id == user.serverID }) else {
            Defaults[.lastSignedInUserID] = .signedOut
            throw UserSessionError.invalidStoredSession(userID: userID)
        }

        guard let accessToken = user.accessToken else {
            Defaults[.lastSignedInUserID] = .signedOut
            logger.warning("Stored session is missing its access token; returning to the signed-out state")
            throw UserSessionError.missingAccessToken(userID: userID)
        }

        let session = UserSession(
            server: server,
            user: user,
            accessToken: accessToken
        )

        do {
            let response = try await session.client.send(Paths.getCurrentUser)
            guard response.value.id == userID else {
                user.accessToken = nil
                Defaults[.lastSignedInUserID] = .signedOut
                logger.warning(
                    "Stored access token resolved to a different user; cleared the credential",
                    metadata: [
                        "userID": .string(userID),
                        "serverID": .string(server.id),
                        "endpoint": .string("/Users/Me"),
                        "status": .string("200"),
                    ]
                )
                throw UserSessionError.rejectedAccessToken(userID: userID)
            }
        } catch {
            guard isUnauthorizedResponse(error) else { throw error }

            user.accessToken = nil
            Defaults[.lastSignedInUserID] = .signedOut
            logger.warning(
                "Server rejected the stored access token; cleared the credential and returned to sign-in",
                metadata: [
                    "userID": .string(userID),
                    "serverID": .string(server.id),
                    "endpoint": .string("/Users/Me"),
                    "status": .string("401"),
                ]
            )
            throw UserSessionError.rejectedAccessToken(userID: userID)
        }

        logger.debug(
            "Validated stored session credentials",
            metadata: [
                "userID": .string(userID),
                "serverID": .string(server.id),
                "endpoint": .string("/Users/Me"),
            ]
        )

        return session
    }

    private func isUnauthorizedResponse(_ error: Error) -> Bool {
        guard let error = error as? APIError else { return false }
        if case .unacceptableStatusCode(401) = error {
            return true
        }
        return false
    }

    private func shouldInvalidateCurrentSession(for error: Error) -> Bool {
        guard let sessionError = error as? UserSessionError else { return false }

        switch sessionError {
        case .invalidStoredSession, .missingAccessToken, .rejectedAccessToken:
            return true
        case .missingCurrentSession:
            return false
        }
    }
}
