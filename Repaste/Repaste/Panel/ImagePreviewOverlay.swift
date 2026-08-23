//
//  ImagePreviewOverlay.swift
//  Repaste
//
//  图片放大查看：半透明黑遮罩 + 居中大图（圆角 12）+ 下方操作条（复制图片 / 关闭）
//  原图已被 TTL 清理时降级显示缩略图 + 顶部「原图已清理」提示 + 不提供复制图片
//

import SwiftUI

// MARK: - 图片放大查看浮层

/// 图片放大查看浮层（挂在 PanelView 之上的 overlay，zIndex 高于列表）
struct ImagePreviewOverlay: View {
    /// 目标图片条目
    let clip: Clip
    /// 图片最大高度（屏幕 70% 与面板可用空间取小，由外部计算）
    let maxImageHeight: CGFloat
    /// 关闭（esc / 点遮罩 / 关闭按钮）
    let onClose: () -> Void
    /// 复制图片（原图写回剪贴板）
    let onCopyImage: () -> Void

    /// 展示的图片（原图，或降级时的缩略图）
    @State private var image: NSImage?
    /// 原图是否仍在盘上（false = 已被 TTL 清理，降级显示缩略图）
    @State private var originalAvailable = true

    var body: some View {
        ZStack {
            // 半透明黑遮罩 rgba(0,0,0,.55)：点击关闭。
            // 关闭层用 Button(.plain) 而非 onTapGesture：裸手势在 NSHostingView 上与
            // 浮层移除 transition 存在竞态（mouseUp 与视图移除竞争），偶发手势图卡死
            // 后吞掉面板内所有后续点击；Button 走 AppKit 完整点击语义更稳
            Color.black.opacity(0.55)
            Button(action: onClose) {
                Color.clear.contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            VStack(spacing: 14) {
                // 降级提示条（原图已被 TTL 清理：显示缩略图、不提供复制图片）
                if !originalAvailable {
                    degradeBanner
                }
                imageView
                actionBar
            }
            .padding(20)
        }
        .onAppear(perform: loadImage)
    }

    // MARK: 图片区

    /// 居中大图（圆角 12、比例适配最大高度；降级时为缩略图，放大后会糊可接受）
    private var imageView: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                // 图片数据缺失占位
                VStack(spacing: 8) {
                    Image(systemName: "photo")
                        .font(.system(size: 28))
                        .foregroundStyle(DT.muted2)
                    Text("图片不可用")
                        .font(.system(size: 12))
                        .foregroundStyle(DT.muted)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: maxImageHeight)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(DT.surface2)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(DT.stroke, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.5), radius: 16, y: 8)
    }

    // MARK: 降级提示条

    /// 「原图已清理」提示条（warn 柔和底 + 暖黄文字）
    private var degradeBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 11))
            Text("原图已清理，当前显示缩略图")
                .font(.system(size: 11.5))
        }
        .foregroundStyle(DT.warnText)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(DT.warn.opacity(0.14))
        )
    }

    // MARK: 操作条

    /// 下方操作条：复制图片（accentBtn 白字胶囊，仅原图在盘时提供）+ 关闭（button 底）
    private var actionBar: some View {
        HStack(spacing: 12) {
            if originalAvailable {
                Button(action: onCopyImage) {
                    Text("复制图片")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(DT.accentBtn))
                }
                .buttonStyle(.mattePress)
            }
            Button(action: onClose) {
                Text("关闭")
                    .font(.system(size: 13))
                    .foregroundStyle(DT.fg)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(DT.button))
            }
            .buttonStyle(.mattePress)
        }
    }

    // MARK: 加载

    /// 加载图片：优先原图；原图已被 TTL 清理则降级加载缩略图
    private func loadImage() {
        guard let ref = clip.payloadRef else {
            originalAvailable = false
            return
        }
        if ImageStore.shared.hasOriginal(name: ref) {
            image = ImageStore.shared.load(name: ref)
            originalAvailable = true
        } else {
            image = ImageStore.shared.load(name: ImageStore.thumbName(for: ref))
            originalAvailable = false
        }
    }
}
