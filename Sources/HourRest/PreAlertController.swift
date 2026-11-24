import AppKit
import SwiftUI

/// 整点前 1 分钟的预告胶囊（DESIGN.md §3.4）：右上角非激活面板，不抢键盘焦点。
@MainActor
final class PreAlertController {
    private let engine: ReminderEngine
    private var panel: NSPanel?
    private static let size = NSSize(width: 312, height: 68)

    init(engine: ReminderEngine) {
        self.engine = engine
    }

    func show() {
        guard let screen = NSScreen.withMouse else { return }
        if panel == nil { panel = makePanel() }
        guard let panel else { return }
        let visible = screen.visibleFrame
        let finalOrigin = NSPoint(x: visible.maxX - Self.size.width - 16, y: visible.maxY - Self.size.height - 12)
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        panel.setFrameOrigin(reduceMotion ? finalOrigin : NSPoint(x: finalOrigin.x, y: finalOrigin.y + 8))
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = reduceMotion ? 0.2 : 0.3
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
            panel.animator().setFrameOrigin(finalOrigin)
        }
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: Self.size),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.contentView = FirstMouseHostingView(rootView: PreAlertView(engine: engine))
        return panel
    }
}

struct PreAlertView: View {
    @ObservedObject var engine: ReminderEngine
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(Theme.accentSoft)
                Image(systemName: "cup.and.saucer.fill")
                    .font(.system(size: 17))
                    .foregroundStyle(Theme.accent)
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(headline)
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Theme.textPrimary)
                Text("先保存手头进度，准备起身活动")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: 0)
            Button("推迟") { engine.snoozeFromPreAlert() }
                .controlSize(.small)
                .help("推迟 \(engine.schedule.policy.snoozeMinutes) 分钟")
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .frame(width: 312, height: 68)
        .background(VisualEffectBackground(material: .popover))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.hairline))
        .overlay(alignment: .topLeading) {
            // 始终挂载（只隐藏外观），VoiceOver 才能找到它。
            Button { engine.dismissPreAlert() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 16, height: 16)
                    .background(Circle().fill(.regularMaterial))
                    .overlay(Circle().strokeBorder(Theme.hairline))
            }
            .buttonStyle(.plain)
            .offset(x: 4, y: 4)
            .opacity(hovering ? 1 : 0)
            .accessibilityLabel("收起预告")
        }
        .onHover { hovering = $0 }
        .accessibilityElement(children: .contain)
    }

    private var headline: String {
        guard case let .preAlert(target) = engine.phase else { return "即将开始整点休息" }
        let seconds = Int(target.timeIntervalSince(engine.now).rounded(.up))
        return seconds >= 55 ? "1 分钟后开始整点休息" : "\(max(0, seconds)) 秒后开始休息"
    }
}
