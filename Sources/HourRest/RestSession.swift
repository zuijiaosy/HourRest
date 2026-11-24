import Foundation

/// 一次全屏休息：出现即开始倒计时，倒计时结束自动关闭；用户可随时一键提前结束（DESIGN.md §4.1）。
/// 结果通过 `onEvent` 回报给 ReminderEngine；预览模式下引擎不计数。
@MainActor
final class RestSession: ObservableObject {
    enum Kind: Equatable {
        /// 整点（或推迟后）触发；anchor 是原定的整点时刻。
        case scheduled(anchor: Date)
        /// 菜单栏「立即休息」。
        case manual
        /// 设置窗口「预览全屏提醒」。
        case preview
    }

    enum Event {
        /// 倒计时走完。
        case completed
        /// 用户点「提前结束」，或在预览里按 Esc。
        case endedEarly
    }

    let kind: Kind
    let end: Date
    let total: TimeInterval
    /// 本次轮换展示的活动建议（§5.2，每次 3 条）。
    let activities: [Activity]
    private var finished = false

    var onEvent: (Event) -> Void = { _ in }

    init(kind: Kind, breakDuration: TimeInterval, now: Date = Date()) {
        self.kind = kind
        self.total = breakDuration
        self.end = now.addingTimeInterval(breakDuration)
        self.activities = Array(Activity.all.shuffled().prefix(3))
    }

    var isPreview: Bool { kind == .preview }

    /// 「提前结束」：一次点击直接关闭，不再二次确认。
    func endEarly() {
        guard !finished else { return }
        finished = true
        onEvent(.endedEarly)
    }

    /// Esc 只在预览模式下关闭，正式休息要点「提前结束」，避免打字时误触。
    func escape() {
        if isPreview { endEarly() }
    }

    func tick(_ now: Date) {
        guard !finished, now >= end else { return }
        finished = true
        onEvent(.completed)
    }
}

struct Activity: Hashable {
    let symbol: String
    let short: String
    let sentence: String

    static let all: [Activity] = [
        Activity(symbol: "figure.stand", short: "站起来伸个懒腰", sentence: "站起来，伸个懒腰。"),
        Activity(symbol: "eye", short: "看看 6 米外", sentence: "看看 6 米外的远处，让眼睛放松。"),
        Activity(symbol: "drop", short: "喝两口温水", sentence: "去喝两口温水。"),
        Activity(symbol: "figure.stand", short: "转转脖子", sentence: "放松双肩，缓慢转转脖子。"),
        Activity(symbol: "lungs", short: "深呼吸", sentence: "深吸气 4 秒，再缓缓呼出。"),
        Activity(symbol: "figure.walk", short: "走动一分钟", sentence: "在房间里走动一分钟。"),
    ]
}
