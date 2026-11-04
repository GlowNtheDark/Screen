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
        RuntimeDiagnostics.lifecycle.notice("event=app.startup")

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

    @Environment(\.scenePhase)
    private var scenePhase

    @State
    private var previousScenePhase: ScenePhase?

    @Default(.appFontChoice)
    private var appFontChoice

    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .fontDesign(appFontChoice.fontDesign)
            .onChange(of: scenePhase, initial: true) { _, newPhase in
                guard previousScenePhase != newPhase else { return }
                if newPhase == .active {
                    RuntimeDiagnostics.lifecycle.notice("event=scene.active")
                    let event = previousScenePhase == nil ? "app.foreground" : "app.foreground_return"
                    RuntimeDiagnostics.lifecycle.notice("event=\(event, privacy: .public)")
                } else {
                    let event: String = switch newPhase {
                    case .inactive:
                        "scene.inactive"
                    case .background:
                        "scene.background"
                    @unknown default:
                        "scene.unknown"
                    }
                    RuntimeDiagnostics.lifecycle.notice("event=\(event, privacy: .public)")
                }
                previousScenePhase = newPhase
            }
    }
}
