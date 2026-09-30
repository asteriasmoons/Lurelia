//
//  ReleaseNotesPage.swift
//  Lurelia
//

import SwiftUI

struct ReleaseNotesPage: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.appTheme) private var theme
    @State private var expandedIDs: Set<String> = [ReleaseNotesCatalog.notes.first?.id ?? ""]

    var body: some View {
        ZStack {
            theme.palette.background
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    topBar
                    introCard

                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(Array(ReleaseNotesCatalog.notes.enumerated()), id: \.element.id) { index, note in
                            releaseNoteCard(note, accentIndex: index)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, horizontalSizeClass == .regular ? 36 : 120)
            }
        }
    }

    private var topBar: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Release Notes")
                    .font(.system(size: 32, weight: .black, design: .rounded))
                    .foregroundStyle(theme.palette.textPrimary)

                Text("Everything new in Lurelia, collected in one place.")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(theme.palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            Button {
                dismiss()
            } label: {
                Image("xmarkwavy")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 20, height: 20)
                    .foregroundStyle(theme.palette.indicators)
                    .bubblyIconMaterial(tint: theme.palette.indicators)
                    .frame(width: 42, height: 42)
                    .background(theme.palette.surface, in: Circle())
                    .overlay {
                        Circle()
                            .strokeBorder(theme.palette.indicators.opacity(0.78), lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
        }
    }

    private var introCard: some View {
        releaseNotesSurface(borderColor: accentColor(for: 0)) {
            HStack(spacing: 14) {
                Image("timebook")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 20, height: 20)
                    .foregroundStyle(theme.palette.indicators)
                    .bubblyIconMaterial(tint: theme.palette.indicators)
                    .frame(width: 42, height: 42)
                    .background(theme.palette.raisedSurface, in: Circle())
                    .overlay {
                        Circle()
                            .strokeBorder(theme.palette.indicators.opacity(0.78), lineWidth: 1)
                    }

                VStack(alignment: .leading, spacing: 4) {
                    Text("What changed")
                        .font(.system(size: 16, weight: .black, design: .rounded))
                        .foregroundStyle(theme.palette.textPrimary)

                    Text("Open any update to see the highlights in Lurelia's glass style.")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(theme.palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
        }
    }

    private func releaseNoteCard(_ note: LureliaReleaseNote, accentIndex: Int) -> some View {
        let isExpanded = expandedIDs.contains(note.id)
        let borderColor = accentColor(for: accentIndex + 1)

        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.84)) {
                toggle(note.id)
            }
        } label: {
            releaseNotesSurface(
                borderColor: borderColor,
                cornerRadius: 20,
                padding: 16
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(note.versionTitle)
                                .font(.system(size: 18, weight: .black, design: .rounded))
                                .foregroundStyle(theme.palette.textPrimary)

                            Text(note.buildTitle)
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundStyle(theme.palette.primaryAction)
                                .bubblyIconMaterial(tint: theme.palette.primaryAction)

                            Text(note.releaseDate)
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundStyle(theme.palette.textSecondary.opacity(0.82))

                            Text(note.headline)
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundStyle(theme.palette.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer(minLength: 0)

                        Image(isExpanded ? "chevup" : "chevdown")
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 14, height: 14)
                            .foregroundStyle(theme.palette.primaryAction)
                            .bubblyIconMaterial(tint: theme.palette.primaryAction)
                    }

                    if isExpanded {
                        VStack(alignment: .leading, spacing: 10) {
                            fullWidthDivider

                            ForEach(Array(note.bullets.enumerated()), id: \.offset) { index, bullet in
                                bulletRow(
                                    bullet,
                                    tint: accentColor(for: index)
                                )
                            }
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
    }

    private var fullWidthDivider: some View {
        GeometryReader { proxy in
            let dotCount = max(Int(proxy.size.width / 8), 1)

            HStack(spacing: 4) {
                ForEach(0..<dotCount, id: \.self) { _ in
                    Circle()
                        .strokeBorder(theme.palette.secondaryAccent, lineWidth: 1)
                        .bubblyIconMaterial(tint: theme.palette.secondaryAccent)
                        .frame(width: 4, height: 4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: 4)
    }

    private func bulletRow(_ text: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(tint)
                .bubblyIconMaterial(tint: tint)
                .frame(width: 8, height: 8)
                .padding(.top, 5)

            Text(text)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(theme.palette.textPrimary.opacity(0.88))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func accentColor(for index: Int) -> Color {
        let rotation = theme.palette.rotation
        guard !rotation.isEmpty else { return theme.palette.primaryAction }
        let normalizedIndex = ((index % rotation.count) + rotation.count) % rotation.count
        return rotation[normalizedIndex]
    }

    private func releaseNotesSurface<Content: View>(
        borderColor: Color,
        cornerRadius: CGFloat = 24,
        padding: CGFloat = LSpacing.cardPadding,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .padding(padding)
            .background(
                theme.palette.surface,
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(borderColor.opacity(0.78), lineWidth: 1)
            }
    }

    private func toggle(_ id: String) {
        if expandedIDs.contains(id) {
            expandedIDs.remove(id)
        } else {
            expandedIDs.insert(id)
        }
    }
}
