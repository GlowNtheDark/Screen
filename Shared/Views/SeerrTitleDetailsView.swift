//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

struct SeerrTitleDetailsView: View {
    private enum FocusTarget: Hashable {
        case title
        case availability
        case requestMovie
        case retry
        case loading
    }

    let title: SeerrTitle
    let isShow: Bool

    @Environment(\.screenTheme)
    private var screenTheme

    @FocusState
    private var focusedTarget: FocusTarget?

    @State
    private var details: SeerrTitleDetails?
    @State
    private var error: String?
    @State
    private var isLoading = true
    @State
    private var requestUser: SeerrUser?
    @State
    private var loadedSession: SeerrSession?
    @State
    private var isConfirmingRequest = false
    @State
    private var isSubmittingRequest = false
    @State
    private var requestStatusOverride: SeerrPresentationStatus?
    @State
    private var requestMessage: String?

    private let posterWidth: CGFloat = 280
    private let backdropHeight: CGFloat = 470

    private var artwork: SeerrPoster {
        SeerrPoster(
            id: "details-\(isShow ? "tv" : "movie")-\(title.id)",
            displayTitle: displayTitle,
            posterURL: details?.posterURL ?? title.posterURL,
            backdropURL: details?.backdropURL
        )
    }

    private var displayTitle: String {
        details?.title ?? details?.name ?? title.displayTitle
    }

    private var presentationStatus: SeerrPresentationStatus? {
        if let requestStatusOverride {
            return requestStatusOverride
        }
        if let details {
            return details.presentationStatus
        }
        guard title.mediaInfo != nil else { return nil }
        return title.presentationStatus
    }

    var body: some View {
        ZStack {
            screenTheme.surfaces.canvas.swiftUIColor
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 42) {
                    if details?.backdropURL != nil {
                        PosterImage(item: artwork, type: .landscape, size: .medium)
                            .frame(maxWidth: .infinity)
                            .frame(height: backdropHeight)
                            .clipped()
                    }

                    HStack(alignment: .top, spacing: 48) {
                        PosterImage(item: artwork, type: .portrait, size: .medium)
                            .frame(width: posterWidth, height: posterWidth * 1.5)
                            .clipShape(RoundedRectangle(cornerRadius: posterWidth * 0.0375))

                        VStack(alignment: .leading, spacing: 24) {
                            Text(displayTitle)
                                .font(.largeTitle.bold())
                                .foregroundStyle(.primary)
                                .lineLimit(2)
                                .focusable(details != nil)
                                .focused($focusedTarget, equals: .title)

                            HStack(spacing: 18) {
                                Text(isShow ? L10n.tvShowsCapitalized : L10n.movie)
                                if let releaseYear = details?.releaseYear {
                                    Text(releaseYear)
                                }
                            }
                            .font(.title3)
                            .foregroundStyle(.secondary)

                            if let details, canRequestMovie(details) {
                                Button {
                                    isConfirmingRequest = true
                                } label: {
                                    Label(
                                        isSubmittingRequest ? L10n.seerrRequestSending : L10n.seerrRequestMovie,
                                        systemImage: "plus"
                                    )
                                    .font(.headline)
                                    .foregroundStyle(screenTheme.actions.primaryForeground.swiftUIColor)
                                    .padding(.horizontal, 30)
                                    .padding(.vertical, 18)
                                    .background(screenTheme.actions.primaryFill.swiftUIColor)
                                }
                                #if os(tvOS)
                                .buttonStyle(BasicHoverButtonStyle(scalesOnInteraction: false))
                                #else
                                .buttonStyle(BasicHoverButtonStyle())
                                #endif
                                .disabled(isSubmittingRequest)
                                .focused($focusedTarget, equals: .requestMovie)
                            }

                            if let overview = details?.overview, !overview.isEmpty {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text(L10n.overview)
                                        .font(.title3.weight(.semibold))
                                        .foregroundStyle(.primary)
                                    Text(overview)
                                        .font(.body)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }

                            if let presentationStatus {
                                availabilityView(for: presentationStatus, isFresh: details != nil)
                            }

                            if details == nil {
                                if isLoading {
                                    ProgressView(L10n.seerrDetailsLoading)
                                        .frame(maxWidth: .infinity, minHeight: 160, alignment: .leading)
                                        .focusable()
                                        .focused($focusedTarget, equals: .loading)
                                } else {
                                    ContentUnavailableView(
                                        L10n.seerrDetailsLoadError,
                                        systemImage: "wifi.exclamationmark",
                                        description: Text(error ?? L10n.seerrRequestNetworkError)
                                    )
                                    Button(L10n.retry) {
                                        focusedTarget = .loading
                                        Task { await loadDetails() }
                                    }
                                    .focused($focusedTarget, equals: .retry)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 12)
                    }
                    .padding(.horizontal, EdgeInsets.edgePadding)
                }
                .padding(.bottom, EdgeInsets.edgePadding)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle(displayTitle)
        .toolbar(.hidden, for: .navigationBar)
        .focusSection()
        .defaultFocus($focusedTarget, initialFocusTarget, priority: .userInitiated)
        .onChange(of: details) { oldDetails, newDetails in
            if oldDetails == nil, let newDetails {
                guard focusedTarget == nil || focusedTarget == .loading else { return }
                focusedTarget = canRequestMovie(newDetails) ? .requestMovie : .availability
            }
        }
        .alert(L10n.seerrRequestConfirmTitle, isPresented: $isConfirmingRequest) {
            Button(L10n.seerrRequestMovie) {
                Task { await submitMovieRequest() }
            }
            Button(L10n.cancel, role: .cancel) {}
        } message: {
            Text(L10n.seerrRequestConfirmMessage(displayTitle))
        }
        .task { await loadDetails() }
    }

    private var initialFocusTarget: FocusTarget {
        if let details {
            canRequestMovie(details) ? .requestMovie : .availability
        } else if isLoading {
            .loading
        } else {
            .retry
        }
    }

    private func availabilityView(for status: SeerrPresentationStatus, isFresh: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.seerrAvailability)
                .font(.headline)
                .foregroundStyle(.primary)
            Text(status.detailsLabel)
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)
            if status == .gettingReady {
                Text(L10n.seerrGettingReadyDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let requestMessage {
                Text(requestMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if isFresh, isShow {
                Text(L10n.seerrRequestPhaseUnavailable)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if isFresh, status == .notRequested, let requestUser {
                if requestUser.permissions == nil {
                    Text(L10n.seerrRequestPermissionsUnavailable)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if !requestUser.canRequestMovies {
                    Text(L10n.seerrRequestNoPermission)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(screenTheme.surfaces.elevated.swiftUIColor)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .focusable(isFresh)
        .focused($focusedTarget, equals: .availability)
    }

    private func canRequestMovie(_ details: SeerrTitleDetails) -> Bool {
        !isShow && details.presentationStatus == .notRequested && requestStatusOverride == nil
            && requestUser?.canRequestMovies == true && loadedSession != nil
    }

    @MainActor
    private func loadDetails() async {
        guard let session = SeerrKeychain.session else {
            error = L10n.seerrSessionInvalid
            isLoading = false
            focusedTarget = .retry
            return
        }

        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            let client = try SeerrClient(url: session.serverURL)
            let loadedDetails = try await client.details(for: title, isShow: isShow, session: session)
            if !isShow {
                do {
                    let user = try await client.testConnection(session: session)
                    guard user.id == session.user.id else { throw SeerrClientError.identityChanged }
                    requestUser = user
                    loadedSession = session
                } catch {
                    requestMessage = SeerrClientError.requestPresentationDescription(for: error)
                }
            }
            details = loadedDetails
        } catch {
            if details == nil {
                self.error = SeerrClientError.requestPresentationDescription(for: error)
                focusedTarget = .retry
            } else {
                requestMessage = SeerrClientError.requestPresentationDescription(for: error)
            }
        }
    }

    @MainActor
    private func submitMovieRequest() async {
        guard !isSubmittingRequest, let details, canRequestMovie(details) else { return }
        guard let session = SeerrKeychain.session, let loadedSession,
              session.serverURL == loadedSession.serverURL,
              session.cookieHeader == loadedSession.cookieHeader,
              session.user.id == loadedSession.user.id
        else {
            requestUser = nil
            requestMessage = L10n.seerrSessionInvalid
            focusedTarget = .availability
            return
        }
        guard let configuredURL = UserDefaults.currentUserSuite.string(forKey: "seerr.serverURL"),
              let configuredClient = try? SeerrClient(url: configuredURL),
              configuredClient.baseURL.absoluteString == session.serverURL
        else {
            requestUser = nil
            requestMessage = L10n.seerrServerChanged
            focusedTarget = .availability
            return
        }

        isSubmittingRequest = true
        requestMessage = nil
        defer { isSubmittingRequest = false }
        var submissionStarted = false

        do {
            let client = try SeerrClient(url: session.serverURL)
            let user = try await client.testConnection(session: session)
            guard user.id == session.user.id else { throw SeerrClientError.identityChanged }
            requestUser = user
            guard user.canRequestMovies else { throw SeerrClientError.requestRestricted }
            let latest = try await client.details(for: title, isShow: false, session: session)
            self.details = latest
            guard latest.presentationStatus == .notRequested else {
                NotificationCenter.default.post(name: .seerrRequestsChanged, object: nil)
                throw SeerrClientError.requestStateChanged
            }

            submissionStarted = true
            let created = try await client.requestMovie(id: title.id, session: session)
            requestStatusOverride = created.presentationStatus
            requestMessage = L10n.seerrRequestSent
            focusedTarget = .availability
            NotificationCenter.default.post(
                name: .seerrRequestsChanged,
                object: SeerrRequestUpdate(key: SeerrRequestKey(session: session, mediaID: title.id), status: created.presentationStatus)
            )

            do {
                let refreshed = try await client.details(for: title, isShow: false, session: session)
                self.details = refreshed
                if refreshed.presentationStatus != .notRequested, refreshed.presentationStatus != .unavailable {
                    requestStatusOverride = refreshed.presentationStatus
                    NotificationCenter.default.post(
                        name: .seerrRequestsChanged,
                        object: SeerrRequestUpdate(
                            key: SeerrRequestKey(session: session, mediaID: title.id),
                            status: refreshed.presentationStatus,
                            refreshDiscovery: false
                        )
                    )
                }
            } catch {
                requestMessage = L10n.seerrRequestRefreshFailed
            }
        } catch {
            requestMessage = SeerrClientError.requestPresentationDescription(for: error)
            if let clientError = error as? SeerrClientError {
                switch clientError {
                case .unauthorized, .identityChanged, .serverChanged:
                    requestUser = nil
                default:
                    break
                }
            }
            if submissionStarted {
                let definiteRejection: Bool = if let clientError = error as? SeerrClientError {
                    switch clientError {
                    case .requestQuotaReached, .requestRestricted, .requestBlocked, .unauthorized:
                        true
                    default:
                        false
                    }
                } else {
                    false
                }
                if !definiteRejection {
                    requestStatusOverride = .unavailable
                    if let clientError = error as? SeerrClientError, case .requestDuplicate = clientError {
                        requestMessage = L10n.seerrRequestDuplicate
                    } else {
                        requestMessage = L10n.seerrRequestOutcomeUnknown
                    }
                    NotificationCenter.default.post(name: .seerrRequestsChanged, object: nil)
                    if let client = try? SeerrClient(url: session.serverURL),
                       let refreshed = try? await client.details(for: title, isShow: false, session: session)
                    {
                        self.details = refreshed
                        if refreshed.presentationStatus != .notRequested, refreshed.presentationStatus != .unavailable {
                            requestStatusOverride = refreshed.presentationStatus
                            NotificationCenter.default.post(
                                name: .seerrRequestsChanged,
                                object: SeerrRequestUpdate(
                                    key: SeerrRequestKey(session: session, mediaID: title.id),
                                    status: refreshed.presentationStatus,
                                    refreshDiscovery: false
                                )
                            )
                        }
                    }
                }
            }
            if requestUser?.canRequestMovies != true || requestStatusOverride != nil ||
                self.details?.presentationStatus != .notRequested
            {
                focusedTarget = .availability
            }
        }
    }
}
