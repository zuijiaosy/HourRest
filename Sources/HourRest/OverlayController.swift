import AppKit
import SwiftUI

/// 覆盖所有显示器的无边框面板。只有主屏那块能成为 key window 接收键盘。
/// 用非激活面板：macOS 14 起应用激活是「协商式」的，用户正在别的应用里打字时 NSApp.activate() 可能被拒，
/// 普通窗口就拿不到键盘，按键会穿透到被遮住的编辑器里；非激活面板不需要激活应用也能成为 key window。
final class OverlayWindow: NSPanel {
    var isPrimary = false
    override var canBecomeKey: Bool { isPrimary }
    override var canBecomeMain: Bool { isPrimary }

    /// 淡出中（或副屏）的窗口吞掉所有按键，避免旧界面上的 Return 等快捷键还生效。
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        isPrimary ? super.performKeyEquivalent(with: event) : true
    }

    override func keyDown(with event: NSEvent) {
        if isPrimary { super.keyDown(with: event) }
    }
}

/// 管理全屏覆盖层窗口（DESIGN.md §9.2）：每块屏幕一个窗口，光标所在屏为主屏，热插拔时重建。
@MainActor
final class OverlayController {
    private var windows: [OverlayWindow] = []
    private var session: RestSession?
    private var keyMonitor: Any?
    private var screenObserver: NSObjectProtocol?

    init() {
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.session != nil else { return }
                self.rebuildWindows(animated: false)
            }
        }
    }

    func show(_ session: RestSession) {
        let alreadyShowing = self.session != nil
        self.session = session
        rebuildWindows(animated: !alreadyShowing)
        installKeyMonitor()

        if session.stage == .prompting {
            announce("到整点了，建议休息 \(Fmt.duration(session.breakDuration))")
        }
    }

    func announce(_ text: String) {
        guard let element = windows.first(where: \.isPrimary) ?? NSApp.windows.first else { return }
        NSAccessibility.post(element: element, notification: .announcementRequested, userInfo: [
            .announcement: text,
            .priority: NSAccessibilityPriorityLevel.high.rawValue,
        ])
    }

    func hide() {
        guard session != nil else { return }
        session = nil
        removeKeyMonitor()
        let closing = windows
        windows = []
        // 淡出期间不再接受点击和按键，避免双击「推迟」之类的重复操作。
        closing.forEach {
            $0.ignoresMouseEvents = true
            $0.isPrimary = false
        }
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = reduceMotion ? 0.18 : 0.26
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            closing.forEach { $0.animator().alphaValue = 0 }
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                closing.forEach { $0.orderOut(nil) }
                // 淡出期间又弹出了新的覆盖层，就不要动前台。
                guard let self, self.session == nil else { return }
                // 从菜单栏面板点「立即休息」时本应用是激活的；关掉覆盖层后若没有其他可交互窗口
                //（设置窗口、刚打开的面板），就把前台交还给之前的应用，免得键盘落空。
                let hasOtherWindow = NSApp.windows.contains { $0.isVisible && $0.canBecomeKey }
                if NSApp.isActive && !hasOtherWindow { NSApp.hide(nil) }
            }
        })
    }

    private func rebuildWindows(animated: Bool) {
        guard let session else { return }
        windows.forEach { $0.orderOut(nil) }
        windows = []

        guard let primaryScreen = NSScreen.withMouse else { return }

        for screen in NSScreen.screens {
            let isPrimary = screen == primaryScreen
            let window = OverlayWindow(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel],
                                       backing: .buffered, defer: false)
            window.hidesOnDeactivate = false
            window.becomesKeyOnlyIfNeeded = false
            window.isPrimary = isPrimary
            window.level = .screenSaver
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.isReleasedWhenClosed = false
            window.animationBehavior = .none
            window.contentView = FirstMouseHostingView(rootView: OverlayRootView(
                session: session, isPrimary: isPrimary,
                onSecondaryClick: { [weak self] in self?.focusPrimary() }
            ))
            window.setFrame(screen.frame, display: true)
            window.alphaValue = animated ? 0 : 1
            // 应用未激活时也要排到最前（含第三方全屏 Space），主屏再成为 key window 接收键盘。
            window.orderFrontRegardless()
            if isPrimary { window.makeKey() }
            windows.append(window)
        }

        if animated {
            let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = reduceMotion ? 0.22 : 0.42
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                windows.forEach { $0.animator().alphaValue = 1 }
            }
        }
    }

    private func focusPrimary() {
        windows.first(where: \.isPrimary)?.makeKey()
    }

    /// Esc 不直接关闭：交给 session 判断（只在完成态 / 预览模式放行）。
    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return event }  // Esc
            MainActor.assumeIsolated { self?.session?.escape() }
            return nil
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }
}

extension NSScreen {
    /// 光标所在屏幕；合盖切换显示器的瞬间屏幕列表可能为空，此时返回 nil。
    static var withMouse: NSScreen? {
        let mouse = NSEvent.mouseLocation
        return screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? main ?? screens.first
    }
}
