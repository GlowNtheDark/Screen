//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

extension Color {

    static let jellyfinPurple = Color(red: 172 / 255, green: 92 / 255, blue: 195 / 255, opacity: 1)

    #if os(tvOS)
    static let screenIceBlue = Color(red: 46 / 255, green: 168 / 255, blue: 255 / 255, opacity: 1)
    static let screenDeepNavy = Color(red: 1 / 255, green: 3 / 255, blue: 5 / 255, opacity: 1)

    var isLegacyJellyfinPurple: Bool {
        let components = rgbaComponents

        return Int((components.red * 255).rounded()) == 172 &&
            Int((components.green * 255).rounded()) == 92 &&
            Int((components.blue * 255).rounded()) == 195 &&
            Int((components.alpha * 255).rounded()) == 255
    }
    #endif

    static var applicationDefaultAccent: Color {
        #if os(tvOS)
        screenIceBlue
        #else
        jellyfinPurple
        #endif
    }

    var uiColor: UIColor {
        UIColor(self)
    }

    var overlayColor: Color {
        Color(uiColor: uiColor.overlayColor)
    }

    /// A related, clearly distinct variant for completed progress.
    var watchedAccentColor: Color {
        let uiColor = uiColor
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0

        guard uiColor.getHue(
            &hue,
            saturation: &saturation,
            brightness: &brightness,
            alpha: &alpha
        ) else {
            let components = rgbaComponents
            return Color(
                red: min(components.red * 0.65 + 0.25, 1),
                green: min(components.green * 0.65 + 0.25, 1),
                blue: min(components.blue * 0.65 + 0.25, 1),
                opacity: components.alpha
            )
        }

        return Color(
            hue: hue,
            saturation: max(saturation * 0.45, 0.32),
            brightness: max(brightness, 0.72),
            opacity: alpha
        )
    }

    // TODO: Correct and add colors
    #if os(tvOS)
    static let systemFill = Color.white
    static let secondarySystemFill = Color.gray
    static let tertiarySystemFill = Color.black
    static let lightGray = Color(UIColor.lightGray)

    #else
    static let systemBackground = Color(UIColor.systemBackground)
    static let secondarySystemBackground = Color(UIColor.secondarySystemBackground)
    static let tertiarySystemBackground = Color(UIColor.tertiarySystemBackground)

    static let systemFill = Color(UIColor.systemFill)
    static let secondarySystemFill = Color(UIColor.secondarySystemFill)
    static let tertiarySystemFill = Color(UIColor.tertiarySystemFill)
    #endif
}

extension Color {

    struct RGBA {

        enum Component {
            case red
            case green
            case blue
            case alpha
        }

        var red: CGFloat
        var green: CGFloat
        var blue: CGFloat
        var alpha: CGFloat
    }

    var rgbaComponents: RGBA {
        get {
            var r: CGFloat = 0
            var g: CGFloat = 0
            var b: CGFloat = 0
            var a: CGFloat = 0

            uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)

            return RGBA(
                red: r,
                green: g,
                blue: b,
                alpha: a
            )
        }
        mutating set {
            self = Color(
                red: newValue.red,
                green: newValue.green,
                blue: newValue.blue,
                opacity: newValue.alpha
            )
        }
    }

    func with(rgba: WritableKeyPath<RGBA, CGFloat>, value: CGFloat) -> Color {
        var components = rgbaComponents
        components[keyPath: rgba] = value
        return Color(
            red: components.red,
            green: components.green,
            blue: components.blue,
            opacity: components.alpha
        )
    }

    init(hex: String) {
        let s = hex.hasPrefix("#") ? hex.dropFirst() : Substring(hex)
        let x = UInt64(s, radix: 16) ?? 0
        self.init(
            .sRGB,
            red: Double((x >> 16) & 255) / 255,
            green: Double((x >> 8) & 255) / 255,
            blue: Double(x & 255) / 255,
            opacity: s.count > 6 ? Double((x >> 24) & 255) / 255 : 1
        )
    }

    var hexString: String {
        let components = rgbaComponents
        let r = Int(components.red * 255)
        let g = Int(components.green * 255)
        let b = Int(components.blue * 255)
        let a = Int(components.alpha * 255)

        if a < 255 {
            return String(format: "%02X%02X%02X%02X", r, g, b, a)
        } else {
            return String(format: "%02X%02X%02X", r, g, b)
        }
    }
}
