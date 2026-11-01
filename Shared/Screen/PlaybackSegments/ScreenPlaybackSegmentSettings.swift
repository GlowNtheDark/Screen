//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults

enum ScreenIntroBehavior: String, CaseIterable, Defaults.Serializable, Displayable {
    case off
    case showSkipButton
    case autoSkip

    var displayTitle: String {
        switch self {
        case .off: "Off"
        case .showSkipButton: "Show Skip Button"
        case .autoSkip: "Auto Skip"
        }
    }
}

enum ScreenCreditsBehavior: String, CaseIterable, Defaults.Serializable, Displayable {
    case off
    case showNextEpisode
    case countdownAutoplay
    case immediateAutoplay

    var displayTitle: String {
        switch self {
        case .off: "Off"
        case .showNextEpisode: "Show Next Episode"
        case .countdownAutoplay: "Countdown + Autoplay"
        case .immediateAutoplay: "Immediate Autoplay"
        }
    }
}

enum ScreenAutoplayCountdownDuration: Int, CaseIterable, Defaults.Serializable, Displayable {
    case five = 5
    case ten = 10
    case fifteen = 15
    case thirty = 30

    var displayTitle: String {
        "\(rawValue) seconds"
    }
}
