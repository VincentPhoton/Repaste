//
//  RepasteApp.swift
//  Repaste
//
//  Created by 陈晓峰 on 2026/8/19.
//

import SwiftUI
import AppKit
import SwiftData

@main
struct RepasteApp: App {
    /// 面板控制器单例（App 启动即创建并持有，后续任务承载刘海面板）
    private let panelController: PanelController

    /// 录制开关（UserDefaults 键 recording_enabled，默认开启）
    @AppStorage("recording_enabled") private var recordingEnabled = true

    /// 用于打开设置窗口
    @Environment(\.openWindow) private var openWindow

    init() {
        // 创建并持有面板控制器单例
        self.panelController = PanelController.shared
        // 启动剪贴板录制引擎（轮询 changeCount 入库；默认不导入启动前已存在的剪贴板内容）
        ClipboardMonitor.shared.start()
        // 呼出系统：刘海悬停状态机 + ⌥⇧V 全局快捷键 + 无刘海屏胶囊兜底
        // （各自监听 willTerminate 在退出时移除 monitor / 注销热键）
        HotZoneWatcher.shared.start()
        HotKeyManager.shared.start()
        CapsuleController.shared.start()
    }

    var body: some Scene {
        // 常驻菜单栏入口
        MenuBarExtra("Repaste", systemImage: "clipboard.on.clipboard") {
            // 注册窗口动作桥：面板内容挂在 NSPanel 的 NSHostingView 上，
            // 不在 SwiftUI Scene 环境内，无法直接使用 @Environment(\.openWindow)
            let _ = AppWindowBridge.shared.register(openWindow)
            // 首启引导：未完成首次引导时打开引导窗口（会话内幂等；
            // 引导期间主功能照常——ClipboardMonitor 已在跑，第 3 步呼出面板正是要验证的）
            let _ = OnboardingLauncher.launchIfNeeded()
            // 录制开关：文案随状态切换
            Button(recordingEnabled ? "暂停录制" : "开启录制") {
                recordingEnabled.toggle()
            }
            Button("清空历史") {
                // 清空历史（保留模板）
                ClipboardStore.shared.clearHistory()
            }
            Button("设置…") {
                // 走窗口桥统一入口：openSettings 内先激活 App 再开窗
                // （菜单栏应用不抢前台，直接 openWindow 会被其他应用窗口挡住）
                AppWindowBridge.shared.openSettings()
            }
            Divider()
            Button("退出 Repaste") {
                NSApplication.shared.terminate(nil)
            }
        }
        .menuBarExtraStyle(.menu)

        // 设置窗口（独立窗口：三分类「常规 / 呼出 / 历史与隐私」，改动即时生效）
        Window("设置", id: "settings") {
            SettingsView()
        }
        // 共享 ModelContainer（后续刘海面板用同一容器）
        .modelContainer(ModelContainerProvider.shared)
        .defaultSize(width: 720, height: 520)
        // 打开时居中于屏幕
        .defaultPosition(.center)

        // 首次启动引导窗口（三步：欢迎 → 隐私 → 刘海呼出试用；完成 / 跳过后不再出现）
        Window("欢迎使用 Repaste", id: "onboarding") {
            OnboardingView()
        }
        .defaultSize(width: 560, height: 420)
        // 居中展示
        .defaultPosition(.center)
        // 不可缩放（内容尺寸锁定）
        .windowResizability(.contentSize)
    }
}

// MARK: - 窗口动作桥

/// 跨层级窗口动作桥：面板内容挂在 NSPanel 的 NSHostingView 上，不在 SwiftUI Scene 环境内，
/// 无法直接使用 @Environment(\.openWindow)；由 App 层在 MenuBarExtra 构建时注册动作供面板调用
final class AppWindowBridge {
    /// 单例
    static let shared = AppWindowBridge()

    /// openWindow 环境动作（由 RepasteApp 的 MenuBarExtra 内容构建时注册）
    private var openWindow: OpenWindowAction?

    private init() {}

    /// 注册 openWindow 动作
    func register(_ action: OpenWindowAction) {
        openWindow = action
    }

    /// 打开设置窗口
    func openSettings() {
        // 菜单栏应用（LSUIElement）点击菜单项不激活 App：先激活再开窗，
        // 否则设置窗口呈现在非激活应用层级，第一时间会被其他应用窗口挡住
        // （与 OnboardingLauncher 同一处理）
        NSApp.activate(ignoringOtherApps: true)
        openWindow?(id: "settings")
    }

    /// 打开首启引导窗口
    func openOnboarding() {
        openWindow?(id: "onboarding")
    }
}
