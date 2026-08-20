//
//  PasteboardReader.swift
//  Repaste
//
//  剪贴板内容读取：类型判定（优先级 fileURL > image > link > rtf > text）与纯函数提取
//

import AppKit
import Foundation
import UniformTypeIdentifiers

// MARK: - 剪贴板内容类型

/// 从 NSPasteboard 提取的类型化内容
enum PasteboardContent {
    /// 文本（isRich：带 RTF 富文本标记）
    case text(String, isRich: Bool)
    /// 图片（原始数据 + 格式 + 像素尺寸）
    case image(data: Data, format: String, pixelW: Int, pixelH: Int)
    /// 文件 URL（多文件只取第一个，MVP）
    case fileURL(URL)
    /// 链接（整串 http/https URL 原文）
    case link(String)
}

// MARK: - 剪贴板读取器

/// 剪贴板读取器：类型判定与内容提取（纯函数集合，URL 判定 / 预览截断 / 类型优先级可独立调用验证）
struct PasteboardReader {
    /// 密码管理器 concealed 标记（1Password / KeePassXC 等复制密码时声明）
    static let concealedType = NSPasteboard.PasteboardType(rawValue: "org.nspasteboard.ConcealedType")
    /// 瞬态内容标记（不应进入历史的临时内容）
    static let transientType = NSPasteboard.PasteboardType(rawValue: "org.nspasteboard.TransientType")

    /// 支持的图片类型（判定顺序即读取顺序）
    private static let imageTypes: [(type: NSPasteboard.PasteboardType, format: String)] = [
        (NSPasteboard.PasteboardType(UTType.png.identifier), "PNG"),
        (NSPasteboard.PasteboardType(UTType.tiff.identifier), "TIFF"),
        (NSPasteboard.PasteboardType(UTType.jpeg.identifier), "JPEG"),
        (NSPasteboard.PasteboardType(UTType.gif.identifier), "GIF"),
        (NSPasteboard.PasteboardType(UTType.heic.identifier), "HEIC"),
        (NSPasteboard.PasteboardType(UTType.bmp.identifier), "BMP"),
    ]

    /// 文本存储上限（超过只保留前 4KB）
    private static let maxTextBytes = 1_048_576
    /// 文本截断保留字节数
    private static let textTruncateBytes = 4096
    /// 文本预览长度（字符）
    private static let previewLength = 200

    /// 建议文件名时间格式（截屏 yyyy-MM-dd HH.mm）
    private static let fileNameFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH.mm"
        return formatter
    }()

    // MARK: 判定入口

    /// 类型判定与内容提取
    /// 优先级（严格遵守，不可互换）：fileURL > image > URL(整串 http/https) > rtf > string
    static func detect(from pasteboard: NSPasteboard) -> PasteboardContent? {
        let types = pasteboard.types ?? []

        // 1. 文件 URL：types 含 .fileURL 且读出有效 URL（Finder 复制文件 / 同时携带图片的文件均判 file）
        if types.contains(.fileURL), let url = firstFileURL(from: pasteboard) {
            return .fileURL(url)
        }

        // 2. 图片：types 含支持的图片类型且能读到数据
        if let image = imageContent(from: pasteboard, types: types) {
            return image
        }

        // 3. 链接：string 内容 trim 后整体是合法 http/https URL（不含 file: 等其他协议）
        if let string = pasteboard.string(forType: .string), let link = linkIfNeeded(string) {
            return .link(link)
        }

        // 4. 富文本：有 RTF 数据但不符合链接 → 按 text 处理并记录富文本标记
        if types.contains(.rtf),
           let rtfData = pasteboard.data(forType: .rtf), !rtfData.isEmpty,
           let text = rtfPlainText(rtfData) ?? pasteboard.string(forType: .string), !text.isEmpty {
            return .text(text, isRich: true)
        }

        // 5. 纯文本
        if let string = pasteboard.string(forType: .string), !string.isEmpty {
            return .text(string, isRich: false)
        }

        return nil
    }

    // MARK: 纯函数（可独立调用验证）

    /// 整串链接判定：trim 后整体是合法 http/https URL 才判链接，否则按文本处理
    /// - scheme 大小写不敏感；整串匹配（URL 解析发生编码/补全即降级为文本）；不含 file: 等其他协议
    static func linkIfNeeded(_ string: String) -> String? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.absoluteString == trimmed else { return nil }
        return trimmed
    }

    /// 文本预览：前 200 字，换行替换为空格
    static func previewText(from text: String) -> String {
        let flattened = text
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
        return String(flattened.prefix(Self.previewLength))
    }

    /// 存储文本：超过 1MB 只保留前 4KB（UTF-8 字节截断，断点处多字节字符退化为替换字符）
    static func truncatedForStorage(_ text: String) -> String {
        guard text.utf8.count > Self.maxTextBytes else { return text }
        return String(decoding: text.utf8.prefix(Self.textTruncateBytes), as: UTF8.self)
    }

    /// 图片建议文件名：截屏 yyyy-MM-dd HH.mm.<ext>（剪贴板图片无真实文件名）
    static func suggestedImageFileName(format: String, date: Date = Date()) -> String {
        "截屏 \(Self.fileNameFormatter.string(from: date)).\(Self.fileExtension(for: format))"
    }

    /// concealed / transient 标记检查：命中则完全跳过不入库
    static func isConcealedOrTransient(_ pasteboard: NSPasteboard) -> Bool {
        let types = pasteboard.types ?? []
        return types.contains(concealedType) || types.contains(transientType)
    }

    // MARK: 私有提取

    /// 第一个有效文件 URL（多文件只取第一个）
    private static func firstFileURL(from pasteboard: NSPasteboard) -> URL? {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL] ?? []
        return urls.first
    }

    /// 图片内容提取：按支持列表顺序取第一个命中类型的非空数据
    private static func imageContent(
        from pasteboard: NSPasteboard,
        types: [NSPasteboard.PasteboardType]
    ) -> PasteboardContent? {
        for (type, format) in imageTypes where types.contains(type) {
            guard let data = pasteboard.data(forType: type), !data.isEmpty else { continue }
            let (pixelW, pixelH) = pixelSize(of: data) ?? (0, 0)
            return .image(data: data, format: format, pixelW: pixelW, pixelH: pixelH)
        }
        return nil
    }

    /// 图片像素尺寸：优先位图 rep 的真实像素，回退 NSImage 尺寸
    private static func pixelSize(of data: Data) -> (Int, Int)? {
        if let rep = NSBitmapImageRep(data: data), rep.pixelsWide > 0, rep.pixelsHigh > 0 {
            return (rep.pixelsWide, rep.pixelsHigh)
        }
        if let image = NSImage(data: data) {
            for case let bitmap as NSBitmapImageRep in image.representations
            where bitmap.pixelsWide > 0 && bitmap.pixelsHigh > 0 {
                return (bitmap.pixelsWide, bitmap.pixelsHigh)
            }
            if image.size.width > 0, image.size.height > 0 {
                return (Int(image.size.width.rounded()), Int(image.size.height.rounded()))
            }
        }
        return nil
    }

    /// RTF 数据 → 纯文本（解析失败由调用方回退 plain string）
    private static func rtfPlainText(_ data: Data) -> String? {
        let attributed = try? NSAttributedString(
            data: data,
            options: [.documentType: NSAttributedString.DocumentType.rtf],
            documentAttributes: nil
        )
        return attributed?.string
    }

    /// 图片格式 → 文件后缀（与 ImageStore 原图命名约定对齐）
    private static func fileExtension(for format: String) -> String {
        switch format.uppercased() {
        case "PNG": return "png"
        case "JPEG", "JPG": return "jpg"
        case "GIF": return "gif"
        case "TIFF", "TIF": return "tif"
        case "HEIC": return "heic"
        case "BMP": return "bmp"
        default: return "png"
        }
    }
}
