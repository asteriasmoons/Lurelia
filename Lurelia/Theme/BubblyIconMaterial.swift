//
//  BubblyIconMaterial.swift
//  Lurelia
//
//  Compact Liquid Glass material tuned for tiny icon masks.
//

import SwiftUI

struct BubblyIconMaterial: View {
    @Environment(\.appTheme) private var theme

    var tint: Color

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            ZStack {
                tint.opacity(0.86)

                if #available(iOS 26.0, *) {
                    Rectangle()
                        .fill(tint.opacity(0.16))
                        .glassEffect(.regular.tint(tint.opacity(0.34)), in: Rectangle())
                }

                RadialGradient(
                    colors: [
                        theme.palette.textPrimary.opacity(0.48),
                        theme.palette.textPrimary.opacity(0.16),
                        Color.clear
                    ],
                    center: UnitPoint(x: 0.22, y: 0.18),
                    startRadius: 0,
                    endRadius: min(w, h) * 0.78
                )
                .blendMode(.screen)

                LinearGradient(
                    colors: [
                        theme.palette.textPrimary.opacity(0.34),
                        theme.palette.textPrimary.opacity(0.10),
                        Color.clear
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .blendMode(.screen)

                LinearGradient(
                    colors: [
                        Color.clear,
                        tint.opacity(0.16),
                        theme.palette.background.opacity(0.18)
                    ],
                    startPoint: .top,
                    endPoint: .bottomTrailing
                )
                .blendMode(.multiply)
            }
            .frame(width: w, height: h)
            .compositingGroup()
        }
    }
}

extension View {
    func bubblyIconMaterial(tint: Color) -> some View {
        foregroundStyle(.clear)
            .overlay {
                BubblyIconMaterial(tint: tint)
                    .mask { self }
                    .allowsHitTesting(false)
            }
    }

    @ViewBuilder
    func bubblyIconMaterial(tint: Color, isEnabled: Bool) -> some View {
        if isEnabled {
            bubblyIconMaterial(tint: tint)
        } else {
            self
        }
    }
}
