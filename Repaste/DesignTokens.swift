//
//  DesignTokens.swift
//  Repaste
//
//  设计系统：哑光纯黑质感（无玻璃 / 无模糊 / 无发光）
//  所有 UI 强制使用本文件定义的颜色、圆角、尺寸、字体与通用组件
//

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
    /// 类型色：未知 #FFB454
    static let unknown = Color(red: 255 / 255, green: 180 / 255, blue: 84 / 255)

    /// 危险色（删除等破坏性动作文字）#FF9089
    static let danger = Color(red: 255 / 255, green: 144 / 255, blue: 137 / 255)
    /// 危险色柔和底（危险项 hover）rgba(255,107,98,.16)
    static let dangerSoft = Color(red: 255 / 255, green: 107 / 255, blue: 98 / 255, opacity: 0.16)
    /// 降级提示文字 #FFD9A0（原图已清理提示条）
    static let warnText = Color(red: 255 / 255, green: 217 / 255, blue: 160 / 255)

    /// 菜单浮层底色 #232323（⋮ 更多菜单，比面板底亮一档以区分层级）
    static let menuSurface = Color(red: 35 / 255, green: 35 / 255, blue: 35 / 255)

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
    static let panelWidth: CGFloat = 620

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
        .buttonStyle(.plain)
    }
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
