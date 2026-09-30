//
//  ScheduleView.swift
//  Lurelia
//

import SwiftUI
import SwiftData

struct KanbanBoardWrapper: Identifiable {
    let id = UUID()
    let board: KanbanBoard
}

struct ScheduleView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appTheme) private var theme

    @Query(sort: \KanbanBoard.sortOrder) private var boards: [KanbanBoard]

    @State private var showCreateBoard = false
    @State private var selectedBoardWrapper: KanbanBoardWrapper?
    @State private var editingBoard: KanbanBoard?

    var body: some View {
        NavigationStack {
            ZStack {
                theme.palette.background
                    .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {

                        // MARK: Header
                        HStack {
                            Text("Kanban")
                                .font(.system(size: 30, weight: .black, design: .rounded))
                                .foregroundStyle(.white)

                            Spacer()

                            Button {
                                showCreateBoard = true
                            } label: {
                                Image("addwavy")
                                    .renderingMode(.template)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 30, height: 30)
                                    .foregroundStyle(theme.palette.indicators)
                                    .bubblyIconMaterial(tint: theme.palette.indicators)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 20)

                        CalendarView()
                            .padding(.bottom, 4)

                        if boards.isEmpty {
                            emptyState
                                .padding(.horizontal, 24)
                                .padding(.top, 40)
                        } else {
                            LazyVStack(spacing: 14) {
                                ForEach(boards) { board in
                                    BoardRowCard(board: board) {
                                        selectedBoardWrapper = KanbanBoardWrapper(board: board)
                                    }
                                    .contextMenu {
                                        Button {
                                            editingBoard = board
                                        } label: {
                                            Label("Edit Board", systemImage: "pencil")
                                        }

                                        Button(role: .destructive) {
                                            deleteBoard(board)
                                        } label: {
                                            Label("Delete Board", systemImage: "trash")
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal, 24)
                        }

                        Spacer().frame(height: 120)
                    }
                    .padding(.bottom, 120)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .sheet(isPresented: $showCreateBoard) {
                CreateBoardView()
            }
            .sheet(item: $editingBoard) { board in
                CreateBoardView(board: board)
            }
            .fullScreenCover(item: $selectedBoardWrapper) { wrapper in
                KanbanBoardView(board: wrapper.board)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image("starcal")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 48, height: 48)
                .foregroundStyle(LGradients.header)

            Text("No Boards Yet")
                .font(.system(size: 21, weight: .bold, design: .rounded))
                .foregroundStyle(LColors.textPrimary)

            Text("Create a board to organize your tasks, reminders, and routines into kanban columns.")
                .font(.system(size: 14, design: .rounded))
                .foregroundStyle(LColors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 18)

            Button {
                showCreateBoard = true
            } label: {
                Text("Create Board")
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .foregroundStyle(LColors.textPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background { LureliaNeutralGlassSurface(cornerRadius: 20) }
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .padding(22)
        .background {
            BubblyCardMaterial(
                tint: theme.palette.surface,
                cornerRadius: 26
            )
        }
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    private func deleteBoard(_ board: KanbanBoard) {
        modelContext.delete(board)
        try? modelContext.save()
    }
}

// MARK: - Board Row Card

struct BoardRowCard: View {
    @Environment(\.appTheme) private var theme

    let board: KanbanBoard
    let onTap: () -> Void

    private var accentColor: Color {
        Color(lureliaHex: board.colorHex)
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Color.black.opacity(0.68))
                        .frame(width: 54, height: 54)

                    BubblyIconMaterial(tint: accentColor)
                        .mask {
                            Circle()
                                .strokeBorder(lineWidth: 1.5)
                        }
                        .frame(width: 54, height: 54)

                    Image(board.icon)
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 28, height: 28)
                        .foregroundStyle(accentColor)
                        .bubblyIconMaterial(tint: accentColor)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(board.name)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(LColors.textPrimary)

                    Text("\((board.columns ?? []).count) column\((board.columns ?? []).count == 1 ? "" : "s")")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(LColors.textSecondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(LColors.textSecondary)
            }
            .padding(16)
            .background {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(theme.palette.surface)
            }
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                BubblyCardMaterial(
                    tint: accentColor,
                    cornerRadius: 22
                )
                .mask {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(lineWidth: 1.6)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Schedule Square Action Card

struct ScheduleSquareActionCard: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        GlassCard {
            VStack(spacing: 12) {
                ZStack {
                    LureliaNeutralGlassCircle()
                        .frame(width: 54, height: 54)

                    Image(icon)
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 26, height: 26)
                        .foregroundStyle(LGradients.header)
                }

                VStack(spacing: 5) {
                    Text(title)
                        .font(.system(size: 15, weight: .black, design: .rounded))
                        .foregroundStyle(LColors.textPrimary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)

                    Text(subtitle)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(LColors.textSecondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 132)
        }
    }
}

// MARK: - Create Board View

struct CreateBoardView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var theme

    @Query(sort: \KanbanBoard.sortOrder) private var boards: [KanbanBoard]

    var board: KanbanBoard?

    @State private var name: String
    @State private var selectedIcon: String
    @State private var selectedColor: Color
    @State private var showIconPicker = false

    init(board: KanbanBoard? = nil) {
        self.board = board
        _name = State(initialValue: board?.name ?? "")
        _selectedIcon = State(initialValue: board?.icon ?? "starcal")
        _selectedColor = State(initialValue: Color(lureliaHex: board?.colorHex ?? "#03dbfc"))
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var isEditing: Bool { board != nil }

    var body: some View {
        ZStack {
            theme.palette.background
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {

                    RoundedRectangle(cornerRadius: 3)
                        .fill(theme.palette.textSecondary.opacity(0.45))
                        .frame(width: 40, height: 5)
                        .padding(.top, 12)

                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(isEditing ? "Edit Board" : "New Board")
                                .font(.system(size: 28, weight: .bold, design: .rounded))
                                .foregroundStyle(theme.palette.textPrimary)

                            Text(isEditing ? "Update your board name, icon, and color." : "Give your board a name, icon, and color.")
                                .font(.system(size: 13, design: .rounded))
                                .foregroundStyle(theme.palette.textSecondary)
                        }

                        Spacer()

                        Button { dismiss() } label: {
                            Image("xmarkwavy")
                                .renderingMode(.template)
                                .resizable()
                            .scaledToFit()
                            .frame(width: 28, height: 28)
                                .foregroundStyle(.white)
                                .bubblyIconMaterial(tint: .white)
                        }
                    }
                    .padding(.horizontal, 24)

                    // Preview
                    HStack(spacing: 14) {
                        ZStack {
                            Circle()
                                .fill(theme.palette.surface)
                                .frame(width: 54, height: 54)
                                .overlay {
                                    Circle()
                                        .strokeBorder(theme.palette.primaryAction, lineWidth: 1.4)
                                }

                            LureliaIconView(iconId: selectedIcon, size: 30)
                                .foregroundStyle(theme.palette.primaryAction)
                                .bubblyIconMaterial(tint: theme.palette.primaryAction)
                        }

                        Text(name.isEmpty ? "Board Name" : name)
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundStyle(name.isEmpty ? theme.palette.textSecondary : theme.palette.textPrimary)

                        Spacer()
                    }
                    .padding(18)
                    .background(theme.palette.surface, in: RoundedRectangle(cornerRadius: 20))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .strokeBorder(theme.palette.primaryAction, lineWidth: 1.2)
                    )
                    .padding(.horizontal, 24)

                    // Name
                    LureliaFormSection(title: "Board Name") {
                        TextField("e.g. Work, Personal, Health", text: $name)
                            .font(.system(size: 15, design: .rounded))
                            .foregroundStyle(theme.palette.textPrimary)
                            .padding(14)
                            .background(theme.palette.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .strokeBorder(theme.palette.secondaryAccent, lineWidth: 1.2)
                            )
                    }

                    // Icon
                    LureliaFormSection(title: "Icon") {
                        Button {
                            showIconPicker = true
                        } label: {
                            HStack(spacing: 12) {
                                ZStack {
                                    Circle()
                                        .fill(theme.palette.surface)

                                    Circle()
                                        .strokeBorder(theme.palette.indicators, lineWidth: 1.3)

                                    LureliaIconView(iconId: selectedIcon, size: 24)
                                        .foregroundStyle(theme.palette.indicators)
                                        .bubblyIconMaterial(tint: theme.palette.indicators)
                                }
                                .frame(width: 38, height: 38)

                                Text(selectedIcon)
                                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                                    .foregroundStyle(theme.palette.textPrimary)

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(theme.palette.indicators)
                                    .bubblyIconMaterial(tint: theme.palette.indicators)
                            }
                            .padding(14)
                            .background(theme.palette.surface, in: RoundedRectangle(cornerRadius: 14))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .strokeBorder(theme.palette.indicators, lineWidth: 1.2)
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    // Color
                    LureliaFormSection(title: "Color") {
                        ColorPicker(selection: $selectedColor, supportsOpacity: false) {
                            Text("Board Color")
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundStyle(theme.palette.textPrimary)
                        }
                        .padding(14)
                        .background(theme.palette.surface, in: RoundedRectangle(cornerRadius: 14))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .strokeBorder(theme.palette.primaryAction, lineWidth: 1.2)
                        )
                    }

                    // Save
                    Button {
                        save()
                    } label: {
                        HStack(spacing: 10) {
                            ZStack {
                                Image(isEditing ? "checkwavy" : "addwavy")
                                    .renderingMode(.template)
                                    .resizable()
                                    .scaledToFit()
                                    .foregroundStyle(Color.black.opacity(0.58))

                                Image(isEditing ? "checkwavy" : "addwavy")
                                    .renderingMode(.template)
                                    .resizable()
                                    .scaledToFit()
                                    .foregroundStyle(.black)
                                    .bubblyIconMaterial(tint: .black)
                            }
                            .frame(width: 14, height: 14)

                            Text(isEditing ? "Save Changes" : "Create Board")
                                .font(.system(size: 16, weight: .black, design: .rounded))
                        }
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 60)
                        .background {
                            BubblyCardMaterial(
                                tint: theme.palette.secondaryAccent,
                                cornerRadius: 22
                            )
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .shadow(color: theme.palette.secondaryAccent.opacity(0.14), radius: 18, y: 10)
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSave)
                    .opacity(canSave ? 1 : 0.45)
                    .padding(.horizontal, 24)

                    Spacer().frame(height: 40)
                }
            }
        }
        .sheet(isPresented: $showIconPicker) {
            IconPickerView(selectedIcon: $selectedIcon)
        }
        .presentationBackground(theme.palette.background)
        .lureliaDismissKeyboardOnTap()
    }

    private func save() {
        guard canSave else { return }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let hex = selectedColor.toHex() ?? board?.colorHex ?? "#03dbfc"

        if let board {
            board.name = trimmedName
            board.icon = selectedIcon
            board.colorHex = hex
        } else {
            let board = KanbanBoard(
                name: trimmedName,
                icon: selectedIcon,
                colorHex: hex,
                sortOrder: boards.count
            )
            modelContext.insert(board)
        }

        try? modelContext.save()
        dismiss()
    }
}
