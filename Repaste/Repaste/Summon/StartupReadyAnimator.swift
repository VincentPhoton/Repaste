//
//  StartupReadyAnimator.swift
//  Repaste
//
//  启动就绪动效（一次性）：刘海苏醒 + 把手残留。
//  回答用户「什么时候可以碰刘海了」--applicationDidFinishLaunching 后播放：
//  阶段一「苏醒」：与刘海同宽同色的黑色临时窗口向下探出（过冲回弹落位），
//    两眼睁开、眨一下、闭眼缩回，像刘海里的小家伙醒来看了一眼；
//  阶段二「把手残留」：缩回同时在刘海下缘留下 96×5 呼吸把手
//    （与无刘海屏胶囊同形态语言），呼吸两个周期、最后一大口气，然后消失。
//  纪律：全程 ignoresMouseEvents 不挡刘海热区；面板任一入口展开立即终止让位；
//    hoverEnabled=false 不播（刘海不可悬停，动效不再「招手」）；
//    首启引导出现的会话不播（引导第 3 步本身教学刘海呼出，由调用方判断）。
//  无刘海屏退化为胶囊位置的把手呼吸（跳过苏醒，交互语义仍成立）。
//  时间轴与交互原型 notch-ready-animation-proposals.html 的「C 苏醒 + 把手残留」对齐。
//

import AppKit
import QuartzCore

// MARK: - 启动就绪动效

/// 启动就绪动效（单例，一次性）：刘海苏醒 + 把手残留
@MainActor
final class StartupReadyAnimator: NSObject {
    /// 单例
    static let shared = StartupReadyAnimator()

    // MARK: 时间轴参数 · 苏醒（秒，相对播放起点）

    /// 静置留白（蓄势）
    private static let wakeDelay: TimeInterval = 0.16
    /// 探头到达过冲点时刻
    private static let peekOvershootTime: TimeInterval = 0.50
    /// 过冲回弹落位时刻
    private static let peekSettleTime: TimeInterval = 0.69
    /// 睁眼起 / 止
    private static let eyesOpenStart: TimeInterval = 0.37
    private static let eyesOpenEnd: TimeInterval = 0.62
    /// 眨眼：压下 / 压到底 / 张回
    private static let blinkDownTime: TimeInterval = 1.01
    private static let blinkBottomTime: TimeInterval = 1.13
    private static let blinkUpTime: TimeInterval = 1.27
    /// 闭眼起 / 止
    private static let eyesCloseStart: TimeInterval = 1.61
    private static let eyesCloseEnd: TimeInterval = 1.84
    /// 缩回起 / 止
    private static let retractStartTime: TimeInterval = 1.91
    private static let retractEndTime: TimeInterval = 2.30

    // MARK: 时间轴参数 · 把手（秒，相对把手出现时刻）

    /// 苏醒模式下把手出现时刻（缩回开始后 40ms，「小家伙缩回去时留下把手」）
    private static let wakeHandleStart: TimeInterval = 1.95
    /// 把手展开完成
    private static let handleAppearEnd: TimeInterval = 0.42
    /// 呼吸开始（展开完成与呼吸之间稍作停顿）
    private static let handleBreatheStart: TimeInterval = 0.47
    /// 单个呼吸周期
    private static let breathCycle: TimeInterval = 1.15
    /// 呼吸周期数
    private static let breathCycles: Int = 2
    /// 确认脉冲起 / 峰值 / 回落（呼吸结束后「一大口气」收束）
    private static let pulseStartTime: TimeInterval = 2.77
    private static let pulsePeakTime: TimeInterval = 2.97
    private static let pulseSettleTime: TimeInterval = 3.17
    /// 渐隐结束
    private static let fadeEndTime: TimeInterval = 3.82
    /// 把手阶段总时长（含收尾余量）
    private static let handleTotal: TimeInterval = 3.90

    // MARK: 形态参数（pt）

    /// 探头过冲延伸量 / 落位延伸量（刘海向下生长深度）
    private static let peekOvershootDepth: CGFloat = 26
    private static let peekDepth: CGFloat = 16
    /// 把手：宽 / 高 / 展开起始横缩 / 呼吸收窄 / 脉冲放大
    private static let handleWidth: CGFloat = 96
    private static let handleHeight: CGFloat = 5
    private static let handleAppearFromScale: CGFloat = 0.25
    private static let handleBreathScale: CGFloat = 0.76
    private static let handlePulseScale: CGFloat = 1.09
    /// 把手透明度档位（底色纯白，透明度即有效亮度；基准档与胶囊把手 white(0.34) 同档）
    private static let handleBaseAlpha: CGFloat = 0.34
    private static let handleBreathAlpha: CGFloat = 0.55
    private static let handlePulseAlpha: CGFloat = 0.85
    private static let handlePostPulseAlpha: CGFloat = 0.5
    /// 眼睛：直径 / 两眼中心距 / 距延伸体下缘留白 / 透明度
    private static let eyeDiameter: CGFloat = 7
    private static let eyeSpacing: CGFloat = 27
    private static let eyeBottomMargin: CGFloat = 10
    private static let eyeAlpha: CGFloat = 0.78
    /// 眨眼压扁下限（scaleY）
    private static let blinkMinScale: CGFloat = 0.06
    /// 延伸体底部圆角（对齐刘海自身收口）
    private static let notchCornerRadius: CGFloat = 12
    /// 舞台下缘余量（容纳探头过冲）
    private static let stageBottomMargin: CGFloat = 8
    /// 退化模式舞台（宽覆盖脉冲放大后的把手 + 余量）
    private static let fallbackStageWidth: CGFloat = 124
    private static let fallbackStageHeight: CGFloat = 16
    /// 播放节拍（60Hz）
    private static let tickInterval: TimeInterval = 1.0 / 60.0

    // MARK: 运行状态

    /// 播放变体（携带舞台几何）
    private enum Variant {
        /// 苏醒 + 把手残留（有刘海屏）
        case wake(stageSize: CGSize, notchHeight: CGFloat)
        /// 仅把手呼吸（无刘海屏，胶囊位置退化）
        case handleOnly(stageSize: CGSize)

        /// 埋点用变体名
        var name: String {
            switch self {
            case .wake: return "notch"
            case .handleOnly: return "fallback"
            }
        }
    }

    /// 某时刻动效状态
    private struct WakeState {
        /// 刘海向下延伸量（pt）
        var notchExtension: CGFloat = 0
        /// 眼睛纵向缩放（0 = 闭眼）
        var eyeScale: CGFloat = 0
        /// 把手横向缩放
        var handleScaleX: CGFloat = 1
        /// 把手透明度
        var handleAlpha: CGFloat = 0
    }

    /// 本次 App 生命周期内是否已处理过（只播一次）
    private var hasPlayed = false
    /// 动效面板
    private var panel: NSPanel?
    /// 黑色刘海延伸体
    private var notchLayer: CALayer?
    /// 双眼
    private var eyeLayers: [CALayer] = []
    /// 呼吸把手
    private var handleLayer: CALayer?
    /// 当前变体
    private var variant: Variant = .handleOnly(stageSize: .zero)
    /// 播放起始时刻（CACurrentMediaTime 基准）
    private var startTime: TimeInterval = 0
    /// 60Hz 驱动定时器
    private var tickTimer: Timer?
    /// 是否被面板展开打断（埋点用）
    private var interrupted = false

    /// 设置中心
    private let settings = SettingsStore.shared

    private override init() {
        super.init()
    }

    // MARK: 入口

    /// 播放入口（AppDelegate 在 applicationDidFinishLaunching 调用；生命周期内只播一次）
    /// 首启引导出现的会话由调用方跳过（引导第 3 步已教学刘海呼出）
    func playIfNeeded() {
        guard !hasPlayed else { return }
        hasPlayed = true
        // hoverEnabled = false：刘海不可悬停呼出，动效不再「招手」（与胶囊兜底同口径）
        guard settings.hoverEnabled else { return }

        // 有刘海屏：优先鼠标所在屏，否则任一有刘海屏
        let notchScreens = NSScreen.screens.compactMap { screen -> (NSScreen, CGRect)? in
            guard let rect = Self.notchRect(on: screen) else { return nil }
            return (screen, rect)
        }
        if let (screen, rect) = notchScreens.first(where: { $0.0.frame.contains(NSEvent.mouseLocation) })
            ?? notchScreens.first {
            // 舞台与刘海同宽，向下容纳探头过冲与把手
            let stageSize = CGSize(
                width: rect.width,
                height: rect.height + Self.peekOvershootDepth + Self.stageBottomMargin
            )
            let stageFrame = CGRect(
                x: rect.minX,
                y: screen.frame.maxY - stageSize.height,
                width: stageSize.width,
                height: stageSize.height
            )
            begin(stageFrame: stageFrame, variant: .wake(stageSize: stageSize, notchHeight: rect.height))
        } else if let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) })
            ?? NSScreen.screens.first {
            // 无刘海屏退化：胶囊位置的把手呼吸（顶边贴屏幕顶居中）
            let stageSize = CGSize(width: Self.fallbackStageWidth, height: Self.fallbackStageHeight)
            let stageFrame = CGRect(
                x: screen.frame.midX - stageSize.width / 2,
                y: screen.frame.maxY - stageSize.height,
                width: stageSize.width,
                height: stageSize.height
            )
            begin(stageFrame: stageFrame, variant: .handleOnly(stageSize: stageSize))
        }
    }

    // MARK: 播放

    /// 开始播放：创建面板与图层，启动 60Hz 定时器
    private func begin(stageFrame: CGRect, variant: Variant) {
        self.variant = variant
        interrupted = false

        let panel = NSPanel(
            contentRect: stageFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        // 鼠标事件穿透：不拦截点击、不干扰刘海热区悬停判定
        panel.ignoresMouseEvents = true

        let host = NSView(frame: NSRect(origin: .zero, size: stageFrame.size))
        host.layer = CALayer()
        host.layer?.frame = NSRect(origin: .zero, size: stageFrame.size)
        host.wantsLayer = true
        panel.contentView = host

        buildLayers(in: host, variant: variant)
        panel.orderFrontRegardless()
        self.panel = panel

        // 先落到静息帧再开表（开局可见即无跳变）
        apply(Self.emptyState)
        startTime = CACurrentMediaTime()
        let timer = Timer(
            timeInterval: Self.tickInterval,
            target: self,
            selector: #selector(tick),
            userInfo: nil,
            repeats: true
        )
        RunLoop.main.add(timer, forMode: .common)
        tickTimer = timer
    }

    /// 构建图层：黑色刘海延伸体 / 双眼 / 把手（把手最上层）
    private func buildLayers(in host: NSView, variant: Variant) {
        guard let root = host.layer else { return }
        let w = host.bounds.width

        if case let .wake(stageSize, notchHeight) = variant {
            // 黑色延伸体：顶边贴屏幕顶、仅底部两角圆角；静息时与刘海完全重合（不可见）
            let notch = CALayer()
            notch.backgroundColor = NSColor.black.cgColor
            notch.cornerRadius = Self.notchCornerRadius
            // 图层坐标 minY 侧 = 视觉底部（NSView 默认非翻转）
            notch.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
            root.addSublayer(notch)
            notchLayer = notch

            // 双眼：白色圆点，纵向跟随延伸体下缘（apply 每帧更新）
            for side in [-1.0, 1.0] {
                let eye = CALayer()
                eye.bounds = CGRect(x: 0, y: 0, width: Self.eyeDiameter, height: Self.eyeDiameter)
                eye.cornerRadius = Self.eyeDiameter / 2
                eye.backgroundColor = NSColor.white.withAlphaComponent(Self.eyeAlpha).cgColor
                eye.position = CGPoint(x: w / 2 + CGFloat(side) * Self.eyeSpacing / 2, y: 0)
                eye.transform = CATransform3DMakeScale(1, 0, 1)
                root.addSublayer(eye)
                eyeLayers.append(eye)
            }
            _ = (stageSize, notchHeight) // 几何在 apply 中经 variant 使用
        }

        // 把手：纯白底 + 透明度驱动，顶边贴刘海下缘（退化模式贴屏幕顶），底部两角圆角
        let handle = CALayer()
        handle.bounds = CGRect(x: 0, y: 0, width: Self.handleWidth, height: Self.handleHeight)
        handle.backgroundColor = NSColor.white.cgColor
        handle.cornerRadius = Self.handleHeight / 2
        handle.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        let handleTopY: CGFloat
        switch variant {
        case let .wake(stageSize, notchHeight):
            handleTopY = stageSize.height - notchHeight // 刘海静息下缘
        case let .handleOnly(stageSize):
            handleTopY = stageSize.height // 屏幕顶
        }
        handle.position = CGPoint(x: w / 2, y: handleTopY - Self.handleHeight / 2)
        handle.opacity = 0
        handle.zPosition = 10
        root.addSublayer(handle)
        handleLayer = handle
    }

    /// 60Hz 驱动：面板任一入口展开即打断让位；超时收尾
    @objc private func tick() {
        // 打断：面板已被展开（刘海热区 / 快捷键 / 胶囊任一入口）
        if PanelController.shared.isPanelVisible {
            interrupted = true
            finish()
            return
        }
        let t = CACurrentMediaTime() - startTime
        apply(state(at: t))
        if t >= totalDuration {
            finish()
        }
    }

    /// 总时长（苏醒模式 = 把手起点 + 把手阶段；退化模式 = 把手阶段）
    private var totalDuration: TimeInterval {
        switch variant {
        case .wake: return Self.wakeHandleStart + Self.handleTotal
        case .handleOnly: return Self.handleTotal
        }
    }

    /// 收尾：停表、撤窗、清图层、埋点
    private func finish() {
        tickTimer?.invalidate()
        tickTimer = nil
        panel?.orderOut(nil)
        panel = nil
        notchLayer = nil
        eyeLayers = []
        handleLayer = nil
        EventLog.track(EventLog.startupWakePlayed, [
            "variant": variant.name,
            "outcome": interrupted ? "interrupted" : "completed",
        ])
    }

    // MARK: 状态计算

    /// 静息帧（开局落帧用）
    private static let emptyState = WakeState()

    /// 计算 t 时刻状态
    private func state(at t: TimeInterval) -> WakeState {
        var s = WakeState()
        if case .wake = variant {
            s.notchExtension = notchExtension(at: t)
            s.eyeScale = eyeScale(at: t)
        }
        let handleStart: TimeInterval
        switch variant {
        case .wake: handleStart = Self.wakeHandleStart
        case .handleOnly: handleStart = 0
        }
        let ht = t - handleStart
        if ht > 0 {
            let (scaleX, alpha) = handleState(at: min(ht, Self.handleTotal))
            s.handleScaleX = scaleX
            s.handleAlpha = alpha
        }
        return s
    }

    /// 刘海向下延伸量（探头过冲回弹 -> 停留 -> 缩回）
    private func notchExtension(at t: TimeInterval) -> CGFloat {
        if t < Self.wakeDelay {
            return 0
        }
        if t < Self.peekOvershootTime {
            // 探头：0 -> 过冲深度（强 easeOut）
            return Self.peekOvershootDepth
                * Self.easeOutQuint(Self.progress(t, from: Self.wakeDelay, to: Self.peekOvershootTime))
        }
        if t < Self.peekSettleTime {
            // 回弹落位：过冲深度 -> 落位深度
            return Self.peekOvershootDepth
                + (Self.peekDepth - Self.peekOvershootDepth)
                    * Self.easeInOut(Self.progress(t, from: Self.peekOvershootTime, to: Self.peekSettleTime))
        }
        if t < Self.retractStartTime {
            return Self.peekDepth
        }
        if t < Self.retractEndTime {
            // 缩回：落位深度 -> 0
            return Self.peekDepth
                * (1 - Self.easeInOut(Self.progress(t, from: Self.retractStartTime, to: Self.retractEndTime)))
        }
        return 0
    }

    /// 眼睛纵向缩放（睁眼 -> 眨 -> 闭眼）
    private func eyeScale(at t: TimeInterval) -> CGFloat {
        if t < Self.eyesOpenStart {
            return 0
        }
        if t < Self.eyesOpenEnd {
            return Self.easeOut(Self.progress(t, from: Self.eyesOpenStart, to: Self.eyesOpenEnd))
        }
        if t < Self.blinkDownTime {
            return 1
        }
        if t < Self.blinkBottomTime {
            return 1 + (Self.blinkMinScale - 1)
                * Self.easeIn(Self.progress(t, from: Self.blinkDownTime, to: Self.blinkBottomTime))
        }
        if t < Self.blinkUpTime {
            return Self.blinkMinScale + (1 - Self.blinkMinScale)
                * Self.easeOut(Self.progress(t, from: Self.blinkBottomTime, to: Self.blinkUpTime))
        }
        if t < Self.eyesCloseStart {
            return 1
        }
        if t < Self.eyesCloseEnd {
            return 1 - Self.easeIn(Self.progress(t, from: Self.eyesCloseStart, to: Self.eyesCloseEnd))
        }
        return 0
    }

    /// 把手横缩与透明度（展开 -> 呼吸 ×2 -> 确认脉冲 -> 渐隐）
    private func handleState(at ht: TimeInterval) -> (scaleX: CGFloat, alpha: CGFloat) {
        if ht < Self.handleAppearEnd {
            // 展开：窄淡 -> 全宽基准
            let p = Self.easeOutQuint(Self.progress(ht, from: 0, to: Self.handleAppearEnd))
            return (
                Self.handleAppearFromScale + (1 - Self.handleAppearFromScale) * p,
                Self.handleBaseAlpha * p
            )
        }
        let breatheEnd = Self.handleBreatheStart + Self.breathCycle * Double(Self.breathCycles)
        if ht < Self.handleBreatheStart {
            return (1, Self.handleBaseAlpha)
        }
        if ht < breatheEnd {
            // 呼吸：每周期前半收窄提亮、后半放开回落
            let inCycle = (ht - Self.handleBreatheStart).truncatingRemainder(dividingBy: Self.breathCycle)
            let half = Self.breathCycle / 2
            let p: CGFloat
            if inCycle < half {
                p = Self.easeInOut(CGFloat(inCycle / half))
            } else {
                p = 1 - Self.easeInOut(CGFloat((inCycle - half) / half))
            }
            return (
                1 + (Self.handleBreathScale - 1) * p,
                Self.handleBaseAlpha + (Self.handleBreathAlpha - Self.handleBaseAlpha) * p
            )
        }
        if ht < Self.pulseStartTime {
            return (1, Self.handleBaseAlpha)
        }
        if ht < Self.pulsePeakTime {
            // 确认脉冲：放大提亮至峰值
            let p = Self.easeOut(Self.progress(ht, from: Self.pulseStartTime, to: Self.pulsePeakTime))
            return (
                1 + (Self.handlePulseScale - 1) * p,
                Self.handleBaseAlpha + (Self.handlePulseAlpha - Self.handleBaseAlpha) * p
            )
        }
        if ht < Self.pulseSettleTime {
            // 回落
            let p = Self.easeOut(Self.progress(ht, from: Self.pulsePeakTime, to: Self.pulseSettleTime))
            return (
                Self.handlePulseScale + (1 - Self.handlePulseScale) * p,
                Self.handlePulseAlpha + (Self.handlePostPulseAlpha - Self.handlePulseAlpha) * p
            )
        }
        if ht < Self.fadeEndTime {
            // 渐隐
            let p = Self.easeIn(Self.progress(ht, from: Self.pulseSettleTime, to: Self.fadeEndTime))
            return (1, Self.handlePostPulseAlpha * (1 - p))
        }
        return (1, 0)
    }

    // MARK: 状态应用

    /// 把状态落到图层（帧驱动，无隐式动画）
    private func apply(_ state: WakeState) {
        if case let .wake(stageSize, notchHeight) = variant {
            if let notch = notchLayer {
                notch.frame = CGRect(
                    x: 0,
                    y: stageSize.height - notchHeight - state.notchExtension,
                    width: stageSize.width,
                    height: notchHeight + state.notchExtension
                )
            }
            // 眼睛纵向跟随延伸体下缘
            let bottomY = stageSize.height - notchHeight - state.notchExtension
            let eyeY = bottomY + Self.eyeBottomMargin + Self.eyeDiameter / 2
            for eye in eyeLayers {
                eye.position = CGPoint(x: eye.position.x, y: eyeY)
                eye.transform = CATransform3DMakeScale(1, state.eyeScale, 1)
            }
        }
        if let handle = handleLayer {
            handle.transform = CATransform3DMakeScale(state.handleScaleX, 1, 1)
            handle.opacity = Float(state.handleAlpha)
        }
    }

    // MARK: 刘海几何（与 HotZoneWatcher.notchHotZone 同源逻辑）

    /// 某屏刘海矩形（全局坐标）：safeAreaInsets.top > 0 判定有刘海；
    /// 宽度由 auxiliaryTopLeftArea.maxX 与 auxiliaryTopRightArea.minX 推算，高度取 safeAreaInsets.top
    private static func notchRect(on screen: NSScreen) -> CGRect? {
        guard screen.safeAreaInsets.top > 0 else { return nil }
        guard let leftArea = screen.auxiliaryTopLeftArea,
              let rightArea = screen.auxiliaryTopRightArea else { return nil }
        let left = normalizedToGlobal(leftArea, screen: screen)
        let right = normalizedToGlobal(rightArea, screen: screen)
        guard right.minX > left.maxX else { return nil }
        return CGRect(
            x: left.maxX,
            y: screen.frame.maxY - screen.safeAreaInsets.top,
            width: right.minX - left.maxX,
            height: screen.safeAreaInsets.top
        )
    }

    /// auxiliaryTopLeft/RightArea 坐标基准归一：落在 screen.frame 范围内视为全局坐标直接用，
    /// 否则视为 screen-local 坐标（原点在该屏左下角），平移到全局基准
    private static func normalizedToGlobal(_ rect: CGRect, screen: NSScreen) -> CGRect {
        if rect.minX >= screen.frame.minX - 1, rect.maxX <= screen.frame.maxX + 1 {
            return rect
        }
        return rect.offsetBy(dx: screen.frame.minX, dy: screen.frame.minY)
    }

    // MARK: 缓动

    /// 区间进度（0…1 截断）
    private static func progress(_ t: TimeInterval, from: TimeInterval, to: TimeInterval) -> CGFloat {
        guard to > from else { return 1 }
        return CGFloat(max(0, min(1, (t - from) / (to - from))))
    }

    /// easeOut（cubic）
    private static func easeOut(_ x: CGFloat) -> CGFloat {
        1 - pow(1 - x, 3)
    }

    /// easeIn（cubic）
    private static func easeIn(_ x: CGFloat) -> CGFloat {
        x * x * x
    }

    /// easeInOut（smoothstep）
    private static func easeInOut(_ x: CGFloat) -> CGFloat {
        x * x * (3 - 2 * x)
    }

    /// 强 easeOut（≈ cubic-bezier(.22,1,.36,1)，展开 / 探头用）
    private static func easeOutQuint(_ x: CGFloat) -> CGFloat {
        1 - pow(1 - x, 5)
    }
}
