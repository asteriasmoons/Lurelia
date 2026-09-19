//
//  Theme.swift
//  Lurelia
//

import SwiftUI

// MARK: - Color Tokens

enum LColors {
    // Base
    static let bg = Color(lureliaHex: "#07070a")
    static let bgSoft = Color(lureliaHex: "#020304")
    
    // Text
    static let textPrimary = Color.white
    static let textSecondary = Color(lureliaHex: "#888888")
    
    // Accent
    static let accent = Color(lureliaHex: "#03dbfc")
    static let accentHover = Color(lureliaHex: "#7d19f7")
    static let accentGradient = LinearGradient(
        colors: [
            Color(lureliaHex: "#03dbfc"),
            Color(lureliaHex: "#7d19f7")
        ],
        startPoint: .leading,
        endPoint: .trailing
    )
    
    // Status
    static let success = Color(lureliaHex: "#e2ed8a")
    static let danger = Color(lureliaHex: "#dc3beb")
    static let warning = Color(lureliaHex: "#a92ce8")
    
    // Glass surfaces
    // Neutral smoked-glass system surfaces
    static let neutralPearl = Color(lureliaHex: "#E6E6EA")
    static let neutralSilver = Color(lureliaHex: "#A8ABB3")
    static let neutralSmoke = Color(lureliaHex: "#6E717A")
    static let neutralGraphite = Color(lureliaHex: "#2A2D36")
    static let neutralDeepGraphite = Color(lureliaHex: "#14161C")
    static let neutralBase = Color(lureliaHex: "#07070A")
    static let neutralGlassBase = Color(lureliaHex: "#171A21")
    static let neutralGlassHighlight = Color(lureliaHex: "#E6E6EA")

    // MARK: - Iridescent Liquid Glass (canonical Lurelia identity)
    // Permanent Lurelia-owned surfaces are dark smoked glass lit from within
    // by these four lights. Exact hexes from the Lurelia identity palette.
    static let foundation = Color(lureliaHex: "#04040C")
    static let darkGlass = Color(lureliaHex: "#171925")
    static let raisedGlass = Color(lureliaHex: "#202231")
    static let glassHighlight = Color(lureliaHex: "#D9E4F2")

    static let glassSurface = Color.white.opacity(0.06)
    static let glassSurface2 = Color.white.opacity(0.09)
    static let glassBorder = neutralSilver.opacity(0.14)
    static let glassBorderStrong = neutralPearl.opacity(0.22)
    
    // Gradient colors
    static let gradientPurple = Color(lureliaHex: "#7d19f7")
    static let gradientBlue = Color(lureliaHex: "#03dbfc")
    static let gradientPink = Color(lureliaHex: "#e019d4")
    static let gradientCyan = Color(lureliaHex: "#00dbff")
    static let gradientYellow = Color(lureliaHex: "#f6f684")
    static let gradientDeepPurple = Color(lureliaHex: "#8000fe")
    
    // Badge colors
    static let badgeOnce = Color(lureliaHex: "#66b8ff")
    static let badgeDaily = Color(lureliaHex: "#7d19f7")
    static let badgeWeekly = Color.white
    static let badgeMonthly = Color(lureliaHex: "#ec4899")
    static let badgeInterval = Color(lureliaHex: "#02edd6")
}

// MARK: - Gradients

enum LGradients {
    /// Flat frosty white (both endpoints identical → renders as solid).
    static let frosty = LinearGradient(
        colors: [
            Color.white.opacity(0.88),
            Color.white.opacity(0.88)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Flat frosty fill (both endpoints identical → renders as solid).
    static let frostyFill = LinearGradient(
        colors: [
            Color.white.opacity(0.14),
            Color.white.opacity(0.14)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Flat frosty white (both endpoints identical → renders as solid).
    static let blue = LinearGradient(
        colors: [
            Color.white.opacity(0.88),
            Color.white.opacity(0.88)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    /// FLAT frosty white. Kept as a `LinearGradient` for API compatibility
    /// (many callers use `.foregroundStyle(LGradients.header)` /
    /// `.background(LGradients.header, in: ...)`) but both endpoints are the
    /// same color so it renders as a solid — NO visible gradient.
    static let header = LinearGradient(
        colors: [
            Color.white.opacity(0.88),
            Color.white.opacity(0.88)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    /// Flat frosty white (both endpoints identical → renders as solid).
    static let tag = LinearGradient(
        colors: [
            Color.white.opacity(0.85),
            Color.white.opacity(0.85)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    // Background ambient glow
    static let bgPurple = RadialGradient(
        colors: [Color(lureliaHex: "#8000fe").opacity(0.34), .clear],
        center: UnitPoint(x: 0.28, y: 0.18),
        startRadius: 0,
        endRadius: 450
    )
    
    static let bgCyan = RadialGradient(
        colors: [Color(lureliaHex: "#00dbff").opacity(0.22), .clear],
        center: UnitPoint(x: 0.76, y: 0.78),
        startRadius: 0,
        endRadius: 475
    )
    
    static let bgYellow = RadialGradient(
        colors: [Color(lureliaHex: "#f6f684").opacity(0.22), .clear],
        center: UnitPoint(x: 0.58, y: 0.26),
        startRadius: 0,
        endRadius: 260
    )
    
    static let bgPink = RadialGradient(
        colors: [Color(lureliaHex: "#e019d4").opacity(0.14), .clear],
        center: UnitPoint(x: 0.42, y: 0.74),
        startRadius: 0,
        endRadius: 260
    )

    static let reward = LinearGradient(
        colors: [Color(lureliaHex: "#FF1493"), Color(lureliaHex: "#FFB8EC")],
        startPoint: .leading,
        endPoint: .trailing
    )
}

// MARK: - Spacing & Radius

enum LSpacing {
    static let cardPadding: CGFloat = 20
    static let cardRadius: CGFloat = 16
    static let buttonRadius: CGFloat = 12
    static let inputRadius: CGFloat = 12
    static let pillRadius: CGFloat = 999
    static let pageHorizontal: CGFloat = 16
    static let sectionGap: CGFloat = 24
}

// MARK: - Color Extension

// MARK: - Adaptive Text Helpers
//
// Any button/pill that fills with a bright frosty-white surface (e.g.
// `LGradients.header`, `LGradients.blue`, `Color.white.opacity(0.85+)`) needs
// dark text or its label disappears. These helpers pick a contrasting text
// color based on the surface's WCAG luminance so authors can write, e.g.:
//
//     .foregroundStyle(surface.adaptivePrimaryText)
//     .modifier(AdaptiveForeground(on: surface))
//
// The underlying calculation lives in `wcagContrastingTextColor` further down
// this file — these are shorter, more discoverable aliases used across the
// button/pill surfaces.

extension Color {
    /// Best-contrast "primary text" color for content placed *on top of this
    /// surface color*. Returns near-black on a light surface, white on a dark
    /// one. Prefer this over `LColors.textPrimary` whenever the container is
    /// a frosty-white pill/button that would otherwise leave white text on a
    /// nearly-white background.
    var adaptivePrimaryText: Color { wcagContrastingTextColor }

    /// Softer, still-readable secondary text color for a given surface.
    /// Muted-black on light surfaces, muted-white on dark ones.
    var adaptiveSecondaryText: Color { wcagContrastingSecondaryTextColor }
}

/// Convenience view modifier: `.adaptiveForeground(on: surface)` sets the
/// foreground style to the WCAG-contrasting primary text color for `surface`.
struct AdaptiveForeground: ViewModifier {
    let surface: Color
    func body(content: Content) -> some View {
        content.foregroundStyle(surface.adaptivePrimaryText)
    }
}

extension View {
    /// Sugar for `.modifier(AdaptiveForeground(on: surface))`.
    func adaptiveForeground(on surface: Color) -> some View {
        modifier(AdaptiveForeground(surface: surface))
    }
}

extension Color {
    init(lureliaHex hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        
        switch hex.count {
        case 6:
            (a, r, g, b) = (
                255,
                int >> 16,
                int >> 8 & 0xFF,
                int & 0xFF
            )
        case 8:
            (a, r, g, b) = (
                int >> 24,
                int >> 16 & 0xFF,
                int >> 8 & 0xFF,
                int & 0xFF
            )
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }

    func toHex() -> String? {
        let ui = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard ui.getRed(&r, green: &g, blue: &b, alpha: &a) else { return nil }
        return String(format: "#%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
    }

    var isLightColor: Bool {
        prefersDarkTextByWCAGContrast
    }

    var wcagContrastingTextColor: Color {
        prefersDarkTextByWCAGContrast ? .black.opacity(0.88) : .white
    }

    var wcagContrastingSecondaryTextColor: Color {
        prefersDarkTextByWCAGContrast ? .black.opacity(0.62) : .white.opacity(0.72)
    }

    var wcagContrastingSolidTextColor: Color {
        prefersDarkTextByWCAGContrast ? .black : .white
    }

    var wcagTextLiftShadowColor: Color {
        prefersDarkTextByWCAGContrast ? .white.opacity(0.32) : .black.opacity(0.55)
    }

    var wcagTextLiftShadowRadius: CGFloat {
        prefersDarkTextByWCAGContrast ? 1.2 : 1.1
    }

    var wcagTextLiftShadowYOffset: CGFloat {
        prefersDarkTextByWCAGContrast ? 0 : 1
    }

    private var prefersDarkTextByWCAGContrast: Bool {
        let backgroundLuminance = wcagRelativeLuminance
        let blackContrast = Color.wcagContrastRatio(backgroundLuminance, 0)
        let whiteContrast = Color.wcagContrastRatio(backgroundLuminance, 1)
        return blackContrast >= whiteContrast
    }

    private var wcagRelativeLuminance: Double {
        let components = srgbComponentsForContrast
        let red = Color.wcagLinearComponent(components.red)
        let green = Color.wcagLinearComponent(components.green)
        let blue = Color.wcagLinearComponent(components.blue)
        return (0.2126 * red) + (0.7152 * green) + (0.0722 * blue)
    }

    private var srgbComponentsForContrast: (red: Double, green: Double, blue: Double) {
        let uiColor = UIColor(self)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0

        guard uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            return (0, 0, 0)
        }

        return (
            Double(max(0, min(1, red))),
            Double(max(0, min(1, green))),
            Double(max(0, min(1, blue)))
        )
    }

    private static func wcagLinearComponent(_ component: Double) -> Double {
        component <= 0.03928
            ? component / 12.92
            : pow((component + 0.055) / 1.055, 2.4)
    }

    private static func wcagContrastRatio(_ firstLuminance: Double, _ secondLuminance: Double) -> Double {
        let lighter = max(firstLuminance, secondLuminance)
        let darker = min(firstLuminance, secondLuminance)
        return (lighter + 0.05) / (darker + 0.05)
    }
}

extension View {
    func wcagContrastLift(on backgroundColor: Color, isActive: Bool = true) -> some View {
        self.shadow(
            color: isActive ? backgroundColor.wcagTextLiftShadowColor : .clear,
            radius: isActive ? backgroundColor.wcagTextLiftShadowRadius : 0,
            x: 0,
            y: isActive ? backgroundColor.wcagTextLiftShadowYOffset : 0
        )
    }
}
