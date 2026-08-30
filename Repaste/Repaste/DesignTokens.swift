//
//  DesignTokens.swift
//  Repaste
//
//  设计系统：哑光纯黑质感（无玻璃 / 无模糊 / 无发光）
//  所有 UI 强制使用本文件定义的颜色、圆角、尺寸、字体与通用组件
//

import AppKit
import SwiftUI

// MARK: - 设计令牌

/// 设计令牌（Design Tokens）集中定义
enum DT {
    // MARK: 颜色

    /// 面板主背景 #0A0A0A
    static let panel = Color(red: 10 / 255, green: 10 / 255, blue: 10 / 255)
    /// 次级表面 #0E0E0E
    static let surface2 = Color(red: 14 / 255, green: 14 / 255, blue: 14 / 255)
    /// 三级表面 #141414
    static let surface3 = Color(red: 20 / 255, green: 20 / 255, blue: 20 / 255)
    /// 按钮实底 #1A1A1A
    static let button = Color(red: 26 / 255, green: 26 / 255, blue: 26 / 255)

    /// 主文字 #D6E4FB
    static let fg = Color(red: 214 / 255, green: 228 / 255, blue: 251 / 255)
    /// 强文字 #EEF3FF
    static let fgStrong = Color(red: 238 / 255, green: 243 / 255, blue: 255 / 255)
    /// 次级文字 #9AA3B8
    static let muted = Color(red: 154 / 255, green: 163 / 255, blue: 184 / 255)
    /// 三级文字 #8D95AB
    static let muted2 = Color(red: 141 / 255, green: 149 / 255, blue: 171 / 255)

    /// 强调色 #8B6BFF
    static let accent = Color(red: 139 / 255, green: 107 / 255, blue: 255 / 255)
    /// 强调亮色 #A38BFF
    static let accentBright = Color(red: 163 / 255, green: 139 / 255, blue: 255 / 255)
    /// 强调按钮色 #7450EA
    static let accentBtn = Color(red: 116 / 255, green: 80 / 255, blue: 234 / 255)

    /// 类型色：文本 #8FD0F4
    static let text = Color(red: 143 / 255, green: 208 / 255, blue: 244 / 255)
    /// 类型色：图片 #F0A3C0
    static let image = Color(red: 240 / 255, green: 163 / 255, blue: 192 / 255)
    /// 类型色：链接 #4FD47F
    static let link = Color(red: 79 / 255, green: 212 / 255, blue: 127 / 255)
    /// 类型色：文件 #FFA856
    static let file = Color(red: 255 / 255, green: 168 / 255, blue: 86 / 255)

    /// 警示色 #FFB454（暂停提示条 / 原图已清理等警告场景；不再兼任类型色）
    static let warn = Color(red: 255 / 255, green: 180 / 255, blue: 84 / 255)
    /// 成功色 #4FD47F（成功 ✓ 反馈；与链接类型色同值、语义独立）
    static let success = Color(red: 79 / 255, green: 212 / 255, blue: 127 / 255)

    /// 危险色（删除等破坏性动作文字）#FF9089
    static let danger = Color(red: 255 / 255, green: 144 / 255, blue: 137 / 255)
    /// 危险色柔和底（危险项 hover）rgba(255,107,98,.16)
    static let dangerSoft = Color(red: 255 / 255, green: 107 / 255, blue: 98 / 255, opacity: 0.16)
    /// 降级提示文字 #FFD9A0（原图已清理提示条）
    static let warnText = Color(red: 255 / 255, green: 217 / 255, blue: 160 / 255)

    /// 菜单浮层底色 #232323（⋮ 更多菜单，比面板底亮一档以区分层级）
    static let menuSurface = Color(red: 35 / 255, green: 35 / 255, blue: 35 / 255)

    /// Toast 背景 rgba(16,16,22,.94)
    static let toastBackground = Color(red: 16 / 255, green: 16 / 255, blue: 22 / 255, opacity: 0.94)
    /// Toast 紫色描边（accent 45% 透明度）
    static let accentLine = Color(red: 139 / 255, green: 107 / 255, blue: 255 / 255, opacity: 0.45)

    /// 描边：白色 10% 透明度 rgba(255,255,255,.10)
    static let stroke = Color(red: 1, green: 1, blue: 1, opacity: 0.10)
    /// 强描边：白色 18% 透明度
    static let strokeStrong = Color(red: 1, green: 1, blue: 1, opacity: 0.18)
    /// 内层卡片描边：白色 12% 透明度
    static let innerCardStroke = Color(red: 1, green: 1, blue: 1, opacity: 0.12)

    // MARK: 圆角

    /// 面板圆角
    static let panelRadius: CGFloat = 28
    /// 对话框圆角
    static let dialogRadius: CGFloat = 20
    /// 引导卡片圆角
    static let guideCardRadius: CGFloat = 24
    /// 内层卡片圆角
    static let innerCardRadius: CGFloat = 12
    /// 胶囊圆角（全圆角）
    static let pillRadius: CGFloat = 99

    // MARK: 尺寸

    /// 面板宽度
    static let panelWidth: CGFloat = 500

    // MARK: 字体

    /// 等宽字体（SF Mono 优先）
    static let monoFont: Font = .system(.body, design: .monospaced)
}

// MARK: - 剪贴板类型

/// 剪贴板条目类型
enum ClipKind: String, CaseIterable, Identifiable {
    case text
    case image
    case file
    case link

    var id: String { rawValue }

    /// 类型颜色
    var kindColor: Color {
        switch self {
        case .text: return DT.text
        case .image: return DT.image
        case .file: return DT.file
        case .link: return DT.link
        }
    }

    /// 中文标签
    var kindLabel: String {
        switch self {
        case .text: return "文本"
        case .image: return "图片"
        case .file: return "文件"
        case .link: return "链接"
        }
    }
}

// MARK: - 通用组件

/// 胶囊标签：未选中 = 透明底 + 主文字色；选中 = 白底 + 近黑文字；无描边无发光
struct PillChip: View {
    let title: String
    var isSelected: Bool = false

    var body: some View {
        Text(title)
            .font(DT.monoFont)
            .foregroundColor(isSelected ? DT.panel : DT.fg)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(
                // 全圆角胶囊（pillRadius）
                Capsule().fill(isSelected ? Color.white : Color.clear)
            )
    }
}

/// 内层卡片：透明底 + 1px 内描边 + 12px 圆角
struct InnerCard<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .clipShape(RoundedRectangle(cornerRadius: DT.innerCardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DT.innerCardRadius, style: .continuous)
                    .strokeBorder(DT.innerCardStroke, lineWidth: 1)
            )
    }
}

/// 实底按钮：#1A1A1A 实底、无高光、12px 圆角、主文字色
struct SolidButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(DT.monoFont)
                .foregroundColor(DT.fg)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: DT.innerCardRadius, style: .continuous)
                        .fill(DT.button)
                )
        }
        .buttonStyle(.mattePress)
    }
}

// MARK: - 哑光按压样式

/// 哑光按压样式：plain 行为 + 按下时透明度反馈（无高光 / 无发光 / 无缩放）
struct MattePressStyle: ButtonStyle {
    /// 按下时降到 0.55 透明度（哑光质感的「压下去」感）
    private static let pressedOpacity: Double = 0.55

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? Self.pressedOpacity : 1)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == MattePressStyle {
    /// 哑光按压样式（.mattePress）：等价 .plain 外观 + 按压透明度反馈
    static var mattePress: MattePressStyle { .init() }
}

// MARK: - 面板背景修饰

/// 面板背景：panelRadius 圆角 + 纯黑面板底色 + 1px 强描边
struct PanelBackgroundModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: DT.panelRadius, style: .continuous)
                    .fill(DT.panel)
            )
            .clipShape(RoundedRectangle(cornerRadius: DT.panelRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DT.panelRadius, style: .continuous)
                    .strokeBorder(DT.strokeStrong, lineWidth: 1)
            )
    }
}

extension View {
    /// 应用面板背景修饰（panelRadius 圆角 + panel 底色 + 1px strokeStrong 描边）
    func panelBackground() -> some View {
        modifier(PanelBackgroundModifier())
    }
}

// MARK: - 即时悬停提示（全局工具提示）

/// 全局即时工具提示控制器：在光标旁弹出无边框小面板（哑光黑风格）。
/// 替代系统 .help 的长延迟（用户感知不到提示作用）；从任意元素
/// （设置项 ? 图标 / 面板「未知来源」）触发，不受视图裁剪与坐标系影响。
@MainActor
final class TooltipController {
    static let shared = TooltipController()

    private var panel: NSPanel?

    private init() {}

    /// 在光标旁显示提示；text 为空则隐藏。悬停期间持续显示，移开元素（onHover 结束）才隐藏。
    func show(_ text: String) {
        guard !text.isEmpty else { hide(); return }
        let panel = makePanel()
        self.panel = panel

        let content = Text(text)
            .font(.system(size: 11))
            .foregroundStyle(DT.fg)
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true) // 按给定宽度换行、取自然高度（不截断）
            .frame(width: 260, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(DT.menuSurface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(DT.stroke, lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.45), radius: 10, y: 5)
            )
        let hosting = NSHostingView(rootView: content)
        // 用实测 fittingSize 布局面板，保证多行文本完整展示
        let size = hosting.fittingSize
        hosting.frame = NSRect(origin: .zero, size: size)
        panel.setContentSize(size)
        panel.contentView = hosting

        // 定位到光标右下方（AppKit：y 向上，光标下方 = 更小的 y）；贴边自动钳制/翻转
        let mouse = NSEvent.mouseLocation
        var x = mouse.x + 14
        var y = mouse.y - size.height - 8
        if let screen = NSScreen.main {
            x = min(max(x, screen.frame.minX + 8), screen.frame.maxX - size.width - 8)
            if y < screen.frame.minY + 8 {
                y = mouse.y + 14 // 光标下方放不下 → 放到光标上方
            }
            y = min(max(y, screen.frame.minY + 8), screen.frame.maxY - size.height - 8)
        }
        panel.setFrameOrigin(NSPoint(x: x, y: y))
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.1
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
    }

    /// 隐藏提示
    func hide() {
        panel?.orderOut(nil)
        panel = nil
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 260, height: 100),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        // 层级必须高于设置窗口（statusBar+1）与主面板（statusBar），否则提示被压在窗口后面不可见
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 2)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        return panel
    }
}

/// 悬停触发全局工具提示（延迟约 0.12s，跟随光标；text 为空不触发）
struct InstantHelpTip: ViewModifier {
    let text: String

    @State private var task: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .onHover { hovering in
                task?.cancel()
                if hovering, !text.isEmpty {
                    // 极短延迟再显示（避免快速扫过即闪），远快于系统 .help
                    task = Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 120_000_000)
                        guard !Task.isCancelled else { return }
                        TooltipController.shared.show(text)
                    }
                } else {
                    TooltipController.shared.hide()
                }
            }
    }
}

extension View {
    /// 即时悬停提示（替代 .help：延迟短、跟随光标、可感知）
    func instantHelpTip(_ text: String) -> some View {
        modifier(InstantHelpTip(text: text))
    }
}
