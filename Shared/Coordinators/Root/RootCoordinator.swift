//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Combine
import Defaults
import FactoryKit
import Foundation
import SwiftUI
import UIKit

enum AppStartupError: Error {

    case dataStack(Error)
}

@MainActor
@Stateful
final class RootCoordinator: ObservableObject {

    @CasePathable
    enum Action {
        case start

        var transition: Transition {
            switch self {
            case .start:
                .to(.ready)
            }
        }
    }

    enum State {
        case initial
        case error
        case ready
    }

    @Published
    private(set) var themePalette = ThemePreference.applicationDefault.palette

    private var started = false
    private var accentColorCancellable: AnyCancellable?
    private var themeIdentifierCancellable: AnyCancellable?
    private var themeCustomPrimaryColorCancellable: AnyCancellable?
    private var appearanceCancellable: AnyCancellable?
    private var currentSessionCancellable: AnyCancellable?
    private var splashScreenCancellable: AnyCancellable?
    private var appliedCompatibilityAccent: ThemeColor?

    @Injected(\.userSessionManager)
    private var userSessionManager: UserSessionManager

    deinit {
        accentColorCancellable?.cancel()
        themeIdentifierCancellable?.cancel()
        themeCustomPrimaryColorCancellable?.cancel()
        appearanceCancellable?.cancel()
        currentSessionCancellable?.cancel()
        splashScreenCancellable?.cancel()
    }

    @Function(\Action.Cases.start)
    private func _start() async throws {
        guard !started else { return }
        started = true

        do {
            try await ScreenStore.setupDataStack()
            startPreferenceObservation()
        } catch {
            throw AppStartupError.dataStack(error)
        }
    }

    private func startPreferenceObservation() {
        setPreferenceObservation(for: userSessionManager.currentSession)

        currentSessionCancellable = userSessionManager.$currentSession
            .dropFirst()
            .sink { [weak self] session in
                Task { @MainActor in
                    self?.setPreferenceObservation(for: session)
                }
            }
    }

    private func setPreferenceObservation(for session: UserSession?) {
        if session == nil {
            setAppDefaultsObservation()
        } else {
            setUserDefaultsObservation()
        }
    }

    private func setUserDefaultsObservation() {
        accentColorCancellable?.cancel()
        themeIdentifierCancellable?.cancel()
        themeCustomPrimaryColorCancellable?.cancel()
        appearanceCancellable?.cancel()
        splashScreenCancellable?.cancel()

        applyUserThemePreference()

        themeIdentifierCancellable = Defaults.publisher(.userThemeIdentifier)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.applyUserThemePreference()
                }
            }

        themeCustomPrimaryColorCancellable = Defaults.publisher(.userThemeCustomPrimaryColor)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.applyUserThemePreference()
                }
            }

        accentColorCancellable = Task {
            var lastObservedAccent = Defaults[.userAccentColor]

            for await newValue in Defaults.updates(.userAccentColor) {
                guard ThemeColor(newValue) != ThemeColor(lastObservedAccent) else { continue }
                lastObservedAccent = newValue
                applyLegacyAccentEdit(newValue)
            }
        }
        .asAnyCancellable()

        appearanceCancellable = Task {
            applyAppearance(Defaults[.userAppearance])

            for await newValue in Defaults.updates(.userAppearance) {
                applyAppearance(newValue)
            }
        }
        .asAnyCancellable()
    }

    private func setAppDefaultsObservation() {
        accentColorCancellable?.cancel()
        themeIdentifierCancellable?.cancel()
        themeCustomPrimaryColorCancellable?.cancel()
        appearanceCancellable?.cancel()
        splashScreenCancellable?.cancel()

        accentColorCancellable = Task {
            applyTheme(
                .applicationDefault,
                compatibilityAccent: .applicationDefaultAccent
            )
        }
        .asAnyCancellable()

        appearanceCancellable = Task {
            applyAppAppearance()

            for await newValue in Defaults.updates(.appAppearance) {
                guard !Defaults[.selectUserUseSplashscreen] else { continue }

                applyAppearance(newValue)
            }
        }
        .asAnyCancellable()

        splashScreenCancellable = Task {
            for await _ in Defaults.updates(.selectUserUseSplashscreen) {
                applyAppAppearance()
            }
        }
        .asAnyCancellable()
    }

    @MainActor
    private func applyAccentColor(_ color: Color) {
        let currentAccent = ThemeColor(color)
        guard appliedCompatibilityAccent != currentAccent else { return }

        appliedCompatibilityAccent = currentAccent
        Defaults[.accentColor] = color

        #if os(iOS)
        UIApplication.shared.setAccentColor(color.uiColor)
        #endif
    }

    private func applyUserThemePreference() {
        let preference = loadUserThemePreference()
        let compatibilityAccent = compatibilityAccentColor(for: preference)
        applyTheme(preference, compatibilityAccent: compatibilityAccent)
    }

    private func applyTheme(_ preference: ThemePreference, compatibilityAccent: Color) {
        let palette = preference.palette
        if themePalette != palette {
            themePalette = palette
        }

        applyAccentColor(compatibilityAccent)
    }

    private func loadUserThemePreference() -> ThemePreference {
        let identifierValue = Defaults[.userThemeIdentifier]
        let migrationVersion = Defaults[.userThemePreferenceMigrationVersion]
        let customPrimaryColor = Defaults[.userThemeCustomPrimaryColor]
        let existingIdentifier = ThemeIdentifier(rawValue: identifierValue)
        let existingPreference = existingIdentifier.map { identifier in
            ThemePreference(
                identifier: identifier,
                customPrimary: identifier == .custom ? ThemeColor(customPrimaryColor) : nil
            )
        }
        let legacyAccent = Defaults[.userAccentColor]
        let preference = ThemePreferenceMigration.resolve(
            existing: existingPreference,
            migrationVersion: migrationVersion,
            legacyAccent: ThemeColor(legacyAccent)
        )

        if existingPreference != nil {
            if migrationVersion < ThemePreferenceMigration.currentVersion {
                Defaults[.userThemePreferenceMigrationVersion] = ThemePreferenceMigration.currentVersion
            }
            return preference
        }

        guard migrationVersion < ThemePreferenceMigration.currentVersion else {
            return preference
        }

        // Save the raw Color before the identifier so an interrupted migration can
        // safely retry without replacing a custom color with the key's default.
        if preference.identifier == .custom {
            Defaults[.userThemeCustomPrimaryColor] = legacyAccent
        }
        Defaults[.userThemeIdentifier] = preference.identifier.rawValue
        Defaults[.userThemePreferenceMigrationVersion] = ThemePreferenceMigration.currentVersion

        return preference
    }

    private func compatibilityAccentColor(for preference: ThemePreference) -> Color {
        if preference.identifier == .custom {
            Defaults[.userThemeCustomPrimaryColor]
        } else {
            preference.compatibilityAccent.swiftUIColor
        }
    }

    private func applyLegacyAccentEdit(_ color: Color) {
        let preference = loadUserThemePreference()
        guard ThemeColor(color) != preference.compatibilityAccent else { return }

        Defaults[.userThemeCustomPrimaryColor] = color
        Defaults[.userThemeIdentifier] = ThemeIdentifier.custom.rawValue
        Defaults[.userThemePreferenceMigrationVersion] = ThemePreferenceMigration.currentVersion
        applyUserThemePreference()
    }

    @MainActor
    private func applyAppearance(_ appearance: AppAppearance) {
        Defaults[.appearance] = appearance
        UIApplication.shared.setAppearance(appearance.style)
    }

    @MainActor
    private func applyAppAppearance() {
        if Defaults[.selectUserUseSplashscreen] {
            applyAppearance(.dark)
        } else {
            applyAppearance(Defaults[.appAppearance])
        }
    }
}
