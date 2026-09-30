//
//  LureliaWidgetsLiveActivity.swift
//  LureliaWidgets
//

import ActivityKit
import WidgetKit
import SwiftUI

struct LureliaWidgetsLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LureliaRoutineActivityAttributes.self) { context in
            LureliaRoutineLiveActivityLockScreenView(context: context)
                .activityBackgroundTint(Color(widgetHex: context.state.colorHex).opacity(0.82))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            let tint = Color(widgetHex: context.state.colorHex)

            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    LureliaRoutineLiveActivityIslandTitle(context: context, tint: tint)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    LureliaRoutineLiveActivityIslandProgress(context: context, tint: tint)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    LureliaRoutineLiveActivityIslandBottom(context: context, tint: tint)
                }
            } compactLeading: {
                Image("hourglassfill")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 16, height: 16)
                    .foregroundStyle(tint)
            } compactTrailing: {
                Group {
                    if context.state.isFinished {
                        Text("Done")
                    } else if context.state.isPaused == true {
                        Text("Paused")
                    } else {
                        Text(context.state.endDate, style: .timer)
                    }
                }
                .font(.system(size: 12, weight: .black, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            } minimal: {
                ZStack {
                    Circle()
                        .fill(tint.opacity(0.32))

                    if context.state.isFinished {
                        Image("checkwavy")
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 12, height: 12)
                            .foregroundStyle(.white)
                    } else if context.state.isPaused == true {
                        Text("II")
                            .font(.system(size: 8, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                    } else {
                        Text(context.state.endDate, style: .timer)
                            .font(.system(size: 7, weight: .black, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.55)
                    }
                }
            }
            .keylineTint(tint)
        }
    }
}

private struct LureliaRoutineLiveActivityLockScreenView: View {
    let context: ActivityViewContext<LureliaRoutineActivityAttributes>

    private var tint: Color {
        Color(widgetHex: context.state.colorHex)
    }

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.24))
                    .frame(width: 48, height: 48)
                    .overlay {
                        Circle()
                            .strokeBorder(tint.opacity(0.55), lineWidth: 1)
                    }

                Image("hourglassfill")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 23, height: 23)
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(context.state.routineName)
                    .font(.system(size: 17, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text("\(context.state.completedCount)/\(context.state.totalCount) tasks")

                    Text("•")

                    if context.state.isFinished {
                        Text("Complete")
                    } else if context.state.isPaused == true {
                        Text("Paused \(context.state.pausedRemainingText)")
                            .monospacedDigit()
                    } else {
                        Text(context.state.endDate, style: .timer)
                            .monospacedDigit()
                    }
                }
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.78))
                .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
    }
}

private struct LureliaRoutineLiveActivityIslandTitle: View {
    let context: ActivityViewContext<LureliaRoutineActivityAttributes>
    let tint: Color

    var body: some View {
        HStack(spacing: 8) {
            Image("hourglassfill")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 18, height: 18)
                .foregroundStyle(tint)

            Text(context.state.routineName)
                .font(.system(size: 14, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }
}

private struct LureliaRoutineLiveActivityIslandProgress: View {
    let context: ActivityViewContext<LureliaRoutineActivityAttributes>
    let tint: Color

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text("\(context.state.completedCount)/\(context.state.totalCount)")
                .font(.system(size: 16, weight: .black, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)

            Text("tasks")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(tint)
        }
    }
}

private struct LureliaRoutineLiveActivityIslandBottom: View {
    let context: ActivityViewContext<LureliaRoutineActivityAttributes>
    let tint: Color

    private var progress: Double {
        guard context.state.totalCount > 0 else { return 0 }
        return min(max(Double(context.state.completedCount) / Double(context.state.totalCount), 0), 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(
                    context.state.isFinished
                    ? "Routine complete"
                    : (context.state.isPaused == true ? "Paused" : "Running")
                )
                    .font(.system(size: 12, weight: .black, design: .rounded))
                    .foregroundStyle(.white)

                Spacer()

                if context.state.isFinished {
                    Text("Done")
                } else if context.state.isPaused == true {
                    Text(context.state.pausedRemainingText)
                        .monospacedDigit()
                } else {
                    Text(context.state.endDate, style: .timer)
                        .monospacedDigit()
                }
            }
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundStyle(.white.opacity(0.82))

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.white.opacity(0.16))

                    Capsule()
                        .fill(tint)
                        .frame(width: proxy.size.width * progress)
                }
            }
            .frame(height: 7)
        }
        .padding(.top, 2)
    }
}

extension LureliaRoutineActivityAttributes {
    fileprivate static var preview: LureliaRoutineActivityAttributes {
        LureliaRoutineActivityAttributes(routineID: "routine-preview")
    }
}

extension LureliaRoutineActivityAttributes.ContentState {
    fileprivate var pausedRemainingText: String {
        let remaining = max(0, Int(pausedRemainingSeconds ?? 0))
        let hours = remaining / 3600
        let minutes = (remaining % 3600) / 60
        let seconds = remaining % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }

    fileprivate static var running: LureliaRoutineActivityAttributes.ContentState {
        LureliaRoutineActivityAttributes.ContentState(
            routineName: "Morning Routine",
            completedCount: 2,
            totalCount: 5,
            endDate: Date().addingTimeInterval(1800),
            isFinished: false,
            colorHex: "#7d19f7",
            isPaused: false,
            pausedRemainingSeconds: nil
        )
    }

    fileprivate static var finished: LureliaRoutineActivityAttributes.ContentState {
        LureliaRoutineActivityAttributes.ContentState(
            routineName: "Morning Routine",
            completedCount: 5,
            totalCount: 5,
            endDate: Date(),
            isFinished: true,
            colorHex: "#7d19f7",
            isPaused: false,
            pausedRemainingSeconds: nil
        )
    }
}

#Preview("Routine", as: .content, using: LureliaRoutineActivityAttributes.preview) {
    LureliaWidgetsLiveActivity()
} contentStates: {
    LureliaRoutineActivityAttributes.ContentState.running
    LureliaRoutineActivityAttributes.ContentState.finished
}
