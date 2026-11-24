import Foundation
import Testing
@testable import HourRestCore

private let cal: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "Asia/Shanghai")!
    c.locale = Locale(identifier: "zh_CN")
    return c
}()

/// 2026-11-23 是周一。
private func d(_ day: Int, _ hour: Int, _ minute: Int = 0, _ second: Int = 0, month: Int = 11) -> Date {
    cal.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute, second: second))!
}

/// 多数用例用「工作日 09:00–19:00」来覆盖时段边界。
private let workday = ReminderSettings(startHour: 9, endHour: 19, weekdaysOnly: true)

private func schedule(_ s: ReminderSettings = workday, _ p: SchedulePolicy = .standard) -> ReminderSchedule {
    ReminderSchedule(settings: s, policy: p, calendar: cal)
}

@Suite struct NextReminderTests {
    @Test func nextFullHourInsideWindow() {
        #expect(schedule().nextReminder(after: d(23, 10, 37)) == d(23, 11))
    }

    @Test func exactHourIsExclusive() {
        #expect(schedule().nextReminder(after: d(23, 11)) == d(23, 12))
    }

    @Test func windowBoundsAreInclusive() {
        #expect(schedule().nextReminder(after: d(23, 7, 30)) == d(23, 9))
        #expect(schedule().nextReminder(after: d(23, 18, 30)) == d(23, 19))
    }

    @Test func afterWindowGoesToNextDay() {
        #expect(schedule().nextReminder(after: d(23, 19, 0, 1)) == d(24, 9))
    }

    @Test func fridayEveningSkipsWeekendWhenWeekdaysOnly() {
        // 2026-11-27 周五 → 2026-11-30 周一
        #expect(schedule().nextReminder(after: d(27, 20)) == d(30, 9))
    }

    @Test func everyDayIncludesWeekend() {
        let s = schedule(.init(startHour: 9, endHour: 19, weekdaysOnly: false))
        #expect(s.nextReminder(after: d(27, 20)) == d(28, 9))
    }

    @Test func defaultSettingsRemindEveryHourEveryDay() {
        let s = schedule(.init())
        #expect(s.nextReminder(after: d(23, 22, 30)) == d(23, 23))
        #expect(s.nextReminder(after: d(23, 23, 30)) == d(24, 0))
        #expect(s.nextReminder(after: d(28, 3, 10)) == d(28, 4)) // 周六凌晨
    }

    @Test func debugIntervalIgnoresWindow() {
        let s = schedule(.init(), .debug(intervalMinutes: 2, breakSeconds: 20))
        #expect(s.nextReminder(after: d(28, 22, 3, 10)) == d(28, 22, 4))
    }
}

@Suite struct ActivePeriodTests {
    @Test func insideAndOutside() {
        let s = schedule()
        #expect(s.isInActivePeriod(d(23, 9)))
        #expect(s.isInActivePeriod(d(23, 18, 30)))
        #expect(!s.isInActivePeriod(d(23, 19, 1)))
        #expect(s.isInActivePeriod(d(23, 8, 30)))   // 时段开始前一小时内显示倒计时
        #expect(!s.isInActivePeriod(d(23, 7, 30)))
        #expect(!s.isInActivePeriod(d(28, 12)))     // 周六
    }

    @Test func allDayIsAlwaysActive() {
        let s = schedule(.init())
        #expect(s.isInActivePeriod(d(23, 23, 30)))
        #expect(s.isInActivePeriod(d(28, 3)))
    }
}

@Suite struct PauseTests {
    @Test func oneHour() {
        #expect(schedule().pauseEnd(.oneHour, from: d(23, 10, 20)) == d(23, 11, 20))
    }

    @Test func todayResumesJustBeforeNextActiveDayFirstReminder() {
        #expect(schedule().pauseEnd(.today, from: d(23, 14)) == d(24, 8, 59))
        // 周五点「今天」→ 周一 08:59（09:00 的预告还能弹出）
        #expect(schedule().pauseEnd(.today, from: d(27, 14)) == d(30, 8, 59))
        // 全天模式：今晚 23:59 解除，明早 00:00 照常提醒
        #expect(schedule(.init()).pauseEnd(.today, from: d(23, 14)) == d(23, 23, 59))
    }

    @Test func todayPauseInsidePreAlertWindowSkipsThatReminder() {
        // 全天模式 23:59:10 点「今天」：不能落在过去立刻解除，改为跳过 00:00，01:00 前解除
        #expect(schedule(.init()).pauseEnd(.today, from: d(23, 23, 59, 10)) == d(24, 0, 59))
    }

    @Test func firstReminderAfterTodayPauseIsNotSwallowed() {
        let s = schedule()
        let end = s.pauseEnd(.today, from: d(23, 14))
        #expect(s.nextReminder(after: end) == d(24, 9))
    }
}

@Suite struct SnoozeTests {
    @Test func normalSnoozeAddsFiveMinutes() {
        #expect(schedule().snooze(now: d(23, 10, 0, 3), due: d(23, 10)) == .snoozed(until: d(23, 10, 5, 3)))
    }

    @Test func preAlertSnoozeCountsFromDueTime() {
        #expect(schedule().snooze(now: d(23, 9, 59, 20), due: d(23, 10)) == .snoozed(until: d(23, 10, 5)))
    }

    @Test func mergesWhenTooCloseToNextHour() {
        #expect(schedule().snooze(now: d(23, 10, 52), due: d(23, 10)) == .merged(into: d(23, 11)))
    }

    @Test func noMergeAtEndOfWindow() {
        #expect(schedule().snooze(now: d(23, 19), due: d(23, 19)) == .snoozed(until: d(23, 19, 5)))
    }
}

@Suite struct CooldownAndWakeTests {
    @Test func cooldownSuppressesNearbyHour() {
        let s = schedule()
        #expect(s.isInCooldown(reminder: d(23, 11), lastCompleted: d(23, 10, 50)))
        #expect(!s.isInCooldown(reminder: d(23, 11), lastCompleted: d(23, 10, 40)))
        #expect(!s.isInCooldown(reminder: d(23, 11), lastCompleted: nil))
    }

    @Test func cooldownIgnoresFutureCompletion() {
        // 时钟被往回调：上次完成时间在未来，不应一直判定为冷却
        #expect(!schedule().isInCooldown(reminder: d(23, 11), lastCompleted: d(23, 11, 5)))
    }

    @Test func nextReminderSkipsCooldownCandidate() {
        let s = schedule()
        #expect(s.nextReminder(after: d(23, 10, 55), lastCompleted: d(23, 10, 50)) == d(23, 12))
        #expect(s.nextReminder(after: d(23, 10, 41), lastCompleted: d(23, 10, 40)) == d(23, 11))
    }

    @Test func wakeRightBeforeHourGetsGrace() {
        let s = schedule()
        #expect(s.wakeAdjustedFire(now: d(23, 10, 58), next: d(23, 11)) == d(23, 11, 3))
        #expect(s.wakeAdjustedFire(now: d(23, 10, 50), next: d(23, 11)) == nil)
    }

    @Test func missedTriggerIsDropped() {
        let s = schedule()
        #expect(s.isMissed(due: d(23, 10), now: d(23, 10, 5)))
        #expect(!s.isMissed(due: d(23, 10), now: d(23, 10, 0, 30)))
    }

    @Test func latestReminderCatchesUpAcrossHours() {
        #expect(schedule().latestReminder(from: d(23, 10), notAfter: d(23, 11, 20)) == d(23, 11))
        #expect(schedule().latestReminder(from: d(23, 10), notAfter: d(23, 10, 40)) == d(23, 10))
    }
}
