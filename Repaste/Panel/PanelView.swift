//
//  PanelView.swift
//  Repaste
//
//  面板主视图：搜索头部 / 标签页 / 来源条 / 暂停提示 / 列表
//  （刘海下拉与快捷键居中双入口共用的核心列表；哑光纯黑设计）
//

import SwiftUI
import UniformTypeIdentifiers

// MARK: - 面板主视图

/// 面板主视图（宽 620、panelRadius 圆角、DT.panel 底色；高度自适应内容，超出内部滚动）
struct PanelView: View {
    let viewModel: PanelViewModel

    /// 面板命名坐标系（⋮ 按钮锚点 frame 的参照系，菜单弹出定位用）
    static let coordinateSpaceName = "panel"

    /// 搜索框聚焦
    @FocusState private var searchFocused: Bool

    /// 面板当前高度（onGeometryChange 持续更新；菜单上下翻转与预览图片高度约束用）
    @State private var panelHeight: CGFloat = 560

    /// 列表区最大高度（固定区约 180 + 列表 380 ≈ 面板最大约 560）
    private static let listMaxHeight: CGFloat = 380
    /// 列表区最小高度（内容少时保底，避免面板过扁）
    private static let listMinHeight: CGFloat = 200

    var body: some View {
        VStack(spacing: 0) {
            headerRow
            tabBar
            if viewModel.showsSourceBar {
                sourceBar
            }
            if viewModel.showsPausedBanner {
                pausedBanner
            }
            listArea
        }
        .frame(width: DT.panelWidth)
        .coordinateSpace(name: Self.coordinateSpaceName)
        .panelShapeBackground(isNotch: viewModel.isNotchMode)
        // ⋮ 更多菜单浮层（zIndex 低于图片预览与 toast；点菜单外任意处关闭）
        .overlay(alignment: .topLeading) {
            moreMenuOverlay
                .animation(.easeOut(duration: 0.12), value: viewModel.moreMenuClip == nil)
        }
        // 模板行 ⋮ 菜单浮层（同历史菜单，点菜单外任意处关闭）
        .overlay(alignment: .topLeading) {
            templateMenuOverlay
                .animation(.easeOut(duration: 0.12), value: viewModel.templateMenuClip == nil)
        }
        // 浏览器选择浮层（⌥ 点「跳转」触发，点浮层外任意处关闭）
        .overlay(alignment: .topLeading) {
            browserChooserOverlay
                .animation(.easeOut(duration: 0.12), value: viewModel.browserChooserClip == nil)
        }
        // 图片放大查看浮层（遮罩盖住整个面板，zIndex 高于列表与菜单）
        .overlay {
            previewOverlay
                .animation(.easeOut(duration: 0.15), value: viewModel.previewingClip == nil)
        }
        // 弹窗浮层（面板内居中：半透明遮罩 + 圆角卡片；zIndex 高于菜单与预览）
        .overlay {
            dialogOverlay
                .animation(.easeOut(duration: 0.15), value: viewModel.activeDialog == nil)
        }
        // toast 轻提示（面板顶部浮现，最上层）
        .overlay(alignment: .top) {
            toastOverlay
                .animation(.easeOut(duration: 0.18), value: viewModel.toastText)
        }
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.height
        } action: { height in
            panelHeight = height
        }
        .onAppear { searchFocused = true }
        .onChange(of: viewModel.searchFocusRequest) { _, _ in
            searchFocused = true
        }
        .onChange(of: viewModel.activeDialog) { _, newValue in
            // 弹窗关闭后焦点回到搜索框（键盘导航不中断）
            if newValue == nil { searchFocused = true }
        }
        .onKeyPress { press in
            handleKeyPress(press)
        }
    }

    // MARK: 头部行（搜索框 + 设置 / 退出按钮）

    private var headerRow: some View {
        HStack(spacing: 9) {
            searchField
            iconButton(icon: "gearshape", help: "设置") {
                // 面板 NSHostingView 不在 Scene 环境内，经桥接调用 openWindow(id: "settings")
                AppWindowBridge.shared.openSettings()
            }
            iconButton(icon: "power", help: "退出") {
                // 退出确认弹窗（面板内浮层，非系统 NSAlert；「退出」= 终止应用）
                viewModel.showQuitConfirm()
            }
        }
        .padding(.horizontal, 12)
        // notch 模式顶边贴合屏幕顶，头部行下移一个刘海 / 菜单栏高度，避免与刘海并排
        .padding(.top, 10 + viewModel.notchTopInset)
        .padding(.bottom, 8)
    }

    /// 搜索框（InnerCard 样式、圆角 12、高 34、聚焦即筛）
    private var searchField: some View {
        @Bindable var model = viewModel

        return InnerCard {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13))
                    .foregroundStyle(DT.muted2)
                TextField("搜索…", text: $model.searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(DT.fg)
                    .focused($searchFocused)
                    .onSubmit { model.useSelected() }
            }
            .padding(.horizontal, 11)
            .frame(height: 34)
        }
    }

    /// 28×28 图标按钮（button 实底、8 圆角）
    private func iconButton(icon: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(DT.fg)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(DT.button)
                )
        }
        .buttonStyle(.plain)
        .help(help)
    }

    // MARK: 标签页行

    /// 标签页数据项
    private struct TabItem: Identifiable {
        let tab: PanelTab
        let title: String

        var id: String {
            switch tab {
            case .all: return "all"
            case .text: return "text"
            case .image: return "image"
            case .link: return "link"
            case .group(let id): return "group-\(id.uuidString)"
            }
        }
    }

    /// 标签页列表：全部 / 文本 / 图片 / 链接 + 各模板组名
    private var tabItems: [TabItem] {
        var items = [
            TabItem(tab: .all, title: "全部"),
            TabItem(tab: .text, title: "文本"),
            TabItem(tab: .image, title: "图片"),
            TabItem(tab: .link, title: "链接"),
        ]
        for group in viewModel.groups {
            items.append(TabItem(tab: .group(group.id), title: group.name))
        }
        return items
    }

    /// 横向标签页行（隐藏滚动条；当前 tab 用 PillChip 选中态白底黑字胶囊；间距 6）
    private var tabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(tabItems) { item in
                    Button {
                        viewModel.selectedTab = item.tab
                    } label: {
                        PillChip(title: item.title, isSelected: viewModel.selectedTab == item.tab)
                    }
                    .buttonStyle(.plain)
                }
                // 新建模板组入口（＋ 弹窗：只问名称，创建即新增 tab 并切换）
                Button {
                    viewModel.showNewGroupDialog()
                } label: {
                    Text("＋")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(DT.accent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
                .help("新建模板组")
            }
            .padding(.horizontal, 14)
        }
        .padding(.bottom, 9)
    }

    // MARK: 来源条

    /// 来源条（横向滚动 chip 行：全部来源 + 各来源 App 图标 16×16 + 名称 + 计数；点击切换 / 再点取消）
    private var sourceBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                sourceChip(
                    icon: nil,
                    title: "全部来源",
                    count: viewModel.sourceTotal,
                    isSelected: viewModel.selectedSourceFilter == nil
                ) {
                    viewModel.selectSource(nil)
                }
                ForEach(viewModel.sourceCounts) { source in
                    sourceChip(
                        icon: source.iconPath.flatMap { AppIconStore.shared.load(fileName: $0) },
                        title: source.name,
                        count: source.count,
                        isSelected: viewModel.selectedSourceFilter == source.key
                    ) {
                        viewModel.selectSource(source.key)
                    }
                }
            }
            .padding(.horizontal, 14)
        }
        .padding(.bottom, 9)
    }

    /// 来源 chip（选中态白底黑字胶囊；未知来源用中性问号图标）
    private func sourceChip(
        icon: NSImage?,
        title: String,
        count: Int,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 16, height: 16)
                } else if title == "全部来源" {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 11))
                        .foregroundStyle(isSelected ? DT.panel : DT.muted2)
                } else {
                    // 未知来源：中性问号图标
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 11))
                        .foregroundStyle(isSelected ? DT.panel : DT.muted2)
                }
                Text(title)
                    .lineLimit(1)
                Text("\(count)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(isSelected ? DT.muted2 : DT.muted)
            }
            .font(.system(size: 11.5))
            .foregroundStyle(isSelected ? DT.panel : DT.fg)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                Capsule().fill(isSelected ? Color.white : DT.surface3)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: 录制暂停提示条

    /// 「录制已暂停」提示条（recordingEnabled == false 时显示，黄色 warn 色小字条）
    private var pausedBanner: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(DT.unknown)
                .frame(width: 7, height: 7)
            Text("录制已暂停，新复制的内容不会进入历史")
                .font(.system(size: 12))
                .foregroundStyle(DT.unknown)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(DT.unknown.opacity(0.16))
        )
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    // MARK: 列表区

    /// 列表区：模板组 tab 渲染模板区，其余渲染历史列表 / 空态（高度自适应，超出内部滚动）
    private var listArea: some View {
        Group {
            if viewModel.isGroupTab {
                templateArea
            } else if viewModel.filteredClips.isEmpty {
                emptyState
            } else {
                clipList
            }
        }
        .frame(minHeight: Self.listMinHeight, maxHeight: Self.listMaxHeight)
    }

    // MARK: 模板组内容区

    /// 模板组 tab 内容区：组管理行 + 模板列表（可拖拽排序）+ 底部操作区（固定，不在滚动区内）
    private var templateArea: some View {
        VStack(spacing: 0) {
            groupManageRow
            if viewModel.filteredClips.isEmpty {
                templateEmptyState
            } else {
                templateList
            }
            templateFooter
        }
    }

    /// 组管理行：右对齐小文字按钮「重命名 / 删除组」（仅模板组 tab 显示）
    private var groupManageRow: some View {
        HStack(spacing: 14) {
            Spacer(minLength: 0)
            SmallTextButton(title: "重命名") {
                viewModel.showRenameGroupDialog()
            }
            SmallTextButton(title: "删除组") {
                viewModel.showDeleteGroupDialog()
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 4)
        .padding(.bottom, 6)
    }

    /// 模板列表（行可拖拽排序；键盘选中滚动跟随；搜索同样生效）
    private var templateList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(Array(viewModel.filteredClips.enumerated()), id: \.element.id) { index, clip in
                        TemplateRow(
                            clip: clip,
                            isSelected: viewModel.selectionIndex == index,
                            onUse: {
                                viewModel.selectionIndex = index
                                viewModel.use(clip: clip)
                            },
                            onMore: { anchor in
                                viewModel.openTemplateMenu(clip: clip, anchor: anchor)
                            }
                        )
                        .id(clip.id)
                        // 拖拽排序：拖起记录条目 id；悬停到目标行即时重排
                        .onDrag {
                            viewModel.draggingTemplateId = clip.id
                            return NSItemProvider(object: clip.id.uuidString as NSString)
                        }
                        .onDrop(of: [UTType.utf8PlainText], delegate: TemplateDropDelegate(target: clip, viewModel: viewModel))
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 2)
                .padding(.bottom, 8)
            }
            // 松手落在行间空白处也提交排序（dragTemplateEnded 幂等）
            .onDrop(of: [UTType.utf8PlainText], isTargeted: nil) { _ in
                viewModel.dragTemplateEnded()
                return true
            }
            .onChange(of: viewModel.selectionIndex) { _, newValue in
                guard let index = newValue,
                      viewModel.filteredClips.indices.contains(index) else { return }
                withAnimation(.easeOut(duration: 0.12)) {
                    proxy.scrollTo(viewModel.filteredClips[index].id, anchor: .center)
                }
            }
        }
    }

    /// 模板组空态：无模板（引导新建）与搜索无结果两种
    private var templateEmptyState: some View {
        let isSearching = !viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return VStack(spacing: 10) {
            Image(systemName: isSearching ? "magnifyingglass" : "doc.on.clipboard")
                .font(.system(size: 32))
                .foregroundStyle(DT.muted2)
            Text(isSearching ? "没有匹配的结果" : "还没有模板")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(DT.fg)
            Text(isSearching ? "试试换个关键词" : "点「＋ 新建模板」添加常用内容")
                .font(.system(size: 12))
                .foregroundStyle(DT.muted)
        }
        .padding(.vertical, 36)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// 模板 tab 底部操作区（固定在列表下方）：左「＋ 新建模板」（仅内容宽度）+ 右条目计数
    private var templateFooter: some View {
        HStack(spacing: 8) {
            SolidButton(title: "＋ 新建模板") {
                viewModel.showNewTemplateDialog()
            }
            Spacer(minLength: 0)
            Text("\(viewModel.currentGroupTemplateCount) 条")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(DT.muted2)
        }
        .padding(.horizontal, 14)
        .padding(.top, 6)
        .padding(.bottom, 10)
    }

    /// 行列表（卡片间 6 间距、水平 padding 14；键盘选中滚动跟随）
    private var clipList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(Array(viewModel.filteredClips.enumerated()), id: \.element.id) { index, clip in
                        ClipRow(
                            clip: clip,
                            isSelected: viewModel.selectionIndex == index,
                            onUse: {
                                viewModel.selectionIndex = index
                                viewModel.use(clip: clip)
                            },
                            onSourceTap: { viewModel.selectSource($0) },
                            onOpenLink: {
                                viewModel.openLink(clip: clip, kind: "inline")
                            },
                            onChooseBrowser: { anchor in
                                viewModel.openBrowserChooser(clip: clip, anchor: anchor)
                            },
                            onMore: { anchor in
                                viewModel.openMoreMenu(clip: clip, anchor: anchor)
                            }
                        )
                        .id(clip.id)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 8)
                .padding(.bottom, 10)
            }
            .onChange(of: viewModel.selectionIndex) { _, newValue in
                guard let index = newValue,
                      viewModel.filteredClips.indices.contains(index) else { return }
                withAnimation(.easeOut(duration: 0.12)) {
                    proxy.scrollTo(viewModel.filteredClips[index].id, anchor: .center)
                }
            }
        }
    }

    // MARK: 空态

    /// 空态：无任何历史（大空态）与有历史但筛选无结果（小空态）两种
    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: viewModel.hasNoHistory ? "doc.on.clipboard" : "magnifyingglass")
                .font(.system(size: 32))
                .foregroundStyle(DT.muted2)
            Text(viewModel.hasNoHistory ? "还没有任何记录" : "没有匹配的结果")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(DT.fg)
            Text(viewModel.hasNoHistory ? "复制点什么试试，内容会自动出现在这里" : "试试换个关键词或来源")
                .font(.system(size: 12))
                .foregroundStyle(DT.muted)
        }
        .padding(.vertical, 36)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: ⋮ 更多菜单浮层

    /// 菜单浮层：透明点击层（点菜单外关闭）+ 菜单本体（按锚点定位，向下弹出、空间不足向上翻转）
    private var moreMenuOverlay: some View {
        ZStack(alignment: .topLeading) {
            if viewModel.moreMenuClip != nil {
                // 点击层：拦截面板内所有点击（含列表滚动），点任意处关闭菜单
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { viewModel.closeMoreMenu() }
            }
            if let clip = viewModel.moreMenuClip {
                let position = menuPosition(
                    anchor: viewModel.moreMenuAnchor,
                    menuWidth: ClipMoreMenu.menuWidth,
                    menuHeight: ClipMoreMenu.estimatedHeight(for: clip)
                )
                ClipMoreMenu(clip: clip) { action in
                    viewModel.closeMoreMenu()
                    handleMenuAction(action, for: clip)
                }
                .offset(x: position.x, y: position.y)
            }
        }
    }

    // MARK: 模板行 ⋮ 菜单浮层

    /// 模板菜单浮层：透明点击层（点菜单外关闭）+ 菜单本体（使用 / 复制 / 删除）
    private var templateMenuOverlay: some View {
        ZStack(alignment: .topLeading) {
            if viewModel.templateMenuClip != nil {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { viewModel.closeTemplateMenu() }
            }
            if let clip = viewModel.templateMenuClip {
                TemplateRowMenu(clip: clip) { action in
                    viewModel.closeTemplateMenu()
                    handleTemplateMenuAction(action, for: clip)
                }
                .offset(
                    x: templateMenuPosition.x,
                    y: templateMenuPosition.y
                )
            }
        }
    }

    /// 模板菜单弹出位置（与历史菜单同规则）
    private var templateMenuPosition: CGPoint {
        guard let clip = viewModel.templateMenuClip else { return .zero }
        return menuPosition(
            anchor: viewModel.templateMenuAnchor,
            menuWidth: TemplateRowMenu.menuWidth,
            menuHeight: TemplateRowMenu.estimatedHeight(for: clip)
        )
    }

    // MARK: 浏览器选择浮层（⌥ 点「跳转」）

    /// 浏览器选择浮层：透明点击层（点浮层外关闭）+ 菜单本体（按跳转按钮锚点定位，含上下翻转）
    @ViewBuilder
    private var browserChooserOverlay: some View {
        ZStack(alignment: .topLeading) {
            if viewModel.browserChooserClip != nil {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { viewModel.closeBrowserChooser() }
            }
            if let clip = viewModel.browserChooserClip {
                let options = BrowserChooserMenu.options()
                let position = menuPosition(
                    anchor: viewModel.browserChooserAnchor,
                    menuWidth: BrowserChooserMenu.menuWidth,
                    menuHeight: BrowserChooserMenu.estimatedHeight(options: options)
                )
                BrowserChooserMenu(clip: clip) { bundleId in
                    viewModel.closeBrowserChooser()
                    viewModel.openLink(clip: clip, browserBundleId: bundleId, kind: "menu")
                }
                .offset(x: position.x, y: position.y)
            }
        }
    }

    /// 菜单弹出位置（通用）：右缘对齐锚点、锚点下方 6px；超出面板高度则向上翻转；整体钳制在面板内
    private func menuPosition(anchor: CGRect, menuWidth: CGFloat, menuHeight: CGFloat) -> CGPoint {
        // 水平：右缘对齐按钮（钳制在面板内）
        var x = anchor.maxX - menuWidth
        x = min(max(x, 10), DT.panelWidth - menuWidth - 10)

        // 垂直：默认按钮下方 6px；菜单底会超出面板则翻转到按钮上方
        var y = anchor.maxY + 6
        if y + menuHeight > panelHeight - 10 {
            y = anchor.minY - 6 - menuHeight
        }
        y = max(y, 10)
        return CGPoint(x: x, y: y)
    }

    /// 分发菜单动作到状态机
    private func handleMenuAction(_ action: ClipMenuAction, for clip: Clip) {
        switch action {
        case .plainCopy:
            viewModel.copyPlainText(clip: clip)
        case .viewImage:
            viewModel.openPreview(clip: clip)
        case .saveToGroup:
            viewModel.requestSaveToGroup(clip: clip)
        case .togglePin:
            viewModel.togglePin(clip: clip)
        case .delete:
            viewModel.delete(clip: clip)
        }
    }

    /// 分发模板菜单动作到状态机
    private func handleTemplateMenuAction(_ action: TemplateMenuAction, for clip: Clip) {
        switch action {
        case .use:
            viewModel.use(clip: clip)
        case .copy:
            viewModel.copyTemplate(clip: clip)
        case .delete:
            viewModel.deleteTemplate(clip: clip)
        }
    }

    // MARK: 弹窗浮层

    /// 弹窗浮层：半透明遮罩（点击取消）+ 居中圆角卡片
    @ViewBuilder
    private var dialogOverlay: some View {
        if let dialog = viewModel.activeDialog {
            ZStack {
                Color.black.opacity(0.5)
                    .contentShape(Rectangle())
                    .onTapGesture { viewModel.cancelDialog() }
                dialogCard(for: dialog)
            }
            .transition(.opacity)
        }
    }

    /// 按弹窗类型分发内容卡片
    @ViewBuilder
    private func dialogCard(for dialog: PanelDialog) -> some View {
        switch dialog {
        case .newGroup:
            NewGroupDialogContent(viewModel: viewModel)
        case .newTemplate(let groupId):
            NewTemplateDialogContent(viewModel: viewModel, groupId: groupId)
        case .saveToGroup(let clipId):
            if let clip = viewModel.clips.first(where: { $0.id == clipId }) {
                SaveToGroupDialogContent(viewModel: viewModel, clip: clip)
            }
        case .renameGroup(let groupId):
            RenameGroupDialogContent(viewModel: viewModel, groupId: groupId)
        case .deleteGroup(let groupId):
            DeleteGroupDialogContent(viewModel: viewModel, groupId: groupId)
        case .quitConfirm:
            QuitDialogContent(viewModel: viewModel)
        }
    }

    // MARK: 图片放大查看浮层

    /// 图片放大查看浮层（previewingClip 非空时显示；遮罩盖住整个面板）
    @ViewBuilder
    private var previewOverlay: some View {
        if let clip = viewModel.previewingClip {
            ImagePreviewOverlay(
                clip: clip,
                maxImageHeight: previewMaxImageHeight,
                onClose: { viewModel.closePreview() },
                onCopyImage: { viewModel.copyPreviewImage(clip: clip) }
            )
        }
    }

    /// 预览图片最大高度：屏幕可见高度 70%，且不超过面板高度扣除操作区（约 150）
    private var previewMaxImageHeight: CGFloat {
        let screenHeight = NSScreen.main?.visibleFrame.height ?? 600
        return max(200, min(screenHeight * 0.7, panelHeight - 150))
    }

    // MARK: toast 轻提示

    /// toast 浮层（面板顶部小黑底圆角条，1.2s 自动消失）
    @ViewBuilder
    private var toastOverlay: some View {
        if let toast = viewModel.toastText {
            Text(toast)
                .font(.system(size: 12))
                .foregroundStyle(DT.fg)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(DT.surface3)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(DT.stroke, lineWidth: 1)
                )
                .padding(.top, 8)
                .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    // MARK: 键盘导航

    /// 键盘事件处理：弹窗打开时 esc 取消（其余交给弹窗输入框）；
    /// ↑↓ 移动选中、⏎ 使用、⌘⏎ 跳转、⌘G 存入模板组、⌫ 删除、esc 逐层关闭（预览 / 菜单 / 搜索 / 面板）
    private func handleKeyPress(_ press: KeyPress) -> KeyPress.Result {
        // 弹窗打开：esc = 取消；Enter 由弹窗内输入框 onSubmit 提交主操作，其余按键透传
        if viewModel.activeDialog != nil {
            if press.key == .escape {
                viewModel.cancelDialog()
                return .handled
            }
            return .ignored
        }
        // ⌘G：存入模板组（作用于键盘选中条目；与 ⋮ 菜单等价入口）
        if press.modifiers.contains(.command), press.characters.lowercased() == "g" {
            if let index = viewModel.selectionIndex, viewModel.filteredClips.indices.contains(index) {
                viewModel.requestSaveToGroup(clip: viewModel.filteredClips[index])
            }
            return .handled
        }
        switch press.key {
        case .upArrow:
            viewModel.moveSelection(-1)
            return .handled
        case .downArrow:
            viewModel.moveSelection(1)
            return .handled
        case .return:
            if press.modifiers.contains(.command) {
                // ⌘⏎ 跳转：选中条目为链接类打开整串 URL；文本类打开首个 http(s) 链接；其他类型忽略
                if let index = viewModel.selectionIndex, viewModel.filteredClips.indices.contains(index) {
                    viewModel.openLink(clip: viewModel.filteredClips[index], kind: "hotkey")
                }
                return .handled
            }
            viewModel.useSelected()
            return .handled
        case .delete:
            viewModel.deleteSelected()
            return .handled
        case .escape:
            // 逐层关闭：图片预览 → ⋮ 菜单 → 模板菜单 → 浏览器选择浮层 → 清空搜索 → 关闭面板
            if viewModel.previewingClip != nil {
                viewModel.closePreview()
            } else if viewModel.moreMenuClip != nil {
                viewModel.closeMoreMenu()
            } else if viewModel.templateMenuClip != nil {
                viewModel.closeTemplateMenu()
            } else if viewModel.browserChooserClip != nil {
                viewModel.closeBrowserChooser()
            } else if !viewModel.searchText.isEmpty {
                viewModel.searchText = ""
            } else {
                PanelController.shared.hide()
            }
            return .handled
        default:
            return .ignored
        }
    }
}

// MARK: - 小文字按钮

/// 小文字按钮（muted 小字，hover 提亮；模板 tab 组管理行用）
private struct SmallTextButton: View {
    let title: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11.5))
                .foregroundStyle(isHovering ? DT.fg : DT.muted)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

// MARK: - 面板底形状

/// 面板底：centered 模式四角 panelRadius 圆角；
/// notch 模式顶部平边（贴合菜单栏下沿，顶部无圆角无描边）
private struct PanelShapeBackground: ViewModifier {
    let isNotch: Bool

    func body(content: Content) -> some View {
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: isNotch ? 0 : DT.panelRadius,
            bottomLeadingRadius: DT.panelRadius,
            bottomTrailingRadius: DT.panelRadius,
            topTrailingRadius: isNotch ? 0 : DT.panelRadius,
            style: .continuous
        )
        return content
            .background(shape.fill(DT.panel))
            .clipShape(shape)
            .overlay(shape.strokeBorder(DT.strokeStrong, lineWidth: 1))
            .overlay(alignment: .top) {
                if isNotch {
                    // 盖掉顶部描边（notch 模式顶边贴合菜单栏，不画描边）
                    Rectangle()
                        .fill(DT.panel)
                        .frame(height: 2)
                }
            }
    }
}

extension View {
    /// 应用面板底形状（notch 顶部平边 / centered 四角圆角 + panel 底色 + strokeStrong 描边）
    func panelShapeBackground(isNotch: Bool) -> some View {
        modifier(PanelShapeBackground(isNotch: isNotch))
    }
}

// MARK: - Xcode 预览

/// 面板预览（居中模式四角圆角；notch 模式需真机/模拟运行——NSPanel 只在运行时由 PanelController 创建）
#Preview("主面板 · 居中") {
    PanelView(viewModel: {
        let vm = PanelViewModel()
        vm.isNotchMode = false
        return vm
    }())
        .padding(40)
        .background(
            LinearGradient(colors: [Color(hex: 0x18181E), Color(hex: 0x0A0A0E)],
                           startPoint: .top, endPoint: .bottom)
        )
        .preferredColorScheme(.dark)
}

/// 面板预览（刘海下拉模式：顶边平直，模拟贴菜单栏下沿）
#Preview("主面板 · 刘海") {
    VStack(spacing: 0) {
        // 模拟菜单栏
        Rectangle()
            .fill(Color.black)
            .frame(height: 28)
            .overlay(alignment: .leading) {
                Text("  Finder  文件  编辑")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.8))
            }
        PanelView(viewModel: PanelViewModel())
    }
    .background(
        LinearGradient(colors: [Color(hex: 0x18181E), Color(hex: 0x0A0A0E)],
                       startPoint: .top, endPoint: .bottom)
    )
    .preferredColorScheme(.dark)
}

/// Color(hex:) 便捷构造（仅预览用）
private extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
