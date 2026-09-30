//
//  LureliaAddCalendarSheet.swift
//  Lurelia
//
//  Create or edit a Lurelia calendar (LureliaCalendar). Layout matches
//  the app's other add/edit sheets. Color card offers the fixed palette
//  plus a rainbow "custom" swatch that opens SwiftUI's ColorPicker so the
//  user can dial in any hex.
//

import SwiftData
import SwiftUI
import UIKit

struct LureliaAddCalendarSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appTheme) private var theme

    /// Optional existing calendar. When non-nil the sheet acts as an editor
    /// (title says "Edit Calendar", save updates in place, delete button
    /// appears at the bottom).
    var editing: LureliaCalendar? = nil

    @State private var name = ""
    @State private var colorHex = "#03dbfc"
    @State private var showCustomColorPicker = false

    private let palette = ["#03dbfc", "#7d19f7", "#ff4fb8", "#f7e86b", "#8ce66f", "#ff9c66", "#7aa8ff", "#f2f2f2"]

    private var isEditing: Bool { editing != nil }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var isCustomColor: Bool {
        !palette.contains { $0.caseInsensitiveCompare(colorHex) == .orderedSame }
    }

    private var customColorBinding: Binding<Color> {
        Binding(
            get: { Color(lureliaHex: colorHex) },
            set: { newColor in
                if let hex = newColor.toHex() {
                    colorHex = hex
                }
            }
        )
    }

    var body: some View {
        NavigationStack {
            ZStack {
                theme.palette.background
                    .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        header

                        nameCard
                        colorCard

                        if isEditing {
                            deleteButton
                        }

                        saveButton
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    .padding(.bottom, 60)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationBarBackButtonHidden(true)
            .toolbar(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { dismissKeyboard() }
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                }
            }
            .onAppear { loadIfEditing() }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text(isEditing ? "Edit Calendar" : "New Calendar")
                .font(.system(size: 28, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Spacer()

            Button { dismiss() } label: {
                Image("xmarkwavy")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(LGradients.header)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 4)
    }

    private var nameCard: some View {
        calendarSurface(border: theme.palette.primaryAction) {
            TextField("Calendar name", text: $name)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(theme.palette.textPrimary)
                .textInputAutocapitalization(.words)
        }
    }

    private var colorCard: some View {
        calendarSurface(border: theme.palette.secondaryAccent) {
            VStack(alignment: .leading, spacing: 12) {
                Text("CALENDAR COLOR")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(theme.palette.textSecondary)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 40), spacing: 10)], spacing: 10) {
                    ForEach(palette, id: \.self) { hex in
                        Button {
                            colorHex = hex
                        } label: {
                            Circle()
                                .fill(Color(lureliaHex: hex))
                                .frame(width: 34, height: 34)
                                .overlay(
                                    Circle().strokeBorder(
                                        colorHex.caseInsensitiveCompare(hex) == .orderedSame
                                            ? Color.white
                                            : Color.white.opacity(0.18),
                                        lineWidth: colorHex.caseInsensitiveCompare(hex) == .orderedSame ? 2 : 1
                                    )
                                )
                        }
                        .buttonStyle(.plain)
                    }

                    customColorSwatch
                }
            }
        }
    }

    private var customColorSwatch: some View {
        Button {
            showCustomColorPicker = true
        } label: {
            ZStack {
                // Rainbow decoration
                Circle()
                    .fill(
                        AngularGradient(
                            gradient: Gradient(colors: [
                                .red, .orange, .yellow, .green, .cyan, .blue, .purple, .pink, .red
                            ]),
                            center: .center
                        )
                    )
                    .frame(width: 34, height: 34)

                // If a custom color is in use, show it inset over the rainbow
                if isCustomColor {
                    Circle()
                        .fill(Color(lureliaHex: colorHex))
                        .frame(width: 22, height: 22)
                        .overlay(Circle().strokeBorder(Color.white, lineWidth: 1))
                }

                // Selection ring when the current color is a custom one
                Circle()
                    .strokeBorder(
                        isCustomColor ? Color.white : Color.white.opacity(0.35),
                        lineWidth: isCustomColor ? 2 : 1
                    )
                    .frame(width: 34, height: 34)
            }
            .frame(width: 34, height: 34)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Custom color")
        .sheet(isPresented: $showCustomColorPicker) {
            LureliaSystemColorPickerSheet(color: customColorBinding)
        }
    }

    private var saveButton: some View {
        Button { save() } label: {
            Text(isEditing ? "Save Calendar" : "Create Calendar")
                .font(.system(size: 16, weight: .black, design: .rounded))
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .frame(height: 58)
                .background {
                    BubblyCardMaterial(
                        tint: theme.palette.indicators,
                        cornerRadius: 22
                    )
                }
        }
        .buttonStyle(.plain)
        .disabled(!canSave)
        .opacity(canSave ? 1 : 0.45)
        .padding(.top, 6)
    }

    private var deleteButton: some View {
        Button(role: .destructive) { deleteCalendar() } label: {
            Text("Delete Calendar")
                .font(.system(size: 14, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(theme.palette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(theme.palette.textPrimary.opacity(0.16), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private func calendarSurface<Content: View>(
        border: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .padding(LSpacing.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(theme.palette.surface)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(border, lineWidth: 1)
            }
    }

    private func loadIfEditing() {
        guard let editing else { return }
        name = editing.name
        colorHex = editing.color
    }

    private func save() {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }

        if let editing {
            editing.name = clean
            editing.color = colorHex
        } else {
            let calendar = LureliaCalendar(name: clean, color: colorHex)
            modelContext.insert(calendar)
        }
        try? modelContext.save()
        dismiss()
    }

    private func deleteCalendar() {
        guard let editing else { return }
        modelContext.delete(editing)
        try? modelContext.save()
        dismiss()
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }
}

// MARK: - System color picker sheet

/// Wraps `UIColorPickerViewController` in a sheet-friendly view so tapping
/// the rainbow swatch presents the real system color picker and writes
/// selections straight back into the bound `Color`. Using
/// SwiftUI's `ColorPicker` with `.labelsHidden()` doesn't work here because
/// its hit area is limited to its own small color-well glyph, not the
/// custom swatch we want to render.
struct LureliaSystemColorPickerSheet: UIViewControllerRepresentable {
    @Binding var color: Color

    func makeCoordinator() -> Coordinator {
        Coordinator(color: $color)
    }

    func makeUIViewController(context: Context) -> UIColorPickerViewController {
        let picker = UIColorPickerViewController()
        picker.selectedColor = UIColor(color)
        picker.supportsAlpha = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIColorPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIColorPickerViewControllerDelegate {
        @Binding var color: Color

        init(color: Binding<Color>) {
            self._color = color
        }

        func colorPickerViewControllerDidSelectColor(_ viewController: UIColorPickerViewController) {
            color = Color(uiColor: viewController.selectedColor)
        }

        func colorPickerViewController(
            _ viewController: UIColorPickerViewController,
            didSelect color: UIColor,
            continuously: Bool
        ) {
            self.color = Color(uiColor: color)
        }
    }
}
