//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import SwiftUI

@main
struct ScreenApp: App {

    init() {
        Self.configure()

        #if DEBUG
        ScreenTopShelfFilesystemProbe.runOnce()
        #endif

        UINavigationBar.appearance().titleTextAttributes = [.foregroundColor: UIColor.label]
    }

    var body: some Scene {
        WindowGroup {
            AppFontEnvironment {
                OverlayToastView {
                    WithUserAuthentication {
                        RootView()
                    }
                }
            }
        }
    }
}

private struct AppFontEnvironment<Content: View>: View {

    @Default(.appFontChoice)
    private var appFontChoice

    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .fontDesign(appFontChoice.fontDesign)
    }
}
