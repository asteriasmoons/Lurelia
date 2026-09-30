//
//  BubblyCardMaterial.swift
//  Lurelia
//
//  Expanded bubbly material tuned for cards and other large surfaces.
//

import SwiftUI
import UIKit

struct BubblyCardMaterial: View {
    @Environment(\.appTheme) private var theme

    var tint: Color
    var cornerRadius: CGFloat

    private var isPurpleTint: Bool {
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0

        guard UIColor(tint).getHue(
            &hue,
            saturation: &saturation,
            brightness: &brightness,
            alpha: &alpha
        ) else {
            return false
        }

        return saturation >= 0.10 && (0.68...0.92).contains(hue)
    }

    var body: some View {
        GeometryReader { proxy in
            let shape = RoundedRectangle(
                cornerRadius: cornerRadius,
                style: .continuous
            )
            let longestEdge = max(proxy.size.width, proxy.size.height)

            ZStack {
                shape
                    .fill(theme.palette.surface)

                shape
                    .fill(tint.opacity(0.50))

                if #available(iOS 26.0, *) {
                    shape
                        .fill(tint.opacity(0.08))
                        .glassEffect(
                            .regular.tint(tint.opacity(0.18)),
                            in: shape
                        )
                }

                RadialGradient(
                    colors: [
                        theme.palette.textPrimary.opacity(0.12),
                        theme.palette.textPrimary.opacity(0.035),
                        Color.clear
                    ],
                    center: UnitPoint(x: 0.16, y: 0.10),
                    startRadius: 0,
                    endRadius: longestEdge * 0.54
                )
                .blendMode(.screen)
                .clipShape(shape)

                LinearGradient(
                    colors: [
                        theme.palette.textPrimary.opacity(0.07),
                        theme.palette.textPrimary.opacity(0.015),
                        Color.clear
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .blendMode(.screen)
                .clipShape(shape)

                LinearGradient(
                    colors: [
                        Color.clear,
                        tint.opacity(0.07),
                        theme.palette.background.opacity(0.22)
                    ],
                    startPoint: .top,
                    endPoint: .bottomTrailing
                )
                .blendMode(.multiply)
                .clipShape(shape)

                if isPurpleTint {
                    shape
                        .fill(tint.opacity(0.26))
                        .blendMode(.multiply)

                    shape
                        .fill(Color.black.opacity(0.16))
                }

                shape
                    .strokeBorder(
                        theme.palette.textPrimary.opacity(0.12),
                        lineWidth: 1
                    )
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .compositingGroup()
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

extension View {
    func bubblyCardMaterial(
        tint: Color,
        cornerRadius: CGFloat
    ) -> some View {
        background {
            BubblyCardMaterial(
                tint: tint,
                cornerRadius: cornerRadius
            )
        }
    }
}
