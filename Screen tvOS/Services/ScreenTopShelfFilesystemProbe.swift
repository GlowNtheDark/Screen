//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

#if DEBUG
import Darwin
import Foundation
import OSLog

private let topShelfFilesystemProbeLogger = Logger(
    subsystem: "com.snowfin.tvos",
    category: "TopShelf"
)

@MainActor
enum ScreenTopShelfFilesystemProbe {

    private static let appGroupIdentifier = "group.com.snowfin.tvos"
    private static var hasRun = false

    static func runOnce() {
        guard !hasRun else { return }
        hasRun = true

        topShelfFilesystemProbeLogger.debug(
            "[SCREEN_TOP_SHELF] Filesystem probe started uid=\(getuid(), privacy: .public) gid=\(getgid(), privacy: .public)"
        )

        guard let appGroupURL = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)
        else {
            topShelfFilesystemProbeLogger.error(
                "[SCREEN_TOP_SHELF] Filesystem probe could not resolve the App Group container URL"
            )
            return
        }

        let appGroupLibraryURL = appGroupURL.appendingPathComponent("Library", isDirectory: true)
        let sharedCachesURL = appGroupLibraryURL.appendingPathComponent("Caches", isDirectory: true)
        let appCachesURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first

        logAttributes(of: appGroupURL, label: "App Group root")
        logAttributes(of: appGroupLibraryURL, label: "App Group Library")
        logAttributes(of: sharedCachesURL, label: "App Group Library/Caches")

        if let appCachesURL {
            logAttributes(of: appCachesURL, label: "App Library/Caches")
        } else {
            topShelfFilesystemProbeLogger.error(
                "[SCREEN_TOP_SHELF] Filesystem probe could not resolve the app Library/Caches URL"
            )
        }

        runWriteProbe(in: sharedCachesURL, label: "App Group Library/Caches")

        if let appCachesURL {
            runWriteProbe(in: appCachesURL, label: "App Library/Caches")
        }

        topShelfFilesystemProbeLogger.debug("[SCREEN_TOP_SHELF] Filesystem probe completed")
    }

    private static func logAttributes(of url: URL, label: String) {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            let resourceValues = try? url.resourceValues(forKeys: [
                .isDirectoryKey,
                .isReadableKey,
                .isSymbolicLinkKey,
                .isWritableKey,
            ])
            let ownerID = (attributes[.ownerAccountID] as? NSNumber)?.stringValue ?? "unavailable"
            let groupID = (attributes[.groupOwnerAccountID] as? NSNumber)?.stringValue ?? "unavailable"
            let permissions = (attributes[.posixPermissions] as? NSNumber)
                .map { String(format: "%04o", $0.intValue) } ?? "unavailable"
            let protection = attributes[.protectionKey].map(String.init(describing:)) ?? "unavailable"
            let isDirectory = resourceValues?.isDirectory.map { $0 ? "true" : "false" } ?? "unavailable"
            let isReadable = resourceValues?.isReadable.map { $0 ? "true" : "false" } ?? "unavailable"
            let isWritable = resourceValues?.isWritable.map { $0 ? "true" : "false" } ?? "unavailable"
            let isSymbolicLink = resourceValues?.isSymbolicLink.map { $0 ? "true" : "false" } ?? "unavailable"

            topShelfFilesystemProbeLogger.debug(
                "[SCREEN_TOP_SHELF] Filesystem attributes label=\(label, privacy: .public) ownerUID=\(ownerID, privacy: .public) ownerGID=\(groupID, privacy: .public) mode=\(permissions, privacy: .public) protection=\(protection, privacy: .public) directory=\(isDirectory, privacy: .public) readable=\(isReadable, privacy: .public) writable=\(isWritable, privacy: .public) symbolicLink=\(isSymbolicLink, privacy: .public)"
            )
        } catch {
            logFailure(error, stage: "attributes for \(label)")
        }
    }

    private static func runWriteProbe(in directoryURL: URL, label: String) {
        let probeURL = directoryURL.appendingPathComponent(
            "screen-topshelf-probe-\(UUID().uuidString).tmp"
        )
        var shouldCleanUp = false
        var stage = "create"

        defer {
            if shouldCleanUp || FileManager.default.fileExists(atPath: probeURL.path) {
                do {
                    try FileManager.default.removeItem(at: probeURL)
                    topShelfFilesystemProbeLogger.debug(
                        "[SCREEN_TOP_SHELF] Write probe cleanup succeeded location=\(label, privacy: .public)"
                    )
                } catch {
                    logFailure(error, stage: "cleanup in \(label)")
                }
            }
        }

        do {
            try Data().write(to: probeURL)
            shouldCleanUp = true
            topShelfFilesystemProbeLogger.debug(
                "[SCREEN_TOP_SHELF] Write probe create succeeded location=\(label, privacy: .public)"
            )

            stage = "write"
            let expectedData = Data([0x53])
            try expectedData.write(to: probeURL)
            topShelfFilesystemProbeLogger.debug(
                "[SCREEN_TOP_SHELF] Write probe write succeeded location=\(label, privacy: .public) bytes=1"
            )

            stage = "read"
            let actualData = try Data(contentsOf: probeURL)
            guard actualData == expectedData else {
                topShelfFilesystemProbeLogger.error(
                    "[SCREEN_TOP_SHELF] Write probe read verification failed location=\(label, privacy: .public)"
                )
                return
            }
            topShelfFilesystemProbeLogger.debug(
                "[SCREEN_TOP_SHELF] Write probe read succeeded location=\(label, privacy: .public) bytes=1"
            )

            stage = "delete"
            try FileManager.default.removeItem(at: probeURL)
            shouldCleanUp = false
            topShelfFilesystemProbeLogger.debug(
                "[SCREEN_TOP_SHELF] Write probe delete succeeded location=\(label, privacy: .public)"
            )
        } catch {
            logFailure(error, stage: "write probe \(stage) in \(label)")
        }
    }

    private static func logFailure(_ error: Error, stage: String) {
        let nsError = error as NSError
        let underlyingError = underlyingPOSIXError(in: nsError)
        let posixDetails: String
        if let underlyingError {
            let description = String(cString: strerror(Int32(clamping: underlyingError.code)))
            posixDetails = "domain=\(underlyingError.domain) code=\(underlyingError.code) description=\(description)"
        } else {
            posixDetails = "unavailable"
        }

        let userInfo = sanitizedUserInfo(from: nsError)
        topShelfFilesystemProbeLogger.error(
            "[SCREEN_TOP_SHELF] Filesystem probe failed stage=\(stage, privacy: .public) domain=\(nsError.domain, privacy: .public) code=\(nsError.code, privacy: .public) description=\(redacted(nsError.localizedDescription), privacy: .public) underlyingPOSIX=\(posixDetails, privacy: .public) userInfo=\(userInfo, privacy: .public)"
        )
    }

    private static func underlyingPOSIXError(in error: NSError, depth: Int = 0) -> NSError? {
        guard depth < 5 else { return nil }
        if error.domain == NSPOSIXErrorDomain {
            return error
        }
        guard let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError else { return nil }
        return underlyingPOSIXError(in: underlying, depth: depth + 1)
    }

    private static func sanitizedUserInfo(from error: NSError) -> String {
        let keys = [
            NSFilePathErrorKey,
            NSURLErrorKey,
            NSLocalizedFailureReasonErrorKey,
            NSLocalizedRecoverySuggestionErrorKey,
            NSUnderlyingErrorKey,
        ]
        let values = keys.compactMap { key -> String? in
            guard let value = error.userInfo[key] else { return nil }
            if key == NSFilePathErrorKey || key == NSURLErrorKey {
                return "\(key)=<redacted>"
            }
            if let underlying = value as? NSError {
                return "\(key)=\(underlying.domain):\(underlying.code):\(redacted(underlying.localizedDescription))"
            }
            return "\(key)=\(redacted(String(describing: value)))"
        }
        return values.isEmpty ? "none" : values.joined(separator: "; ")
    }

    private static func redacted(_ value: String) -> String {
        value
            .replacingOccurrences(
                of: #"(?i)(?:https?|swiftfin)://[^\s\"']+"#,
                with: "<redacted-url>",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"/(?:Users|private/var)/[^\s\"']+"#,
                with: "<redacted-path>",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"\b[0-9a-fA-F]{8}-[0-9a-fA-F-]{27,}\b|\b[0-9a-fA-F]{24,}\b"#,
                with: "<redacted-id>",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"(?i)(api[_-]?key|access[_-]?token|token|authorization)=([^&\s]+)"#,
                with: "$1=<redacted>",
                options: .regularExpression
            )
    }
}
#endif
