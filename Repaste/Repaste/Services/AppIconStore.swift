//
//  AppIconStore.swift
//  Repaste
//
//  来源 App 图标缓存：32×32 PNG 落盘
//

import AppKit
import Foundation

// MARK: - App 图标缓存

/// 来源 App 图标缓存（单例）：Application Support/Repaste/icons/
final class AppIconStore {
    /// 单例
    static let shared = AppIconStore()

    /// 根目录（自动创建）
    private let root: URL

    /// 图标渲染尺寸（32×32）
    private static let iconSize: CGFloat = 32

    /// 内存缓存：解码后的 NSImage 按文件名缓存（NSCache 线程安全，主线程 load 与后台解码共用）。
    /// 避免同一来源 App 的多行/反复滚动时对同一图标文件反复解码。
    nonisolated(unsafe) private static let cache = NSCache<NSString, NSImage>()

    private init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        root = support.appendingPathComponent("Repaste/icons", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    // MARK: 公开接口

    /// 获取来源 App 图标缓存文件名
    /// - Parameters:
    ///   - bundleId: 来源 App bundleId
    ///   - appName: 来源 App 显示名（预留：bundleId 定位失败时的备用匹配入口）
    /// - Returns: 缓存文件名；命中缓存直接返回；定位或渲染失败返回 nil（UI 显示中性未知图标）
    @discardableResult
    func icon(for bundleId: String, appName: String) -> String? {
        // 命中缓存直接返回
        let fileName = Self.fileName(for: bundleId)
        let cachedURL = root.appendingPathComponent(fileName)
        if FileManager.default.fileExists(atPath: cachedURL.path) { return fileName }

        // 通过 bundleId 定位 App 路径
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else {
            return nil
        }

        // 用 App 路径取图标，渲染 32×32 PNG 写盘
        let icon = NSWorkspace.shared.icon(forFile: appURL.path)
        guard let data = Self.pngData(from: icon, size: Self.iconSize) else { return nil }
        do {
            try data.write(to: cachedURL)
            // 新文件写盘后清掉该 key 的缓存，避免后续 load 命中旧的解码结果
            Self.cache.removeObject(forKey: fileName as NSString)
            return fileName
        } catch {
            return nil // 写盘失败静默：UI 显示未知图标
        }
    }

    /// 磁盘解码图标并走内存缓存（线程安全；主线程 load 与后台解码均可调用）
    nonisolated static func decodeCached(fileName: String, url: URL) -> NSImage? {
        let key = fileName as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard let image = NSImage(contentsOf: url) else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }

    /// 图标文件完整 URL
    func fileURL(fileName: String) -> URL {
        root.appendingPathComponent(fileName)
    }

    /// 加载缓存图标（命中内存缓存避免重复解码）
    func load(fileName: String) -> NSImage? {
        Self.decodeCached(fileName: fileName, url: root.appendingPathComponent(fileName))
    }

    // MARK: 私有

    /// bundleId → 缓存文件名（替换路径非法字符）
    private static func fileName(for bundleId: String) -> String {
        let sanitized = bundleId
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
        return "\(sanitized).png"
    }

    /// NSImage 以固定正方形尺寸渲染为 PNG 数据
    private static func pngData(from icon: NSImage, size: CGFloat) -> Data? {
        let target = NSSize(width: size, height: size)
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size),
            pixelsHigh: Int(size),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }
        rep.size = target

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        guard let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        icon.draw(in: NSRect(origin: .zero, size: target))

        return rep.representation(using: .png, properties: [:])
    }
}
