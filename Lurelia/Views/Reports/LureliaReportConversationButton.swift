//
//  LureliaReportConversationButton.swift
//  Lurelia
//

import SwiftUI

struct LureliaReportConversationButton: View {
    @Environment(\.appTheme) private var theme

    let state: LureliaReportConversationState
    let unreadCount: Int
    var accentColor: Color? = nil
    let action: () -> Void

    private var title: String {
        switch state {
        case .notStarted:
            return "Private Conversation"
        case .invited:
            return "Voxiverse Sent You a Message"
        case .accepted:
            return unreadCount > 0 ? "New Message from Voxiverse" : "Conversation with Voxiverse"
        case .declined:
            return "Conversation Declined"
        }
    }

    private var subtitle: String {
        switch state {
        case .notStarted:
            return "If Voxiverse needs details, the message will appear here."
        case .invited:
            return "Review the invitation for this report."
        case .accepted:
            return unreadCount > 0 ? "\(unreadCount) unread" : "Open your private report thread."
        case .declined:
            return "You declined this private report conversation."
        }
    }

    private var showsBadge: Bool {
        state == .invited || unreadCount > 0
    }

    var body: some View {
        Button(action: action) {
            LureliaReportSurfaceCard(cornerRadius: 24, borderColor: accentColor) {
                HStack(spacing: 14) {
                    ZStack(alignment: .topTrailing) {
                        if let accentColor {
                            ZStack {
                                Circle().fill(theme.palette.raisedSurface)
                                BubblyIconMaterial(tint: accentColor)
                                    .mask { Circle().strokeBorder(lineWidth: 1.2) }
                                Image("chatstar")
                                    .renderingMode(.template)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 24, height: 24)
                                    .bubblyIconMaterial(tint: accentColor)
                            }
                            .frame(width: 52, height: 52)
                        } else {
                            LureliaReportIcon(asset: "chatstar", size: 52, iconSize: 24)
                        }

                        if showsBadge {
                            Circle()
                                .fill(accentColor ?? theme.palette.primaryAction)
                                .frame(width: 13, height: 13)
                                .overlay(Circle().strokeBorder(theme.palette.background, lineWidth: 2))
                                .offset(x: 3, y: -3)
                                .accessibilityHidden(true)
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(.system(size: 17, weight: .black, design: .rounded))
                            .foregroundStyle(accentColor ?? theme.palette.textPrimary)
                            .bubblyIconMaterial(
                                tint: accentColor ?? theme.palette.primaryAction,
                                isEnabled: accentColor != nil
                            )
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(subtitle)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(accentColor ?? theme.palette.textSecondary)
                            .bubblyIconMaterial(
                                tint: accentColor ?? theme.palette.primaryAction,
                                isEnabled: accentColor != nil
                            )
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 8)

                    Image("chevright")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 22, height: 22)
                        .foregroundStyle(
                            accentColor.map { AnyShapeStyle($0) } ?? AnyShapeStyle(LGradients.header)
                        )
                        .bubblyIconMaterial(tint: accentColor ?? LColors.accents.primary, isEnabled: accentColor != nil)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityHint(subtitle)
    }
}
