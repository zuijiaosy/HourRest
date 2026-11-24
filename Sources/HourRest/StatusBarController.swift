import AppKit
import HourRestCore
import SwiftUI

/// 菜单栏图标（DESIGN.md §3.2）：模板 SF Symbol，4 种状态靠图标与不透明度区分。
@MainActor
final class StatusBarController: NSObject {
    private let engine: ReminderEngine
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private var lastAppearance: (symbol: String, title: String, alpha: CGFloat)?

    init(engine: ReminderEngine, openSettings: @escaping () -> Void) {
        self.engine = engine
        super.init()
        let content = PopoverView(
            engine: engine,
            close: { [weak self] in self?.popover.performClose(nil) },
            openSettings: { [weak self] in
                self?.popover.performClose(nil)
                openSettings()
            }
        )
        let controller = NSHostingController(rootView: content)
        controller.sizingOptions = .preferredContentSize
        popover.contentViewController = controller
        popover.behavior = .transient
        popover.animates = true

        if let button = item.button {
            button.target = self
            button.action = #selector(togglePopover)
            button.imagePosition = .imageLeading
            button.setAccessibilityLabel("整点歇")
        }
        refresh()
    }

    @objc private func togglePopover() {
        guard let button = item.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            NSApp.activate()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    func refresh() {
        guard let button = item.button else { return }
        let summary = StatusSummary(engine: engine)
        let appearance = currentAppearance(summary)
        if lastAppearance.map({ $0 != appearance }) ?? true {
            lastAppearance = appearance
            let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)
            let image = NSImage(systemSymbolName: appearance.symbol, accessibilityDescription: "整点歇")?
                .withSymbolConfiguration(config)
            image?.isTemplate = true
            button.image = image
            button.attributedTitle = NSAttributedString(
                string: appearance.title.isEmpty ? "" : " \(appearance.title)",
                attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)]
            )
            button.alphaValue = appearance.alpha
        }
        button.setAccessibilityValue(summary.accessibilityValue)
    }

    /// 与面板状态摘要保持一致：面板显示「已结束 / 未开始」时图标同样变淡。
    private func currentAppearance(_ summary: StatusSummary) -> (symbol: String, title: String, alpha: CGFloat) {
        if engine.pausedUntil != nil { return ("moon.zzz", "", 0.65) }
        if case .preAlert = engine.phase { return ("cup.and.saucer.fill", "1m", 1) }
        if summary.tone == .inactive { return ("cup.and.saucer", "", 0.45) }
        return ("cup.and.saucer", "", 1)
    }
}

/// 面板顶部的状态摘要文案（§5.3）。
struct StatusSummary {
    enum Tone { case normal, paused, inactive }
    let title: String
    let subtitle: String
    let tone: Tone

    @MainActor
    init(engine: ReminderEngine) {
        let now = engine.now
        let schedule = engine.schedule
        if let resumeAt = engine.pausedUntil {
            tone = .paused
            title = "提醒已暂停"
            if engine.pauseKind == .today {
                // 「今天」在次日首次提醒前一刻解除，直接显示那次提醒的时间更直观。
                // 过了零点仍处于「今天」暂停（如熬夜），就不再说「今天不再提醒」。
                let target = engine.nextReminder ?? resumeAt
                subtitle = Calendar.current.isDate(target, inSameDayAs: now)
                    ? "\(Fmt.time(target)) 恢复"
                    : "今天不再提醒 · \(Fmt.relative(target, now: now)) 恢复"
            } else if let next = engine.nextReminder {
                subtitle = "\(Fmt.relative(resumeAt, now: now)) 恢复 · 下次 \(Fmt.relative(next, now: now))"
            } else {
                subtitle = "\(Fmt.relative(resumeAt, now: now)) 自动恢复"
            }
            return
        }
        switch engine.phase {
        case .overlay:
            (title, subtitle, tone) = ("正在休息", "休息结束后回到工作", .normal)
        case let .preAlert(target):
            (title, subtitle, tone) = ("即将休息", "\(max(0, Int(target.timeIntervalSince(now).rounded(.up)))) 秒后开始", .normal)
        case let .snoozed(until):
            (title, subtitle, tone) = ("下次休息 \(Fmt.time(until))", "已推迟 · \(Fmt.until(until, now: now))", .normal)
        case .deferred:
            (title, subtitle, tone) = ("提醒已顺延", "检测到会议或演示，结束后提醒", .paused)
        case .idle:
            guard let next = engine.nextReminder else {
                (title, subtitle, tone) = ("没有安排提醒", "请检查设置中的生效时段", .inactive)
                return
            }
            // 冷却跳过了当天最后一次提醒时，下一次会落到明天，此时按「已结束」显示。
            let soon = next.timeIntervalSince(now) <= TimeInterval(schedule.policy.intervalMinutes * 120)
            if schedule.isInActivePeriod(now) && soon {
                (title, subtitle, tone) = ("下次休息 \(Fmt.time(next))", Fmt.until(next, now: now), .normal)
            } else if Calendar.current.isDate(next, inSameDayAs: now) {
                (title, subtitle, tone) = ("提醒尚未开始", "\(Fmt.time(next)) 开始", .inactive)
            } else {
                (title, subtitle, tone) = ("今日提醒已结束", "\(Fmt.relative(next, now: now)) 恢复", .inactive)
            }
        }
    }

    var accessibilityValue: String { "\(title)，\(subtitle)" }
}

struct PopoverView: View {
    @ObservedObject var engine: ReminderEngine
    let close: () -> Void
    let openSettings: () -> Void

    var body: some View {
        let summary = StatusSummary(engine: engine)
        VStack(alignment: .leading, spacing: 0) {
            // 1. 状态摘要
            HStack(alignment: .center, spacing: 10) {
                Circle()
                    .fill(dotColor(summary.tone))
                    .frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 2) {
                    Text(summary.title)
                        .font(.system(size: 14, weight: .semibold).monospacedDigit())
                        .foregroundStyle(Theme.textPrimary)
                    Text(summary.subtitle)
                        .font(.system(size: 12).monospacedDigit())
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
                if engine.pausedUntil != nil {
                    Button { engine.resume() } label: {
                        Label("恢复", systemImage: "arrow.counterclockwise")
                    }
                    .controlSize(.small)
                } else {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.accent)
                        Text("今日 \(engine.todayCount) 次")
                            .font(.system(size: 12, weight: .medium).monospacedDigit())
                            .foregroundStyle(Theme.textPrimary)
                    }
                    .padding(.horizontal, 9)
                    .frame(height: 26)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Theme.subtleFill))
                    .accessibilityElement(children: .combine)
                }
            }
            .frame(minHeight: 56)
            .padding(.horizontal, 4)

            Divider().padding(.vertical, 8)

            // 2. 快捷操作
            Button {
                close()
                engine.restNow()
            } label: {
                Label("立即休息", systemImage: "play.fill")
                    .font(.system(size: 13, weight: .medium))
                    .frame(maxWidth: .infinity, minHeight: 34)
            }
            .buttonStyle(PanelPrimaryButtonStyle())
            .disabled(engine.phase == .overlay)

            HStack(spacing: 6) {
                Image(systemName: "pause.circle")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.textSecondary)
                Text("暂停提醒")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                // 再点一次已选中的项即取消暂停（§3.2）。
                PauseChip(title: "1 小时", selected: engine.pauseKind == .oneHour) { togglePause(.oneHour) }
                PauseChip(title: "今天", selected: engine.pauseKind == .today) { togglePause(.today) }
            }
            .padding(.horizontal, 4)
            .padding(.top, 8)

            Divider().padding(.vertical, 8)

            // 3. 规则速览
            MenuRow(action: openSettings) {
                Text(rulesText)
                    .font(.system(size: 11.5).monospacedDigit())
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textTertiary)
            }

            Divider().padding(.vertical, 8)

            // 4. 底部菜单项
            MenuRow(action: openSettings) {
                Image(systemName: "gearshape")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
                Text("设置…").font(.system(size: 13))
                Spacer()
                Text("⌘,").font(.system(size: 12)).foregroundStyle(Theme.textTertiary)
            }
            Divider().padding(.vertical, 4)
            MenuRow(action: { NSApp.terminate(nil) }) {
                Text("退出整点歇").font(.system(size: 13))
                Spacer()
                Text("⌘Q").font(.system(size: 12)).foregroundStyle(Theme.textTertiary)
            }
        }
        .padding(12)
        .frame(width: 288)
    }

    private func togglePause(_ kind: PauseKind) {
        engine.pauseKind == kind ? engine.resume() : engine.pause(kind)
    }

    private var rulesText: String {
        let s = engine.settings
        if s.isDebug { return "调试模式 · 每 \(s.policy.intervalMinutes) 分钟提醒" }
        let days = s.weekdaysOnly ? "工作日" : "每天"
        return "每次 \(s.breakMinutes) 分钟 · \(days) \(String(format: "%02d:00–%02d:00", s.startHour, s.endHour))"
    }

    private func dotColor(_ tone: StatusSummary.Tone) -> Color {
        switch tone {
        case .normal: return Theme.accent
        case .paused: return Theme.paused
        case .inactive: return Theme.textTertiary
        }
    }
}

private struct PauseChip: View {
    let title: String
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? Theme.paused : Theme.textPrimary)
                .padding(.horizontal, 10)
                .frame(height: 26)
                .background(RoundedRectangle(cornerRadius: 6).fill(
                    selected ? Theme.pausedSoft : (hovering ? Theme.subtleFillHover : Theme.subtleFill)))
                .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct MenuRow<Content: View>: View {
    let action: () -> Void
    @ViewBuilder var content: () -> Content
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) { content() }
                .padding(.horizontal, 8)
                .frame(height: 28)
                .background(RoundedRectangle(cornerRadius: 6).fill(hovering ? Theme.subtleFillHover : Color.clear))
                .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.textPrimary)
        .onHover { hovering = $0 }
    }
}

/// 面板「立即休息」：主题色填充，悬停加深、按下变淡。
private struct PanelPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Styled(configuration: configuration)
    }

    private struct Styled: View {
        let configuration: Configuration
        @Environment(\.isEnabled) private var isEnabled
        @State private var hovering = false

        var body: some View {
            configuration.label
                .foregroundStyle(Theme.onAccent)
                .background(RoundedRectangle(cornerRadius: 8).fill(hovering ? Theme.accentHover : Theme.accent))
                .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.45)
                .contentShape(RoundedRectangle(cornerRadius: 8))
                .onHover { hovering = $0 && isEnabled }
        }
    }
}
