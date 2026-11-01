//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import JellyfinAPI

struct ScreenPlaybackSegment: Hashable, Identifiable {
    let id: String
    let type: MediaSegmentType
    let start: Duration
    let end: Duration

    init?(_ dto: MediaSegmentDto) {
        guard let type = dto.type,
              type == .intro || type == .outro,
              let startTicks = dto.startTicks,
              let endTicks = dto.endTicks,
              endTicks > startTicks
        else { return nil }

        self.type = type
        self.start = .ticks(startTicks)
        self.end = .ticks(endTicks)
        self.id = dto.id ?? "\(type.rawValue)-\(startTicks)-\(endTicks)"
    }

    func contains(_ seconds: Duration) -> Bool {
        seconds >= start && seconds < end
    }

    func startWasCrossed(from previous: Duration, to current: Duration) -> Bool {
        previous <= start && current >= start && current > previous
    }
}
