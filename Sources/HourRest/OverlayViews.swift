import SwiftUI

/// 全屏休息提醒覆盖层（DESIGN.md §3.1）。主屏显示完整交互，副屏只显示同步倒计时。
struct OverlayRootView: View {
    @ObservedObject var session: RestSession
    let isPrimary: Bool
    var onSecondaryClick: () -> Void = {}

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        ZStack {
            background.ignoresSafeArea()
            if !isPrimary {
                // 副屏点击任意位置只把焦点交还主屏，不做任何跳过操作。
                Color.clear.contentShape(Rectangle()).onTapGesture(perform: onSecondaryClick)
            }
            Group {
                if isPrimary {
                    PrimaryOverlayContent(session: session)
                } else {
                    SecondaryOverlayContent(session: session)
                }
            }
            .scaleEffect(appeared || reduceMotion ? 1 : 0.985)
            .opacity(appeared ? 1 : 0)

            if isPrimary && session.isPreview {
                VStack {
                    Spacer()
                    Text("预览模式 · 按 Esc 退出")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textTertiary)
                        .padding(.bottom, 32)
                }
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: reduceMotion ? 0.22 : 0.38).delay(0.06)) { appeared = true }
        }
    }

    @ViewBuilder private var background: some View {
        if reduceTransparency {
            Theme.overlaySolid
        } else {
            ZStack {
                VisualEffectBackground(material: .fullScreenUI)
                Theme.overlayScrim
            }
        }
    }
}

// MARK: - 主屏

private struct PrimaryOverlayContent: View {
    @ObservedObject var session: RestSession
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 跳过按钮获得键盘焦点时，Return 交给它（弹确认条），不再触发「开始休息」。
    @FocusState private var skipFocused: Bool

    private enum StageKey { case prompting, resting, completed }

    private var stageKey: StageKey {
        switch session.stage {
        case .prompting: return .prompting
        case .resting: return .resting
        case .completed: return .completed
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            AnchorPill(text: anchorText)
                .padding(.bottom, 24)

            Text(title)
                .font(.system(size: 32, weight: .semibold))
                .tracking(-0.5)
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)

            Text(subtitle)
                .font(.system(size: 15))
                .lineSpacing(4)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
                .padding(.top, 10)

            ring.padding(.top, 36)

            activities.padding(.top, 32)

            actions.padding(.top, stageKey == .resting ? 48 : 40)
        }
        .frame(maxWidth: 560)
        .padding(64)
        .animation(reduceMotion ? .easeInOut(duration: 0.18) : .easeInOut(duration: 0.3), value: stageKey)
    }

    // MARK: 文案（§5.1）

    private var anchorText: String {
        switch (session.kind, stageKey) {
        case (.preview, _): return "预览模式"
        case (.manual, .completed): return "休息完成"
        case (.manual, _): return "正在休息 · 随时小憩"
        case let (.scheduled(anchor, snoozed, due), .prompting):
            return snoozed ? "\(Fmt.time(due)) 推迟提醒" : "\(Fmt.time(anchor)) 整点提醒"
        case let (.scheduled(anchor, _, _), .resting): return "正在休息 · \(Fmt.time(anchor))"
        case let (.scheduled(anchor, _, _), .completed): return "休息完成 · \(Fmt.time(anchor))"
        }
    }

    private var title: String {
        switch stageKey {
        case .prompting: return "到整点了，起身活动一下"
        case .resting: return "离开屏幕，活动一下"
        case .completed: return "休息完成，精神回来了"
        }
    }

    private var subtitle: String {
        switch stageKey {
        case .prompting: return "已经专注了一会儿，离开屏幕 \(Fmt.duration(session.breakDuration))，让眼睛和肩颈松一松。"
        case .resting: return "倒计时结束会提醒你回来。"
        case .completed:
            return session.isPreview
                ? "这是预览，不会计入今天的休息次数。"
                : "今天已完成第 \(session.completedToday) 次休息，随时可以回到工作。"
        }
    }


    private var snoozeTitle: String {
        switch session.snoozesLeft {
        case 0: return "已达推迟上限"
        case 1: return "推迟 \(session.snoozeMinutes) 分钟（剩 1 次）"
        default: return "推迟 \(session.snoozeMinutes) 分钟"
        }
    }

    // MARK: 倒计时环

    @ViewBuilder private var ring: some View {
        switch session.stage {
        case .prompting:
            TimerRing(progress: 1, color: Theme.accent) {
                RingLabel(time: Fmt.countdown(session.breakDuration), caption: "建议休息")
            }
        case let .resting(end, total):
            TimelineView(.periodic(from: .now, by: reduceMotion ? 1 : 0.25)) { context in
                let remaining = max(0, end.timeIntervalSince(context.date))
                TimerRing(progress: total > 0 ? remaining / total : 0, color: Theme.accent, animated: !reduceMotion) {
                    RingLabel(time: Fmt.countdown(remaining), caption: "剩余时间")
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("剩余时间")
                .accessibilityValue("\(Int(remaining.rounded(.up)) / 60) 分 \(Int(remaining.rounded(.up)) % 60) 秒")
            }
        case .completed:
            TimerRing(progress: 1, color: Theme.success) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(Theme.success)
                    .shadow(color: Theme.success.opacity(0.35), radius: 18)
                    .accessibilityLabel("休息完成")
            }
        }
    }

    // MARK: 活动建议

    @ViewBuilder private var activities: some View {
        switch stageKey {
        case .prompting:
            HStack(spacing: 10) {
                ForEach(session.activities, id: \.self) { a in
                    HStack(spacing: 6) {
                        Image(systemName: a.symbol).font(.system(size: 14)).foregroundStyle(Theme.accent)
                        Text(a.short).font(.system(size: 13)).foregroundStyle(Theme.textPrimary)
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 36)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Theme.subtleFill))
                }
            }
        case .resting:
            // 每 60 秒平缓切换一条引导句。
            TimelineView(.periodic(from: .now, by: 60)) { context in
                let index = Int(context.date.timeIntervalSinceReferenceDate / 60) % session.activities.count
                Text(session.activities[index].sentence)
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.textSecondary)
                    .id(index)
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.6), value: index)
            }
        case .completed:
            EmptyView()
        }
    }

    // MARK: 操作区

    @ViewBuilder private var actions: some View {
        switch session.stage {
        case .prompting:
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Button("开始休息") { session.startRest() }
                        .buttonStyle(PillButtonStyle(prominent: true, minWidth: 156))
                        .keyboardShortcut(session.confirmation == nil && !skipFocused ? .defaultAction : nil)
                    Button { session.snooze() } label: {
                        Label(snoozeTitle, systemImage: "clock.arrow.circlepath")
                    }
                    .buttonStyle(PillButtonStyle(prominent: false, minWidth: 136))
                    .disabled(session.snoozesLeft == 0)
                }
                Group {
                    if session.confirmation == .skip {
                        ConfirmBar(question: "确定跳过这次休息？", keep: "返回休息", confirm: "确认跳过",
                                   onKeep: { session.confirmation = nil }, onConfirm: { session.skip() })
                    } else {
                        HoldToSkipButton(onComplete: { session.skip() },
                                         onRequestConfirm: { session.confirmation = .skip },
                                         focused: $skipFocused)
                    }
                }
                .padding(.top, 16)
                Text("按 Return 开始休息 · 长按跳过按钮 1.5 秒可跳过")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.top, 20)
            }
        case let .resting(end, _):
            if session.confirmation == .endEarly {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    ConfirmBar(question: "还剩 \(Fmt.countdown(end.timeIntervalSince(context.date)))，确定提前结束？",
                               keep: "继续休息", confirm: "结束休息",
                               onKeep: { session.confirmation = nil }, onConfirm: { session.endEarly() })
                }
            } else {
                Button("提前结束") { session.confirmation = .endEarly }
                    .buttonStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textTertiary)
            }
        case .completed:
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Button("回去工作") { session.finish() }
                        .buttonStyle(PillButtonStyle(prominent: true, minWidth: 156))
                        .keyboardShortcut(.defaultAction)
                    Button("再多歇 2 分钟") { session.extend() }
                        .buttonStyle(PillButtonStyle(prominent: false))
                }
                Text(session.isPreview ? "按 Return 或 Esc 退出预览" : "按 Return 或 Esc 回到工作")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.top, 20)
            }
        }
    }
}

// MARK: - 副屏

private struct SecondaryOverlayContent: View {
    @ObservedObject var session: RestSession

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "cup.and.saucer")
                .font(.system(size: 24))
                .foregroundStyle(Theme.textSecondary)
            Group {
                switch session.stage {
                case .prompting:
                    Text(Fmt.countdown(session.breakDuration))
                case let .resting(end, _):
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(Fmt.countdown(end.timeIntervalSince(context.date)))
                    }
                case .completed:
                    Text("休息完成")
                }
            }
            .font(.system(size: 44, weight: .light).monospacedDigit())
            .foregroundStyle(Theme.textPrimary)
            Text(session.stage == .completed ? "休息完成 · 在主屏幕返回工作" : "请在主屏幕操作")
                .font(.system(size: 13))
                .foregroundStyle(Theme.textTertiary)
        }
    }
}

// MARK: - 组件

private struct AnchorPill: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .medium).monospacedDigit())
            .foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background(Capsule().fill(Theme.subtleFill))
            .overlay(Capsule(style: .circular).strokeBorder(Theme.hairline))
    }
}

private struct TimerRing<Center: View>: View {
    var progress: Double
    var color: Color
    var animated = false
    @ViewBuilder var center: () -> Center

    var body: some View {
        ZStack {
            Circle().stroke(Theme.ringTrack, lineWidth: 4)
            Circle()
                .trim(from: 0, to: min(1, max(0, progress)))
                .stroke(color, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(animated ? .linear(duration: 0.25) : nil, value: progress)
            center()
        }
        .frame(width: 208, height: 208)
    }
}

private struct RingLabel: View {
    let time: String
    let caption: String

    var body: some View {
        VStack(spacing: 4) {
            Text(time)
                .font(.system(size: 56, weight: .light).monospacedDigit())
                .tracking(-1)
                .foregroundStyle(Theme.textPrimary)
            Text(caption)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
        }
    }
}

private struct ConfirmBar: View {
    let question: String
    let keep: String
    let confirm: String
    let onKeep: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text(question)
                .font(.system(size: 13).monospacedDigit())
                .foregroundStyle(Theme.textSecondary)
            Button(keep, action: onKeep)
                .buttonStyle(PillButtonStyle(prominent: true, height: 30))
                .keyboardShortcut(.defaultAction)  // Return = 保守选项
            Button(confirm, action: onConfirm)
                .buttonStyle(PillButtonStyle(prominent: false, height: 30))
        }
        .padding(.leading, 16)
        .padding(.trailing, 6)
        .padding(.vertical, 6)
        .background(Capsule().fill(Theme.subtleFill))
        .overlay(Capsule(style: .circular).strokeBorder(Theme.hairline))
    }
}

/// 「长按跳过本次」：鼠标按住 1.5 秒才生效，未满松手或拖出按钮都会回弹（§4.2）。
/// 键盘（聚焦后按空格 / Return）、VoiceOver、以及开启「减弱动态效果」时的点击，都改为行内二次确认。
private struct HoldToSkipButton: View {
    let onComplete: () -> Void
    let onRequestConfirm: () -> Void
    var focused: FocusState<Bool>.Binding

    private let duration: TimeInterval = 1.5
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var progress: CGFloat = 0
    @State private var holding = false
    @State private var pending: DispatchWorkItem?
    @State private var hovering = false
    @State private var size: CGSize = .zero

    var body: some View {
        // 用较长的文案占位，按下切换文案时按钮宽度不跳动。
        ZStack {
            Text("继续按住以跳过…").hidden()
            Text(holding ? "继续按住以跳过…" : "长按跳过本次")
        }
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(holding || hovering ? Theme.textPrimary : Theme.textSecondary)
            .padding(.horizontal, 16)
            .frame(height: 34)
            .background(alignment: .leading) {
                GeometryReader { geo in
                    Rectangle().fill(Theme.accentSoft).frame(width: geo.size.width * progress)
                        .onAppear { size = geo.size }
                        .onChange(of: geo.size) { size = geo.size }
                }
            }
            .background(hovering ? Theme.subtleFill : Color.clear)
            .clipShape(Capsule())
            .overlay(focusRing)
            .contentShape(Capsule())
            .onHover { hovering = $0 }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard !reduceMotion else { return }
                        // 拖出按钮即取消，和系统按钮的行为一致。
                        isInside(value.location) ? begin() : cancel()
                    }
                    .onEnded { value in
                        if reduceMotion && isInside(value.location) { onRequestConfirm() }
                        cancel()
                    }
            )
            .focusable()
            .focused(focused)
            .onKeyPress(keys: [.space, .return]) { _ in
                onRequestConfirm()
                return .handled
            }
            .accessibilityElement()
            .accessibilityLabel("跳过本次休息")
            .accessibilityHint("点击后需再次确认以跳过本次休息")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { onRequestConfirm() }
            .onDisappear { pending?.cancel() }
    }

    /// 键盘焦点用 2pt 鼠尾草绿高对比描边（§8.3）；按住时用细描边。
    @ViewBuilder private var focusRing: some View {
        if focused.wrappedValue {
            Capsule(style: .circular).strokeBorder(Theme.accent, lineWidth: 2)
        } else if holding {
            Capsule(style: .circular).strokeBorder(Theme.hairline)
        }
    }

    /// 命中区域留 8pt 余量。
    private func isInside(_ point: CGPoint) -> Bool {
        CGRect(origin: .zero, size: size).insetBy(dx: -8, dy: -8).contains(point)
    }

    private func begin() {
        guard !holding else { return }
        holding = true
        withAnimation(.linear(duration: duration)) { progress = 1 }
        let item = DispatchWorkItem {
            holding = false
            onComplete()
        }
        pending = item
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: item)
    }

    private func cancel() {
        guard holding else { return }
        pending?.cancel()
        pending = nil
        holding = false
        withAnimation(.easeOut(duration: 0.18)) { progress = 0 }
    }
}
