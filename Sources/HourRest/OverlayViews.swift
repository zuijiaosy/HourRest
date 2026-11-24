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

    var body: some View {
        VStack(spacing: 0) {
            AnchorPill(text: anchorText)
                .padding(.bottom, 24)

            Text("离开屏幕，活动一下")
                .font(.system(size: 32, weight: .semibold))
                .tracking(-0.5)
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)

            Text("倒计时结束后自动关闭。")
                .font(.system(size: 15))
                .lineSpacing(4)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
                .padding(.top, 10)

            ring.padding(.top, 36)

            activity.padding(.top, 32)

            // 不绑定 Return：提醒弹出时用户可能正在打字，按键不应结束休息。
            Button("提前结束") { session.endEarly() }
                .buttonStyle(PillButtonStyle(prominent: false, minWidth: 136))
                .padding(.top, 48)
        }
        .frame(maxWidth: 560)
        .padding(64)
    }

    private var anchorText: String {
        switch session.kind {
        case .preview: return "预览模式"
        case .manual: return "正在休息 · 随时小憩"
        case let .scheduled(anchor): return "正在休息 · \(Fmt.time(anchor)) 整点"
        }
    }

    // MARK: 倒计时环

    private var ring: some View {
        TimelineView(.periodic(from: .now, by: reduceMotion ? 1 : 0.25)) { context in
            let remaining = max(0, session.end.timeIntervalSince(context.date))
            TimerRing(progress: session.total > 0 ? remaining / session.total : 0, color: Theme.accent, animated: !reduceMotion) {
                RingLabel(time: Fmt.countdown(remaining), caption: "剩余时间")
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("剩余时间")
            .accessibilityValue("\(Int(remaining.rounded(.up)) / 60) 分 \(Int(remaining.rounded(.up)) % 60) 秒")
        }
    }

    // MARK: 活动建议

    /// 每 60 秒平缓切换一条引导句。
    private var activity: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let index = Int(context.date.timeIntervalSinceReferenceDate / 60) % session.activities.count
            Text(session.activities[index].sentence)
                .font(.system(size: 15))
                .foregroundStyle(Theme.textSecondary)
                .id(index)
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.6), value: index)
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
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(Fmt.countdown(max(0, session.end.timeIntervalSince(context.date))))
            }
            .font(.system(size: 44, weight: .light).monospacedDigit())
            .foregroundStyle(Theme.textPrimary)
            Text("倒计时结束后自动关闭")
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
