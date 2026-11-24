import AppKit
import HourRestCore
import os

private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "HourRest", category: "engine")

/// 引擎通知 UI 层显示 / 隐藏各个界面。
@MainActor
protocol EngineUI: AnyObject {
    func showOverlay(_ session: RestSession)
    func hideOverlay()
    func showPreAlert()
    func hidePreAlert()
    func announce(_ text: String)
    func engineDidTick()
}

/// 调度核心：每秒检查一次绝对时间（不累加计时，避免漂移），按 DESIGN.md §4 的状态机推进。
@MainActor
final class ReminderEngine: ObservableObject {
    enum Phase: Equatable {
        case idle
        case preAlert(target: Date)
        case snoozed(until: Date)
        case deferred(until: Date)
        case overlay
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var now = Date()
    /// 空闲时下一次提醒（已考虑暂停与冷却期）。
    @Published private(set) var nextReminder: Date? {
        didSet {
            guard nextReminder != oldValue else { return }
            log.info("下一次提醒：\(self.nextReminder?.description(with: .current) ?? "无", privacy: .public)")
        }
    }
    @Published private(set) var pausedUntil: Date?
    @Published private(set) var pauseKind: PauseKind?
    @Published private(set) var todayCount = 0

    weak var ui: EngineUI?
    let settings: SettingsStore
    private let meetings = MeetingDetector()
    private let defaults: UserDefaults

    private var session: RestSession?
    private var previewSession: RestSession?
    /// 预告胶囊被用户点 × 收起（整点仍会全屏提醒）。
    private var preAlertDismissed = false
    /// 当前这一轮提醒原定的整点。
    private var anchor: Date?
    private var snoozeCount = 0
    private var lastCompleted: Date?
    private var countedCurrentSession = false
    private var timer: Timer?
    /// 应用生命周期内常驻，无需移除。
    private var observers: [NSObjectProtocol] = []

    private enum Key {
        static let countDay = "todayCountDay"
        static let count = "todayCount"
        static let pausedUntil = "pausedUntil"
        static let pauseKind = "pauseKind"
        static let lastCompleted = "lastCompleted"
    }

    init(settings: SettingsStore, defaults: UserDefaults = .standard) {
        self.settings = settings
        self.defaults = defaults
        restore()
        settings.onScheduleChange = { [weak self] in self?.scheduleChanged() }
    }

    var schedule: ReminderSchedule { settings.schedule }

    func start() {
        log.info("启动，策略：每 \(self.schedule.policy.intervalMinutes) 分钟，时段 \(self.settings.startHour):00–\(self.settings.endHour):00，仅工作日 \(self.settings.weekdaysOnly)")
        nextReminder = computeNext(Date())
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        t.tolerance = 0.2
        RunLoop.main.add(t, forMode: .common)
        timer = t

        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.handleWake() }
        })
        for name in [Notification.Name.NSSystemClockDidChange, .NSSystemTimeZoneDidChange] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.scheduleChanged() }
            })
        }
        // 跨日不改变规则，只需立刻推进一次（计数归零、触发 00:00 提醒）；重算反而会把 00:00 算丢。
        observers.append(NotificationCenter.default.addObserver(forName: .NSCalendarDayChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        })
        tick()
    }

    /// 下一次提醒：暂停中从暂停结束算起，并跳过刚休息完的冷却期。
    private func computeNext(_ now: Date) -> Date? {
        schedule.nextReminder(after: pausedUntil.map { max($0, now) } ?? now, lastCompleted: lastCompleted)
    }

    // MARK: 每秒推进

    func tick() {
        let now = Date()
        self.now = now
        rollOverCountIfNeeded(now)
        if let p = pausedUntil, now >= p { resume() }

        switch phase {
        case .idle:
            guard pausedUntil == nil else { break }
            guard let next = nextReminder else {
                nextReminder = computeNext(now)
                break
            }
            if now >= next {
                fire(anchor: next, due: next, now: now)
            } else if settings.preAlertEnabled, next.timeIntervalSince(now) <= schedule.policy.preAlertLead {
                phase = .preAlert(target: next)
                preAlertDismissed = false
                ui?.showPreAlert()
            }
        case let .preAlert(target):
            if now >= target { fire(anchor: target, due: target, now: now) }
        case let .snoozed(until), let .deferred(until):
            if now >= until { fire(anchor: anchor ?? until, due: until, now: now) }
        case .overlay:
            session?.tick(now)
        }
        previewSession?.tick(now)
        ui?.engineDidTick()
    }

    private func fire(anchor: Date, due: Date, now: Date) {
        if schedule.isMissed(due: due, now: now) {
            log.info("跳过：触发时刻已错过（可能在休眠）")
            goIdle(now)
            return
        }
        // 会议顺延期间若又跨过了整点，标签更新为最近的整点，推迟次数重新计算。
        let latest = schedule.latestReminder(from: anchor, notAfter: now)
        if case .deferred = phase, !schedule.isInActivePeriod(now),
           now.timeIntervalSince(latest) >= TimeInterval(schedule.policy.intervalMinutes * 60) {
            log.info("放弃：会议一直开到生效时段之外")
            goIdle(now)
            return
        }
        if latest != anchor { snoozeCount = 0 }
        self.anchor = latest

        if settings.deferDuringMeetings, meetings.isInMeeting() {
            log.info("顺延：检测到摄像头正在使用")
            ui?.hidePreAlert()
            phase = .deferred(until: now.addingTimeInterval(schedule.policy.meetingRecheck))
            return
        }
        log.info("触发全屏提醒")
        present(RestSession(
            kind: .scheduled(anchor: latest, snoozed: snoozeCount > 0, due: due),
            breakDuration: schedule.breakDuration,
            snoozeMinutes: schedule.policy.snoozeMinutes,
            snoozesLeft: max(0, schedule.policy.maxSnoozes - snoozeCount),
            completedToday: todayCount
        ))
    }

    private func present(_ s: RestSession) {
        previewSession = nil  // 真正的提醒优先于正在进行的预览
        ui?.hidePreAlert()
        countedCurrentSession = false
        bind(s)
        session = s
        phase = .overlay
        ui?.showOverlay(s)
    }

    private func bind(_ s: RestSession) {
        s.onEvent = { [weak self, weak s] event in
            guard let self, let s else { return }
            self.handle(event, from: s)
        }
    }

    private func handle(_ event: RestSession.Event, from s: RestSession) {
        // 淡出中的旧会话（双击、紧跟着按 Return）不再生效。
        guard s === (s.isPreview ? previewSession : session) else { return }
        let now = Date()
        log.info("全屏提醒事件：\(String(describing: event), privacy: .public)\(s.isPreview ? "（预览）" : "", privacy: .public)")
        if event == .completed { ui?.announce("休息完成") }
        if s.isPreview {
            switch event {
            case .startedRest, .completed: playSound(for: event)
            default: closePreview()
            }
            return
        }
        switch event {
        case .startedRest:
            playSound(for: event)
        case .completed:
            playSound(for: event)
            if !countedCurrentSession {
                countedCurrentSession = true
                todayCount += 1
                s.completedToday = todayCount
                saveCount(now)
            }
            lastCompleted = now
            defaults.set(now, forKey: Key.lastCompleted)
        case .snoozed:
            guard case let .scheduled(_, _, due) = s.kind else { return goIdle(now) }
            applySnooze(now: now, due: due)
        case .skipped, .endedEarly, .dismissed:
            goIdle(now)
        }
    }

    private func applySnooze(now: Date, due: Date) {
        switch schedule.snooze(now: now, due: due) {
        case let .merged(into: next):
            goIdle(now)
            nextReminder = next
        case let .snoozed(until):
            snoozeCount += 1
            if anchor == nil { anchor = due }
            session = nil
            ui?.hideOverlay()
            ui?.hidePreAlert()
            phase = .snoozed(until: until)
        }
    }

    private func goIdle(_ now: Date) {
        let hadOverlay = session != nil
        phase = .idle
        anchor = nil
        snoozeCount = 0
        session = nil
        if hadOverlay { ui?.hideOverlay() }
        ui?.hidePreAlert()
        nextReminder = computeNext(now)
    }

    // MARK: 菜单栏 / 预告 / 设置窗口调用

    /// 「立即休息」：直接进入休息倒计时，丢弃挂起的推迟。
    func restNow() {
        guard phase != .overlay else { return }
        anchor = nil
        snoozeCount = 0
        present(RestSession(kind: .manual, breakDuration: schedule.breakDuration,
                            snoozeMinutes: schedule.policy.snoozeMinutes, snoozesLeft: 0, completedToday: todayCount))
    }

    /// 预告胶囊上的「推迟」。
    func snoozeFromPreAlert() {
        guard case let .preAlert(target) = phase else { return }
        anchor = target
        applySnooze(now: Date(), due: target)
    }

    /// 预告胶囊上的 ×：只收起预告。
    func dismissPreAlert() {
        preAlertDismissed = true
        ui?.hidePreAlert()
    }

    func pause(_ kind: PauseKind) {
        let now = Date()
        if phase != .overlay { goIdle(now) }
        pausedUntil = schedule.pauseEnd(kind, from: now)
        pauseKind = kind
        defaults.set(pausedUntil, forKey: Key.pausedUntil)
        defaults.set(kind.rawValue, forKey: Key.pauseKind)
        nextReminder = computeNext(now)
        ui?.engineDidTick()
    }

    func resume() {
        pausedUntil = nil
        pauseKind = nil
        defaults.removeObject(forKey: Key.pausedUntil)
        defaults.removeObject(forKey: Key.pauseKind)
        if phase == .idle { nextReminder = computeNext(Date()) }
        ui?.engineDidTick()
    }

    /// 设置窗口「预览全屏提醒」：不影响计数与调度。
    func preview() {
        guard phase != .overlay else { return }
        let s = RestSession(kind: .preview, breakDuration: schedule.breakDuration,
                            snoozeMinutes: schedule.policy.snoozeMinutes,
                            snoozesLeft: schedule.policy.maxSnoozes, completedToday: todayCount)
        bind(s)
        previewSession = s
        ui?.hidePreAlert()
        ui?.showOverlay(s)
    }

    private func closePreview() {
        previewSession = nil
        ui?.hideOverlay()
        if case .preAlert = phase, !preAlertDismissed { ui?.showPreAlert() }
    }

    // MARK: 系统事件

    /// 设置或系统时钟变化后重算。以「尚未触发的那次提醒」为基准：恰好在整点那一瞬间收到通知时，
    /// 这次提醒不会被算丢；已过期太久的由 tick → fire 按 missTolerance 丢弃。
    private func scheduleChanged() {
        let now = Date()
        self.now = now
        switch phase {
        case .idle, .preAlert:
            let pending = min(nextReminder ?? now, now).addingTimeInterval(-0.001)
            let next = computeNext(pending)
            if case let .preAlert(target) = phase {
                // 不变就别打扰（也不让已收起的预告重弹）；时钟被往回调出了预告窗口则收起。
                if next == target && settings.preAlertEnabled
                    && target.timeIntervalSince(now) <= schedule.policy.preAlertLead { break }
                phase = .idle
                ui?.hidePreAlert()
            }
            nextReminder = next
        default:
            break
        }
        ui?.engineDidTick()
    }

    /// 休眠期间错过的提醒不补弹；唤醒后马上就到整点时给 5 分钟缓冲（§4.3）。
    private func handleWake() {
        let now = Date()
        self.now = now
        if let p = pausedUntil, now >= p { resume() }
        if phase == .overlay {
            // 合盖前停在「提醒到达」没处理，醒来时它已过时，收起而不是继续挂着几小时前的提醒。
            guard let s = session, s.stage == .prompting, case let .scheduled(_, _, due) = s.kind,
                  now.timeIntervalSince(due) >= TimeInterval(schedule.policy.intervalMinutes * 30) else { return }
            log.info("唤醒：收起过时的提醒")
        }
        goIdle(now)
        guard pausedUntil == nil, let next = nextReminder,
              let delayed = schedule.wakeAdjustedFire(now: now, next: next) else { return }
        anchor = next
        phase = .snoozed(until: delayed)
    }

    // MARK: 持久化

    private func restore() {
        if let p = defaults.object(forKey: Key.pausedUntil) as? Date, p > Date() {
            pausedUntil = p
            pauseKind = defaults.string(forKey: Key.pauseKind).flatMap(PauseKind.init(rawValue:))
        }
        lastCompleted = defaults.object(forKey: Key.lastCompleted) as? Date
        rollOverCountIfNeeded(Date())
    }

    private func dayKey(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return "\(c.year!)-\(c.month!)-\(c.day!)"
    }

    private func rollOverCountIfNeeded(_ now: Date) {
        let key = dayKey(now)
        if defaults.string(forKey: Key.countDay) == key {
            let stored = defaults.integer(forKey: Key.count)
            if stored != todayCount { todayCount = stored }
        } else {
            todayCount = 0
            defaults.set(key, forKey: Key.countDay)
            defaults.set(0, forKey: Key.count)
        }
    }

    private func saveCount(_ now: Date) {
        defaults.set(dayKey(now), forKey: Key.countDay)
        defaults.set(todayCount, forKey: Key.count)
    }

    private func playSound(for event: RestSession.Event) {
        guard settings.soundEnabled else { return }
        NSSound(named: event == .completed ? "Glass" : "Tink")?.play()
    }
}
