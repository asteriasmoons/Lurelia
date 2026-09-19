//
//  LureliaComponents.swift
//  Lurelia
//

import SwiftUI

// MARK: - Lurelia Background

struct LureliaBackground: View {
    var body: some View {
        ZStack {
            // Base background
            LColors.bg
                .ignoresSafeArea()
            
            // Ambient glows
            LGradients.bgPurple
                .blendMode(.screen)
                .ignoresSafeArea()
            
            LGradients.bgCyan
                .blendMode(.screen)
                .ignoresSafeArea()
            
            LGradients.bgYellow
                .blendMode(.screen)
                .ignoresSafeArea()
            
            LGradients.bgPink
                .blendMode(.screen)
                .ignoresSafeArea()
            
            // Soft vignette
            LinearGradient(
                colors: [
                    Color.black.opacity(0.22),
                    Color.clear,
                    Color.black.opacity(0.34)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            // Atmosphere overlay
            Rectangle()
                .fill(Color.white.opacity(0.015))
                .blendMode(.softLight)
                .ignoresSafeArea()
        }
    }
}

// MARK: - Gradient Stepper

struct LureliaGradientStepper: View {
    let title: String
    let subtitle: String?
    @Binding var value: Int
    var range: ClosedRange<Int> = 1...999
    var step: Int = 1
    var tint: Color?

    private var canDecrease: Bool {
        value - step >= range.lowerBound
    }

    private var canIncrease: Bool {
        value + step <= range.upperBound
    }

    var body: some View {
        HStack(spacing: 14) {
            if !title.isEmpty || subtitle != nil {
                VStack(alignment: .leading, spacing: 3) {
                    if !title.isEmpty {
                        Text(title)
                            .font(.system(size: 14, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                    }

                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: title.isEmpty ? 15 : 11, weight: .black, design: .rounded))
                            .foregroundStyle(title.isEmpty ? .white.opacity(0.78) : .white.opacity(0.5))
                    }
                }
            }

            Spacer()

            stepperButton(icon: "minuswavy", isEnabled: canDecrease) {
                value = max(range.lowerBound, value - step)
            }

            Text("\(value)")
                .font(.system(size: 18, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .monospacedDigit()
                .frame(minWidth: 38)

            stepperButton(icon: "addwavy", isEnabled: canIncrease) {
                value = min(range.upperBound, value + step)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background {
            LureliaNeutralGlassSurface(cornerRadius: 16, prominence: .lens)
        }
    }

    private func stepperButton(
        icon: String,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        LureliaRepeatingStepperButton(
            icon: icon,
            isEnabled: isEnabled,
            tint: tint,
            action: action
        )
    }
}

// MARK: - Sliding Icon Toggle

struct LureliaSlidingIconToggle: View {
    @Binding var isOn: Bool
    let iconName: String
    var accentColor: Color
    var accessibilityLabel: String
    var isDisabled: Bool = false
    var width: CGFloat = 58
    var height: CGFloat = 32

    private var knobSize: CGFloat {
        max(24, height - 6)
    }

    var body: some View {
        Button {
            toggle()
        } label: {
            ZStack {
                Capsule()
                    .fill(trackFill)
                    .overlay {
                        Capsule()
                            .strokeBorder(trackStroke, lineWidth: 1)
                    }

                HStack {
                    if isOn { Spacer(minLength: 0) }

                    ZStack {
                        Circle()
                            .fill(knobFill)
                            .overlay {
                                Circle()
                                    .strokeBorder(knobStroke, lineWidth: 1)
                            }

                        Image(iconName)
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 14, height: 14)
                            .foregroundStyle(knobIconColor)
                    }
                    .frame(width: knobSize, height: knobSize)

                    if !isOn { Spacer(minLength: 0) }
                }
                .padding(3)
            }
            .frame(width: width, height: height)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.45 : 1)
        .animation(.spring(response: 0.28, dampingFraction: 0.86), value: isOn)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { toggle() }
    }

    private var trackFill: Color {
        isOn ? accentColor.opacity(0.24) : Color.white.opacity(0.07)
    }

    private var trackStroke: Color {
        isOn ? accentColor.opacity(0.58) : Color.white.opacity(0.16)
    }

    private var knobFill: Color {
        isOn ? accentColor : LColors.glassSurface2
    }

    private var knobStroke: Color {
        isOn ? Color.white.opacity(0.16) : Color.white.opacity(0.12)
    }

    private var knobIconColor: Color {
        isOn ? accentColor.wcagContrastingSolidTextColor : .white.opacity(0.62)
    }

    private func toggle() {
        guard !isDisabled else { return }
        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
            isOn.toggle()
        }
    }
}

private struct LureliaRepeatingStepperButton: View {
    let icon: String
    let isEnabled: Bool
    let tint: Color?
    let action: () -> Void

    @State private var repeatTask: Task<Void, Never>?

    private var activeStyle: AnyShapeStyle {
        if let tint {
            return AnyShapeStyle(tint)
        }

        return AnyShapeStyle(LGradients.header)
    }

    private var inactiveStyle: AnyShapeStyle {
        AnyShapeStyle(Color.white.opacity(0.25))
    }

    private var activeBackground: Color {
        if let tint {
            return tint.opacity(0.13)
        }

        return .clear
    }

    private var activeBorderStyle: AnyShapeStyle {
        if let tint {
            return AnyShapeStyle(tint.opacity(isEnabled ? 0.50 : 0.20))
        }

        return AnyShapeStyle(LGradients.header.opacity(isEnabled ? 0.85 : 0.25))
    }

    var body: some View {
        Image(icon)
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .foregroundStyle(isEnabled ? activeStyle : inactiveStyle)
            .opacity(isEnabled ? 1 : 0.28)
            .frame(width: 22, height: 22)
            .frame(width: 38, height: 38)
            .background {
                if tint == nil {
                    LureliaNeutralGlassCircle(prominence: isEnabled ? .active : .lens)
                } else {
                    Circle()
                        .fill(activeBackground)
                }
            }
            .overlay {
                if tint != nil {
                    Circle()
                        .strokeBorder(activeBorderStyle, lineWidth: 1)
                }
            }
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        startRepeating()
                    }
                    .onEnded { _ in
                        stopRepeating()
                    }
            )
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(icon == "minuswavy" ? "Decrease" : "Increase")
            .disabled(!isEnabled)
            .onChange(of: isEnabled) { _, enabled in
                if !enabled {
                    stopRepeating()
                }
            }
            .onDisappear {
                stopRepeating()
            }
    }

    private func startRepeating() {
        guard isEnabled, repeatTask == nil else { return }

        repeatTask = Task { @MainActor in
            action()

            try? await Task.sleep(nanoseconds: 360_000_000)

            while !Task.isCancelled {
                action()
                try? await Task.sleep(nanoseconds: 80_000_000)
            }
        }
    }

    private func stopRepeating() {
        repeatTask?.cancel()
        repeatTask = nil
    }

}

// MARK: - Glass Card

enum LureliaNeutralGlassProminence {
    case surface
    case lens
    case active
}

// MARK: - Iridescent Liquid Glass
//
// Lurelia's permanent, non-user-colored surfaces render as dark smoked glass
// lit from within by overlapping radial fields in the canonical Lurelia
// palette (blue / violet / pink / gold). The colored light is *illumination
// suspended inside* a near-black body -- never an opaque surface color, never
// a flat rainbow gradient. The four light colors are configurable so the same
// material can later receive harmonized colors derived from nearby user
// content; the default is always the canonical palette. This is the ONLY place
// the effect is defined -- every Lurelia-owned surface shares it.

/// Shared renderer for Lurelia's neutral glass. The theme is JUST GLASS:
/// dark smoked frosted glass with a faint hairline edge for definition and
/// NOTHING else — no color, no white light pools, no iridescent rim. Users
/// pick the colors for the real components, so Lurelia-owned surfaces stay
/// colorless and sit calmly under any mix of user colors on screen.
struct IridescentLiquidGlass<S: InsettableShape>: View {
    let shape: S
    var prominence: LureliaNeutralGlassProminence = .surface

    var body: some View {
        ZStack {
            // The actual glass: real frosted translucency, tinted only with
            // black so it reads as dark smoked glass. No hue, no white light.
            if #available(iOS 26.0, *) {
                Color.clear
                    .glassEffect(.regular.tint(Color.black.opacity(smokeOpacity)), in: shape)
            } else {
                shape.fill(.ultraThinMaterial)
                shape.fill(Color.black.opacity(smokeOpacity))
            }
        }
        // A hairline neutral edge so the glass shape reads. This is a glass
        // rim for definition, not a light source — kept very faint.
        .overlay {
            shape.strokeBorder(Color.white.opacity(edgeOpacity), lineWidth: 1)
        }
    }

    // Darker for large surfaces, slightly lighter/glassier for small controls.
    private var smokeOpacity: Double {
        switch prominence {
        case .surface: return 0.42
        case .lens:    return 0.36
        case .active:  return 0.30
        }
    }

    private var edgeOpacity: Double {
        switch prominence {
        case .surface: return 0.09
        case .lens:    return 0.11
        case .active:  return 0.13
        }
    }
}

struct LureliaNeutralGlassSurface: View {
    var cornerRadius: CGFloat = 24
    var prominence: LureliaNeutralGlassProminence = .surface

    var body: some View {
        IridescentLiquidGlass(
            shape: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous),
            prominence: prominence
        )
    }
}

struct LureliaNeutralGlassCircle: View {
    var prominence: LureliaNeutralGlassProminence = .surface

    var body: some View {
        IridescentLiquidGlass(
            shape: Circle(),
            prominence: prominence
        )
    }
}

extension View {
    func lureliaNeutralGlass(
        cornerRadius: CGFloat = 24,
        prominence: LureliaNeutralGlassProminence = .surface
    ) -> some View {
        background {
            LureliaNeutralGlassSurface(
                cornerRadius: cornerRadius,
                prominence: prominence
            )
        }
    }
}

// MARK: - User Choice Color Surfaces

enum LureliaUserChoiceSurfaceRole {
    case hero
    case supporting
}

struct LureliaUserChoiceSurface: View {
    let tint: Color
    var role: LureliaUserChoiceSurfaceRole = .supporting
    var cornerRadius: CGFloat = 22

    private var fillOpacity: Double {
        role == .hero ? 0.30 : 0.22
    }

    private var borderOpacity: Double {
        role == .hero ? 0.55 : 0.50
    }

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(LColors.glassSurface)
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(tint.opacity(fillOpacity))
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(tint.opacity(borderOpacity), lineWidth: 1)
            }
            .shadow(
                color: role == .hero ? tint.opacity(0.16) : .clear,
                radius: role == .hero ? 18 : 0,
                x: 0,
                y: role == .hero ? 10 : 0
            )
    }
}

extension View {
    func lureliaUserChoiceSurface(
        tint: Color,
        role: LureliaUserChoiceSurfaceRole = .supporting,
        cornerRadius: CGFloat = 22
    ) -> some View {
        background {
            LureliaUserChoiceSurface(tint: tint, role: role, cornerRadius: cornerRadius)
        }
    }
}

struct GlassCard<Content: View>: View {
    var cornerRadius: CGFloat = 24
    var padding: CGFloat = LSpacing.cardPadding
    var tint: Color?
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(padding)
            .background { cardBackground }
            .shadow(color: softShadowColor, radius: softShadowRadius, y: softShadowY)
            .shadow(color: depthShadowColor, radius: depthShadowRadius, y: depthShadowY)
    }

    private var softShadowColor: Color {
        tint?.opacity(0.10) ?? .clear
    }

    private var depthShadowColor: Color {
        (tint ?? Color.clear).opacity(tint == nil ? 0 : 0.22)
    }

    private var softShadowRadius: CGFloat {
        tint == nil ? 0 : 16
    }

    private var depthShadowRadius: CGFloat {
        tint == nil ? 0 : 18
    }

    private var softShadowY: CGFloat {
        tint == nil ? 0 : 8
    }

    private var depthShadowY: CGFloat {
        tint == nil ? 0 : 10
    }

    @ViewBuilder
    private var cardBackground: some View {
        if let tint {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.white.opacity(0.09))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(tint.opacity(0.24))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(tint.opacity(0.78), lineWidth: 1.05)
                }
        } else {
            LureliaNeutralGlassSurface(cornerRadius: cornerRadius)
        }
    }
}

// MARK: - Alternate Lurelia Background

struct LureliaBackgroundAlt: View {
    var body: some View {
        LColors.bgSoft
            .ignoresSafeArea()
    }
}

// MARK: - Gradient Time Drum Picker

struct LureliaGradientTimeDrumPicker: View {
    @Binding var hour: Int
    @Binding var minute: Int
    
    @State private var displayHour: Int = 9
    @State private var meridiem: String = "AM"
    
    private let meridiems = ["AM", "PM"]
    
    private var formattedPreview: String {
        String(format: "%d:%02d %@", displayHour, minute, meridiem)
    }

    private var displayHourBinding: Binding<Int> {
        Binding(
            get: { displayHour },
            set: { newValue in
                let clamped = max(1, min(12, newValue))
                guard displayHour != clamped else { return }
                displayHour = clamped
            }
        )
    }

    private var minuteBinding: Binding<Int> {
        Binding(
            get: { max(0, min(59, minute)) },
            set: { newValue in
                let clamped = max(0, min(59, newValue))
                guard minute != clamped else { return }
                minute = clamped
            }
        )
    }

    private var meridiemBinding: Binding<String> {
        Binding(
            get: { meridiem },
            set: { newValue in
                guard meridiems.contains(newValue), meridiem != newValue else { return }
                meridiem = newValue
            }
        )
    }
    
    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "clock.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(LGradients.header)
                
                Text(formattedPreview)
                    .font(.system(size: 18, weight: .black, design: .rounded))
                    .foregroundStyle(LColors.textPrimary)
                
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background {
                LureliaNeutralGlassSurface(cornerRadius: 16, prominence: .lens)
            }
            
            ZStack {
                LureliaNeutralGlassSurface(cornerRadius: 24)
                
                VStack(spacing: 0) {
                    Spacer()
                    
                    LureliaNeutralGlassSurface(cornerRadius: 12, prominence: .active)
                        .frame(height: 38)
                    
                    Spacer()
                }
                .padding(.horizontal, 12)
                
                HStack(spacing: 6) {
                    LureliaDrumPickerColumn(
                        values: Array(1...12),
                        labels: Array(1...12).map { "\($0)" },
                        selection: displayHourBinding
                    )
                    .frame(maxWidth: .infinity)
                    .frame(height: 120)
                    .clipped()

                    Text(":")
                        .font(.system(size: 24, weight: .black, design: .rounded))
                        .foregroundStyle(LGradients.header)

                    LureliaDrumPickerColumn(
                        values: Array(0..<60),
                        labels: Array(0..<60).map { String(format: "%02d", $0) },
                        selection: minuteBinding
                    )
                    .frame(maxWidth: .infinity)
                    .frame(height: 120)
                    .clipped()

                    LureliaDrumPickerColumn(
                        values: meridiems,
                        labels: meridiems,
                        selection: meridiemBinding
                    )
                    .frame(maxWidth: .infinity)
                    .frame(height: 120)
                    .clipped()
                }
                .padding(.horizontal, 8)
            }
            .frame(height: 138)
        }
        .onAppear {
            syncDisplayValuesFromStoredHour()
        }
        .onChange(of: displayHour) { _, _ in
            syncStoredHour()
        }
        .onChange(of: meridiem) { _, _ in
            syncStoredHour()
        }
        .onChange(of: hour) { _, _ in
            syncDisplayValuesFromStoredHour()
        }
    }
    
    private func syncDisplayValuesFromStoredHour() {
        let normalizedHour = max(0, min(23, hour))
        let newDisplayHour: Int
        let newMeridiem: String

        if normalizedHour == 0 {
            newDisplayHour = 12
            newMeridiem = "AM"
        } else if normalizedHour < 12 {
            newDisplayHour = normalizedHour
            newMeridiem = "AM"
        } else if normalizedHour == 12 {
            newDisplayHour = 12
            newMeridiem = "PM"
        } else {
            newDisplayHour = normalizedHour - 12
            newMeridiem = "PM"
        }

        guard displayHour != newDisplayHour || meridiem != newMeridiem else { return }

        displayHour = newDisplayHour
        meridiem = newMeridiem
    }

    private func syncStoredHour() {
        let newHour: Int
        if meridiem == "AM" {
            newHour = displayHour == 12 ? 0 : displayHour
        } else {
            newHour = displayHour == 12 ? 12 : displayHour + 12
        }

        guard hour != newHour else { return }
        hour = newHour
    }
}

// MARK: - Tinted Time Drum Picker (Routine Tint)

struct LureliaTintedTimeDrumPicker: View {
    @Binding var hour: Int
    @Binding var minute: Int
    let tint: Color

    @State private var displayHour: Int = 9
    @State private var meridiem: String = "AM"

    private let meridiems = ["AM", "PM"]

    private var formattedPreview: String {
        String(format: "%d:%02d %@", displayHour, minute, meridiem)
    }

    private var displayHourBinding: Binding<Int> {
        Binding(
            get: { displayHour },
            set: { newValue in
                let clamped = max(1, min(12, newValue))
                guard displayHour != clamped else { return }
                displayHour = clamped
            }
        )
    }

    private var minuteBinding: Binding<Int> {
        Binding(
            get: { max(0, min(59, minute)) },
            set: { newValue in
                let clamped = max(0, min(59, newValue))
                guard minute != clamped else { return }
                minute = clamped
            }
        )
    }

    private var meridiemBinding: Binding<String> {
        Binding(
            get: { meridiem },
            set: { newValue in
                guard meridiems.contains(newValue), meridiem != newValue else { return }
                meridiem = newValue
            }
        )
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "clock.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(tint)

                Text(formattedPreview)
                    .font(.system(size: 18, weight: .black, design: .rounded))
                    .foregroundStyle(LColors.textPrimary)

                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                LColors.glassSurface2,
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(tint.opacity(0.45), lineWidth: 1)
            )

            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(LColors.glassSurface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(tint.opacity(0.08))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .strokeBorder(LColors.glassBorder, lineWidth: 1)
                    )

                VStack(spacing: 0) {
                    Spacer()

                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(tint.opacity(0.20))
                        .frame(height: 38)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(tint.opacity(0.55), lineWidth: 1)
                        )

                    Spacer()
                }
                .padding(.horizontal, 12)

                HStack(spacing: 6) {
                    LureliaDrumPickerColumn(
                        values: Array(1...12),
                        labels: Array(1...12).map { "\($0)" },
                        selection: displayHourBinding
                    )
                    .frame(maxWidth: .infinity)
                    .frame(height: 120)
                    .clipped()

                    Text(":")
                        .font(.system(size: 24, weight: .black, design: .rounded))
                        .foregroundStyle(tint)

                    LureliaDrumPickerColumn(
                        values: Array(0..<60),
                        labels: Array(0..<60).map { String(format: "%02d", $0) },
                        selection: minuteBinding
                    )
                    .frame(maxWidth: .infinity)
                    .frame(height: 120)
                    .clipped()

                    LureliaDrumPickerColumn(
                        values: meridiems,
                        labels: meridiems,
                        selection: meridiemBinding
                    )
                    .frame(maxWidth: .infinity)
                    .frame(height: 120)
                    .clipped()
                }
                .padding(.horizontal, 8)
            }
            .frame(height: 138)
        }
        .onAppear {
            syncDisplayValuesFromStoredHour()
        }
        .onChange(of: displayHour) { _, _ in
            syncStoredHour()
        }
        .onChange(of: meridiem) { _, _ in
            syncStoredHour()
        }
        .onChange(of: hour) { _, _ in
            syncDisplayValuesFromStoredHour()
        }
    }

    private func syncDisplayValuesFromStoredHour() {
        let normalizedHour = max(0, min(23, hour))
        let newDisplayHour: Int
        let newMeridiem: String

        if normalizedHour == 0 {
            newDisplayHour = 12
            newMeridiem = "AM"
        } else if normalizedHour < 12 {
            newDisplayHour = normalizedHour
            newMeridiem = "AM"
        } else if normalizedHour == 12 {
            newDisplayHour = 12
            newMeridiem = "PM"
        } else {
            newDisplayHour = normalizedHour - 12
            newMeridiem = "PM"
        }

        guard displayHour != newDisplayHour || meridiem != newMeridiem else { return }

        displayHour = newDisplayHour
        meridiem = newMeridiem
    }

    private func syncStoredHour() {
        let newHour: Int
        if meridiem == "AM" {
            newHour = displayHour == 12 ? 0 : displayHour
        } else {
            newHour = displayHour == 12 ? 12 : displayHour + 12
        }

        guard hour != newHour else { return }
        hour = newHour
    }
}

// MARK: - Pure SwiftUI Drum Picker Column

private struct LureliaDrumPickerColumn<Value: Hashable>: View {
    let values: [Value]
    let labels: [String]
    @Binding var selection: Value

    private let itemHeight: CGFloat = 38

    @State private var dragOffset: CGFloat = 0
    @State private var baseOffset: CGFloat = 0
    @State private var isDragging = false

    private var selectedIndex: Int {
        values.firstIndex(of: selection) ?? 0
    }

    private var totalOffset: CGFloat {
        baseOffset + dragOffset
    }

    private var currentIndex: Int {
        let raw = -totalOffset / itemHeight
        return max(0, min(values.count - 1, Int(raw.rounded())))
    }

    var body: some View {
        GeometryReader { geo in
            let centerY = (geo.size.height - itemHeight) / 2

            ZStack {
                ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                    let offsetY = centerY + CGFloat(index) * itemHeight + totalOffset
                    let distanceFromCenter = abs(offsetY - centerY)
                    let normalized = max(0, 1 - distanceFromCenter / (itemHeight * 1.5))

                    Text(labels.indices.contains(index) ? labels[index] : "")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.3 + 0.65 * normalized))
                        .scaleEffect(0.85 + 0.2 * normalized)
                        .frame(height: itemHeight)
                        .frame(maxWidth: .infinity)
                        .offset(y: offsetY)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        isDragging = true
                        dragOffset = value.translation.height
                    }
                    .onEnded { value in
                        isDragging = false
                        let velocity = value.predictedEndTranslation.height - value.translation.height
                        let projected = totalOffset + velocity * 0.3
                        let rawIndex = -projected / itemHeight
                        let snapped = max(0, min(values.count - 1, Int(rawIndex.rounded())))
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            baseOffset = -CGFloat(snapped) * itemHeight
                            dragOffset = 0
                        }
                        if values.indices.contains(snapped) {
                            selection = values[snapped]
                        }
                    }
            )
            .onAppear {
                baseOffset = -CGFloat(selectedIndex) * itemHeight
            }
            .onChange(of: selection) { _, _ in
                guard !isDragging else { return }
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    baseOffset = -CGFloat(selectedIndex) * itemHeight
                    dragOffset = 0
                }
            }
        }
    }
}

// MARK: - Completion Banner

struct LureliaCompletionBanner: View {
    let message: String
    var isShowing: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image("checkwavy")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 14, height: 14)
                .foregroundStyle(.white)

            Text(message)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(LColors.textPrimary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background { LureliaNeutralGlassSurface(cornerRadius: 999) }
        .opacity(isShowing ? 1 : 0)
        .offset(y: isShowing ? 0 : -20)
        .animation(.spring(response: 0.38, dampingFraction: 0.72), value: isShowing)
    }
}

extension View {
    func completionBanner(isShowing: Bool, message: String = "Done!") -> some View {
        self.overlay(alignment: .top) {
            LureliaCompletionBanner(message: message, isShowing: isShowing)
                .padding(.top, 16)
                .zIndex(999)
        }
    }
}

// MARK: - Gradient Date Drum Picker

/// Three-drum (Month / Day / Year) date picker in the same gradient style
/// as `LureliaGradientTimeDrumPicker`. Time-of-day components on the bound
/// `Date` are preserved — only year/month/day are edited.
struct LureliaGradientDateDrumPicker: View {
    @Binding var date: Date

    @State private var year: Int
    @State private var month: Int
    @State private var day: Int

    private let calendar = Calendar.current

    private let monthShortLabels = [
        "Jan", "Feb", "Mar", "Apr", "May", "Jun",
        "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"
    ]

    private static let referenceYear = Calendar.current.component(.year, from: Date())
    private let yearRange: [Int] = Array((referenceYear - 5)...(referenceYear + 20))

    init(date: Binding<Date>) {
        self._date = date
        let comps = Calendar.current.dateComponents([.year, .month, .day], from: date.wrappedValue)
        _year = State(initialValue: comps.year ?? LureliaGradientDateDrumPicker.referenceYear)
        _month = State(initialValue: comps.month ?? 1)
        _day = State(initialValue: comps.day ?? 1)
    }

    private var daysInMonth: Int {
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        guard let firstOfMonth = calendar.date(from: comps),
              let range = calendar.range(of: .day, in: .month, for: firstOfMonth)
        else { return 31 }
        return range.count
    }

    private var monthBinding: Binding<Int> {
        Binding(
            get: { month },
            set: { newValue in
                let clamped = max(1, min(12, newValue))
                guard month != clamped else { return }
                month = clamped
            }
        )
    }

    private var dayBinding: Binding<Int> {
        Binding(
            get: { min(day, daysInMonth) },
            set: { newValue in
                let clamped = max(1, min(daysInMonth, newValue))
                guard day != clamped else { return }
                day = clamped
            }
        )
    }

    private var yearBinding: Binding<Int> {
        Binding(
            get: { year },
            set: { newValue in
                guard yearRange.contains(newValue), year != newValue else { return }
                year = newValue
            }
        )
    }

    private var formattedPreview: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMM d, yyyy"
        return formatter.string(from: date)
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "calendar")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(LGradients.header)

                Text(formattedPreview)
                    .font(.system(size: 18, weight: .black, design: .rounded))
                    .foregroundStyle(LColors.textPrimary)

                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background {
                LureliaNeutralGlassSurface(cornerRadius: 16, prominence: .lens)
            }

            ZStack {
                LureliaNeutralGlassSurface(cornerRadius: 24)

                VStack(spacing: 0) {
                    Spacer()

                    LureliaNeutralGlassSurface(cornerRadius: 12, prominence: .active)
                        .frame(height: 38)

                    Spacer()
                }
                .padding(.horizontal, 12)

                HStack(spacing: 6) {
                    LureliaDrumPickerColumn(
                        values: Array(1...12),
                        labels: monthShortLabels,
                        selection: monthBinding
                    )
                    .frame(maxWidth: .infinity)
                    .frame(height: 120)
                    .clipped()

                    LureliaDrumPickerColumn(
                        values: Array(1...daysInMonth),
                        labels: Array(1...daysInMonth).map { "\($0)" },
                        selection: dayBinding
                    )
                    .frame(maxWidth: .infinity)
                    .frame(height: 120)
                    .clipped()

                    LureliaDrumPickerColumn(
                        values: yearRange,
                        labels: yearRange.map { "\($0)" },
                        selection: yearBinding
                    )
                    .frame(maxWidth: .infinity)
                    .frame(height: 120)
                    .clipped()
                }
                .padding(.horizontal, 8)
            }
            .frame(height: 138)
        }
        .onChange(of: month) { _, _ in syncDateFromDrums() }
        .onChange(of: day) { _, _ in syncDateFromDrums() }
        .onChange(of: year) { _, _ in syncDateFromDrums() }
        .onChange(of: date) { _, newValue in syncDrumsFromDate(newValue) }
    }

    private func syncDateFromDrums() {
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = min(day, daysInMonth)

        let timeComps = calendar.dateComponents([.hour, .minute, .second], from: date)
        comps.hour = timeComps.hour
        comps.minute = timeComps.minute
        comps.second = timeComps.second

        guard let newDate = calendar.date(from: comps), newDate != date else { return }
        date = newDate
    }

    private func syncDrumsFromDate(_ newDate: Date) {
        let comps = calendar.dateComponents([.year, .month, .day], from: newDate)
        if let newYear = comps.year, newYear != year { year = newYear }
        if let newMonth = comps.month, newMonth != month { month = newMonth }
        if let newDay = comps.day, newDay != day { day = newDay }
    }
}

// MARK: - Tinted Date Drum Picker (Routine Tint)

/// Three-drum (Month / Day / Year) date picker using a caller-provided tint.
/// Time-of-day components on the bound `Date` are preserved.
struct LureliaTintedDateDrumPicker: View {
    @Binding var date: Date
    let tint: Color
    let minimumDate: Date?
    let maximumDate: Date?

    @State private var year: Int
    @State private var month: Int
    @State private var day: Int

    private let calendar = Calendar.current

    private let monthShortLabels = [
        "Jan", "Feb", "Mar", "Apr", "May", "Jun",
        "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"
    ]

    private static let referenceYear = Calendar.current.component(.year, from: Date())

    init(
        date: Binding<Date>,
        tint: Color,
        minimumDate: Date? = nil,
        maximumDate: Date? = nil
    ) {
        self._date = date
        self.tint = tint
        self.minimumDate = minimumDate
        self.maximumDate = maximumDate

        let clampedDate = LureliaTintedDateDrumPicker.clamped(
            date.wrappedValue,
            minimumDate: minimumDate,
            maximumDate: maximumDate,
            calendar: .current
        )
        let comps = Calendar.current.dateComponents([.year, .month, .day], from: clampedDate)
        _year = State(initialValue: comps.year ?? LureliaTintedDateDrumPicker.referenceYear)
        _month = State(initialValue: comps.month ?? 1)
        _day = State(initialValue: comps.day ?? 1)
    }

    private var minimumDay: Date? {
        minimumDate.map { calendar.startOfDay(for: $0) }
    }

    private var maximumDay: Date? {
        maximumDate.map { calendar.startOfDay(for: $0) }
    }

    private var yearRange: [Int] {
        let minYear = minimumDay.map { calendar.component(.year, from: $0) } ?? Self.referenceYear - 5
        let maxYear = maximumDay.map { calendar.component(.year, from: $0) } ?? Self.referenceYear + 20
        return Array(minYear...max(minYear, maxYear))
    }

    private var monthValues: [Int] {
        guard let firstYear = yearRange.first,
              let lastYear = yearRange.last else {
            return Array(1...12)
        }

        var lower = 1
        var upper = 12

        if year == firstYear,
           let minimumDay {
            lower = max(lower, calendar.component(.month, from: minimumDay))
        }

        if year == lastYear,
           let maximumDay {
            upper = min(upper, calendar.component(.month, from: maximumDay))
        }

        return lower <= upper ? Array(lower...upper) : [lower]
    }

    private var daysInMonth: Int {
        var comps = DateComponents()
        comps.year = clampedYear(year)
        comps.month = clampedMonth(month)
        guard let firstOfMonth = calendar.date(from: comps),
              let range = calendar.range(of: .day, in: .month, for: firstOfMonth)
        else { return 31 }
        return range.count
    }

    private var dayValues: [Int] {
        let selectedYear = clampedYear(year)
        let selectedMonth = clampedMonth(month)

        var lower = 1
        var upper = daysInMonth

        if let minimumDay,
           calendar.component(.year, from: minimumDay) == selectedYear,
           calendar.component(.month, from: minimumDay) == selectedMonth {
            lower = max(lower, calendar.component(.day, from: minimumDay))
        }

        if let maximumDay,
           calendar.component(.year, from: maximumDay) == selectedYear,
           calendar.component(.month, from: maximumDay) == selectedMonth {
            upper = min(upper, calendar.component(.day, from: maximumDay))
        }

        return lower <= upper ? Array(lower...upper) : [lower]
    }

    private var monthLabels: [String] {
        monthValues.map { month in
            monthShortLabels.indices.contains(month - 1) ? monthShortLabels[month - 1] : "\(month)"
        }
    }

    private var yearBinding: Binding<Int> {
        Binding(
            get: { clampedYear(year) },
            set: { newValue in
                let clamped = clampedYear(newValue)
                guard year != clamped else { return }
                year = clamped
            }
        )
    }

    private var monthBinding: Binding<Int> {
        Binding(
            get: { clampedMonth(month) },
            set: { newValue in
                let clamped = clampedMonth(newValue)
                guard month != clamped else { return }
                month = clamped
            }
        )
    }

    private var dayBinding: Binding<Int> {
        Binding(
            get: { clampedDay(day) },
            set: { newValue in
                let clamped = clampedDay(newValue)
                guard day != clamped else { return }
                day = clamped
            }
        )
    }

    private var formattedPreview: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMM d, yyyy"
        return formatter.string(from: date)
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Image("starcal")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 13, height: 13)
                    .foregroundStyle(tint)

                Text(formattedPreview)
                    .font(.system(size: 18, weight: .black, design: .rounded))
                    .foregroundStyle(LColors.textPrimary)

                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                LColors.glassSurface2,
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(tint.opacity(0.45), lineWidth: 1)
            )

            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(LColors.glassSurface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(tint.opacity(0.08))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .strokeBorder(LColors.glassBorder, lineWidth: 1)
                    )

                VStack(spacing: 0) {
                    Spacer()

                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(tint.opacity(0.20))
                        .frame(height: 38)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(tint.opacity(0.55), lineWidth: 1)
                        )

                    Spacer()
                }
                .padding(.horizontal, 12)

                HStack(spacing: 6) {
                    LureliaDrumPickerColumn(
                        values: monthValues,
                        labels: monthLabels,
                        selection: monthBinding
                    )
                    .frame(maxWidth: .infinity)
                    .frame(height: 120)
                    .clipped()

                    LureliaDrumPickerColumn(
                        values: dayValues,
                        labels: dayValues.map { "\($0)" },
                        selection: dayBinding
                    )
                    .frame(maxWidth: .infinity)
                    .frame(height: 120)
                    .clipped()

                    LureliaDrumPickerColumn(
                        values: yearRange,
                        labels: yearRange.map { "\($0)" },
                        selection: yearBinding
                    )
                    .frame(maxWidth: .infinity)
                    .frame(height: 120)
                    .clipped()
                }
                .padding(.horizontal, 8)
            }
            .frame(height: 138)
        }
        .onAppear {
            syncDrumsFromDate(date)
        }
        .onChange(of: month) { _, _ in syncDateFromDrums() }
        .onChange(of: day) { _, _ in syncDateFromDrums() }
        .onChange(of: year) { _, _ in syncDateFromDrums() }
        .onChange(of: date) { _, newValue in syncDrumsFromDate(newValue) }
    }

    private func clampedYear(_ value: Int) -> Int {
        guard let first = yearRange.first,
              let last = yearRange.last else {
            return value
        }
        return max(first, min(last, value))
    }

    private func clampedMonth(_ value: Int) -> Int {
        guard let first = monthValues.first,
              let last = monthValues.last else {
            return value
        }
        return max(first, min(last, value))
    }

    private func clampedDay(_ value: Int) -> Int {
        guard let first = dayValues.first,
              let last = dayValues.last else {
            return value
        }
        return max(first, min(last, value))
    }

    private func syncDateFromDrums() {
        let nextYear = clampedYear(year)
        let nextMonth = clampedMonth(month)
        let nextDay = clampedDay(day)

        if year != nextYear { year = nextYear }
        if month != nextMonth { month = nextMonth }
        if day != nextDay { day = nextDay }

        var comps = DateComponents()
        comps.year = nextYear
        comps.month = nextMonth
        comps.day = nextDay

        let timeComps = calendar.dateComponents([.hour, .minute, .second], from: date)
        comps.hour = timeComps.hour
        comps.minute = timeComps.minute
        comps.second = timeComps.second

        guard let newDate = calendar.date(from: comps) else { return }
        let clampedDate = Self.clamped(
            newDate,
            minimumDate: minimumDate,
            maximumDate: maximumDate,
            calendar: calendar
        )

        guard clampedDate != date else { return }
        date = clampedDate
    }

    private func syncDrumsFromDate(_ newDate: Date) {
        let clampedDate = Self.clamped(
            newDate,
            minimumDate: minimumDate,
            maximumDate: maximumDate,
            calendar: calendar
        )

        if clampedDate != date {
            date = clampedDate
            return
        }

        let comps = calendar.dateComponents([.year, .month, .day], from: clampedDate)
        if let newYear = comps.year, newYear != year { year = newYear }
        if let newMonth = comps.month, newMonth != month { month = newMonth }
        if let newDay = comps.day, newDay != day { day = newDay }
    }

    private static func clamped(
        _ date: Date,
        minimumDate: Date?,
        maximumDate: Date?,
        calendar: Calendar
    ) -> Date {
        let day = calendar.startOfDay(for: date)
        let minimumDay = minimumDate.map { calendar.startOfDay(for: $0) }
        let maximumDay = maximumDate.map { calendar.startOfDay(for: $0) }

        if let minimumDay, day < minimumDay {
            return minimumDay
        }

        if let maximumDay, day > maximumDay {
            return maximumDay
        }

        return date
    }
}

// MARK: - Gradient Dropdown

/// Fully custom dropdown menu in the Lurelia style. Adapts to any size —
/// place it inside a `GlassCard`, a `HStack`, or on its own. The row is a
/// tappable label; tapping expands an inline options list below it (no
/// system menu / picker UI). Set `allowsClear: true` to let the user reset
/// to `nil`.
struct LureliaGradientDropdown<Value: Hashable>: View {
    var placeholder: String = "Select"
    var options: [Value]
    @Binding var selection: Value?
    var allowsClear: Bool = false
    var label: (Value) -> String

    @State private var isExpanded = false

    var body: some View {
        VStack(spacing: 8) {
            Button {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 10) {
                    Text(selection.map(label) ?? placeholder)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(selection == nil ? Color.white.opacity(0.45) : Color.white)
                        .lineLimit(1)

                    Spacer(minLength: 8)

                    Image("chevdown")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 14, height: 14)
                        .foregroundStyle(LGradients.header)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background {
                    LureliaNeutralGlassSurface(
                        cornerRadius: 14,
                        prominence: isExpanded ? .active : .lens
                    )
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(spacing: 4) {
                    if allowsClear && selection != nil {
                        optionRow(nil, labelText: "Clear")
                    }
                    ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                        optionRow(option, labelText: label(option))
                    }
                }
                .padding(6)
                .background {
                    LureliaNeutralGlassSurface(cornerRadius: 14)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    @ViewBuilder
    private func optionRow(_ value: Value?, labelText: String) -> some View {
        let isSelected = value == selection
        Button {
            selection = value
            withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                isExpanded = false
            }
        } label: {
            HStack(spacing: 10) {
                Image(isSelected ? "checkwavy" : "chevright")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 14, height: 14)
                    .foregroundStyle(
                        isSelected
                        ? AnyShapeStyle(LGradients.header)
                        : AnyShapeStyle(Color.white.opacity(0.35))
                    )

                Text(labelText)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Spacer(minLength: 4)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .background {
                if isSelected {
                    LureliaNeutralGlassSurface(cornerRadius: 10, prominence: .active)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Gradient Multi-Select Dropdown

/// Multi-select twin of `LureliaGradientDropdown`. Same trigger + expanded
/// panel styling — the only differences are that the trigger summarizes the
/// current selection ("None", "Family", or "3 selected") and each option
/// row toggles membership in a `Set<Value>` rather than replacing a single
/// `Value?`. Options can be filtered per-render via `optionsFilter` so the
/// caller can e.g. hide the currently-selected Primary Calendar without
/// mutating the `options` array itself.
struct LureliaGradientMultiSelectDropdown<Value: Hashable & Identifiable>: View {
    let placeholder: String
    let options: [Value]
    @Binding var selection: Set<Value.ID>
    var label: (Value) -> String
    /// Return `true` to include the option in the panel. Default: include all.
    var optionsFilter: (Value) -> Bool = { _ in true }

    @State private var isExpanded = false

    private var visibleOptions: [Value] {
        options.filter(optionsFilter)
    }

    private var selectedOptions: [Value] {
        visibleOptions.filter { selection.contains($0.id) }
    }

    private var triggerText: String {
        let count = selectedOptions.count
        switch count {
        case 0: return placeholder
        case 1: return label(selectedOptions[0])
        default: return "\(count) selected"
        }
    }

    private var triggerIsPlaceholder: Bool {
        selectedOptions.isEmpty
    }

    var body: some View {
        VStack(spacing: 8) {
            Button {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 10) {
                    Text(triggerText)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(triggerIsPlaceholder ? Color.white.opacity(0.45) : Color.white)
                        .lineLimit(1)

                    Spacer(minLength: 8)

                    Image("chevdown")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 14, height: 14)
                        .foregroundStyle(LGradients.header)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background {
                    LureliaNeutralGlassSurface(
                        cornerRadius: 14,
                        prominence: isExpanded ? .active : .lens
                    )
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(spacing: 4) {
                    if visibleOptions.isEmpty {
                        Text("No calendars available")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.55))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 10)
                    } else {
                        ForEach(visibleOptions) { option in
                            multiOptionRow(option, labelText: label(option))
                        }
                    }
                }
                .padding(6)
                .background {
                    LureliaNeutralGlassSurface(cornerRadius: 14)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    @ViewBuilder
    private func multiOptionRow(_ value: Value, labelText: String) -> some View {
        let isSelected = selection.contains(value.id)
        Button {
            if isSelected {
                selection.remove(value.id)
            } else {
                selection.insert(value.id)
            }
            // No auto-close: multi-select users usually want to pick more
            // than one in a row.
        } label: {
            HStack(spacing: 10) {
                Image(isSelected ? "checkwavy" : "chevright")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 14, height: 14)
                    .foregroundStyle(
                        isSelected
                        ? AnyShapeStyle(LGradients.header)
                        : AnyShapeStyle(Color.white.opacity(0.35))
                    )

                Text(labelText)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Spacer(minLength: 4)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .background {
                if isSelected {
                    LureliaNeutralGlassSurface(cornerRadius: 10, prominence: .active)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Flow Layout

/// Simple left-to-right flow layout: places variable-width subviews in a
/// row, and wraps to a new row when the next one wouldn't fit. Used by the
/// icon picker's category tabs so they wrap to new lines instead of
/// scrolling horizontally.
struct LureliaFlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var maxRowWidthSeen: CGFloat = 0
        var isFirstInRow = true

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let addWidth = isFirstInRow ? size.width : size.width + spacing

            if !isFirstInRow, rowWidth + addWidth > maxWidth {
                // wrap
                totalHeight += rowHeight + lineSpacing
                maxRowWidthSeen = max(maxRowWidthSeen, rowWidth)
                rowWidth = size.width
                rowHeight = size.height
            } else {
                rowWidth += addWidth
                rowHeight = max(rowHeight, size.height)
            }
            isFirstInRow = false
        }

        totalHeight += rowHeight
        maxRowWidthSeen = max(maxRowWidthSeen, rowWidth)
        let width = maxWidth.isFinite ? maxWidth : maxRowWidthSeen
        return CGSize(width: width, height: totalHeight)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let maxWidth = bounds.width
        var x: CGFloat = bounds.minX
        var y: CGFloat = bounds.minY
        var rowHeight: CGFloat = 0
        var isFirstInRow = true

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let addWidth = isFirstInRow ? size.width : size.width + spacing

            if !isFirstInRow, (x - bounds.minX) + addWidth > maxWidth {
                // wrap
                y += rowHeight + lineSpacing
                x = bounds.minX
                rowHeight = 0
                isFirstInRow = true
            }

            if !isFirstInRow { x += spacing }

            subview.place(
                at: CGPoint(x: x, y: y),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: size.width, height: size.height)
            )
            x += size.width
            rowHeight = max(rowHeight, size.height)
            isFirstInRow = false
        }
    }
}

// MARK: - Frosty Tile

/// Companion to `GlassCard`. Used inside cards, grids, and compact groups as a
/// quieter secondary glass lens.
struct FrostyTile<Content: View>: View {
    var cornerRadius: CGFloat = 18
    var padding: CGFloat = 14
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                LureliaNeutralGlassSurface(cornerRadius: cornerRadius, prominence: .lens)
            }
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        LureliaBackground()

        Text("Lurelia")
            .font(.system(size: 42, weight: .black, design: .rounded))
            .foregroundStyle(LGradients.header)
    }
}
