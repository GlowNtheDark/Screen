//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

struct CinematicContentGroupContainer<Content: View>: View {

    @Environment(\.frameForParentView)
    private var frameForParentView

    private let content: Content
    private let preferredHeight: CGFloat?

    init(
        preferredHeight: CGFloat? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.content = content()
        self.preferredHeight = preferredHeight
    }

    private var resolvedHeight: CGFloat {
        let parentHeight = frameForParentView[.scrollView, default: .zero].frame.height

        if let preferredHeight {
            return parentHeight > 0 ? min(preferredHeight, parentHeight) : preferredHeight
        }

        return max(parentHeight - 75, 0)
    }

    var body: some View {
        content
            .frame(height: resolvedHeight, alignment: .bottomLeading)
            .frame(maxWidth: .infinity)
    }
}
