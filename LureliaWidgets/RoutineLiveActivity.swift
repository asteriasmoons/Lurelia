//
//  LureliaRoutineLiveActivity.swift
//  Lurelia + LureliaWidgets
//
//  Created by Asteria Moon on 5/16/26.
//
//  IMPORTANT: Add this file to BOTH the Lurelia app target AND the LureliaWidgets
//  widget extension target in Xcode (tick both boxes in File Inspector).
//  This is the single source of truth for LureliaRoutineActivityAttributes.
//

import ActivityKit
import Foundation

// MARK: - Attributes (shared between app + widget targets)

struct LureliaRoutineActivityAttributes: ActivityAttributes {
    
    struct ContentState: Codable, Hashable {
        var routineName: String
        var completedCount: Int
        var totalCount: Int
        var endDate: Date
        var isFinished: Bool
        var colorHex: String
        var isPaused: Bool?
        var pausedRemainingSeconds: TimeInterval?
    }
    
    var routineID: String
}
