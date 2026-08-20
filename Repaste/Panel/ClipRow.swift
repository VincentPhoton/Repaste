//
//  ClipRow.swift
//  Repaste
//
//  列表单行卡片：文本 / 图片 / 链接三类形态（整行可点 = 使用；无彩色竖线）
//

import SwiftUI

// MARK: - 相对时间

/// 相对时间格式化：刚刚 / N 分钟前 / N 小时前 / 昨天 / N 天前（>7 天显示日期）
enum RelativeTime {
    /// 跨年日期格式化器（缓存复用）
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/M/d"
        return formatter
    }()

    /// 相对时间文本
    static func string(from date: Date, now: Date = Date()) -> String {
        let interval = now.timeIntervalSince(date)
        if interval < 60 { return "刚刚" }
        if interval < 3600 { return "\(Int(interval / 60)) 分钟前" }
        if interval < 86400 { return "\(Int(interval / 3600)) 小时前" }
        let calendar = Calendar.current
        if calendar.isDateInYesterday(date) { return "昨天" }
        if interval < 7 * 86400 { return "\(Int(interval / 86400)) 天前" }
        // >7 天显示日期（同年省略年份）
        if calendar.isDate(date, equalTo: now, toGranularity: .year) {
            return "\(calendar.component(.month, from: date))月\(calendar.component(.day, from: date))日"
        }
        return dateFormatter.string(from: date)
    }
}

// MARK: - 单行卡片

/// 单行卡片（三类形态：文本 / 图片 / 链接；整行点击 = 使用）
struct ClipRow: View {
    let clip: Clip
    /// 是否键盘选中（surface3 高亮）
    let isSelected: Bool
    /// 使用条目（点击整行）
    let onUse: () -> Void
    /// 点击行内来源标签（key = bundleId 或 "unknown"，等同来源条筛选）
    let onSourceTap: (String) -> Void
    /// 打开链接（链接卡「跳转」按钮普通点击 / 文本卡「打开链接」次级按钮；默认浏览器打开）
    let onOpenLink: () -> Void
    /// 按住 ⌥ 点「跳转」：弹出浏览器选择浮层（参数 = 跳转按钮在面板坐标系中的锚点 frame）
    let onChooseBrowser: (CGRect) -> Void
    /// ⋮ 菜单（参数 = ⋮ 按钮在面板坐标系中的锚点 frame，供菜单弹出定位）
    let onMore: (CGRect) -> Void

    /// 行 hover 状态
    @State private var isHovering = false
    /// 行内来源标签 hover 状态
    @State private var isSourceHovering = false
    /// 「打开链接」次级按钮 hover 状态
    @State private var isLinkHovering = false
    /// 来源图标（onAppear 加载一次，避免重复读盘）
    @State private var sourceIcon: NSImage?
    /// 图片缩略图（onAppear 加载一次）
    @State private var thumbnail: NSImage?
    /// ⋮ 按钮在面板坐标系中的锚点 frame（滚动时随布局更新）
    @State private var moreButtonFrame: CGRect = .zero
    /// 跳转按钮在面板坐标系中的锚点 frame（⌥ 点击弹浏览器选择浮层定位用）
    @State private var jumpButtonFrame: CGRect = .zero

    /// 千分位格式化器（>1000 字时使用）
    private static let decimalFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter
    }()

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // 置顶标记
            if clip.pinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(DT.unknown)
                    .padding(.top, 4)
            }

            // 左侧类型标签（kindLabel 文字 + kindColor 色）
            Text(clip.kindEnum.kindLabel)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(clip.kindEnum.kindColor)
                .frame(width: 30, alignment: .leading)
                .padding(.top, 2)

            // 左侧缩略图（仅图片卡，40×40 圆角 8）
            if clip.kindEnum == .image {
                thumbnailView
                    .padding(.top, 1)
            }

            // 内容区（三类形态）
            contentView
                .frame(maxWidth: .infinity, alignment: .leading)

            // 右侧操作区（链接卡的「跳转」主按钮 + ⋮ 按钮）
            HStack(spacing: 8) {
                if clip.kindEnum == .link {
                    jumpButton
                }
                moreButton
            }
            .padding(.top, 2)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: DT.innerCardRadius, style: .continuous)
                .fill(rowBackground)
        )
        .contentShape(RoundedRectangle(cornerRadius: DT.innerCardRadius, style: .continuous))
        .onTapGesture(perform: onUse)
        .onHover { isHovering = $0 }
        .onAppear(perform: loadImages)
    }

    // MARK: 行背景

    /// 选中 = surface3；hover = surface2；否则透明（无彩色竖线）
    private var rowBackground: Color {
        if isSelected { return DT.surface3 }
        if isHovering { return DT.surface2 }
        return .clear
    }

    // MARK: 内容区（三类形态）

    @ViewBuilder
    private var contentView: some View {
        switch clip.kindEnum {
        case .image:
            // 图片卡：preview（文件名）fgStrong + 元信息（来源 + 时间 + 「1280×800 · PNG」）
            VStack(alignment: .leading, spacing: 5) {
                Text(clip.preview)
                    .font(.system(size: 13))
                    .foregroundStyle(DT.fgStrong)
                    .lineLimit(1)
                metaRow(extras: imageDimensionText.map { [$0] } ?? [])
            }
        case .link:
            // 链接卡：域名加粗 fgStrong（防钓鱼设计）+ 路径 muted 小字 + 来源 + 时间
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Image(systemName: "link")
                        .font(.system(size: 11))
                        .foregroundStyle(DT.link)
                    Text(hostText)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(DT.fgStrong)
                        .lineLimit(1)
                }
                HStack(spacing: 7) {
                    Text(pathText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    dot
                    sourceLabel
                    dot
                    Text(RelativeTime.string(from: clip.createdAt))
                }
                .font(.system(size: 12))
                .foregroundStyle(DT.muted)
            }
        case .text, .file:
            // 文本卡：preview 两行截断 fg 色 + 元信息（来源 + 时间 + 字数 + 富文本标记 + 可选「打开链接」）
            VStack(alignment: .leading, spacing: 5) {
                Text(clip.preview)
                    .font(.system(size: 13))
                    .foregroundStyle(DT.fg)
                    .lineLimit(2)
                metaRow(extras: textExtras, showsOpenLink: textContainsLink)
            }
        }
    }

    // MARK: 元信息行（统一 muted 12pt）

    /// 元信息行：来源（可点，等同来源条筛选）+ 相对时间 + 附加段（字数 / 富文本 / 图片尺寸）
    /// + 可选「打开链接」次级按钮（文本卡 payloadText 检出首个 http(s) URL 时）
    private func metaRow(extras: [String], showsOpenLink: Bool = false) -> some View {
        HStack(spacing: 7) {
            sourceLabel
            dot
            Text(RelativeTime.string(from: clip.createdAt))
            ForEach(extras, id: \.self) { text in
                dot
                Text(text)
            }
            if showsOpenLink {
                dot
                openLinkButton
            }
        }
        .font(.system(size: 12))
        .foregroundStyle(DT.muted)
    }

    /// 文本卡是否含可打开的 http(s) 链接（正则检出首个 URL 即出「打开链接」按钮）
    private var textContainsLink: Bool {
        guard clip.kindEnum == .text, let text = clip.payloadText else { return false }
        return PanelViewModel.firstURL(in: text) != nil
    }

    /// 「打开链接」次级小按钮（muted 色，hover 提亮 accent；调 onOpenLink 走默认浏览器）
    private var openLinkButton: some View {
        Button(action: onOpenLink) {
            HStack(spacing: 3) {
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 9, weight: .semibold))
                Text("打开链接")
            }
            .font(.system(size: 12))
            .foregroundStyle(isLinkHovering ? DT.accentBright : DT.muted)
        }
        .buttonStyle(.plain)
        .onHover { isLinkHovering = $0 }
    }

    /// 行内来源标签（可点切筛选；未知来源用中性问号图标）
    private var sourceLabel: some View {
        HStack(spacing: 5) {
            if let sourceIcon {
                Image(nsImage: sourceIcon)
                    .resizable()
                    .frame(width: 12, height: 12)
            } else {
                Image(systemName: "questionmark.circle")
                    .font(.system(size: 10))
                    .foregroundStyle(DT.muted2)
            }
            Text(clip.sourceAppName ?? "未知来源")
        }
        .foregroundStyle(isSourceHovering ? DT.fg : DT.muted)
        .contentShape(Rectangle())
        .onTapGesture { onSourceTap(sourceKey) }
        .onHover { isSourceHovering = $0 }
    }

    /// 来源筛选 key（bundleId 或 "unknown"）
    private var sourceKey: String {
        clip.sourceBundleId ?? PanelViewModel.unknownSourceKey
    }

    /// 元信息分隔小圆点
    private var dot: some View {
        Circle()
            .fill(DT.muted2.opacity(0.55))
            .frame(width: 3, height: 3)
    }

    // MARK: 图片缩略图

    /// 40×40 缩略图（优先缩略图，缺失回退原图；再缺失显示占位块）
    private var thumbnailView: some View {
        Group {
            if let thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle().fill(DT.surface3)
            }
        }
        .frame(width: 40, height: 40)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    // MARK: 链接卡专属

    /// 链接 URL（payloadText 存完整 URL 原文）
    private var linkURL: URL? {
        URL(string: clip.payloadText ?? clip.preview)
    }

    /// 域名（加粗展示，防钓鱼设计）
    private var hostText: String {
        linkURL?.host ?? (clip.payloadText ?? clip.preview)
    }

    /// 路径 + query（弱化小字；根路径显示 "/"）
    private var pathText: String {
        guard let url = linkURL else { return "" }
        var path = url.path.isEmpty ? "/" : url.path
        if let query = url.query, !query.isEmpty {
            path += "?\(query)"
        }
        return path
    }

    /// 「跳转 ↗」主按钮（accentBtn 底白字小胶囊）：
    /// 普通点击 = 默认浏览器打开链接；按住 ⌥ 点击 = 弹浏览器选择浮层
    /// （onTapGesture 捕获点击时刻的 NSEvent.modifierFlags，系统 Button 不暴露修饰键）
    private var jumpButton: some View {
        HStack(spacing: 4) {
            Text("跳转")
            Image(systemName: "arrow.up.right")
                .font(.system(size: 9, weight: .semibold))
        }
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(Capsule().fill(DT.accentBtn))
        .contentShape(Capsule())
        .onTapGesture {
            if NSEvent.modifierFlags.contains(.option) {
                onChooseBrowser(jumpButtonFrame)
            } else {
                onOpenLink()
            }
        }
        // 持续跟踪按钮在面板坐标系中的 frame（列表滚动时同步更新，供浏览器浮层弹出定位）
        .onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .named(PanelView.coordinateSpaceName))
        } action: { frame in
            jumpButtonFrame = frame
        }
    }

    // MARK: 右侧操作按钮

    /// ⋮ 按钮（28×28、button 底；点击弹出更多菜单，携带按钮锚点 frame）
    private var moreButton: some View {
        Button {
            onMore(moreButtonFrame)
        } label: {
            VStack(spacing: 3.5) {
                Circle().fill(DT.muted).frame(width: 4.5, height: 4.5)
                Circle().fill(DT.muted).frame(width: 4.5, height: 4.5)
                Circle().fill(DT.muted).frame(width: 4.5, height: 4.5)
            }
            .frame(width: 28, height: 28)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(DT.button)
            )
        }
        .buttonStyle(.plain)
        // 持续跟踪按钮在面板坐标系中的 frame（列表滚动时同步更新，供菜单弹出定位）
        .onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .named(PanelView.coordinateSpaceName))
        } action: { frame in
            moreButtonFrame = frame
        }
    }

    // MARK: 元数据文本

    /// 文本卡附加段：字数（>1000 千分位）+ 富文本标记（format == "rtf"）
    private var textExtras: [String] {
        guard clip.kindEnum == .text else { return [] }
        var parts = ["\(formattedCharCount) 字"]
        if clip.format == "rtf" {
            parts.append("富文本")
        }
        return parts
    }

    /// 字数（payloadText 全文计；>1000 显示千分位）
    private var formattedCharCount: String {
        let count = clip.payloadText?.count ?? clip.preview.count
        guard count > 1000 else { return "\(count)" }
        return Self.decimalFormatter.string(from: NSNumber(value: count)) ?? "\(count)"
    }

    /// 图片尺寸与格式（如「1280×800 · PNG」；缺数据显示 nil）
    private var imageDimensionText: String? {
        guard clip.kindEnum == .image else { return nil }
        var parts: [String] = []
        if let width = clip.pixelWidth, let height = clip.pixelHeight, width > 0, height > 0 {
            parts.append("\(width)×\(height)")
        }
        if let format = clip.format, !format.isEmpty {
            parts.append(format)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    // MARK: 图片懒加载

    /// 加载来源图标与图片缩略图（每行一次）
    private func loadImages() {
        // 来源 App 图标
        if let iconPath = clip.sourceIconPath {
            sourceIcon = AppIconStore.shared.load(fileName: iconPath)
        }
        // 图片缩略图（缩略图名由原图名推导 "-thumb"，缺失回退原图）
        if clip.kindEnum == .image, let ref = clip.payloadRef {
            thumbnail = ImageStore.shared.load(name: ImageStore.thumbName(for: ref))
                ?? ImageStore.shared.load(name: ref)
        }
    }
}
