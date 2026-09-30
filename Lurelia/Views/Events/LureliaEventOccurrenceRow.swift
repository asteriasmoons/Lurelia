//
//  LureliaEventOccurrenceRow.swift
//  Lurelia
//
//  A single event row used by all three event list views. Every row keeps
//  its event color while sharing the nested Kanban card material.
//

import SwiftUI

struct LureliaEventOccurrenceRow: View {
    let row: LureliaEventUnifiedOccurrence
    let onSelect: (LureliaEventUnifiedOccurrence) -> Void
    let onDelete: (LureliaEventUnifiedOccurrence) -> Void

    var body: some View {
        Button {
            onSelect(row)
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.black.opacity(0.34))
                        .frame(width: 42, height: 42)

                    Circle()
                        .strokeBorder(lineWidth: 1.4)
                        .frame(width: 42, height: 42)
                        .bubblyIconMaterial(tint: row.color)
                        .allowsHitTesting(false)

                    LureliaIconView(iconId: row.icon, size: 20)
                        .foregroundStyle(row.color)
                        .bubblyIconMaterial(tint: row.color)
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text(row.title)
                        .font(.system(size: 14, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(2)

                    HStack(spacing: 6) {
                        if row.calendarName != nil {
                            Circle()
                                .fill(row.color)
                                .frame(width: 7, height: 7)
                        }

                        Text(row.subtitle)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(LColors.textSecondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 8)

                if row.isApple {
                    Text("APPLE")
                        .font(.system(size: 9, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.white.opacity(0.10), in: Capsule())
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.20), lineWidth: 1))
                }
            }
            .padding(12)
            .background {
                ZStack {
                    BubblyCardMaterial(tint: row.color, cornerRadius: 16)

                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.black.opacity(0.12))
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(lineWidth: 1.2)
                    .bubblyIconMaterial(tint: row.color)
                    .allowsHitTesting(false)
            }
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) {
                onDelete(row)
            } label: {
                Text("Delete Event")
            }
        }
    }
}
