//
//  ClipMoreMenu.swift
//  Repaste
//
//  ⋮ 更多菜单：自绘哑光黑浮层（menuSurface 底、14 圆角、项 hover stroke、danger 红）
//  菜单项按 kind 组合：文本=无格式复制；图片=查看图片；链接/文件无专属动作（打开链接已外置为行内按钮）
//

import SwiftUI

// MARK: - 菜单动作

/// ⋮ 菜单动作（由 PanelView 分发到 PanelViewModel）
enum ClipMenuAction {
    /// 无格式复制（仅文本）
    case plainCopy
    /// 查看图片（仅图片）
    case viewImage
    /// 存入模板组…（⌘G 等价）
    case saveToGroup
    /// 固定到顶部 / 取消固定
    case togglePin
    /// 删除（直接删，无确认）
    case delete
}

// MARK: - 自绘菜单浮层

/// ⋮ 更多菜单浮层（严格按 kind 组合菜单项；原生 Menu 为系统材质与哑光黑差异过大，故自绘）
struct ClipMoreMenu: View {
    /// 目标条目
    let clip: Clip
    /// 菜单项动作回调
    let onAction: (ClipMenuAction) -> Void

    /// 当前 hover 的动作（高亮对应项）
    @State private var hoveredAction: ClipMenuAction?

    /// 菜单宽度（原型 mmenu 规格 218）
    static let menuWidth: CGFloat = 218

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            menuTitle
            // 文本专属：无格式复制（其后加分隔线）
            if clip.kindEnum == .text {
                item(.plainCopy, icon: "doc.on.doc", title: "无格式复制")
                separator
            }
            // 图片专属：查看图片（其后加分隔线）
            if clip.kindEnum == .image {
                item(.viewImage, icon: "photo", title: "查看图片")
                separator
            }
            // 通用动作：存组（⌘G）/ 固定 / 删除（链接打开已外置为行内「打开链接」按钮，不在菜单内）
            item(.saveToGroup, icon: "folder.badge.plus", title: "存入模板组…", hotkey: "⌘G")
            item(.togglePin, icon: clip.pinned ? "pin.slash" : "pin", title: clip.pinned ? "取消固定" : "固定到顶部")
            item(.delete, icon: "trash", title: "删除", isDanger: true)
        }
        .padding(6)
        .frame(width: Self.menuWidth, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(DT.menuSurface)
        )
        .shadow(color: .black.opacity(0.55), radius: 18, y: 10)
    }

    // MARK: 标题

    /// 顶部小标题（如「文本内容 · 更多操作」）
    private var menuTitle: some View {
        Text("\(clip.kindEnum.kindLabel)内容 · 更多操作")
            .font(.system(size: 10.5))
            .foregroundStyle(DT.muted2)
            .padding(.horizontal, 11)
            .padding(.top, 7)
            .padding(.bottom, 5)
    }

    // MARK: 菜单项

    /// 单个菜单项：图标 + 文字左对齐，右侧可选快捷键提示；hover 高亮（危险项红色）
    private func item(
        _ action: ClipMenuAction,
        icon: String,
        title: String,
        hotkey: String? = nil,
        isDanger: Bool = false
    ) -> some View {
        let isHovering = hoveredAction == action
        return Button {
            onAction(action)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .foregroundStyle(isDanger ? DT.danger : DT.muted)
                    .frame(width: 16, alignment: .center)
                Text(title)
                    .font(.system(size: 12.5))
                    .foregroundStyle(isDanger ? DT.danger : DT.fg)
                Spacer(minLength: 0)
                if let hotkey {
                    Text(hotkey)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(DT.muted2)
                }
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(hoverBackground(isHovering: isHovering, isDanger: isDanger))
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            // 仅 hover 高亮，无需动画（哑光即时反馈）
            hoveredAction = hovering ? action : nil
        }
    }

    /// 项 hover 底色：普通项白 10%（stroke），危险项 dangerSoft
    private func hoverBackground(isHovering: Bool, isDanger: Bool) -> Color {
        guard isHovering else { return .clear }
        return isDanger ? DT.dangerSoft : DT.stroke
    }

    /// 分隔线（白 8% ≈ stroke，两侧留边）
    private var separator: some View {
        Rectangle()
            .fill(DT.stroke)
            .frame(height: 1)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
    }

    // MARK: 高度估算

    /// 菜单高度估算（供弹出方向上下翻转判断；行高 33、标题 32、分隔线 11、容器 padding 12）
    static func estimatedHeight(for clip: Clip) -> CGFloat {
        let hasExtraItem = clip.kindEnum == .text || clip.kindEnum == .image
        let itemCount = hasExtraItem ? 4 : 3
        let separatorCount = hasExtraItem ? 1 : 0
        return 32 + 12 + CGFloat(itemCount) * 33 + CGFloat(separatorCount) * 11
    }
}
