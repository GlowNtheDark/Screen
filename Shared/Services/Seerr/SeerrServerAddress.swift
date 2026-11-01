//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Darwin
import Foundation

enum SeerrProtocol: String, CaseIterable, Identifiable {
    case http
    case https

    var id: String {
        rawValue
    }
}

enum SeerrAddressError: LocalizedError {
    case addressRequired
    case invalidHost
    case missingPort
    case invalidPort
    case unsupportedProtocol
    case credentialsNotAllowed
    case queryOrFragmentNotAllowed
    case malformedAddress

    var errorDescription: String? {
        switch self {
        case .addressRequired: L10n.seerrAddressRequired
        case .invalidHost: L10n.seerrInvalidHost
        case .missingPort: L10n.seerrMissingPort
        case .invalidPort: L10n.seerrInvalidPort
        case .unsupportedProtocol: L10n.seerrUnsupportedProtocol
        case .credentialsNotAllowed: L10n.seerrCredentialsNotAllowed
        case .queryOrFragmentNotAllowed: L10n.seerrQueryOrFragmentNotAllowed
        case .malformedAddress: L10n.seerrMalformedAddress
        }
    }
}

enum SeerrServerAddress {
    static func makeURL(protocol serverProtocol: SeerrProtocol, address: String) throws -> URL {
        let address = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !address.isEmpty else { throw SeerrAddressError.addressRequired }
        guard !address.contains(where: { $0.isWhitespace || $0.isNewline }) else {
            throw SeerrAddressError.malformedAddress
        }

        let authority = address.split(whereSeparator: { $0 == "/" || $0 == "?" || $0 == "#" }).first.map(String.init) ?? address
        try validatePort(in: authority)

        guard var components = URLComponents(string: "http://\(address)"),
              let host = components.host,
              isValidHost(host)
        else { throw SeerrAddressError.invalidHost }
        guard components.user == nil, components.password == nil else {
            throw SeerrAddressError.credentialsNotAllowed
        }
        guard components.query == nil, components.fragment == nil else {
            throw SeerrAddressError.queryOrFragmentNotAllowed
        }
        if let port = components.port, !(1 ... 65535).contains(port) {
            throw SeerrAddressError.invalidPort
        }

        components.scheme = serverProtocol.rawValue
        guard let url = components.url else { throw SeerrAddressError.malformedAddress }
        return url
    }

    static func split(fullURL: String) throws -> (transport: SeerrProtocol, address: String) {
        let fullURL = fullURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if let schemeSeparator = fullURL.range(of: "://") {
            let authority = fullURL[schemeSeparator.upperBound...]
                .split(whereSeparator: { $0 == "/" || $0 == "?" || $0 == "#" })
                .first
                .map(String.init) ?? ""
            try validatePort(in: authority)
        }
        guard let components = URLComponents(string: fullURL) else {
            throw SeerrAddressError.malformedAddress
        }
        guard let scheme = components.scheme?.lowercased(), let serverProtocol = SeerrProtocol(rawValue: scheme) else {
            throw SeerrAddressError.unsupportedProtocol
        }
        guard let host = components.host, isValidHost(host) else { throw SeerrAddressError.invalidHost }
        guard components.user == nil, components.password == nil else {
            throw SeerrAddressError.credentialsNotAllowed
        }
        guard components.query == nil, components.fragment == nil else {
            throw SeerrAddressError.queryOrFragmentNotAllowed
        }
        if let port = components.port, !(1 ... 65535).contains(port) {
            throw SeerrAddressError.invalidPort
        }

        var address = host
        if let port = components.port {
            address += ":\(port)"
        }
        address += components.percentEncodedPath
        return (transport: serverProtocol, address: address)
    }

    static func parseSavedValue(_ value: String) throws -> (transport: SeerrProtocol, address: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.contains("://") {
            return try split(fullURL: trimmed)
        }
        _ = try makeURL(protocol: .http, address: trimmed)
        return (transport: .http, address: trimmed)
    }

    private static func validatePort(in authority: String) throws {
        let portText: Substring?
        if authority.hasPrefix("[") {
            guard let closingBracket = authority.firstIndex(of: "]") else { throw SeerrAddressError.invalidHost }
            let suffix = authority[authority.index(after: closingBracket)...]
            guard !suffix.isEmpty else { return }
            guard suffix.first == ":" else { throw SeerrAddressError.invalidHost }
            portText = suffix.dropFirst()
        } else if authority.contains(":") {
            guard authority.filter({ $0 == ":" }).count == 1,
                  let separator = authority.lastIndex(of: ":")
            else { throw SeerrAddressError.invalidHost }
            portText = authority[authority.index(after: separator)...]
        } else {
            return
        }

        guard let portText else { return }
        guard !portText.isEmpty else { throw SeerrAddressError.missingPort }
        guard portText.allSatisfy(\.isNumber), let port = Int(portText), (1 ... 65535).contains(port) else {
            throw SeerrAddressError.invalidPort
        }
    }

    private static func isValidHost(_ host: String) -> Bool {
        if host.hasPrefix("["), host.hasSuffix("]") {
            let address = host.dropFirst().dropLast()
            var parsedAddress = in6_addr()
            return address.withCString { inet_pton(AF_INET6, $0, &parsedAddress) == 1 }
        }

        guard !host.isEmpty, host.count <= 253, !host.contains(":"), !host.contains("%") else { return false }
        let normalizedHost = host.hasSuffix(".") ? String(host.dropLast()) : host
        let labels = normalizedHost.split(separator: ".", omittingEmptySubsequences: false)
        guard !labels.isEmpty, labels.allSatisfy(isValidHostLabel) else { return false }

        if labels.count == 4, labels.allSatisfy({ $0.allSatisfy(\.isNumber) }) {
            return labels.allSatisfy { label in
                guard let octet = UInt8(String(label)) else { return false }
                return octet <= 255
            }
        }
        return true
    }

    private static func isValidHostLabel(_ label: Substring) -> Bool {
        guard !label.isEmpty, label.count <= 63,
              label.first?.isLetter == true || label.first?.isNumber == true,
              label.last?.isLetter == true || label.last?.isNumber == true
        else { return false }
        return label.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" }
    }
}
