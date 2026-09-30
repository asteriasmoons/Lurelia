//
//  RoutineContractDetailView.swift
//  Lurelia
//

import SwiftUI
import SwiftData

struct RoutineContractDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Bindable var contract: LureliaRoutineContract
    let routine: LureliaRoutine?

    @State private var showRenewContract = false
    @State private var displayedContractID: String?

    private var displayRoutine: LureliaRoutine? {
        routine ?? contract.routine
    }

    private var displayedContract: LureliaRoutineContract {
        guard let displayedContractID,
              let match = displayRoutine?.contracts?.first(where: { $0.persistentID == displayedContractID })
        else {
            return contract
        }
        return match
    }

    private var routineTint: Color {
        Color(lureliaHex: displayedContract.routineDisplayColorHex)
    }

    private var solidTextColor: Color {
        routineTint.wcagContrastingSolidTextColor
    }

    private var signedDateText: String {
        displayedContract.dateCommitted.formatted(date: .long, time: .omitted)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LureliaBackgroundAlt()
                    .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        header
                        titleCard
                        contractMetaCards
                        documentCards
                        managementCard

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
            .sheet(isPresented: $showRenewContract, onDismiss: {
                showNewestCurrentContract()
            }) {
                if let displayRoutine {
                    RoutineContractEditorView(
                        routine: displayRoutine,
                        renewingFrom: displayedContract
                    )
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Routine Contract")
                    .font(.system(size: 20, weight: .black, design: .rounded))
                    .bubblyIconMaterial(tint: routineTint)
                    .shadow(color: .black.opacity(0.68), radius: 3, x: 0, y: 2)

                Text(displayedContract.routineDisplayName)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.58))
                    .lineLimit(1)
            }

            Spacer()

            Button {
                dismiss()
            } label: {
                Image("xmarkwavy")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 17, height: 17)
                    .bubblyIconMaterial(tint: solidTextColor)
                    .shadow(color: .black.opacity(0.68), radius: 3, x: 0, y: 2)
                    .frame(width: 42, height: 42)
                    .background {
                        BubblyIconMaterial(tint: routineTint)
                            .clipShape(Circle())
                    }
            }
            .buttonStyle(.plain)
        }
    }

    private var titleCard: some View {
        routineTintCard(cornerRadius: 28) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(Color.black.opacity(0.48))
                            .frame(width: 60, height: 60)

                        BubblyIconMaterial(tint: routineTint)
                            .mask {
                                Circle().strokeBorder(lineWidth: 1.5)
                            }
                            .frame(width: 60, height: 60)

                        contractMaterialIcon(displayedContract.routineDisplayIcon, size: 31)
                    }

                    VStack(alignment: .leading, spacing: 5) {
                        Text("ROUTINE CONTRACT")
                            .font(.system(size: 10, weight: .black, design: .rounded))
                            .bubblyIconMaterial(tint: routineTint)
                            .shadow(color: .black.opacity(0.68), radius: 2, x: 0, y: 1)

                        Text(displayedContract.routineDisplayName)
                            .font(.system(size: 17, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                    }

                    Spacer()
                }
            }
        }
    }

    private var contractMetaCards: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ],
            spacing: 10
        ) {
            contractMetaTile(title: "Status", value: displayedContract.status.rawValue, icon: displayedContract.status.icon)
            contractMetaTile(title: "Committed", value: displayedContract.committedDateText, icon: "starcal")
            contractMetaTile(title: "Duration", value: displayedContract.durationText, icon: "hourglassfill")
            contractMetaTile(title: "Failed Days", value: displayedContract.failedRoutineDayText, icon: "warnwavy")
            if let brokenDateText = displayedContract.brokenDateText {
                contractMetaTile(title: "Broken", value: brokenDateText, icon: "xmarkwavy")
            }
        }
    }

    private var documentCards: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                documentSmallField(title: "Date Committed", value: signedDateText)
                documentSmallField(title: "Contractee", value: displayedContract.contracteeName)
            }

            contractDocumentSection("Meaning", text: displayedContract.meaning)
            contractDocumentSection("Decree Statement", text: displayedContract.decreeStatement)
            contractDocumentSection("Consequences", text: displayedContract.consequences)
            signatureSection
        }
    }

    private var managementCard: some View {
        routineTintCard(cornerRadius: 24) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 9) {
                    contractMaterialIcon("settings", size: 16)

                    Text("Contract Status")
                        .font(.system(size: 14, weight: .black, design: .rounded))
                        .foregroundStyle(.white)

                    Spacer()
                }

                if displayedContract.status == .renewed {
                    HStack(spacing: 10) {
                        contractMaterialIcon("repeatfill", size: 14)
                        Text("This contract was renewed and preserved in history.")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.68))
                        Spacer()
                    }
                    .padding(12)
                    .background {
                        BubblyCardMaterial(tint: routineTint, cornerRadius: 14)
                    }
                } else {
                    LazyVGrid(
                        columns: [
                            GridItem(.flexible()),
                            GridItem(.flexible()),
                            GridItem(.flexible())
                        ],
                        spacing: 8
                    ) {
                        statusButton(.active)
                        statusButton(.completed)
                        statusButton(.broken)
                    }

                    if displayRoutine != nil {
                        Button {
                            showRenewContract = true
                        } label: {
                            HStack(spacing: 9) {
                                Image("repeatfill")
                                    .renderingMode(.template)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 16, height: 16)
                                    .bubblyIconMaterial(tint: solidTextColor)
                                    .shadow(color: .black.opacity(0.95), radius: 5, x: 0, y: 3)

                                Text("Renew Contract")
                                    .font(.system(size: 14, weight: .black, design: .rounded))
                            }
                            .foregroundStyle(solidTextColor)
                            .wcagContrastLift(on: routineTint)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background {
                                BubblyCardMaterial(tint: routineTint, cornerRadius: 16)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var signatureSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Signed,")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.62))

            Text(displayedContract.typedSignature)
                .font(.system(size: 17, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)

            Text(signedDateText)
                .font(.system(size: 12, weight: .black, design: .rounded))
                .bubblyIconMaterial(tint: routineTint)
        }
        .routineContractCardSurface(routineTint, cornerRadius: 22, padding: 16)
    }

    private func contractMetaTile(title: String, value: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            contractMaterialIcon(icon, size: 17)

            Text(title.uppercased())
                .font(.system(size: 10, weight: .black, design: .rounded))
                .foregroundStyle(.white.opacity(0.48))

            Text(value)
                .font(.system(size: 12, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(2)
        }
        .routineContractCardSurface(routineTint, cornerRadius: 18, padding: 13)
    }

    private func documentSmallField(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .black, design: .rounded))
                .foregroundStyle(.white.opacity(0.46))

            Text(value)
                .font(.system(size: 12, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(2)
        }
        .routineContractCardSurface(routineTint, cornerRadius: 16, padding: 13)
    }

    private func contractDocumentSection(
        _ title: String,
        text: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title)
                .font(.system(size: 12, weight: .black, design: .rounded))
                .foregroundStyle(.white.opacity(0.78))

            Text(text)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.86))
                .fixedSize(horizontal: false, vertical: true)
        }
        .routineContractCardSurface(routineTint, cornerRadius: 20, padding: 16)
    }

    private func statusButton(_ status: LureliaRoutineContractStatus) -> some View {
        let isSelected = displayedContract.status == status
        return Button {
            setStatus(status)
        } label: {
            VStack(spacing: 7) {
                contractMaterialIcon(
                    status.icon,
                    size: 16,
                    tint: isSelected ? solidTextColor : routineTint
                )

                Text(status.rawValue)
                    .font(.system(size: 12, weight: .black, design: .rounded))
                    .foregroundStyle(isSelected ? solidTextColor : .white.opacity(0.68))
                    .wcagContrastLift(on: isSelected ? routineTint : routineTint.opacity(0.14))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background {
                BubblyIconMaterial(
                    tint: isSelected ? routineTint : routineTint.opacity(0.32)
                )
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(isSelected ? Color.white.opacity(0.16) : routineTint.opacity(0.38), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private func showNewestCurrentContract() {
        guard let newest = displayRoutine?.contracts?
            .filter({ $0.isCurrent })
            .sorted(by: { $0.createdAt > $1.createdAt })
            .first
        else { return }

        displayedContractID = newest.persistentID
    }

    private func setStatus(_ status: LureliaRoutineContractStatus) {
        displayedContract.status = status
        if status == .broken {
            displayedContract.brokenAt = displayedContract.brokenAt ?? Date()
        }
        displayedContract.updatedAt = Date()
        try? modelContext.save()
    }

    private func routineTintCard<Content: View>(
        cornerRadius: CGFloat,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .routineContractCardSurface(routineTint, cornerRadius: cornerRadius, padding: 18)
    }

    private func contractMaterialIcon(
        _ icon: String,
        size: CGFloat,
        tint: Color? = nil
    ) -> some View {
        LureliaIconView(iconId: icon, size: size)
            .bubblyIconMaterial(tint: tint ?? routineTint)
            .shadow(color: .black.opacity(0.95), radius: 5, x: 0, y: 3)
    }
}

private extension View {
    func routineContractCardSurface(
        _ tint: Color,
        cornerRadius: CGFloat,
        padding: CGFloat
    ) -> some View {
        self
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(padding)
            .background {
                BubblyCardMaterial(tint: tint, cornerRadius: cornerRadius)
            }
    }
}
