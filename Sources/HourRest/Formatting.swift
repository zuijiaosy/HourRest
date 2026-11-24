import Foundation

enum Fmt {
    private static let hm: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.timeZone = .autoupdatingCurrent
        f.dateFormat = "HH:mm"
        return f
    }()

    private static let weekday: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.timeZone = .autoupdatingCurrent
        f.dateFormat = "EEE"  // 周一
        return f
    }()

    private static let monthDay: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.timeZone = .autoupdatingCurrent
        f.dateFormat = "M月d日"
        return f
    }()

    static func time(_ date: Date) -> String { hm.string(from: date) }

    /// 「11:00」「明天 09:00」「周一 09:00」「12月1日 09:00」
    static func relative(_ date: Date, now: Date) -> String {
        let cal = Calendar.autoupdatingCurrent
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: now), to: cal.startOfDay(for: date)).day ?? .max
        switch days {
        case 0: return time(date)
        case 1: return "明天 \(time(date))"
        case 2..<7: return "\(weekday.string(from: date)) \(time(date))"
        default: return "\(monthDay.string(from: date)) \(time(date))"
        }
    }

    /// 「还有 23 分钟」「不到 1 分钟」
    static func until(_ date: Date, now: Date) -> String {
        let seconds = date.timeIntervalSince(now)
        if seconds < 60 { return "不到 1 分钟" }
        let minutes = Int((seconds / 60).rounded(.up))
        if minutes < 60 { return "还有 \(minutes) 分钟" }
        let h = minutes / 60, m = minutes % 60
        return m == 0 ? "还有 \(h) 小时" : "还有 \(h) 小时 \(m) 分钟"
    }

    /// 「5 分钟」；调试模式下不足一分钟显示「20 秒」。
    static func duration(_ seconds: TimeInterval) -> String {
        let s = Int(seconds)
        return s < 60 ? "\(s) 秒" : "\(s / 60) 分钟"
    }

    /// 05:00
    static func countdown(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds.rounded(.up)))
        return String(format: "%02d:%02d", s / 60, s % 60)
    }
}
