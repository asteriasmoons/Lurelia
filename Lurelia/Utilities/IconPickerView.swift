//
//  IconPickerView.swift
//  Lurelia
//

import SwiftUI
import UIKit

// MARK: - Icon Picker Sheet

struct IconPickerView: View {
    @Binding var selectedIcon: String
    var dismissesOnSelection = false
    var allowedSources: [LureliaIconSource] = LureliaIconSource.allCases
    var onSelection: ((String) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var theme

    @State private var searchText = ""
    @State private var selectedCategory = ""
    @State private var categoryDropdownExpanded = false

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var availableIcons: [LureliaIconItem] {
        LureliaIconLibrary.allIcons.filter { allowedSources.contains($0.source) }
    }

    private var categories: [String] {
        Array(Set(availableIcons.map(\.category))).sorted()
    }

    private var activeCategory: String {
        if categories.contains(selectedCategory) {
            return selectedCategory
        }

        return categories.first ?? ""
    }

    private var visibleIcons: [LureliaIconItem] {
        let icons = isSearching
            ? searchAvailableIcons(searchText)
            : availableIcons.filter { $0.category == activeCategory }

        return Array(
            icons
                .sorted {
                    if $0.category != $1.category {
                        return $0.category < $1.category
                    }

                    return $0.name < $1.name
                }
                .prefix(300)
        )
    }

    private var resultCountText: String {
        if isSearching {
            return "\(visibleIcons.count) result\(visibleIcons.count == 1 ? "" : "s")"
        }

        return "\(visibleIcons.count) icon\(visibleIcons.count == 1 ? "" : "s")"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                theme.palette.background
                    .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 18, pinnedViews: []) {
                        searchField

                        if !isSearching {
                            categoryDropdown
                        }

                        HStack {
                            Text(isSearching ? "Search Results" : activeCategory)
                                .font(.system(size: 13, weight: .black, design: .rounded))
                                .foregroundStyle(theme.palette.textSecondary)

                            Spacer()

                            Text(resultCountText)
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundStyle(theme.palette.textSecondary.opacity(0.62))
                        }

                        LazyVGrid(
                            columns: [
                                GridItem(.adaptive(minimum: 44, maximum: 50), spacing: 10)
                            ],
                            spacing: 10
                        ) {
                            ForEach(visibleIcons) { icon in
                                Button {
                                    selectedIcon = icon.name
                                    onSelection?(icon.name)

                                    if dismissesOnSelection {
                                        dismiss()
                                    }
                                } label: {
                                    iconCell(icon)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .id(isSearching ? "search-\(searchText)" : activeCategory)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 16)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle("Choose Icon")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(theme.palette.primaryAction)
                }
            }
            .onAppear {
                normalizeSelectedCategory()
            }
            .onChange(of: categories) { _, _ in
                normalizeSelectedCategory()
            }
        }
    }

    // MARK: - Search Field

    private var searchField: some View {
        HStack(spacing: 10) {
            Image("searchwavy")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 16, height: 16)
                .foregroundStyle(theme.palette.primaryAction)
                .bubblyIconMaterial(tint: theme.palette.primaryAction)

            TextField("Search icons", text: $searchText)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(theme.palette.textPrimary)
                .tint(theme.palette.primaryAction)
        }
        .padding(.horizontal, 14)
        .frame(height: 50)
        .background(theme.palette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(theme.palette.primaryAction, lineWidth: 1)
        }
    }

    // MARK: - Custom Collapsible Category Dropdown

    private var categoryDropdown: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                    categoryDropdownExpanded.toggle()
                }
            } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("CATEGORY")
                            .font(.system(size: 10, weight: .black, design: .rounded))
                            .foregroundStyle(Color.black.opacity(0.62))

                        Text(activeCategory.isEmpty ? "All" : activeCategory)
                            .font(.system(size: 15, weight: .black, design: .rounded))
                            .foregroundStyle(.black)
                    }

                    Spacer()

                    Image(categoryDropdownExpanded ? "chevup" : "chevdown")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 14, height: 14)
                        .foregroundStyle(.black)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
                .background {
                    BubblyCardMaterial(
                        tint: theme.palette.primaryAction,
                        cornerRadius: LSpacing.cardRadius
                    )
                }
                .overlay(
                    RoundedRectangle(cornerRadius: LSpacing.cardRadius, style: .continuous)
                        .strokeBorder(theme.palette.primaryAction, lineWidth: 1)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if categoryDropdownExpanded {
                categoryDropdownList
                    .padding(.top, 8)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var categoryDropdownList: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(spacing: 6) {
                ForEach(categories, id: \.self) { category in
                    let isActive = category == activeCategory

                    HStack(spacing: 10) {
                        Text(category)
                            .font(.system(size: 14, weight: isActive ? .black : .bold, design: .rounded))
                            .foregroundStyle(isActive ? .black : theme.palette.textSecondary)
                            .lineLimit(1)

                        Spacer()

                        if isActive {
                            Image("checkwavy")
                                .renderingMode(.template)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 14, height: 14)
                                .foregroundStyle(.black)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background {
                        if isActive {
                            BubblyIconMaterial(tint: theme.palette.primaryAction)
                                .clipShape(
                                    RoundedRectangle(
                                        cornerRadius: LSpacing.inputRadius,
                                        style: .continuous
                                    )
                                )
                        } else {
                            RoundedRectangle(cornerRadius: LSpacing.inputRadius, style: .continuous)
                                .fill(theme.palette.surface)
                        }
                    }
                    .overlay(
                        RoundedRectangle(cornerRadius: LSpacing.inputRadius, style: .continuous)
                            .strokeBorder(
                                isActive
                                    ? theme.palette.primaryAction
                                    : theme.palette.textPrimary.opacity(0.12),
                                lineWidth: 1
                            )
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.spring(response: 0.24, dampingFraction: 0.86)) {
                            selectedCategory = category
                            categoryDropdownExpanded = false
                        }
                    }
                }
            }
            .padding(10)
        }
        .frame(maxHeight: 220)
        .background {
            BubblyCardMaterial(
                tint: theme.palette.primaryAction,
                cornerRadius: LSpacing.cardRadius
            )
        }
        .overlay(
            RoundedRectangle(cornerRadius: LSpacing.cardRadius, style: .continuous)
                .strokeBorder(theme.palette.primaryAction, lineWidth: 1)
        )
    }

    // MARK: - Icon Cell

    private func iconCell(_ icon: LureliaIconItem) -> some View {
        let isSelected = selectedIcon == icon.name

        return LureliaIconGlyph(icon: icon, size: 18)
            .foregroundStyle(theme.palette.primaryAction)
            .bubblyIconMaterial(tint: theme.palette.primaryAction)
            .frame(width: 44, height: 44)
            .background(
                isSelected ? theme.palette.raisedSurface : theme.palette.surface,
                in: RoundedRectangle(cornerRadius: LSpacing.inputRadius)
            )
            .overlay {
                RoundedRectangle(cornerRadius: LSpacing.inputRadius)
                    .strokeBorder(
                        isSelected
                            ? theme.palette.primaryAction
                            : theme.palette.textPrimary.opacity(0.12),
                        lineWidth: isSelected ? 1.5 : 1
                    )
            }
            .contentShape(RoundedRectangle(cornerRadius: LSpacing.inputRadius))
    }

    private func normalizeSelectedCategory() {
        if selectedCategory.isEmpty || !categories.contains(selectedCategory) {
            selectedCategory = categories.first ?? ""
        }
    }

    private func searchAvailableIcons(_ query: String) -> [LureliaIconItem] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedQuery.isEmpty else {
            return availableIcons
        }

        return availableIcons.filter {
            $0.name.localizedCaseInsensitiveContains(trimmedQuery)
            || $0.category.localizedCaseInsensitiveContains(trimmedQuery)
        }
    }
}

struct LureliaIconPickerView: View {
    @Binding var selectedIcon: String

    var body: some View {
        IconPickerView(selectedIcon: $selectedIcon, dismissesOnSelection: true)
    }
}

// MARK: - Inline Icon Renderer

struct LureliaIconView: View {
    let iconId: String
    var size: CGFloat = 22

    private var icon: LureliaIconItem? {
        LureliaIconLibrary.icon(named: iconId)
    }

    var body: some View {
        Group {
            if let icon {
                LureliaIconGlyph(icon: icon, size: size)
            } else {
                fallbackIcon
            }
        }
        .frame(width: size, height: size)
    }
}

private struct LureliaIconGlyph: View {
    let icon: LureliaIconItem
    var size: CGFloat

    @ViewBuilder
    var body: some View {
        switch icon.source {
        case .asset:
            if UIImage(named: icon.name) != nil {
                Image(icon.name)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
            } else {
                fallbackIcon
            }

        case .sfSymbol:
            // Legacy source kept for Codable compatibility with previously
            // saved data — never used by the current library.
            fallbackIcon
        }
    }
}

private var fallbackIcon: some View {
    Image("sparkle")
        .renderingMode(.template)
        .resizable()
        .scaledToFit()
}
