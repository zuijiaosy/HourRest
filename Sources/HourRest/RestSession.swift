import Foundation

/// 一次全屏提醒的生命周期：提醒到达 → 休息中 → 完成（DESIGN.md §4.1）。
/// 结果通过 `onEvent` 回报给 ReminderEngine；预览模式下引擎会忽略计数类事件。
@MainActor
final class RestSession: ObservableObject {
    enum Kind: Equatable {
        /// 整点（或推迟后）触发；anchor 是原定的整点时刻。
        case scheduled(anchor: Date, snoozed: Bool, due: Date)
        /// 菜单栏「立即休息」。
        case manual
        /// 设置窗口「预览全屏提醒」。
        case preview
    }

    enum Stage: Equatable {
        case prompting
        case resting(end: Date, total: TimeInterval)
        case completed
    }

    enum Event {
        case startedRest, snoozed, skipped, endedEarly, completed, dismissed
    }

    /// 行内二次确认条（§4.2）。
    enum Confirmation {
        case skip, endEarly
    }

    let kind: Kind
    let breakDuration: TimeInterval
    let snoozeMinutes: Int
    let snoozesLeft: Int
    /// 本次轮换展示的活动建议（§5.2，每次 3 条）。
    let activities: [Activity]

    @Published private(set) var stage: Stage {
        didSet { confirmation = nil }
    }
    @Published var confirmation: Confirmation?
    /// 完成态文案里的「今天已完成第 N 次」。
    @Published var completedToday: Int

    var onEvent: (Event) -> Void = { _ in }

    init(kind: Kind, breakDuration: TimeInterval, snoozeMinutes: Int, snoozesLeft: Int, completedToday: Int, now: Date = Date()) {
        self.kind = kind
        self.breakDuration = breakDuration
        self.snoozeMinutes = snoozeMinutes
        self.snoozesLeft = snoozesLeft
        self.completedToday = completedToday
        self.activities = Array(Activity.all.shuffled().prefix(3))
        self.stage = kind == .manual ? .resting(end: now.addingTimeInterval(breakDuration), total: breakDuration) : .prompting
    }

    var isPreview: Bool { kind == .preview }

    // MARK: 用户操作

    func startRest() {
        guard stage == .prompting else { return }
        stage = .resting(end: Date().addingTimeInterval(breakDuration), total: breakDuration)
        onEvent(.startedRest)
    }

    func snooze() {
        guard stage == .prompting, snoozesLeft > 0 else { return }
        onEvent(.snoozed)
    }

    func skip() {
        guard stage == .prompting else { return }
        onEvent(.skipped)
    }

    func endEarly() {
        guard case .resting = stage else { return }
        onEvent(.endedEarly)
    }

    /// 完成态「再多歇 2 分钟」。
    func extend() {
        guard stage == .completed else { return }
        stage = .resting(end: Date().addingTimeInterval(120), total: 120)
    }

    /// 完成态「回去工作」。
    func finish() {
        guard stage == .completed else { return }
        onEvent(.dismissed)
    }

    /// Esc：先收起确认条；否则只在完成态与预览模式下关闭（§4.2）。
    func escape() {
        if confirmation != nil {
            confirmation = nil
        } else if isPreview {
            onEvent(.dismissed)
        } else if stage == .completed {
            finish()
        }
    }

    func tick(_ now: Date) {
        if case let .resting(end, _) = stage, now >= end {
            stage = .completed
            onEvent(.completed)
        }
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
