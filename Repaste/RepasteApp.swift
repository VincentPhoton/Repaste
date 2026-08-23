//
//  RepasteApp.swift
//  Repaste
//
//  Created by 陈晓峰 on 2026/8/19.
//

import SwiftUI
import AppKit

@main
struct RepasteApp: App {
    /// 面板控制器单例（App 启动即创建并持有，后续任务承载刘海面板）
    private let panelController: PanelController

    /// App 代理：启动完成后触发首启引导
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

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
        // 菜单栏不驻留应用图标：设置 / 退出入口均在面板头部（PanelView 头部行），
        // 设置与首启引导窗口由 AppWindowBridge 以 NSWindow 手动管理（与面板挂 NSPanel 同模式）；
        // 这里仅保留空 Settings 场景满足 SwiftUI App 至少声明一个 Scene（不产生可见界面）
        Settings {
            EmptyView()
        }
    }
}

// MARK: - App 代理

/// App 代理：启动完成后按需打开首启引导窗口（幂等；完成 / 跳过后不再出现）
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 启动就绪动效：刘海苏醒 + 把手残留（已完成首启引导才播--
        // 引导出现的会话由引导第 3 步教学刘海呼出，动效不叠加）
        if SettingsStore.shared.onboardingCompleted {
            StartupReadyAnimator.shared.playIfNeeded()
        }
        OnboardingLauncher.launchIfNeeded()
    }
}

// MARK: - 窗口管理桥

/// 窗口管理桥：设置 / 首启引导窗口由此以 NSWindow + NSHostingView 手动管理
/// （菜单栏不驻留图标、无 Scene 环境入口，面板内容挂 NSPanel 同理不依赖 openWindow）
@MainActor
final class AppWindowBridge {
    /// 单例
    static let shared = AppWindowBridge()

    /// 设置窗口（懒创建；关闭仅移出屏，会话内复用）
    private var settingsWindow: NSWindow?

    /// 引导窗口（懒创建；完成 / 跳过后关闭）
    private var onboardingWindow: NSWindow?

    private init() {}

    /// 打开设置窗口
    func openSettings() {
        if settingsWindow == nil {
            settingsWindow = Self.makeWindow(
                title: "设置",
                content: SettingsView(),
                size: NSSize(width: 720, height: 520),
                resizable: true
            )
        }
        present(settingsWindow)
    }

    /// 打开首启引导窗口（无边框：无系统标题栏 / 边框 / 控制按钮，仅自绘引导卡）
    func openOnboarding() {
        if onboardingWindow == nil {
            onboardingWindow = Self.makeBorderlessWindow(
                content: OnboardingView(),
                size: NSSize(width: 560, height: 420)
            )
        }
        present(onboardingWindow)
    }

    /// 关闭首启引导窗口（引导完成 / 跳过时由 OnboardingView 调用）
    func closeOnboarding() {
        onboardingWindow?.close()
    }

    /// 激活 App 并将窗口居中置前
    /// （LSUIElement 应用点击不激活 App：先激活再开窗，否则会被其他应用窗口挡住）
    private func present(_ window: NSWindow?) {
        guard let window else { return }
        NSApp.activate(ignoringOtherApps: true)
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    /// 创建标准标题栏窗口（暗色外观随 App 哑光纯黑风格）；
    /// isReleasedWhenClosed = false 使关闭仅移出屏（实例由桥持有，可复用）
    private static func makeWindow(title: String, content: some View, size: NSSize, resizable: Bool) -> NSWindow {
        var style: NSWindow.StyleMask = [.titled, .closable]
        if resizable {
            style.insert(.resizable)
            style.insert(.miniaturizable)
        }
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: style,
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .vibrantDark)
        // 标题栏透明 + 窗口底色 = DT.panel（#0A0A0A），
        // 使顶部标题栏横条与内容区背景色一致（哑光纯黑，无系统浅灰标题栏）
        window.titlebarAppearsTransparent = true
        window.backgroundColor = NSColor(red: 10 / 255, green: 10 / 255, blue: 10 / 255, alpha: 1)
        window.contentView = NSHostingView(rootView: content)
        return window
    }

    /// 创建无边框窗口（引导弹框用）：无系统标题栏 / 边框 / 控制按钮，
    /// 透明底仅承载自绘界面，窗口阴影随引导卡轮廓自然投射；
    /// .borderless 默认 canBecomeKey = false（esc 跳过快捷键会失效），用子类覆写恢复
    private static func makeBorderlessWindow(content: some View, size: NSSize) -> NSWindow {
        let window = BorderlessKeyWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .vibrantDark)
        window.contentView = NSHostingView(rootView: content)
        return window
    }
}

// MARK: - 无边框窗口子类

/// 无边框窗口：覆写 canBecomeKey / canBecomeMain，
/// 使 .borderless 窗口可接收键盘事件（引导卡的 esc 跳过快捷键依赖 key window）
private final class BorderlessKeyWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
