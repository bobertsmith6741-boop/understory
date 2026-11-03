// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Understory contributors

import Foundation

/// Desktop widget strings. English only for now: every language falls back
/// to it until translations are added.
struct DesktopWidgetFeatureStrings {
    let pageTitle: String
    let hubDescription: String
    let searchKeywords: String
}

extension FeatureStrings {
    static func desktopWidgets(_ language: AppLanguage) -> DesktopWidgetFeatureStrings {
        .enUS
    }
}

extension DesktopWidgetFeatureStrings {
    static let enUS = DesktopWidgetFeatureStrings(
        pageTitle: "Desktop widgets",
        hubDescription: "Clock, stats, music, calendar and weather widgets you style yourself",
        searchKeywords: "widgets clock weather calendar now playing stats desktop"
    )
}
