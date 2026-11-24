import AppKit

/// 应用入口：纯 AppKit 生命周期，菜单栏常驻、无 Dock 图标。
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, EngineUI {
    private let settings = SettingsStore()
    private lazy var engine = ReminderEngine(settings: settings)
    private let overlay = OverlayController()
    private lazy var preAlert = PreAlertController(engine: engine)
    private lazy var settingsWindow = SettingsWindowController(settings: settings) { [weak self] in
        self?.engine.preview()
    }
    private var statusBar: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        #if DEBUG
        if DebugSnapshots.runIfRequested(settings: settings, engine: engine) { return }
        #endif
        NSApp.mainMenu = makeMainMenu()
        engine.ui = self
        statusBar = StatusBarController(engine: engine) { [weak self] in self?.openSettings() }
        engine.start()
    }

    @objc func openSettings() {
        settingsWindow.show()
    }

    /// 没有 Dock 图标，用户从 Finder / Spotlight 再次打开应用时给出可见反馈。
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openSettings()
        return false
    }

    /// 菜单栏应用看不到主菜单，但它让 ⌘, / ⌘Q 在面板和设置窗口里可用。
    private func makeMainMenu() -> NSMenu {
        let main = NSMenu()
        let appItem = NSMenuItem()
        main.addItem(appItem)
        let appMenu = NSMenu()
        let settingsItem = NSMenuItem(title: "设置…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        appMenu.addItem(settingsItem)
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "退出整点歇", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appItem.submenu = appMenu

        // 让设置窗口里的 ⌘W 能关闭窗口。
        let windowItem = NSMenuItem()
        main.addItem(windowItem)
        let windowMenu = NSMenu(title: "窗口")
        windowMenu.addItem(NSMenuItem(title: "关闭", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        windowItem.submenu = windowMenu
        return main
    }

    // MARK: EngineUI

    func showOverlay(_ session: RestSession) { overlay.show(session) }
    func hideOverlay() { overlay.hide() }
    func showPreAlert() { preAlert.show() }
    func hidePreAlert() { preAlert.hide() }
    func announce(_ text: String) { overlay.announce(text) }
    func engineDidTick() { statusBar?.refresh() }
}
