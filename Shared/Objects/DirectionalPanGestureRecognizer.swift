//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import UIKit

class DirectionalPanGestureRecognizer: UIPanGestureRecognizer {

    var direction: Direction
    #if os(tvOS)
    private static let minimumDirectionalVelocity: CGFloat = 20
    private static let directionalDominanceRatio: CGFloat = 1.2

    #endif

    init(direction: Direction, target: AnyObject, action: Selector) {
        self.direction = direction
        super.init(target: target, action: action)
    }

    static func matches(
        direction: Direction,
        velocity: CGPoint,
        translation: CGPoint
    ) -> Bool {
        #if os(tvOS)
        guard direction != .all else { return true }

        let intent = directionalIntent(velocity: velocity, translation: translation)

        if direction == .allButDown {
            return intent == .up || intent?.isHorizontal == true
        }
        if direction == .horizontal {
            return intent?.isHorizontal == true
        }
        if direction == .vertical {
            return intent?.isVertical == true
        }
        if direction == .up {
            return intent == .up
        }
        if direction == .down {
            return intent == .down
        }
        if direction == .left {
            return intent == .left
        }
        if direction == .right {
            return intent == .right
        }

        return false
        #else
        let isUp = velocity.y < 0
        let isHorizontal = velocity.y.magnitude < velocity.x.magnitude
        let isVertical = velocity.x.magnitude < velocity.y.magnitude

        switch direction {
        case .all: return true
        case .allButDown: return isUp || isHorizontal
        case .horizontal: return isHorizontal
        case .vertical: return isVertical
        case .up: return isVertical && velocity.y < 0
        case .down: return isVertical && velocity.y > 0
        case .left: return isHorizontal && velocity.x < 0
        case .right: return isHorizontal && velocity.x > 0
        default: return false
        }
        #endif
    }

    #if os(tvOS)
    private static func directionalIntent(velocity: CGPoint, translation: CGPoint) -> Direction? {
        if hypot(velocity.x, velocity.y) >= minimumDirectionalVelocity,
           let intent = directionalIntent(from: velocity)
        {
            return intent
        }

        return directionalIntent(from: translation)
    }

    private static func directionalIntent(from vector: CGPoint) -> Direction? {
        let horizontalMagnitude = abs(vector.x)
        let verticalMagnitude = abs(vector.y)
        guard horizontalMagnitude > 0 || verticalMagnitude > 0 else { return nil }

        if horizontalMagnitude >= verticalMagnitude * directionalDominanceRatio {
            return vector.x < 0 ? .left : .right
        }
        if verticalMagnitude >= horizontalMagnitude * directionalDominanceRatio {
            return vector.y < 0 ? .up : .down
        }

        return nil
    }
    #endif

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesMoved(touches, with: event)

        if state == .began {
            let velocity = velocity(in: view)
            let translation = translation(in: view)

            guard Self.matches(direction: direction, velocity: velocity, translation: translation) else {
                state = .cancelled
                return
            }
        }
    }
}
