#if DEBUG
import AppKit
import SwiftUI

/// 仅 debug 构建：`swift run HourRest -snapshotDir /tmp/shots` 把各界面离屏渲染成 PNG 后退出，
/// 用于检查布局，不会在屏幕上弹出任何窗口。
@MainActor
enum DebugSnapshots {
    static func runIfRequested(settings: SettingsStore, engine: ReminderEngine) -> Bool {
        guard let dir = UserDefaults.standard.string(forKey: "snapshotDir") else { return false }
        let url = URL(fileURLWithPath: dir, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)

        let anchor = Calendar.current.date(bySettingHour: 10, minute: 0, second: 0, of: Date())!
        func session(_ kind: RestSession.Kind, snoozesLeft: Int = 2) -> RestSession {
            RestSession(kind: kind, breakDuration: 300, snoozeMinutes: 5, snoozesLeft: snoozesLeft, completedToday: 3)
        }
        let prompting = session(.scheduled(anchor: anchor, snoozed: false, due: anchor))
        let resting = session(.scheduled(anchor: anchor, snoozed: false, due: anchor))
        resting.startRest()
        let completed = session(.manual)
        completed.tick(Date().addingTimeInterval(400))
        engine.start()  // 让菜单栏面板显示真实的「下次休息」
        let snoozedOnce = session(.scheduled(anchor: anchor, snoozed: true, due: anchor.addingTimeInterval(300)), snoozesLeft: 1)

        for (name, dark) in [("light", false), ("dark", true)] {
            let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)!
            let size = NSSize(width: 1280, height: 860)
            render(OverlayRootView(session: prompting, isPrimary: true), size: size, appearance: appearance, to: url, "overlay-prompting-\(name)")
            render(OverlayRootView(session: snoozedOnce, isPrimary: true), size: size, appearance: appearance, to: url, "overlay-snoozed-\(name)")
            render(OverlayRootView(session: resting, isPrimary: true), size: size, appearance: appearance, to: url, "overlay-resting-\(name)")
            render(OverlayRootView(session: completed, isPrimary: true), size: size, appearance: appearance, to: url, "overlay-completed-\(name)")
            render(OverlayRootView(session: resting, isPrimary: false), size: NSSize(width: 960, height: 600), appearance: appearance, to: url, "overlay-secondary-\(name)")
            render(PopoverView(engine: engine, close: {}, openSettings: {}), size: NSSize(width: 288, height: 300), appearance: appearance, to: url, "popover-\(name)")
            render(PreAlertView(engine: engine), size: NSSize(width: 312, height: 68), appearance: appearance, to: url, "prealert-\(name)")
            render(SettingsView(settings: settings, onPreview: {}), size: NSSize(width: 480, height: 600), appearance: appearance, to: url, "settings-\(name)")
        }
        NSApp.terminate(nil)
        return true
    }

    private static func render<V: View>(_ view: V, size: NSSize, appearance: NSAppearance, to dir: URL, _ name: String) {
        let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height).background(Color(nsColor: .windowBackgroundColor)))
        host.appearance = appearance
        let window = NSWindow(contentRect: NSRect(origin: NSPoint(x: -10_000, y: -10_000), size: size),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = appearance
        window.backgroundColor = appearance.name == .darkAqua ? NSColor(white: 0.12, alpha: 1) : NSColor(white: 0.93, alpha: 1)
        window.contentView = host
        window.orderBack(nil)
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.8))  // 等入场动画结束
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent("\(name).png"))
        window.orderOut(nil)
    }
}
#endif
