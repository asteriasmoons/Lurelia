//
//  RoutineContractsView.swift
//  Lurelia
//

import SwiftUI
import SwiftData

struct RoutineContractsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var theme

    @Query(sort: \LureliaRoutineContract.dateCommitted, order: .reverse)
    private var contracts: [LureliaRoutineContract]

    @State private var selectedContract: LureliaRoutineContract?
    @State private var visiblePastContractCount = 4

    private var currentContracts: [LureliaRoutineContract] {
        contracts.filter { $0.isCurrent }
    }

    private var pastContracts: [LureliaRoutineContract] {
        contracts.filter { !$0.isCurrent }
    }

    private var visiblePastContracts: [LureliaRoutineContract] {
        Array(pastContracts.prefix(visiblePastContractCount))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LureliaBackgroundAlt()
                    .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        header

                        if contracts.isEmpty {
                            emptyState
                        } else {
                            contractSection("Current Contracts", contracts: currentContracts)
                            pastContractsSection
                        }

                        Spacer()
                            .frame(height: 120)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    .routinePageWidthLocked()
                }
                .routinePageScrollClipped(bottomClearance: 150)
            }
            .navigationBarBackButtonHidden(true)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(item: $selectedContract) { contract in
                RoutineContractDetailView(
                    contract: contract,
                    routine: contract.routine
                )
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("My Contracts")
                    .font(.system(size: 30, weight: .black, design: .rounded))
                    .foregroundStyle(.white)

                Text("Current and past routine commitments.")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.54))
            }

            Spacer()

            Button {
                dismiss()
            } label: {
                Image("xmarkwavy")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 26, height: 26)
                    .foregroundStyle(.white)
                    .bubblyIconMaterial(tint: .white)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private var emptyState: some View {
        GlassCard(cornerRadius: 28) {
            VStack(spacing: 12) {
                LureliaIconView(iconId: "stardoc", size: 42)
                    .foregroundStyle(LColors.textPrimary)

                Text("No contracts yet")
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundStyle(.white)

                Text("Create one from a routine's detail page when you are ready to formally commit.")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.62))
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private func contractSection(
        _ title: String,
        contracts: [LureliaRoutineContract]
    ) -> some View {
        if !contracts.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text(title)
                    .font(.system(size: 18, weight: .black, design: .rounded))
                    .foregroundStyle(.white)

                VStack(spacing: 10) {
                    ForEach(contracts) { contract in
                        contractTile(contract)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var pastContractsSection: some View {
        if !pastContracts.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Past Contracts")
                    .font(.system(size: 18, weight: .black, design: .rounded))
                    .foregroundStyle(.white)

                VStack(spacing: 10) {
                    ForEach(visiblePastContracts) { contract in
                        contractTile(contract)
                    }
                }

                if visiblePastContracts.count < pastContracts.count {
                    Button {
                        withAnimation(.spring(response: 0.30, dampingFraction: 0.86)) {
                            visiblePastContractCount = min(
                                visiblePastContractCount + 4,
                                pastContracts.count
                            )
                        }
                    } label: {
                        Text("Load More")
                            .font(.system(size: 14, weight: .black, design: .rounded))
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background {
                                BubblyCardMaterial(
                                    tint: theme.palette.primaryAction,
                                    cornerRadius: 16
                                )
                            }
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func contractTile(_ contract: LureliaRoutineContract) -> some View {
        let tint = Color(lureliaHex: contract.routineDisplayColorHex)
        let solidText = tint.wcagContrastingSolidTextColor
        let badgeShadow = tint.isLightColor ? Color.clear : Color.black.opacity(0.68)

        return Button {
            selectedContract = contract
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(tint.opacity(0.22))
                        .frame(width: 84, height: 84)

                    LureliaIconView(iconId: contract.routineDisplayIcon, size: 72)
                        .foregroundStyle(tint)
                        .shadow(color: Color.black.opacity(0.72), radius: 5, x: 0, y: 3)
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text(contract.routineDisplayName)
                        .font(.system(size: 16, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Text("\(contract.contracteeName) · \(contract.committedDateText)")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.58))
                        .lineLimit(1)
                }

                Spacer()

                HStack(spacing: 6) {
                    LureliaIconView(iconId: contract.status.icon, size: 12)
                        .foregroundStyle(solidText)
                        .bubblyIconMaterial(tint: solidText)
                        .shadow(color: badgeShadow, radius: 2, x: 0, y: 1)

                    Text(contract.status.rawValue)
                        .font(.system(size: 11, weight: .black, design: .rounded))
                        .foregroundStyle(solidText)
                        .shadow(color: badgeShadow, radius: 2, x: 0, y: 1)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 7)
                .background(tint, in: Capsule())
            }
            .padding(12)
            .background {
                BubblyCardMaterial(
                    tint: tint,
                    cornerRadius: 20
                )
            }
        }
        .buttonStyle(.plain)
    }
}
