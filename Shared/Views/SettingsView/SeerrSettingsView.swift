//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

struct SeerrSettingsView: View {
    @Environment(\.screenTheme)
    private var screenTheme

    @State
    private var serverProtocol: SeerrProtocol = .http
    @State
    private var serverAddress = ""
    @State
    private var didLoadConfiguration = false
    @State
    private var session: SeerrSession?
    @State
    private var quickConnectCode: String?
    @State
    private var pollTask: Task<Void, Never>?
    @State
    private var message: String?
    @State
    private var isConnecting = false
    @State
    private var isTesting = false

    private var serverURL: String {
        let configuration: (transport: SeerrProtocol, address: String)
        if serverAddress.contains("://") {
            guard let parsed = try? SeerrServerAddress.split(fullURL: serverAddress) else { return "" }
            configuration = parsed
        } else {
            configuration = (serverProtocol, serverAddress)
        }
        guard let url = try? SeerrServerAddress.makeURL(
            protocol: configuration.transport,
            address: configuration.address
        ) else {
            return ""
        }
        return url.absoluteString
    }

    private var isConfigured: Bool {
        !serverURL.isEmpty
    }

    private var validationMessage: String? {
        guard !serverAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        do {
            if serverAddress.contains("://") {
                _ = try SeerrServerAddress.split(fullURL: serverAddress)
            } else {
                _ = try SeerrServerAddress.makeURL(protocol: serverProtocol, address: serverAddress)
            }
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    private var connectedUsername: String {
        session?.user.username ?? session?.user.email ?? L10n.seerrConnected
    }

    var body: some View {
        Form {
            Section {
                Picker(L10n.seerrProtocol, selection: $serverProtocol) {
                    Text(L10n.seerrHTTP).tag(SeerrProtocol.http)
                    Text(L10n.seerrHTTPS).tag(SeerrProtocol.https)
                }
                .onChange(of: serverProtocol) { _, _ in
                    saveConfiguration()
                }

                TextField(L10n.seerrAddress, text: $serverAddress, prompt: Text(L10n.seerrAddressPlaceholder))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onChange(of: serverAddress) { _, value in
                        handleAddressChange(value)
                    }

                if let validationMessage {
                    Text(validationMessage).foregroundStyle(.secondary)
                }
                Text(L10n.seerrAddressHelp).foregroundStyle(.secondary)

                if let session {
                    LabeledContent(L10n.seerrConnectedAccount, value: connectedUsername)
                    if let permissions = session.user.permissions {
                        LabeledContent(L10n.seerrPermissions, value: String(permissions))
                    }
                    Button(L10n.seerrTestConnection) {
                        Task { await testConnection() }
                    }
                    .disabled(isTesting || !isConfigured)
                    Button(L10n.seerrDisconnect, role: .destructive) {
                        Task { await disconnect() }
                    }
                    Button(L10n.seerrReconnect) {
                        Task { await disconnect()
                            await startQuickConnect()
                        }
                    }
                    .disabled(isConnecting || !isConfigured)
                } else if quickConnectCode == nil {
                    Button(L10n.seerrConnect) {
                        Task { await startQuickConnect() }
                    }
                    .disabled(isConnecting || !isConfigured)
                }

                if isConnecting && quickConnectCode == nil {
                    ProgressView(L10n.seerrConnecting)
                }

                if let quickConnectCode {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(L10n.seerrQuickConnectInstructions)
                            .font(.headline)
                            .foregroundStyle(screenTheme.foregrounds.primary.swiftUIColor)
                        Text(L10n.seerrQuickConnectSteps)
                            .foregroundStyle(screenTheme.foregrounds.secondary.swiftUIColor)
                        Text(quickConnectCode)
                            .font(.system(size: 54, weight: .bold, design: .rounded).monospacedDigit())
                            .foregroundStyle(screenTheme.foregrounds.primary.swiftUIColor)
                            .accessibilityLabel(L10n.seerrQuickConnectCode)
                        HStack {
                            ProgressView()
                                .tint(screenTheme.actions.primaryFill.swiftUIColor)
                            Text(L10n.seerrWaitingForAuthorization)
                                .foregroundStyle(screenTheme.foregrounds.secondary.swiftUIColor)
                        }
                        Button(L10n.seerrCancel) {
                            cancelQuickConnect(message: L10n.seerrCancelled)
                        }
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 24)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        screenTheme.surfaces.elevated.swiftUIColor,
                        in: RoundedRectangle(cornerRadius: 18)
                    )
                    .listRowBackground(screenTheme.surfaces.canvas.swiftUIColor)
                }

                if isTesting {
                    ProgressView()
                }
                if let message {
                    Text(message).foregroundStyle(.secondary)
                }
            } header: {
                Text(L10n.seerr)
            } footer: {
                Text(L10n.seerrQuickConnectSecurityNote)
            }
        }
        .navigationTitle(L10n.seerr)
        .onAppear {
            loadConfiguration()
            session = SeerrKeychain.session
        }
        .onDisappear {
            cancelQuickConnect(message: nil)
        }
    }

    @MainActor
    private func startQuickConnect() async {
        message = nil
        isConnecting = true
        defer { isConnecting = false }

        do {
            let client = try SeerrClient(url: serverURL)
            let challenge = try await client.initiateQuickConnect()
            quickConnectCode = challenge.code
            pollTask?.cancel()
            pollTask = Task { @MainActor in
                await pollAuthorization(secret: challenge.secret, client: client)
            }
        } catch {
            message = error.localizedDescription
        }
    }

    @MainActor
    private func loadConfiguration() {
        let defaults = UserDefaults.currentUserSuite
        if defaults.object(forKey: "seerr.address") != nil {
            serverProtocol = SeerrProtocol(rawValue: defaults.string(forKey: "seerr.protocol") ?? "") ?? .http
            serverAddress = defaults.string(forKey: "seerr.address") ?? ""
        } else if let savedURL = defaults.string(forKey: "seerr.serverURL"), !savedURL.isEmpty {
            if let configuration = try? SeerrServerAddress.parseSavedValue(savedURL) {
                serverProtocol = configuration.transport
                serverAddress = configuration.address
            } else {
                serverProtocol = .http
                serverAddress = savedURL
            }
        } else {
            serverProtocol = .http
            serverAddress = ""
        }
        didLoadConfiguration = true
        saveConfiguration()
    }

    @MainActor
    private func handleAddressChange(_ value: String) {
        guard didLoadConfiguration else { return }
        if value.contains("://"), let configuration = try? SeerrServerAddress.split(fullURL: value) {
            serverProtocol = configuration.transport
            serverAddress = configuration.address
        }
        saveConfiguration()
        message = nil
    }

    @MainActor
    private func saveConfiguration() {
        guard didLoadConfiguration else { return }
        let defaults = UserDefaults.currentUserSuite
        defaults.set(serverProtocol.rawValue, forKey: "seerr.protocol")
        defaults.set(serverAddress.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "seerr.address")
        if !serverURL.isEmpty {
            defaults.set(serverURL, forKey: "seerr.serverURL")
        }
    }

    @MainActor
    private func pollAuthorization(secret: String, client: SeerrClient) async {
        while !Task.isCancelled {
            do {
                try await Task.sleep(nanoseconds: 3_000_000_000)
                guard try await client.checkQuickConnect(secret: secret) else { continue }

                message = L10n.seerrAuthenticating
                let newSession = try await client.authenticate(secret: secret)
                guard SeerrKeychain.save(session: newSession) else {
                    throw SeerrClientError.sessionStorage
                }
                session = newSession
                quickConnectCode = nil
                pollTask = nil
                message = L10n.seerrConnectedAs(connectedUsername)
                return
            } catch is CancellationError {
                return
            } catch SeerrClientError.quickConnectExpired {
                cancelQuickConnect(message: L10n.seerrExpired)
                return
            } catch let error as SeerrClientError {
                guard !Task.isCancelled else { return }
                if case .network = error {
                    message = error.localizedDescription
                    do {
                        try await Task.sleep(nanoseconds: 5_000_000_000)
                    } catch {
                        return
                    }
                    continue
                }
                cancelQuickConnect(message: error.localizedDescription)
                return
            } catch {
                guard !Task.isCancelled else { return }
                cancelQuickConnect(message: L10n.seerrNetworkError)
                return
            }
        }
    }

    @MainActor
    private func cancelQuickConnect(message: String?) {
        pollTask?.cancel()
        pollTask = nil
        quickConnectCode = nil
        isConnecting = false
        self.message = message
    }

    @MainActor
    private func testConnection() async {
        guard let session else { return }
        isTesting = true
        defer { isTesting = false }
        do {
            let client = try SeerrClient(url: serverURL)
            let user = try await client.testConnection(session: session)
            guard user.id == session.user.id else {
                throw SeerrClientError.identityChanged
            }
            let refreshedSession = SeerrSession(
                serverURL: session.serverURL,
                cookieHeader: session.cookieHeader,
                user: user
            )
            guard SeerrKeychain.save(session: refreshedSession) else {
                throw SeerrClientError.sessionStorage
            }
            self.session = refreshedSession
            message = L10n.seerrConnectedAs(user.username ?? user.email ?? L10n.seerrConnected)
        } catch {
            message = error.localizedDescription
        }
    }

    @MainActor
    private func disconnect() async {
        pollTask?.cancel()
        if let session, let client = try? SeerrClient(url: serverURL) {
            await client.disconnect(session: session)
        }
        _ = SeerrKeychain.clear()
        session = nil
        quickConnectCode = nil
        message = L10n.seerrDisconnected
    }
}
