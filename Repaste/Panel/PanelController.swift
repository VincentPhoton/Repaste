//
//  PanelController.swift
//  Repaste
//
//  NSPanel 面板控制器：刘海剪贴板主面板的承载与展示控制
//

import AppKit
import SwiftUI

// MARK: - 面板展示模式

/// 面板展示模式
enum PanelMode {
    /// 刘海模式：屏幕顶部居中，顶边贴合屏幕顶
    case notch
    /// 居中模式：屏幕水平垂直居中
    case centered
}

// MARK: - 面板窗口

/// 面板 NSPanel 子类：borderless 面板默认不能成为 key window，
/// 重写 canBecomeKey 使面板可接收键盘事件（nonactivating，不激活 App）
private final class RepastePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

// MARK: - 面板控制器

/// NSPanel 面板控制器（单例）
/// 展示 / 隐藏均不激活 App；面板展示时 makeKey（不激活 App）确保键盘事件到达；
/// 面板高度随内容自适应（最大约 560，且不超屏幕可用高度 - 120）
final class PanelController {
    /// 单例
    static let shared = PanelController()

    /// 面板状态机（视图与控制器共用）
    let viewModel = PanelViewModel()

    /// 承载 SwiftUI 内容的面板
    private let panel: RepastePanel

    /// SwiftUI 承载视图（用于计算内容自适应高度）
    private let hostingView: NSHostingView<PanelView>

    /// 当前展示模式（尺寸锚定计算用）
    private var currentMode: PanelMode = .notch

    /// 当前所在屏（多屏下面板在触发热区 / 胶囊的屏展示；内容高度重算时沿用）
    private weak var currentScreen: NSScreen?

    private init() {
        let panel = RepastePanel(
            contentRect: NSRect(x: 0, y: 0, width: DT.panelWidth, height: 320),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false

        let hostingView = NSHostingView(rootView: PanelView(viewModel: viewModel))
        panel.contentView = hostingView

        self.panel = panel
        self.hostingView = hostingView

        // 首次渲染即有数据（避免首次展示闪空态）
        viewModel.reload()
        // 观察内容规模变化，动态调整面板高度
        observeContentForSizing()
    }

    // MARK: 展示 / 隐藏

    /// 展示面板（渐显动画，不激活 App）
    /// - Parameters:
    ///   - mode: 展示模式（刘海 / 居中）
    ///   - screen: 目标屏（nil = NSScreen.main；刘海热区 / 胶囊触发展开时传所在屏）
    ///   - trigger: 埋点触发来源（nil 时按 mode 推断：notch → "notch"、centered → "hotkey"）
    func show(mode: PanelMode, on screen: NSScreen? = nil, trigger: String? = nil) {
        guard let screen = screen ?? NSScreen.main ?? NSScreen.screens.first else { return }
        currentMode = mode
        currentScreen = screen
        viewModel.isNotchMode = (mode == .notch)
        // notch 模式顶边贴合屏幕顶，头部行需下移一个菜单栏 / 刘海高度避开刘海
        viewModel.notchTopInset = (mode == .notch) ? screen.frame.maxY - screen.visibleFrame.maxY : 0

        // 恢复设置（tab / 来源筛选）、清空搜索、重置键盘选中、刷新数据快照
        viewModel.prepareForDisplay()
        EventLog.track(EventLog.panelOpen, ["trigger": trigger ?? (mode == .notch ? "notch" : "hotkey")])

        applyPanelFrame(screen: screen)

        // 渐显动画（150ms 内 alpha 0 → 1）；orderFrontRegardless 不激活 App
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        // 成为 key window（nonactivating 不激活 App），确保键盘事件到达
        panel.makeKey()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
    }

    /// 隐藏面板（渐隐动画后移出）
    func hide() {
        // 持久化来源筛选（rememberAppFilter 开启时保存 lastSourceFilter）
        viewModel.persistOnHide()
        let panel = self.panel
        guard panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        }, completionHandler: {
            // 若动画期间面板被重新展示（alpha 回升），则不移出
            if panel.alphaValue < 0.05 {
                panel.orderOut(nil)
            }
        })
    }

    // MARK: 尺寸与位置

    /// 面板高度上限：内容自适应，最大约 560，且不超屏幕可用高度 - 120
    private func maxHeight(for screen: NSScreen) -> CGFloat {
        max(240, min(560, screen.visibleFrame.height - 120))
    }

    /// 按内容自适应高度重算并应用面板 frame
    /// - Parameter animated: 内容变化期间是否带动画过渡（notch 顶边锚定、centered 中心锚定）
    private func applyPanelFrame(screen: NSScreen, animated: Bool = false) {
        // fittingSize 由 SwiftUI 内容理想尺寸得出（宽度固定 620，列表区受 maxHeight 约束）
        let fitting = hostingView.fittingSize
        let height = min(max(fitting.height, 200), maxHeight(for: screen))
        let size = CGSize(width: DT.panelWidth, height: height)

        // 计算放置原点（AppKit 坐标系：原点在左下角）
        let origin: CGPoint
        switch currentMode {
        case .notch:
            // 顶部居中，顶边贴合屏幕顶（与刘海同高，视觉从菜单栏下沿垂下）
            origin = CGPoint(
                x: screen.frame.midX - size.width / 2,
                y: screen.frame.maxY - size.height
            )
        case .centered:
            // 屏幕水平垂直居中
            origin = CGPoint(
                x: screen.frame.midX - size.width / 2,
                y: screen.frame.midY - size.height / 2
            )
        }

        let newFrame = NSRect(origin: origin, size: size)
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.15
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().setFrame(newFrame, display: true)
            }
        } else {
            panel.setFrame(newFrame, display: false)
        }
    }

    // MARK: 悬停收起支持（HotZoneWatcher / CapsuleController / HotKeyManager 使用）

    /// 面板当前是否可见（含渐隐动画期间，orderOut 前均为 true）
    var isPanelVisible: Bool { panel.isVisible }

    /// 面板命中区域（全局 AppKit 坐标，四周外扩 tolerance；悬停收起检测用）
    func panelHitFrame(tolerance: CGFloat) -> CGRect {
        panel.frame.insetBy(dx: -tolerance, dy: -tolerance)
    }

    /// 暂停自动收起：面板内浮层（⋮ 菜单 / 图片预览 / 弹窗 / 模板拖拽 / 浏览器选择）打开期间，
    /// 鼠标可能长时间离开面板 frame，不应触发「离开 400ms 收起」
    var suspendAutoHide: Bool {
        viewModel.moreMenuClip != nil
            || viewModel.templateMenuClip != nil
            || viewModel.previewingClip != nil
            || viewModel.activeDialog != nil
            || viewModel.draggingTemplateId != nil
            || viewModel.browserChooserClip != nil
    }

    // MARK: 内容尺寸观察

    /// 观察面板内容规模（列表条数 / 来源条与提示条显隐 / 模板组数量），
    /// 变化时动态调整面板高度（面板可见期间）
    private func observeContentForSizing() {
        withObservationTracking {
            _ = viewModel.contentSizeRevision
        } onChange: {
            // onChange 回调在非隔离上下文执行，捕获列表挂在 MainActor Task 上
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.panel.isVisible,
                   let screen = self.currentScreen ?? NSScreen.main ?? NSScreen.screens.first {
                    self.applyPanelFrame(screen: screen, animated: true)
                }
                // onChange 触发后观察即失效，重新注册
                self.observeContentForSizing()
            }
        }
    }
}
