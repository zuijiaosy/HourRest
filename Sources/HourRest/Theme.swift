import AppKit
import SwiftUI

/// DESIGN.md §6.1 配色 Token。浅色 / 深色由系统外观自动切换。
enum Theme {
    static let overlayScrim = dynamic(light: rgba(244, 246, 244, 0.84), dark: rgba(18, 22, 21, 0.86))
    /// 开启「降低透明度」时的纯色底（§8）。
    static let overlaySolid = dynamic(light: hex(0xF2F4F2), dark: hex(0x161A19))
    static let subtleFill = dynamic(light: rgba(28, 36, 33, 0.055), dark: rgba(240, 246, 243, 0.08))
    static let subtleFillHover = dynamic(light: rgba(28, 36, 33, 0.10), dark: rgba(240, 246, 243, 0.14))
    static let hairline = dynamic(light: rgba(28, 36, 33, 0.10), dark: rgba(255, 255, 255, 0.10))
    static let textPrimary = dynamic(light: hex(0x17211E), dark: hex(0xF0F5F3))
    static let textSecondary = dynamic(light: hex(0x4D5E58), dark: hex(0xA7B5B0))
    static let textTertiary = dynamic(light: hex(0x6E7D78), dark: hex(0x7F8E89))
    static let accent = dynamic(light: hex(0x266D5D), dark: hex(0x52B79E))
    static let accentHover = dynamic(light: hex(0x1F5B4E), dark: hex(0x66C4AC))
    static let onAccent = dynamic(light: hex(0xFFFFFF), dark: hex(0x0F241F))
    static let accentSoft = dynamic(light: rgba(38, 109, 93, 0.12), dark: rgba(82, 183, 158, 0.16))
    static let paused = dynamic(light: hex(0xB26A00), dark: hex(0xE5A93B))
    static let pausedSoft = dynamic(light: rgba(178, 106, 0, 0.12), dark: rgba(229, 169, 59, 0.16))
    static let ringTrack = dynamic(light: rgba(28, 36, 33, 0.10), dark: rgba(240, 246, 243, 0.12))

    private static func dynamic(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        })
    }

    private static func hex(_ v: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
                blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }

    private static func rgba(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat) -> NSColor {
        NSColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: a)
    }
}

/// 原生磨砂材质（NSVisualEffectView）。
struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blending: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = blending
        v.state = .active
        return v
    }

    func updateNSView(_ v: NSVisualEffectView, context: Context) {
        v.material = material
        v.blendingMode = blending
    }
}

/// 全屏层的胶囊按钮（主按钮实心鼠尾草绿，次按钮半透明磨砂描边）。
struct PillButtonStyle: ButtonStyle {
    var prominent: Bool
    var minWidth: CGFloat = 0

    func makeBody(configuration: Configuration) -> some View {
        PillButton(configuration: configuration, prominent: prominent, minWidth: minWidth)
    }

    private struct PillButton: View {
        let configuration: Configuration
        let prominent: Bool
        let minWidth: CGFloat
        @Environment(\.isEnabled) private var isEnabled
        @State private var hovering = false

        var body: some View {
            configuration.label
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(prominent ? Theme.onAccent : Theme.textPrimary)
                .padding(.horizontal, prominent ? 24 : 20)
                .frame(minWidth: minWidth, minHeight: 44)
                .background(
                    Capsule().fill(prominent
                                   ? (hovering ? Theme.accentHover : Theme.accent)
                                   : (hovering ? Theme.subtleFillHover : Theme.subtleFill))
                )
                .overlay(Capsule(style: .circular).strokeBorder(prominent ? Color.clear : Theme.hairline))
                .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.45)
                .contentShape(Capsule())
                .onHover { hovering = $0 && isEnabled }
        }
    }
}

/// 让无边框 / 非激活窗口里的按钮第一次点击就生效。
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
