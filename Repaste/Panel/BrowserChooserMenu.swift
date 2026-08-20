//
//  BrowserChooserMenu.swift
//  Repaste
//
//  浏览器选择浮层：⌥ 点「跳转」弹出的面板内自绘浮层（menuSurface 底、14 圆角），
//  只列出已安装的浏览器；点选后用该浏览器打开链接（不用系统 menu）
//

import SwiftUI

// MARK: - 浏览器选项

/// 浏览器选项（bundleId nil = 跟随系统默认浏览器）
struct BrowserOption: Identifiable {
    /// 显示名
    let name: String
    /// 浏览器 bundleId（nil = 跟随系统）
    let bundleId: String?

    var id: String { bundleId ?? "system" }
}

// MARK: - 浏览器选择浮层

/// 浏览器选择浮层：跟随系统 + 已安装的常见浏览器（Safari / Chrome / Arc / Edge / Firefox / Brave）
struct BrowserChooserMenu: View {
    /// 目标条目（标题展示待打开链接的域名）
    let clip: Clip
    /// 选中浏览器回调（bundleId nil = 跟随系统）
    let onSelect: (String?) -> Void

    /// 当前 hover 的选项 id（高亮对应项）
    @State private var hoveredId: String?

    /// 菜单宽度（与 ⋮ 菜单同规格 218）
    static let menuWidth: CGFloat = 218
    /// 单项行高（与 ⋮ 菜单一致）
    private static let itemHeight: CGFloat = 33
    /// 标题高度 + 容器上下 padding
    private static let chromeHeight: CGFloat = 44

    /// 常见浏览器候选（按显示顺序；仅列出已安装的）
    private static let knownBrowsers: [BrowserOption] = [
        BrowserOption(name: "Safari", bundleId: "com.apple.Safari"),
        BrowserOption(name: "Chrome", bundleId: "com.google.Chrome"),
        BrowserOption(name: "Arc", bundleId: "company.thebrowser.Browser"),
        BrowserOption(name: "Edge", bundleId: "com.microsoft.edgemac"),
        BrowserOption(name: "Firefox", bundleId: "org.mozilla.firefox"),
        BrowserOption(name: "Brave", bundleId: "com.brave.Browser"),
    ]

    /// 可选浏览器列表：跟随系统（恒显）+ 已安装的常见浏览器
    /// （用 NSWorkspace urlForApplication(withBundleIdentifier:) 检测已安装才显示）
    static func options() -> [BrowserOption] {
        var result = [BrowserOption(name: "跟随系统", bundleId: nil)]
        for browser in knownBrowsers
        where NSWorkspace.shared.urlForApplication(withBundleIdentifier: browser.bundleId ?? "") != nil {
            result.append(browser)
        }
        return result
    }

    /// 菜单高度估算（供弹出方向上下翻转判断）
    static func estimatedHeight(options: [BrowserOption]) -> CGFloat {
        Self.chromeHeight + CGFloat(options.count) * Self.itemHeight
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("\(hostText) · 选择浏览器")
                .font(.system(size: 10.5))
                .foregroundStyle(DT.muted2)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.horizontal, 11)
                .padding(.top, 7)
                .padding(.bottom, 5)

            ForEach(Self.options()) { option in
                item(option)
            }
        }
        .padding(6)
        .frame(width: Self.menuWidth, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(DT.menuSurface)
        )
        .shadow(color: .black.opacity(0.55), radius: 18, y: 10)
    }

    // MARK: 待打开链接的域名（防钓鱼：明确告知要打开哪个站点）

    private var hostText: String {
        PanelViewModel.openableURL(in: clip)?.host ?? "链接"
    }

    // MARK: 菜单项

    /// 单个浏览器项：App 图标（跟随系统用地球图标）+ 名称；hover 白 10% 高亮
    private func item(_ option: BrowserOption) -> some View {
        let isHovering = hoveredId == option.id
        return Button {
            onSelect(option.bundleId)
        } label: {
            HStack(spacing: 10) {
                browserIcon(option)
                    .frame(width: 16, height: 16)
                Text(option.name)
                    .font(.system(size: 12.5))
                    .foregroundStyle(DT.fg)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isHovering ? DT.stroke : Color.clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            // 仅 hover 高亮，无需动画（哑光即时反馈）
            hoveredId = hovering ? option.id : nil
        }
    }

    /// 浏览器图标：已安装浏览器取 App 真实图标；跟随系统用中性地球图标
    @ViewBuilder
    private func browserIcon(_ option: BrowserOption) -> some View {
        if let bundleId = option.bundleId,
           let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: appURL.path))
                .resizable()
        } else {
            Image(systemName: "globe")
                .font(.system(size: 13))
                .foregroundStyle(DT.muted)
        }
    }
}
