//
//  BubblyTileSurface.swift
//  Lurelia
//
//  Reusable glossy, tinted glass surface used for
//  accent tiles, buttons, chips, statistics, and controls.
//

import SwiftUI

struct BubblyTileSurface: View {
    @Environment(\.appTheme) private var theme

    var tint: Color
    var cornerRadius: CGFloat

    var body: some View {
        let shape = RoundedRectangle(
            cornerRadius: cornerRadius,
            style: .continuous
        )

        ZStack {
            // Base tinted Liquid Glass surface
            if #available(iOS 26.0, *) {
                shape
                    .fill(tint)
                    .glassEffect(
                        .regular
                            .tint(tint)
                            .interactive(),
                        in: shape
                    )
            } else {
                shape
                    .fill(tint)
            }

            // Glossy diagonal highlight
            shape
                .fill(
                    LinearGradient(
                        colors: [
                            theme.palette.textPrimary.opacity(0.50),
                            theme.palette.textPrimary.opacity(0.16),
                            theme.palette.textPrimary.opacity(0.0)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .blendMode(.screen)

            // Subtle bright edge
            shape
                .strokeBorder(
                    theme.palette.textPrimary.opacity(0.34),
                    lineWidth: 1
                )
        }
    }
}


// MARK: - Bubbly Tile Lift

struct BubblyTileLift: ViewModifier {
    @Environment(\.appTheme) private var theme

    func body(content: Content) -> some View {
        content
            .shadow(
                color: theme.palette.background.opacity(0.55),
                radius: 1,
                x: 0,
                y: 2
            )
    }
}


// MARK: - View Extensions

extension View {

    /// Adds the subtle raised shadow used by Lurelia's bubbly surfaces.
    func bubblyTileLift() -> some View {
        modifier(BubblyTileLift())
    }

    /// Conditionally applies the bubbly tile lift.
    @ViewBuilder
    func bubblyTileLift(isEnabled: Bool) -> some View {
        if isEnabled {
            bubblyTileLift()
        } else {
            self
        }
    }
}
