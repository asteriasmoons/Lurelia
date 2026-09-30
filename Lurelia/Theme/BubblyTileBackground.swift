//
//  BubblyTileBackground.swift
//  Lurelia
//
//  Full-bleed tinted background for large sheets and detail surfaces.
//  Unlike BubblyCardMaterial, its light is intentionally broad so the
//  material does not look stretched across an entire screen.
//

import SwiftUI

struct BubblyTileBackground: View {
    @Environment(\.appTheme) private var theme

    var tint: Color

    var body: some View {
        ZStack {
            theme.palette.background

            theme.palette.surface
                .opacity(0.78)

            tint
                .opacity(0.14)

            LinearGradient(
                colors: [
                    theme.palette.textPrimary.opacity(0.055),
                    Color.clear,
                    theme.palette.background.opacity(0.26)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [
                    tint.opacity(0.18),
                    tint.opacity(0.055),
                    Color.clear
                ],
                center: .topTrailing,
                startRadius: 0,
                endRadius: 620
            )
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
