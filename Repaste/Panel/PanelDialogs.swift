//
//  PanelDialogs.swift
//  Repaste
//
//  面板内浮层弹窗：新建模板组 / 新建模板 / 存入模板组 / 重命名组 / 删除组
//  （半透明遮罩 + dialogRadius 20 圆角卡片；哑光纯黑，不用系统 NSAlert）
//

import SwiftUI

// MARK: - 弹窗卡片外壳

/// 弹窗卡片外壳：标题 15pt fgStrong + 副标题 muted + 内容区 + 右下角「取消 / 主按钮」
struct PanelDialogCard<Content: View>: View {
    let title: String
    var subtitle: String? = nil
    let cancelTitle: String
    let confirmTitle: String
    /// 主按钮底色（默认强调紫；删除确认传 danger）
    var confirmColor: Color = DT.accentBtn
    let onCancel: () -> Void
    let onConfirm: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(DT.fgStrong)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 11.5))
                    .foregroundStyle(DT.muted)
                    .padding(.top, 2)
            }
            content()
                .padding(.top, 14)
            // 按钮行：右下角，取消（SolidButton）+ 主按钮（accentBtn 底白字）
            HStack(spacing: 9) {
                Spacer(minLength: 0)
                SolidButton(title: cancelTitle, action: onCancel)
                DialogPrimaryButton(title: confirmTitle, color: confirmColor, action: onConfirm)
            }
            .padding(.top, 18)
        }
        .padding(20)
        .frame(width: 380)
        .background(
            RoundedRectangle(cornerRadius: DT.dialogRadius, style: .continuous)
                .fill(DT.menuSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DT.dialogRadius, style: .continuous)
                .strokeBorder(DT.strokeStrong, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.6), radius: 34, y: 14)
    }
}

// MARK: - 通用控件

/// 弹窗主按钮：accentBtn 实底白字（与 SolidButton 同尺寸；危险确认传 danger 底）
struct DialogPrimaryButton: View {
    let title: String
    var color: Color = DT.accentBtn
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(DT.monoFont)
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: DT.innerCardRadius, style: .continuous)
                        .fill(color)
                )
        }
        .buttonStyle(.mattePress)
    }
}

/// 弹窗字段标签（11.5pt muted）
struct DialogFieldLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11.5))
            .foregroundStyle(DT.muted)
    }
}

/// 弹窗单行输入框：InnerCard 样式、自动聚焦、Enter 提交、聚焦时紫色描边
struct DialogTextField: View {
    let placeholder: String
    @Binding var text: String
    let onSubmit: () -> Void

    @FocusState private var focused: Bool

    var body: some View {
        InnerCard {
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(DT.fg)
                .padding(.horizontal, 11)
                .frame(height: 34)
                .focused($focused)
                .onSubmit(onSubmit)
        }
        // 聚焦描边（accent 1px，哑光无光晕）
        .overlay(
            RoundedRectangle(cornerRadius: DT.innerCardRadius, style: .continuous)
                .strokeBorder(focused ? DT.accent : .clear, lineWidth: 1)
        )
        .onAppear { focused = true }
    }
}

/// 弹窗多行输入（InnerCard 样式 TextEditor，高约 120；Enter 换行、⌘Enter 提交）
struct DialogTextEditor: View {
    let placeholder: String
    @Binding var text: String
    let onSubmit: () -> Void

    @FocusState private var focused: Bool

    var body: some View {
        InnerCard {
            ZStack(alignment: .topLeading) {
                // 占位文案（TextEditor 无原生 placeholder）
                if text.isEmpty {
                    Text(placeholder)
                        .font(.system(size: 13))
                        .foregroundStyle(DT.muted2)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $text)
                    .font(.system(size: 13))
                    .foregroundStyle(DT.fg)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .frame(height: 120)
                    .focused($focused)
                    .onKeyPress { keyPress in
                        // ⌘Return 提交（普通 Return 在多行输入框内换行）
                        guard keyPress.key == .return, keyPress.modifiers.contains(.command) else { return .ignored }
                        onSubmit()
                        return .handled
                    }
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: DT.innerCardRadius, style: .continuous)
                .strokeBorder(focused ? DT.accent : .clear, lineWidth: 1)
        )
        .onAppear { focused = true }
    }
}

// MARK: - 模板组下拉选择器

/// 模板组下拉选择器（InnerCard 样式按钮 + 自绘下拉列表；末尾固定「＋ 新建模板组…」项）
struct GroupPicker: View {
    let groups: [TemplateGroup]
    /// 选中的组 id（nil = 「＋ 新建模板组…」当场新建）
    @Binding var selection: UUID?

    /// 下拉展开状态
    @State private var isOpen = false

    var body: some View {
        pickerButton
            // 点击层（展开时盖住弹窗区域，点任意处收起下拉；不影响布局尺寸）
            .overlay {
                if isOpen {
                    Color.clear
                        .frame(width: 460, height: 420)
                        .contentShape(Rectangle())
                        .onTapGesture { isOpen = false }
                }
            }
            // 下拉列表（悬浮于按钮下方 6px；后挂 overlay 层级高于点击层）
            .overlay(alignment: .top) {
                if isOpen {
                    dropdown
                        .offset(y: 42)
                }
            }
    }

    // MARK: 按钮本体

    /// 当前选中项 + chevron
    private var pickerButton: some View {
        Button {
            isOpen.toggle()
        } label: {
            HStack(spacing: 8) {
                Text(selectedTitle)
                    .font(.system(size: 13))
                    .foregroundStyle(selection == nil ? DT.accent : DT.fg)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DT.muted)
            }
            .padding(.horizontal, 11)
            .frame(height: 36)
        }
        .buttonStyle(.mattePress)
        .background(
            RoundedRectangle(cornerRadius: DT.innerCardRadius, style: .continuous)
                .fill(DT.surface2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DT.innerCardRadius, style: .continuous)
                .strokeBorder(DT.innerCardStroke, lineWidth: 1)
        )
    }

    /// 按钮展示文案：选中组名 / 「＋ 新建模板组…」
    private var selectedTitle: String {
        if selection == nil { return "＋ 新建模板组…" }
        return groups.first { $0.id == selection }?.name ?? ""
    }

    // MARK: 下拉列表

    /// 下拉列表（menuSurface 底 14 圆角；已有组名项 + 新建项）
    private var dropdown: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(groups, id: \.id) { group in
                row(title: group.name, isSelected: selection == group.id) {
                    selection = group.id
                    isOpen = false
                }
            }
            if !groups.isEmpty {
                separator
            }
            row(title: "＋ 新建模板组…", isSelected: selection == nil, isNew: true) {
                selection = nil
                isOpen = false
            }
        }
        .padding(6)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(DT.menuSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(DT.stroke, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.55), radius: 18, y: 10)
    }

    /// 下拉行（选中项白 10% 底；新建项强调紫）
    private func row(title: String, isSelected: Bool, isNew: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 12.5))
                    .foregroundStyle(isNew ? DT.accent : DT.fg)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(DT.accentBright)
                }
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? DT.stroke : .clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.mattePress)
    }

    /// 分隔线
    private var separator: some View {
        Rectangle()
            .fill(DT.stroke)
            .frame(height: 1)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
    }
}

// MARK: - 新建模板组弹窗

/// 新建模板组弹窗内容（只问名称；创建即新增 tab 并自动切换）
struct NewGroupDialogContent: View {
    @Bindable var viewModel: PanelViewModel

    var body: some View {
        PanelDialogCard(
            title: "新建模板组",
            subtitle: "创建后在顶部标签行新增一个标签页，并自动切换到该组。",
            cancelTitle: "取消",
            confirmTitle: "创建",
            onCancel: { viewModel.cancelDialog() },
            onConfirm: { viewModel.confirmNewGroup() }
        ) {
            VStack(alignment: .leading, spacing: 6) {
                DialogFieldLabel(text: "名称")
                DialogTextField(placeholder: "例：回复模板", text: $viewModel.groupNameInput) {
                    viewModel.confirmNewGroup()
                }
            }
        }
    }
}

// MARK: - 新建模板弹窗

/// 新建模板弹窗内容（归属即当前组；不命名，直接填内容）
struct NewTemplateDialogContent: View {
    @Bindable var viewModel: PanelViewModel
    let groupId: UUID

    /// 当前组名（弹窗标题用）
    private var groupName: String {
        viewModel.groups.first { $0.id == groupId }?.name ?? ""
    }

    var body: some View {
        PanelDialogCard(
            title: "新建模板 · \(groupName)",
            subtitle: "归属即当前模板组，无「归组」选择，也不命名——直接填内容。",
            cancelTitle: "取消",
            confirmTitle: "保存",
            onCancel: { viewModel.cancelDialog() },
            onConfirm: { viewModel.confirmNewTemplate() }
        ) {
            VStack(alignment: .leading, spacing: 6) {
                DialogFieldLabel(text: "内容")
                DialogTextEditor(placeholder: "静态文本即可。", text: $viewModel.templateContentInput) {
                    viewModel.confirmNewTemplate()
                }
            }
        }
    }
}

// MARK: - 存入模板组弹窗

/// 存入模板组弹窗内容（目标组下拉 + 当场新建 + 内容只读预览）
struct SaveToGroupDialogContent: View {
    @Bindable var viewModel: PanelViewModel
    /// 待存入的历史条目
    let clip: Clip

    var body: some View {
        PanelDialogCard(
            title: "存入模板组",
            subtitle: "把这条历史沉淀为模板（等价 ⌘G），不命名，存后不参与 200 条淘汰。",
            cancelTitle: "取消",
            confirmTitle: "保存",
            onCancel: { viewModel.cancelDialog() },
            onConfirm: { viewModel.confirmSaveToGroup() }
        ) {
            VStack(alignment: .leading, spacing: 12) {
                // 目标组选择
                VStack(alignment: .leading, spacing: 6) {
                    DialogFieldLabel(text: "存入模板组")
                    GroupPicker(groups: viewModel.groups, selection: $viewModel.saveToGroupTargetId)
                }
                // 选中「＋ 新建模板组…」时追加：新组名称输入
                if viewModel.saveToGroupTargetId == nil {
                    VStack(alignment: .leading, spacing: 6) {
                        DialogFieldLabel(text: "新模板组名称")
                        DialogTextField(placeholder: "例：常用信息", text: $viewModel.groupNameInput) {
                            viewModel.confirmSaveToGroup()
                        }
                    }
                }
                // 内容只读预览（两行截断）
                VStack(alignment: .leading, spacing: 6) {
                    DialogFieldLabel(text: "内容")
                    InnerCard {
                        Text(clip.preview)
                            .font(.system(size: 13))
                            .foregroundStyle(DT.muted)
                            .lineLimit(2)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 9)
                    }
                }
            }
        }
    }
}

// MARK: - 重命名模板组弹窗

/// 重命名模板组弹窗内容（预填旧名，保存更新组名）
struct RenameGroupDialogContent: View {
    @Bindable var viewModel: PanelViewModel
    let groupId: UUID

    var body: some View {
        PanelDialogCard(
            title: "重命名模板组",
            subtitle: "修改后顶部标签页同步更新。",
            cancelTitle: "取消",
            confirmTitle: "保存",
            onCancel: { viewModel.cancelDialog() },
            onConfirm: { viewModel.confirmRenameGroup() }
        ) {
            VStack(alignment: .leading, spacing: 6) {
                DialogFieldLabel(text: "名称")
                DialogTextField(placeholder: "组名", text: $viewModel.groupNameInput) {
                    viewModel.confirmRenameGroup()
                }
            }
        }
    }
}

// MARK: - 删除模板组弹窗

/// 删除模板组确认弹窗内容（组内模板一并移除，需二次确认）
struct DeleteGroupDialogContent: View {
    @Bindable var viewModel: PanelViewModel
    let groupId: UUID

    /// 组名（副标题文案用）
    private var groupName: String {
        viewModel.groups.first { $0.id == groupId }?.name ?? ""
    }

    /// 组内模板条数
    private var templateCount: Int {
        viewModel.clips.filter { $0.groupId == groupId }.count
    }

    var body: some View {
        PanelDialogCard(
            title: "删除模板组",
            subtitle: "删除后「\(groupName)」及组内 \(templateCount) 个模板将一并移除，此操作不可撤销。",
            cancelTitle: "取消",
            confirmTitle: "删除",
            confirmColor: DT.danger,
            onCancel: { viewModel.cancelDialog() },
            onConfirm: { viewModel.confirmDeleteGroup() }
        ) {
            EmptyView()
        }
    }
}

// MARK: - 退出确认弹窗

/// 退出确认弹窗（头部 ⏻ 按钮触发；「退出」= 终止应用，esc / 取消 / 点遮罩 = 关闭弹窗）
struct QuitDialogContent: View {
    @Bindable var viewModel: PanelViewModel

    var body: some View {
        PanelDialogCard(
            title: "退出刘海剪贴板？",
            subtitle: "退出后剪贴板监听将停止，历史记录仍保留在本机。",
            cancelTitle: "取消",
            confirmTitle: "退出",
            confirmColor: DT.danger,
            onCancel: { viewModel.cancelDialog() },
            onConfirm: { viewModel.confirmQuit() }
        ) {
            EmptyView()
        }
    }
}
