import Foundation

/// 用户可配置的提醒规则（对应设置窗口「休息节奏」分组）。
public struct ReminderSettings: Equatable, Sendable {
    /// 休息时长，5–10 分钟。
    public var breakMinutes: Int
    /// 生效时段开始整点（含），0–23。
    public var startHour: Int
    /// 生效时段结束整点（含），0–23，必须晚于 startHour。
    public var endHour: Int
    /// true = 仅工作日；false = 每天。
    public var weekdaysOnly: Bool

    /// 默认每天 00:00–23:00，即每个整点都提醒。
    public init(breakMinutes: Int = 5, startHour: Int = 0, endHour: Int = 23, weekdaysOnly: Bool = false) {
        self.breakMinutes = breakMinutes
        self.startHour = startHour
        self.endHour = endHour
        self.weekdaysOnly = weekdaysOnly
    }
}

/// 产品规则里的固定数值（DESIGN.md §4.3）。调试时可整体缩短，方便不用等一个小时就能测试。
public struct SchedulePolicy: Equatable, Sendable {
    /// 提醒间隔（分钟），正式为 60，即每个整点。
    public var intervalMinutes: Int
    /// 每次推迟的分钟数。
    public var snoozeMinutes: Int
    /// 推迟目标距离下一次提醒不足该时长时，直接合并到下一次提醒。
    public var mergeThreshold: TimeInterval
    /// 距上次完成休息不足该时长时，跳过紧邻的那次提醒。
    public var cooldown: TimeInterval
    /// 提前多久弹出预告胶囊。
    public var preAlertLead: TimeInterval
    /// 唤醒后若下一次提醒在该时长内……
    public var wakeGuard: TimeInterval
    /// ……则改为唤醒后过这么久再提醒。
    public var wakeGrace: TimeInterval
    /// 触发时刻已过去超过该时长（比如休眠中错过）就丢弃，不补弹。
    public var missTolerance: TimeInterval
    /// 检测到会议时，每隔多久重新检查一次。
    public var meetingRecheck: TimeInterval
    /// 调试用：忽略生效时段与工作日限制。
    public var ignoresActiveWindow: Bool
    /// 调试用：覆盖休息时长（秒）。
    public var breakDurationOverride: TimeInterval?

    public static let standard = SchedulePolicy(
        intervalMinutes: 60, snoozeMinutes: 5,
        mergeThreshold: 10 * 60, cooldown: 15 * 60, preAlertLead: 60,
        wakeGuard: 3 * 60, wakeGrace: 5 * 60, missTolerance: 90,
        meetingRecheck: 5 * 60, ignoresActiveWindow: false, breakDurationOverride: nil
    )

    /// 调试策略：每 `intervalMinutes` 分钟提醒一次，推迟 1 分钟，关闭冷却与合并，忽略生效时段。
    public static func debug(intervalMinutes: Int, breakSeconds: TimeInterval?) -> SchedulePolicy {
        let interval = max(1, intervalMinutes)
        return SchedulePolicy(
            intervalMinutes: interval, snoozeMinutes: 1,
            mergeThreshold: 0, cooldown: 0, preAlertLead: min(60, TimeInterval(interval * 60) / 2),
            wakeGuard: 30, wakeGrace: 60, missTolerance: 90,
            meetingRecheck: 60, ignoresActiveWindow: true, breakDurationOverride: breakSeconds
        )
    }
}

public enum PauseKind: String, Sendable {
    case oneHour
    case today
}

public enum SnoozeResult: Equatable, Sendable {
    /// 推迟到该时刻。
    case snoozed(until: Date)
    /// 离下一次提醒太近，直接合并到下一次提醒。
    case merged(into: Date)
}

/// 所有时间计算都是纯函数，只依赖传入的时间与日历。
public struct ReminderSchedule: Sendable {
    public var settings: ReminderSettings
    public var policy: SchedulePolicy
    public var calendar: Calendar

    public init(settings: ReminderSettings, policy: SchedulePolicy = .standard, calendar: Calendar = .current) {
        self.settings = settings
        self.policy = policy
        self.calendar = calendar
    }

    public var breakDuration: TimeInterval {
        policy.breakDurationOverride ?? TimeInterval(settings.breakMinutes * 60)
    }

    public func isActiveDay(_ date: Date) -> Bool {
        if policy.ignoresActiveWindow || !settings.weekdaysOnly { return true }
        return !calendar.isDateInWeekend(date)
    }

    /// 当前是否处于生效时段内（用于菜单栏图标是否降低不透明度）：下一次提醒在一个间隔之内即视为生效。
    /// 这样全天模式下 23:xx 不会被误判为「已结束」，时段开始前最后一小时也会显示倒计时。
    public func isInActivePeriod(_ date: Date) -> Bool {
        guard let next = nextReminder(after: date) else { return false }
        return next.timeIntervalSince(date) <= TimeInterval(policy.intervalMinutes * 60)
    }

    /// `date` 之后（不含）的下一次提醒时刻。生效时段首尾两个整点都会提醒。
    public func nextReminder(after date: Date) -> Date? {
        let interval = policy.intervalMinutes
        let firstMinute: Int
        let lastMinute: Int
        if policy.ignoresActiveWindow {
            firstMinute = 0
            lastMinute = 24 * 60 - 1
        } else {
            firstMinute = settings.startHour * 60
            lastMinute = settings.endHour * 60
        }
        let today = calendar.startOfDay(for: date)
        for offset in 0..<9 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today), isActiveDay(day) else { continue }
            // 对齐到从零点起 interval 的整数倍。
            var minute = ((firstMinute + interval - 1) / interval) * interval
            while minute <= lastMinute {
                if let t = calendar.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: day), t > date {
                    return t
                }
                minute += interval
            }
        }
        return nil
    }

    /// 同上，但跳过刚完成休息后冷却期内的候选（面板显示的「下次休息」与实际行为保持一致）。
    public func nextReminder(after date: Date, lastCompleted: Date?) -> Date? {
        var candidate = nextReminder(after: date)
        while let c = candidate, isInCooldown(reminder: c, lastCompleted: lastCompleted) {
            candidate = nextReminder(after: c)
        }
        return candidate
    }

    /// 截至 `date`（含）已经到点的最近一次提醒时刻，从 `anchor` 往后推。会议顺延跨过整点时用于更新提醒标签。
    public func latestReminder(from anchor: Date, notAfter date: Date) -> Date {
        var current = anchor
        while let next = nextReminder(after: current), next <= date {
            current = next
        }
        return current
    }

    /// 暂停结束时刻。「今天」= 下一个生效日首次提醒的预告时刻，保证那次提醒和它的预告都不会被吞掉。
    public func pauseEnd(_ kind: PauseKind, from now: Date) -> Date {
        switch kind {
        case .oneHour:
            return now.addingTimeInterval(3600)
        case .today:
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))
                ?? now.addingTimeInterval(86_400)
            guard var first = nextReminder(after: tomorrow.addingTimeInterval(-1)) else { return tomorrow }
            // 已经进入那次提醒的预告窗口（如全天模式 23:59 点「今天」），就连它一起跳过。
            if first.addingTimeInterval(-policy.preAlertLead) <= now, let after = nextReminder(after: first) {
                first = after
            }
            return first.addingTimeInterval(-policy.preAlertLead)
        }
    }

    /// 推迟一次。`due` 是本次提醒原定的触发时刻（预告阶段推迟时它在未来）。
    public func snooze(now: Date, due: Date) -> SnoozeResult {
        let base = max(now, due)
        let target = base.addingTimeInterval(TimeInterval(policy.snoozeMinutes * 60))
        if let next = nextReminder(after: base), next.timeIntervalSince(target) < policy.mergeThreshold {
            return .merged(into: next)
        }
        return .snoozed(until: target)
    }

    /// 是否因为刚完成过休息而跳过 `reminder` 这次提醒。
    public func isInCooldown(reminder: Date, lastCompleted: Date?) -> Bool {
        guard let lastCompleted, policy.cooldown > 0 else { return false }
        let elapsed = reminder.timeIntervalSince(lastCompleted)
        return elapsed >= 0 && elapsed < policy.cooldown  // 时钟被往回调时 lastCompleted 可能在未来
    }

    /// 唤醒后如果马上就要提醒，返回推后的触发时刻；否则返回 nil。
    public func wakeAdjustedFire(now: Date, next: Date) -> Date? {
        next.timeIntervalSince(now) < policy.wakeGuard ? now.addingTimeInterval(policy.wakeGrace) : nil
    }

    /// 触发时刻是否早已过去（例如休眠期间错过）。
    public func isMissed(due: Date, now: Date) -> Bool {
        now.timeIntervalSince(due) > policy.missTolerance
    }
}
