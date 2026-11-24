import AppKit
import SwiftUI

/// 设置窗口（DESIGN.md §3.3）：480 pt 单页分组表单。
@MainActor
final class SettingsWindowController {
    private let settings: SettingsStore
    private let onPreview: () -> Void
    private var window: NSWindow?

    init(settings: SettingsStore, onPreview: @escaping () -> Void) {
        self.settings = settings
        self.onPreview = onPreview
    }

    func show() {
        if window == nil {
            let controller = NSHostingController(rootView: SettingsView(settings: settings, onPreview: onPreview))
            controller.sizingOptions = .preferredContentSize
            let w = NSWindow(contentViewController: controller)
            w.title = "整点歇 设置"
            w.styleMask = [.titled, .closable, .miniaturizable]
            w.collectionBehavior = [.fullScreenNone]
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        settings.refreshLaunchAtLogin()  // 用户可能在系统设置里改过登录项
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}

struct SettingsView: View {
    @ObservedObject var settings: SettingsStore
    let onPreview: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("休息节奏") {
                    LabeledContent("休息时长") {
                        HStack(spacing: 12) {
                            Slider(value: Binding(
                                get: { Double(settings.breakMinutes) },
                                set: { settings.breakMinutes = Int($0.rounded()) }
                            ), in: 5...10, step: 1)
                            .frame(width: 180)
                            .accessibilityValue("\(settings.breakMinutes) 分钟")
                            Text("\(settings.breakMinutes) 分钟")
                                .font(.system(size: 13, weight: .medium).monospacedDigit())
                                .frame(width: 48, alignment: .trailing)
                        }
                    }

                    LabeledContent("生效时段") {
                        HStack(spacing: 6) {
                            Picker("开始", selection: $settings.startHour) {
                                ForEach(0..<settings.endHour, id: \.self) { Text(hourText($0)).tag($0) }
                            }
                            .labelsHidden()
                            .fixedSize()
                            Text("—").foregroundStyle(.secondary)
                            Picker("结束", selection: $settings.endHour) {
                                ForEach((settings.startHour + 1)...23, id: \.self) { Text(hourText($0)).tag($0) }
                            }
                            .labelsHidden()
                            .fixedSize()
                        }
                    }

                    Picker("重复", selection: $settings.weekdaysOnly) {
                        Text("仅工作日").tag(true)
                        Text("每天").tag(false)
                    }
                    .pickerStyle(.segmented)
                }

                Section("提醒与防打扰") {
                    Toggle(isOn: $settings.preAlertEnabled) {
                        RowLabel("整点前 1 分钟预告", "提前 1 分钟右上角轻提示，方便保存手头进度")
                    }
                    Toggle(isOn: $settings.soundEnabled) {
                        RowLabel("提示音", "休息开始与结束时播放轻柔提示音")
                    }
                    Toggle(isOn: $settings.deferDuringMeetings) {
                        RowLabel("会议或演示时自动延迟", "检测到摄像头正在使用时自动顺延，每 5 分钟复查")
                    }
                }

                Section("系统") {
                    Toggle(isOn: Binding(get: { settings.launchAtLogin }, set: { settings.setLaunchAtLogin($0) })) {
                        RowLabel("登录时自动启动", settings.launchMessage ?? "开机登录后自动在菜单栏运行")
                    }
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)

            HStack {
                Button(action: onPreview) {
                    Label("预览全屏提醒", systemImage: "macwindow")
                }
                Spacer()
                Text("版本 \(settings.version)" + (settings.isDebug ? " · 调试模式" : ""))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(.horizontal, 20)
            .frame(height: 44)
            .padding(.bottom, 8)
        }
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func hourText(_ h: Int) -> String { String(format: "%02d:00", h) }
}

private struct RowLabel: View {
    let title: String
    let detail: String

    init(_ title: String, _ detail: String) {
        self.title = title
        self.detail = detail
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            Text(detail)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }
}
