//
//  BubblyLightWash.swift
//  Lurelia
//

import SwiftUI

/// A reusable wash of soft colored light that fades away vertically.
/// Designed to sit inside an overlay and preserve the surface beneath it.
struct BubblyLightWash: View {
    @Environment(\.appTheme) private var theme

    var colors: [Color]?
    var intensity: Double = 0.32
    var fadeEnd: CGFloat = 0.48

    init(
        colors: [Color]? = nil,
        intensity: Double = 0.32,
        fadeEnd: CGFloat = 0.48
    ) {
        self.colors = colors
        self.intensity = intensity
        self.fadeEnd = fadeEnd
    }

    var body: some View {
        GeometryReader { proxy in
            let colors = colors ?? theme.palette.rotation

            ZStack(alignment: .top) {
                ForEach(Array(colors.enumerated()), id: \.offset) { index, color in
                    Ellipse()
                        .fill(color.opacity(intensity))
                        .frame(
                            width: proxy.size.width * 1.18,
                            height: proxy.size.height * 0.62
                        )
                        .blur(radius: 24)
                        .offset(
                            x: horizontalOffset(for: index, width: proxy.size.width),
                            y: -proxy.size.height * 0.26
                        )
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
            .mask(verticalFade)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var verticalFade: some View {
        LinearGradient(
            stops: [
                .init(color: .white, location: 0),
                .init(color: .white.opacity(0.9), location: max(0, fadeEnd * 0.35)),
                .init(color: .clear, location: min(1, fadeEnd))
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private func horizontalOffset(for index: Int, width: CGFloat) -> CGFloat {
        let colorCount = colors?.count ?? theme.palette.rotation.count
        guard colorCount > 1 else { return 0 }
        let progress = CGFloat(index) / CGFloat(colorCount - 1)
        return (progress - 0.5) * width * 0.72
    }
}
