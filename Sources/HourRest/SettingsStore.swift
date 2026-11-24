import Foundation
import HourRestCore
import ServiceManagement

/// 设置项，持久化到 UserDefaults。
@MainActor
final class SettingsStore: ObservableObject {
    private let defaults: UserDefaults
    /// 任一会影响调度的设置变化时回调（由 ReminderEngine 订阅）。
    var onScheduleChange: (() -> Void)?

    // 只有影响「何时提醒」的设置才通知引擎重新调度。
    @Published var breakMinutes: Int { didSet { save(breakMinutes, Key.breakMinutes) } }
    @Published var startHour: Int { didSet { save(startHour, Key.startHour, reschedule: true) } }
    @Published var endHour: Int { didSet { save(endHour, Key.endHour, reschedule: true) } }
    @Published var weekdaysOnly: Bool { didSet { save(weekdaysOnly, Key.weekdaysOnly, reschedule: true) } }
    @Published var preAlertEnabled: Bool { didSet { save(preAlertEnabled, Key.preAlert, reschedule: true) } }
    @Published var soundEnabled: Bool { didSet { save(soundEnabled, Key.sound) } }
    @Published var deferDuringMeetings: Bool { didSet { save(deferDuringMeetings, Key.deferMeetings) } }

    /// 「登录时自动启动」以系统登录项为准，每次打开设置窗口时刷新。
    @Published private(set) var launchAtLogin = false
    @Published private(set) var launchMessage: String?

    /// 调试策略：启动参数 `-debugIntervalMinutes 2 -debugBreakSeconds 20`。
    let policy: SchedulePolicy

    private enum Key {
        static let breakMinutes = "breakMinutes"
        static let startHour = "startHour"
        static let endHour = "endHour"
        static let weekdaysOnly = "weekdaysOnly"
        static let preAlert = "preAlertEnabled"
        static let sound = "soundEnabled"
        static let deferMeetings = "deferDuringMeetings"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.breakMinutes: 5, Key.startHour: 0, Key.endHour: 23, Key.weekdaysOnly: false,
            Key.preAlert: true, Key.sound: true, Key.deferMeetings: true,
        ])
        breakMinutes = min(10, max(5, defaults.integer(forKey: Key.breakMinutes)))
        let start = min(22, max(0, defaults.integer(forKey: Key.startHour)))
        startHour = start
        endHour = min(23, max(start + 1, defaults.integer(forKey: Key.endHour)))
        weekdaysOnly = defaults.bool(forKey: Key.weekdaysOnly)
        preAlertEnabled = defaults.bool(forKey: Key.preAlert)
        soundEnabled = defaults.bool(forKey: Key.sound)
        deferDuringMeetings = defaults.bool(forKey: Key.deferMeetings)

        let debugInterval = defaults.integer(forKey: "debugIntervalMinutes")
        let debugBreak = defaults.double(forKey: "debugBreakSeconds")
        policy = debugInterval > 0
            ? .debug(intervalMinutes: debugInterval, breakSeconds: debugBreak > 0 ? debugBreak : nil)
            : .standard
    }

    var isDebug: Bool { policy != .standard }

    var reminderSettings: ReminderSettings {
        ReminderSettings(breakMinutes: breakMinutes, startHour: startHour, endHour: endHour, weekdaysOnly: weekdaysOnly)
    }

    var schedule: ReminderSchedule {
        ReminderSchedule(settings: reminderSettings, policy: policy)
    }

    private func save(_ value: Any, _ key: String, reschedule: Bool = false) {
        defaults.set(value, forKey: key)
        if reschedule { onScheduleChange?() }
    }

    var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    // MARK: 登录时自动启动（SMAppService，需从 .app 包运行）

    func refreshLaunchAtLogin() {
        launchAtLogin = SMAppService.mainApp.status == .enabled
        launchMessage = SMAppService.mainApp.status == .requiresApproval ? Self.approvalHint : nil
    }

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            refreshLaunchAtLogin()
        } catch {
            refreshLaunchAtLogin()
            launchMessage = Bundle.main.bundleURL.pathExtension == "app"
                ? "设置失败：\(error.localizedDescription)"
                : "需要从打包好的 HourRest.app 运行才能设置开机启动"
        }
    }

    private static let approvalHint = "请在「系统设置 › 通用 › 登录项」中允许整点歇"
}
