//
//  OnboardingView.swift
//  Repaste
//
//  首次启动引导（三步）：欢迎与默认 Tab → 隐私与本地存储 → 试试看（刘海呼出验证）
//  独立标准窗口 + 自绘引导卡（guideCardRadius 24、DT.panel 底、1px strokeStrong 描边）；
//  全程不索要任何系统权限；完成 / 跳过均写 onboardingCompleted（重启不再出现）
//

import SwiftUI
import AppKit

// MARK: - 首启触发器

/// 首启触发器：MenuBarExtra 内容会随状态变化（如录制开关）重建，需会话内幂等
@MainActor
enum OnboardingLauncher {
    /// 本 App 进程内是否已触发过
    private static var launchedThisSession = false

    /// 未完成首次引导时打开引导窗口并激活 App（菜单栏应用默认不抢前台，首启引导需要被看到）
    /// 经 AppWindowBridge 转发 openWindow，避免在非 App Lifecycle 环境（Xcode 预览宿主）直接持有 OpenWindowAction
    static func launchIfNeeded() {
        guard !launchedThisSession else { return }
        launchedThisSession = true
        // Xcode 预览宿主不是完整 App Lifecycle，调 openWindow 会抛
        // "Use of OpenWindowAction requires the SwiftUI App Lifecycle"，直接跳过
        guard ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1" else { return }
        guard !SettingsStore.shared.onboardingCompleted else { return }
        NSApp.activate(ignoringOtherApps: true)
        AppWindowBridge.shared.openOnboarding()
    }
}

// MARK: - 引导视图

/// 三步首次启动引导视图（窗口约 560×420，不可缩放；esc = 跳过当前步）
struct OnboardingView: View {
    /// 当前步号（1…3）
    @State private var step = 1

    /// 第 3 步：是否已成功呼出面板（刘海悬停 / ⌥⇧V 均可）
    @State private var summoned = false

    /// 面板可见性轮询任务（NSPanel.isVisible 非 @Observable，需主动轮询）
    @State private var pollTask: Task<Void, Never>?

    /// 关闭引导窗口（完成 / 跳过后）
    @Environment(\.dismiss) private var dismiss

    /// 设置中心（第 1 步默认 Tab 单选，点选即写 defaultTab）
    private let settings = SettingsStore.shared

    /// 步骤头部小标题
    private var stepHeadTitle: String {
        switch step {
        case 1: return "开始使用"
        case 2: return "隐私与本地存储"
        default: return "试试看"
        }
    }

    var body: some View {
        guideCard
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(DT.surface2)
            .preferredColorScheme(.dark)
            // esc = 跳过当前步（隐藏按钮承载 cancelAction 快捷键）
            .background(
                Button("") { skip() }
                    .keyboardShortcut(.cancelAction)
                    .opacity(0)
                    .frame(width: 1, height: 1)
                    .accessibilityHidden(true)
            )
            .onChange(of: step) { _, newStep in
                // 进入第 3 步开始监听面板呼出；离开则停止
                if newStep == 3 {
                    startPanelPolling()
                } else {
                    stopPanelPolling()
                }
            }
            .onDisappear { stopPanelPolling() }
    }

    // MARK: 引导卡外壳

    /// 引导卡：guideCardRadius 24 圆角 + DT.panel 底 + 1px strokeStrong 描边；
    /// 结构：头部（步骤小标题 + 步数指示）→ 步骤内容 → 底部按钮行
    private var guideCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            headRow
                .padding(.bottom, 16)
            stepContent
            Spacer(minLength: 0)
            footerRow
        }
        .padding(22)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: DT.guideCardRadius, style: .continuous)
                .fill(DT.panel)
        )
        .clipShape(RoundedRectangle(cornerRadius: DT.guideCardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DT.guideCardRadius, style: .continuous)
                .strokeBorder(DT.strokeStrong, lineWidth: 1)
        )
    }

    /// 头部行：步骤小标题 + 步数指示「N / 3」
    private var headRow: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(stepHeadTitle)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(DT.fgStrong)
            Spacer(minLength: 0)
            Text("\(step) / 3")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(DT.muted2)
        }
    }

    // MARK: 步骤内容

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case 1: welcomeStep
        case 2: privacyStep
        default: tryStep
        }
    }

    /// 第 1 步：欢迎 + 呼出方式说明 + 默认 Tab 单选
    private var welcomeStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("欢迎使用刘海剪贴板")
                .font(.system(size: 21, weight: .bold))
                .foregroundStyle(DT.fgStrong)
            VStack(alignment: .leading, spacing: 7) {
                // 「0.1 秒」用 markdown 粗体强调
                Text("把鼠标滑到 MacBook 刘海，停留 **0.1 秒** 就能呼出剪贴板历史。")
                    .font(.system(size: 12.5))
                    .foregroundStyle(DT.muted)
                HStack(spacing: 5) {
                    Text("也可以随时按")
                        .font(.system(size: 12.5))
                        .foregroundStyle(DT.muted)
                    KbdKey(text: "⌥⇧V")
                    Text("从屏幕中间呼出。")
                        .font(.system(size: 12.5))
                        .foregroundStyle(DT.muted)
                }
            }
            .padding(.top, 8)
            // 默认 Tab 分组（单选；点选即写 SettingsStore.defaultTab）
            InnerCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text("打开历史时默认显示")
                        .font(.system(size: 11.5))
                        .foregroundStyle(DT.muted)
                    HStack(spacing: 6) {
                        ForEach(Self.tabOptions, id: \.rawValue) { option in
                            Button {
                                settings.defaultTab = option.rawValue
                            } label: {
                                PillChip(title: option.title, isSelected: settings.defaultTab == option.rawValue)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(14)
            }
            .padding(.top, 18)
        }
    }

    /// 第 2 步：隐私与本地存储三条说明（SF Symbol + accent 圆角小方块）
    private var privacyStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("数据只在你自己的 Mac 上")
                .font(.system(size: 21, weight: .bold))
                .foregroundStyle(DT.fgStrong)
            Text("不登录、不上传、不同步，剪贴板历史永远属于你。")
                .font(.system(size: 12.5))
                .foregroundStyle(DT.muted)
                .padding(.top, 8)
            VStack(spacing: 13) {
                featureRow(
                    icon: "lock.fill",
                    title: "所有记录只存在本机",
                    desc: "不登录、不上传、不同步。"
                )
                featureRow(
                    icon: "shield.lefthalf.filled",
                    title: "密码类内容自动跳过",
                    desc: "从 1Password / 钥匙串等 App 复制时不会入库。"
                )
                featureRow(
                    icon: "eye",
                    title: "来源 App 一眼可见",
                    desc: "每条历史都显示它来自哪个应用。"
                )
            }
            .padding(.top, 18)
        }
    }

    /// 第 2 步单条说明行：accent 软底圆角方块内 SF Symbol + 标题 / 描述
    private func featureRow(icon: String, title: String, desc: String) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(DT.accent.opacity(0.16))
                .frame(width: 34, height: 34)
                .overlay(
                    Image(systemName: icon)
                        .font(.system(size: 14))
                        .foregroundStyle(DT.accentBright)
                )
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(DT.fg)
                Text(desc)
                    .font(.system(size: 11.5))
                    .foregroundStyle(DT.muted)
            }
            Spacer(minLength: 0)
        }
    }

    /// 第 3 步：刘海呼出验证（刘海图形 + 向上脉冲 + 状态行）
    private var tryStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("来，滑一次刘海")
                .font(.system(size: 21, weight: .bold))
                .foregroundStyle(DT.fgStrong)
            Text("把鼠标滑到屏幕顶部的刘海 ↓")
                .font(.system(size: 12.5))
                .foregroundStyle(DT.muted)
                .padding(.top, 8)
            // 刘海图形区：surface2 底内嵌一块黑色刘海 + 摄像头点 + 向上脉冲 + 状态行
            VStack(spacing: 12) {
                NotchPulse()
                notchShape
                statusLine
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(
                RoundedRectangle(cornerRadius: DT.innerCardRadius, style: .continuous)
                    .fill(DT.surface2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DT.innerCardRadius, style: .continuous)
                    .strokeBorder(DT.innerCardStroke, lineWidth: 1)
            )
            .padding(.top, 18)
        }
    }

    /// 黑色刘海形状：宽 200 高 30 圆角矩形 + 居中摄像头点
    private var notchShape: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.black)
                .frame(width: 200, height: 30)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(DT.strokeStrong, lineWidth: 1)
                )
            // 摄像头点
            Circle()
                .fill(DT.surface3)
                .frame(width: 8, height: 8)
        }
    }

    /// 状态行：等待呼出（muted）→ 已成功呼出 ✓（绿色）
    private var statusLine: some View {
        HStack(spacing: 6) {
            if summoned {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(DT.link)
            }
            Text(summoned ? "已成功呼出 ✓" : "状态：等待呼出…")
                .font(.system(size: 12))
                .foregroundStyle(summoned ? DT.link : DT.muted)
        }
    }

    // MARK: 底部按钮行

    /// 底部按钮行：左侧次要动作（跳过 / 上一步）+ 右侧主按钮（下一步 / 开始试用）
    private var footerRow: some View {
        HStack(spacing: 10) {
            // 左侧次要按钮（muted 文字按钮）
            switch step {
            case 1:
                OnboardingGhostButton(title: "跳过引导") { skip() }
            case 2:
                OnboardingGhostButton(title: "← 上一步") {
                    withAnimation(.easeOut(duration: 0.15)) { step = 1 }
                }
            default:
                OnboardingGhostButton(title: "跳过") { skip() }
            }
            Spacer(minLength: 0)
            // 右侧主按钮
            switch step {
            case 1, 2:
                DialogPrimaryButton(title: "下一步 →") {
                    withAnimation(.easeOut(duration: 0.15)) { step += 1 }
                }
            default:
                // 未呼出也可点（直接进入主界面）；呼出成功后升级为 accent 主按钮
                if summoned {
                    DialogPrimaryButton(title: "开始试用") { finish(skipped: false) }
                } else {
                    SolidButton(title: "开始试用") { finish(skipped: false) }
                }
            }
        }
        .padding(.top, 18)
    }

    // MARK: 动作

    /// 跳过当前步：同样写完成标记（不再出现），事件带当前步号
    private func skip() {
        finish(skipped: true)
    }

    /// 结束引导：写 onboardingCompleted；完成记 onboardingCompleted 事件、跳过记 onboardingSkipped（step 字段）；关窗
    private func finish(skipped: Bool) {
        settings.onboardingCompleted = true
        if skipped {
            EventLog.track(EventLog.onboardingSkipped, ["step": "\(step)"])
        } else {
            EventLog.track(EventLog.onboardingCompleted)
        }
        dismiss()
    }

    // MARK: 面板呼出监听

    /// 第 3 步轮询面板可见性（150ms；isPanelVisible 变 true 即「已成功呼出」）
    private func startPanelPolling() {
        pollTask?.cancel()
        pollTask = Task { @MainActor in
            while !Task.isCancelled && !summoned {
                if PanelController.shared.isPanelVisible {
                    withAnimation(.easeOut(duration: 0.2)) { summoned = true }
                    return
                }
                try? await Task.sleep(for: .milliseconds(150))
            }
        }
    }

    /// 停止轮询
    private func stopPanelPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    // MARK: 常量

    /// 第 1 步 Tab 单选选项（rawValue 与 SettingsStore.defaultTab 对齐）
    private static let tabOptions: [(title: String, rawValue: String)] = [
        ("全部", "all"),
        ("文本", "text"),
        ("图片", "image"),
        ("链接", "link"),
    ]
}

// MARK: - 向上脉冲

/// 刘海上方的 accent 光条：上移 + 淡出循环（scale/opacity 循环）；reduced-motion 时静止
private struct NotchPulse: View {
    /// 脉冲动画相位（false = 起点 / true = 终点）
    @State private var animating = false

    /// 减弱动态效果时静止
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(DT.accent)
            .frame(width: 44, height: 4)
            .offset(y: animating ? -12 : 0)
            .opacity(animating ? 0 : 0.7)
            .onAppear {
                // reduce-motion：保持静止微光，不做循环动画
                guard !reduceMotion else { return }
                withAnimation(.easeOut(duration: 1.1).repeatForever(autoreverses: false)) {
                    animating = true
                }
            }
    }
}

// MARK: - 引导次要文字按钮

/// 引导次要按钮：muted 等宽文字、hover 提亮（跳过 / 上一步）
private struct OnboardingGhostButton: View {
    let title: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(DT.monoFont)
                .foregroundColor(isHovering ? DT.fg : DT.muted)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

// MARK: - Xcode 预览

/// 首启引导预览（三步：欢迎 → 隐私 → 刘海试用）
#Preview("首次启动引导") {
    OnboardingView()
        .frame(width: 560, height: 420)
        .preferredColorScheme(.dark)
}
