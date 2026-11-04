//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import OSLog

enum RuntimeDiagnostics {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.screen.tvos"

    static let lifecycle = Logger(subsystem: subsystem, category: "lifecycle")
    static let requests = Logger(subsystem: subsystem, category: "requests")
    static let playback = Logger(subsystem: subsystem, category: "playback")
    static let playbackSegments = Logger(subsystem: subsystem, category: "playback.segments")

    static func elapsedMilliseconds(since uptimeNanoseconds: UInt64) -> Double {
        Double(DispatchTime.now().uptimeNanoseconds - uptimeNanoseconds) / 1_000_000
    }
}
