//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

struct SeerrUser: Codable, Hashable {
    let id: Int
    let username: String?
    let email: String?
    let userType: Int?
    let permissions: Int?

    var canRequestMovies: Bool {
        guard let permissions else { return false }
        return permissions & (2 | 32 | 262_144) != 0
    }
}

struct SeerrSession: Codable, Hashable {
    let serverURL: String
    let cookieHeader: String
    let user: SeerrUser
}

struct SeerrQuickConnect: Decodable {
    let code: String
    let secret: String
}

enum SeerrPresentationStatus: Hashable {
    case readyToWatch
    case partiallyReady
    case awaitingApproval
    case lookingForMedia
    case gettingReady
    case requestDeclined
    case unavailable
    case notRequested

    var detailsLabel: String {
        switch self {
        case .readyToWatch: L10n.seerrReadyToWatch
        case .partiallyReady: L10n.seerrPartiallyReady
        case .awaitingApproval: L10n.seerrAwaitingApproval
        case .lookingForMedia: L10n.seerrLookingForMedia
        case .gettingReady: L10n.seerrGettingReady
        case .requestDeclined: L10n.seerrRequestDeclined
        case .unavailable: L10n.seerrStatusUnavailable
        case .notRequested: L10n.seerrNotRequested
        }
    }

    var posterLabel: String? {
        switch self {
        case .unavailable, .notRequested: nil
        default: detailsLabel
        }
    }
}

struct SeerrTitle: Decodable, Identifiable, Hashable {
    struct MediaInfo: Decodable, Hashable {
        struct Request: Decodable, Hashable {
            let status: Int?
        }

        let status: Int?
        let requests: [Request]?

        var presentationStatus: SeerrPresentationStatus {
            let requestStatuses = requests?.compactMap(\.status) ?? []
            if status == 5 {
                return .readyToWatch
            }
            if status == 4 {
                return .partiallyReady
            }
            if requestStatuses.contains(1) {
                return .awaitingApproval
            }

            if requestStatuses.contains(2) {
                switch status {
                case 2: return .lookingForMedia
                case 3: return .gettingReady
                default: return .unavailable
                }
            }

            if !requestStatuses.isEmpty, requestStatuses.allSatisfy({ $0 == 3 }) {
                return .requestDeclined
            }

            return .unavailable
        }
    }

    let id: Int
    let mediaType: String?
    let title: String?
    let name: String?
    let posterPath: String?
    let mediaInfo: MediaInfo?

    var displayTitle: String {
        title ?? name ?? L10n.seerrUntitled
    }

    var posterURL: URL? {
        guard let posterPath else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/w500\(posterPath)")
    }

    var presentationStatus: SeerrPresentationStatus {
        mediaInfo?.presentationStatus ?? .notRequested
    }

    func replacingMediaInfo(_ mediaInfo: MediaInfo?) -> SeerrTitle {
        SeerrTitle(
            id: id,
            mediaType: mediaType,
            title: title,
            name: name,
            posterPath: posterPath,
            mediaInfo: mediaInfo
        )
    }
}

struct SeerrTitleDetails: Decodable, Hashable {
    let title: String?
    let name: String?
    let overview: String?
    let posterPath: String?
    let backdropPath: String?
    let releaseDate: String?
    let firstAirDate: String?
    let mediaInfo: SeerrTitle.MediaInfo?

    var presentationStatus: SeerrPresentationStatus {
        mediaInfo?.presentationStatus ?? .notRequested
    }

    var displayTitle: String {
        title ?? name ?? L10n.seerrUntitled
    }

    var releaseYear: String? {
        let date = releaseDate ?? firstAirDate
        guard let year = date?.prefix(4), year.count == 4, year.allSatisfy(\.isNumber) else { return nil }
        return String(year)
    }

    var posterURL: URL? {
        Self.imageURL(for: posterPath, width: "w500")
    }

    var backdropURL: URL? {
        Self.imageURL(for: backdropPath, width: "w1280")
    }

    private static func imageURL(for path: String?, width: String) -> URL? {
        guard let path else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/\(width)\(path)")
    }
}

struct SeerrCreatedRequest: Decodable {
    let id: Int
    let status: Int
    let media: SeerrTitle.MediaInfo?

    var presentationStatus: SeerrPresentationStatus {
        SeerrTitle.MediaInfo(
            status: media?.status,
            requests: [.init(status: status)]
        ).presentationStatus
    }
}

struct SeerrRequestKey: Hashable {
    let serverURL: String
    let userID: Int
    let mediaID: Int

    init(session: SeerrSession, mediaID: Int) {
        serverURL = session.serverURL
        userID = session.user.id
        self.mediaID = mediaID
    }
}

struct SeerrRequestUpdate {
    let key: SeerrRequestKey
    let status: SeerrPresentationStatus
    var refreshDiscovery = true
}

extension Notification.Name {
    static let seerrRequestsChanged = Notification.Name("seerrRequestsChanged")
}

private struct SeerrPage: Decodable {
    let page: Int
    let totalPages: Int
    let results: [SeerrTitle]
}

struct SeerrTrendingPage {
    let page: Int
    let totalPages: Int
    let results: [SeerrTitle]
}

struct SeerrListedRequest: Decodable {
    struct Media: Decodable {
        let tmdbId: Int
        let status: Int?
    }

    let type: String
    let status: Int
    let is4k: Bool?
    let media: Media
}

private struct SeerrRequestPage: Decodable {
    struct PageInfo: Decodable {
        let pages: Int
    }

    let pageInfo: PageInfo
    let results: [SeerrListedRequest]
}

private struct SeerrQuickConnectStatus: Decodable {
    let authenticated: Bool
}

enum SeerrClientError: LocalizedError {
    case invalidURL
    case quickConnectUnavailable
    case unauthorized
    case accessDenied
    case quickConnectExpired
    case missingSessionCookie
    case sessionStorage
    case identityChanged
    case serverChanged
    case network
    case server(status: Int)
    case invalidResponse
    case requestRestricted
    case requestBlocked
    case requestQuotaReached
    case requestDuplicate
    case requestStateChanged

    var errorDescription: String? {
        switch self {
        case .invalidURL: L10n.seerrInvalidURL
        case .quickConnectUnavailable: L10n.seerrQuickConnectUnavailable
        case .unauthorized: L10n.seerrSessionInvalid
        case .accessDenied: L10n.seerrPermissionDenied
        case .quickConnectExpired: L10n.seerrExpired
        case .missingSessionCookie: L10n.seerrMissingSession
        case .sessionStorage: L10n.seerrSessionStorageError
        case .identityChanged: L10n.seerrIdentityChanged
        case .serverChanged: L10n.seerrServerChanged
        case .network: L10n.seerrNetworkError
        case let .server(status): L10n.seerrServerError(status)
        case .invalidResponse: L10n.seerrInvalidResponse
        case .requestRestricted: L10n.seerrRequestRestricted
        case .requestBlocked: L10n.seerrRequestBlocked
        case .requestQuotaReached: L10n.seerrRequestQuotaReached
        case .requestDuplicate: L10n.seerrRequestDuplicate
        case .requestStateChanged: L10n.seerrRequestStateChanged
        }
    }

    var requestPresentationDescription: String {
        switch self {
        case .invalidURL: L10n.seerrRequestServerAddressInvalid
        case .unauthorized: L10n.seerrRequestSessionExpired
        case .accessDenied: L10n.seerrRequestNoPermission
        case .identityChanged: L10n.seerrRequestAccountChanged
        case .serverChanged: L10n.seerrRequestServerChanged
        case .network: L10n.seerrRequestNetworkError
        case let .server(status): L10n.seerrRequestServerError(status)
        case .invalidResponse: L10n.seerrRequestInvalidResponse
        default: localizedDescription
        }
    }

    static func requestPresentationDescription(for error: Error) -> String {
        (error as? SeerrClientError)?.requestPresentationDescription ?? error.localizedDescription
    }
}

struct SeerrClient {
    let baseURL: URL

    init(url: String) throws {
        guard let parsed = URL(string: url.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = parsed.scheme?.lowercased(), ["http", "https"].contains(scheme),
              parsed.host != nil,
              parsed.user == nil,
              parsed.password == nil,
              parsed.query == nil,
              parsed.fragment == nil
        else { throw SeerrClientError.invalidURL }
        guard var components = URLComponents(url: parsed, resolvingAgainstBaseURL: false) else {
            throw SeerrClientError.invalidURL
        }
        if !components.path.hasSuffix("/") {
            components.path.append("/")
        }
        guard let normalizedURL = components.url else { throw SeerrClientError.invalidURL }
        baseURL = normalizedURL
    }

    func initiateQuickConnect() async throws -> SeerrQuickConnect {
        do {
            return try await send(path: "api/v1/auth/jellyfin/quickconnect/initiate", method: "POST")
        } catch let SeerrClientError.server(status) where status == 404 || status == 405 {
            throw SeerrClientError.quickConnectUnavailable
        }
    }

    func checkQuickConnect(secret: String) async throws -> Bool {
        var components = URLComponents()
        components.queryItems = [URLQueryItem(name: "secret", value: secret)]
        let query = components.percentEncodedQuery.map { "?\($0)" } ?? ""
        let status: SeerrQuickConnectStatus = try await send(
            path: "api/v1/auth/jellyfin/quickconnect/check\(query)",
            method: "GET",
            expiredOnNotFound: true
        )
        return status.authenticated
    }

    func authenticate(secret: String) async throws -> SeerrSession {
        let (data, response) = try await sendRaw(
            path: "api/v1/auth/jellyfin/quickconnect/authenticate",
            method: "POST",
            body: JSONEncoder().encode(SecretBody(secret: secret))
        )
        let user = try JSONDecoder().decode(SeerrUser.self, from: data)
        guard let responseURL = response.url,
              let cookieHeader = Self.sessionCookieHeader(in: response, for: responseURL)
        else { throw SeerrClientError.missingSessionCookie }
        return SeerrSession(serverURL: baseURL.absoluteString, cookieHeader: cookieHeader, user: user)
    }

    func testConnection(session: SeerrSession) async throws -> SeerrUser {
        try await send(path: "api/v1/auth/me", method: "GET", session: session)
    }

    func trending(type: String, page pageNumber: Int = 1, session: SeerrSession) async throws -> SeerrTrendingPage {
        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "mediaType", value: type),
            URLQueryItem(name: "timeWindow", value: "week"),
            URLQueryItem(name: "page", value: String(pageNumber)),
        ]
        let query = components.percentEncodedQuery.map { "?\($0)" } ?? ""
        let page: SeerrPage = try await send(
            path: "api/v1/discover/trending\(query)",
            method: "GET",
            session: session
        )
        return SeerrTrendingPage(
            page: page.page,
            totalPages: page.totalPages,
            results: page.results.filter { $0.mediaType == nil || $0.mediaType == type }
        )
    }

    func discover(
        type: String,
        sortBy: String? = nil,
        upcoming: Bool = false,
        page pageNumber: Int = 1,
        session: SeerrSession
    ) async throws -> SeerrTrendingPage {
        var components = URLComponents()
        components.queryItems = [URLQueryItem(name: "page", value: String(pageNumber))]
        if let sortBy {
            components.queryItems?.append(URLQueryItem(name: "sortBy", value: sortBy))
        }
        let query = components.percentEncodedQuery.map { "?\($0)" } ?? ""
        let path: String
        if upcoming {
            path = "api/v1/discover/movies/upcoming\(query)"
        } else {
            let mediaPath = type == "tv" ? "tv" : "movies"
            path = "api/v1/discover/\(mediaPath)\(query)"
        }
        let page: SeerrPage = try await send(path: path, method: "GET", session: session)
        return SeerrTrendingPage(
            page: page.page,
            totalPages: page.totalPages,
            results: page.results.filter { $0.mediaType == nil || $0.mediaType == type }
        )
    }

    func requests(session: SeerrSession) async throws -> [SeerrListedRequest] {
        let pageSize = 100
        var skip = 0
        var requests: [SeerrListedRequest] = []
        while true {
            try Task.checkCancellation()
            let page: SeerrRequestPage = try await send(
                path: "api/v1/request?take=\(pageSize)&skip=\(skip)",
                method: "GET",
                session: session
            )
            requests.append(contentsOf: page.results)
            skip += pageSize
            if page.results.isEmpty || skip / pageSize >= page.pageInfo.pages {
                return requests
            }
        }
    }

    func details(for title: SeerrTitle, isShow: Bool, session: SeerrSession) async throws -> SeerrTitleDetails {
        let mediaPath = isShow ? "tv" : "movie"
        return try await send(
            path: "api/v1/\(mediaPath)/\(title.id)",
            method: "GET",
            session: session
        )
    }

    func requestMovie(id: Int, session: SeerrSession) async throws -> SeerrCreatedRequest {
        let (data, response) = try await sendRaw(
            path: "api/v1/request",
            method: "POST",
            body: JSONEncoder().encode(MovieRequestBody(mediaId: id)),
            session: session,
            isMovieRequest: true
        )
        guard response.statusCode == 201,
              let created = try? JSONDecoder().decode(SeerrCreatedRequest.self, from: data),
              created.id > 0
        else { throw SeerrClientError.invalidResponse }
        return created
    }

    func disconnect(session: SeerrSession) async {
        guard session.serverURL == baseURL.absoluteString else { return }
        _ = try? await sendRaw(path: "api/v1/auth/logout", method: "POST", session: session)
    }

    private func send<Response: Decodable>(
        path: String,
        method: String,
        body: Data? = nil,
        session: SeerrSession? = nil,
        expiredOnNotFound: Bool = false
    ) async throws -> Response {
        let (data, _) = try await sendRaw(
            path: path,
            method: method,
            body: body,
            session: session,
            expiredOnNotFound: expiredOnNotFound
        )
        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw SeerrClientError.invalidResponse
        }
    }

    private func sendRaw(
        path: String,
        method: String,
        body: Data? = nil,
        session: SeerrSession? = nil,
        expiredOnNotFound: Bool = false,
        isMovieRequest: Bool = false
    ) async throws -> (Data, HTTPURLResponse) {
        if let session, session.serverURL != baseURL.absoluteString {
            throw SeerrClientError.serverChanged
        }
        guard let url = URL(string: path, relativeTo: baseURL)?.absoluteURL else {
            throw SeerrClientError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.httpShouldHandleCookies = false
        request.timeoutInterval = 20
        if body != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        var cookieHeader = session?.cookieHeader
        if method == "POST" {
            let csrf = try await csrfContext(session: session)
            cookieHeader = Self.mergingCookies(session?.cookieHeader, csrf.cookieHeader)
            if let token = csrf.token {
                request.setValue(token, forHTTPHeaderField: "X-XSRF-TOKEN")
                request.setValue(token, forHTTPHeaderField: "X-CSRF-Token")
            }
            if let origin = Self.origin(of: baseURL) {
                request.setValue(origin, forHTTPHeaderField: "Origin")
                request.setValue(baseURL.absoluteString, forHTTPHeaderField: "Referer")
            }
        }
        if let cookieHeader {
            request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw SeerrClientError.network
        }
        guard let response = response as? HTTPURLResponse else {
            throw SeerrClientError.invalidResponse
        }
        switch response.statusCode {
        case 200 ... 299:
            return (data, response)
        case 401:
            throw SeerrClientError.unauthorized
        case 403:
            if isMovieRequest {
                let message = (try? JSONDecoder().decode(SeerrErrorResponse.self, from: data))?.message ?? ""
                if message.localizedCaseInsensitiveContains("quota") {
                    throw SeerrClientError.requestQuotaReached
                }
                if message.localizedCaseInsensitiveContains("blocklisted") {
                    throw SeerrClientError.requestBlocked
                }
                throw SeerrClientError.requestRestricted
            }
            throw SeerrClientError.accessDenied
        case 409 where isMovieRequest:
            throw SeerrClientError.requestDuplicate
        case 404 where expiredOnNotFound:
            throw SeerrClientError.quickConnectExpired
        default:
            throw SeerrClientError.server(status: response.statusCode)
        }
    }

    private static func sessionCookieHeader(in response: HTTPURLResponse, for url: URL) -> String? {
        let headers = response.allHeaderFields.reduce(into: [String: String]()) { result, entry in
            result[String(describing: entry.key)] = String(describing: entry.value)
        }
        guard let cookie = HTTPCookie.cookies(withResponseHeaderFields: headers, for: url)
            .first(where: { $0.name == "connect.sid" })
        else { return nil }
        return HTTPCookie.requestHeaderFields(with: [cookie])["Cookie"]
    }

    private func csrfContext(session: SeerrSession?) async throws -> (token: String?, cookieHeader: String?) {
        guard let url = URL(string: "api/v1/settings/public", relativeTo: baseURL) else {
            throw SeerrClientError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.httpShouldHandleCookies = false
        request.timeoutInterval = 20
        if let session {
            request.setValue(session.cookieHeader, forHTTPHeaderField: "Cookie")
        }

        let response: URLResponse
        do {
            (_, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw SeerrClientError.network
        }
        guard let response = response as? HTTPURLResponse else {
            throw SeerrClientError.invalidResponse
        }
        guard (200 ... 299).contains(response.statusCode) else {
            throw SeerrClientError.server(status: response.statusCode)
        }
        let headers = response.allHeaderFields.reduce(into: [String: String]()) { result, entry in
            result[String(describing: entry.key)] = String(describing: entry.value)
        }
        let cookies = HTTPCookie.cookies(withResponseHeaderFields: headers, for: url)
            .filter { !$0.isSecure || baseURL.scheme == "https" }
        let tokenCookie = cookies.first(where: { $0.name == "XSRF-TOKEN" }) ??
            cookies.first(where: { $0.name == "_csrf" })
        let token = tokenCookie?.value.removingPercentEncoding ?? tokenCookie?.value
        let cookieHeader = HTTPCookie.requestHeaderFields(with: cookies)["Cookie"]
        return (token, cookieHeader)
    }

    private static func mergingCookies(_ current: String?, _ updated: String?) -> String? {
        guard let updated, !updated.isEmpty else { return current }
        guard let current, !current.isEmpty else { return updated }
        let updatedNames = Set(updated.split(separator: ";").compactMap { pair -> String? in
            guard let separator = pair.firstIndex(of: "=") else { return nil }
            return String(pair[..<separator]).trimmingCharacters(in: .whitespaces)
        })
        let retained = current.split(separator: ";").map(String.init).filter { pair in
            guard let separator = pair.firstIndex(of: "=") else { return false }
            let name = pair[..<separator].trimmingCharacters(in: .whitespaces)
            return !updatedNames.contains(String(name))
        }
        return (retained + updated.split(separator: ";").map(String.init))
            .joined(separator: "; ")
    }

    private static func origin(of url: URL) -> String? {
        guard let scheme = url.scheme, let host = url.host else { return nil }
        let port = url.port.map { ":\($0)" } ?? ""
        return "\(scheme)://\(host)\(port)"
    }
}

private struct SecretBody: Encodable {
    let secret: String
}

private struct MovieRequestBody: Encodable {
    let mediaType = "movie"
    let mediaId: Int
}

private struct SeerrErrorResponse: Decodable {
    let message: String?
}
