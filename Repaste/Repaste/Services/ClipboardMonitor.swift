//
//  ClipboardMonitor.swift
//  Repaste
//
//  剪贴板录制引擎：0.5s 轮询 changeCount，类型化入库（去重 / 淘汰 / 图片 TTL）
//

import AppKit
import Foundation
import Observation

// MARK: - 剪贴板录制引擎

/// 剪贴板录制引擎（单例）：
/// - Timer 0.5s 轮询 NSPasteboard.general.changeCount，未变化直接返回（空闲开销≈0）
/// - 变化时立即捕获来源 App → 类型判定提取 → 入库（去重 / 淘汰 / 图片 TTL）
/// - concealed / transient（密码 / 瞬态）内容 100% 跳过；忽略 App、录制暂停跳过
@Observable
final class ClipboardMonitor: NSObject {
    /// 单例
    static let shared = ClipboardMonitor()

    /// 轮询间隔（秒）
    private static let pollInterval: TimeInterval = 0.5
    /// 图片 TTL 检查间隔（1 小时）
    private static let ttlCheckInterval: TimeInterval = 3600
    /// 来源归因容差（秒）：前台 App 在「变化窗口起点 + 容差」之后才激活则归因不可靠
    private static let sourceGraceWindow: TimeInterval = 0.3

    /// 引擎运行状态
    private(set) var isRunning = false

    /// 轮询定时器（加入 .common 模式：面板 / 菜单交互期间不停摆）
    private var pollTimer: Timer?
    /// TTL 清理定时器
    private var ttlTimer: Timer?
    /// 上次已处理的 changeCount
    private var lastChangeCount = 0
    /// 上次轮询时刻（changeCount 变化时刻的近似下界：变化必然发生在两次轮询之间）
    private var lastPollDate = Date()
    /// 最近一次前台 App 切换时刻（来源归因：变化窗口后期发生切换则归因不可靠）
    private var frontmostSwitchDate: Date?
    /// 最近约 5 秒（10 次轮询）的前台 App bundleId（来源归因「净切换」判断：
    /// 截图工具等后台 App 瞬态激活又退回时，前台 App 仍在近期历史中，可直接归因）
    private var lastFrontmostBundleIds: [String?] = []
    /// 应用自己写回剪贴板时记录的 changeCount（防自吞）
    private var externalWriteChangeCount: Int?

    /// 来源 App 信息
    private struct SourceApp {
        let bundleId: String?
        let name: String?
    }

    private override init() {
        super.init()
    }

    // MARK: 生命周期

    /// 启动引擎（幂等；App 启动时调用）。
    /// readClipboardOnLaunch == false（默认）只记录基准不导入，避免打开即导入敏感内容；
    /// true 则导入当前剪贴板（来源发生在启动前，无法归因，记未知）。
    func start() {
        guard !isRunning else { return }
        isRunning = true

        let settings = SettingsStore.shared

        // 记录基准：只追踪启动之后发生的变化
        lastChangeCount = NSPasteboard.general.changeCount
        lastPollDate = Date()

        // 启动导入当前剪贴板（默认关闭）
        if settings.readClipboardOnLaunch {
            importCurrent()
        }

        // 图片 TTL：启动清理一次 + 每小时复查
        purgeImageTTL()

        // 监听前台 App 切换（记录切换时刻，供来源归因可靠性判断；NSWorkspace 通知在主线程）
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(appDidActivate),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )

        startTimers()
    }

    /// 应用自己写回剪贴板（复制动作）后调用：记录写回完成时的 changeCount，
    /// 后续轮询跳过所有 ≤ 该值的变化（写回分多步，changeCount 会递增多次），
    /// 避免刚复制的条目再次入库置顶（防自吞；PasteboardWriter 调用）
    func markExternalWrite() {
        externalWriteChangeCount = NSPasteboard.general.changeCount
    }

    // MARK: 轮询

    /// 启动定时器（target-selector 方式，回调在主线程）
    private func startTimers() {
        let poll = Timer(
            timeInterval: Self.pollInterval,
            target: self,
            selector: #selector(pollTick),
            userInfo: nil,
            repeats: true
        )
        RunLoop.main.add(poll, forMode: .common)
        pollTimer = poll

        let ttl = Timer(
            timeInterval: Self.ttlCheckInterval,
            target: self,
            selector: #selector(ttlTick),
            userInfo: nil,
            repeats: true
        )
        RunLoop.main.add(ttl, forMode: .common)
        ttlTimer = ttl
    }

    /// 轮询触发（主线程）
    @objc private func pollTick() {
        poll()
    }

    /// TTL 检查触发（主线程）
    @objc private func ttlTick() {
        purgeImageTTL()
    }

    /// 前台 App 切换（主线程）：记录切换时刻
    @objc private func appDidActivate() {
        frontmostSwitchDate = Date()
    }

    /// 单次轮询：changeCount 未变直接返回；变化时进入处理链
    private func poll() {
        let pasteboard = NSPasteboard.general
        let now = Date()
        let since = lastPollDate
        lastPollDate = now
        // 每次轮询记录前台 App（供来源归因的「净切换」判断；无论是否有变化都记录）
        defer { recordFrontmost() }

        let count = pasteboard.changeCount
        // 空闲：changeCount 与上次相同，直接返回（开销≈0）
        guard count != lastChangeCount else { return }
        lastChangeCount = count

        // 防自吞：写回分多步（清空 + 逐类型 setData），changeCount 会递增多次，
        // 轮询可能先撞上中途值——跳过所有 ≤ 记录值的变化（到达记录值才消费标记）；
        // 超过记录值说明写回之后又有新复制，清标记继续处理新内容
        if let external = externalWriteChangeCount {
            if count <= external {
                if count == external { externalWriteChangeCount = nil }
                return
            }
            externalWriteChangeCount = nil
        }

        handleChange(pasteboard: pasteboard, since: since)
    }

    /// 记录当前前台 App bundleId（保留最近 10 次轮询 ≈ 5 秒；来源归因「净切换」判断用）
    private func recordFrontmost() {
        let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        lastFrontmostBundleIds.append(front)
        if lastFrontmostBundleIds.count > 10 {
            lastFrontmostBundleIds.removeFirst()
        }
    }

    // MARK: 变化处理链

    /// 处理一次剪贴板变化：跳过检查 → 来源捕获 → 类型判定 → 入库
    private func handleChange(pasteboard: NSPasteboard, since: Date) {
        // 1. 密码 / 瞬态内容：完全跳过不入库（无论录制开关状态）
        if PasteboardReader.isConcealedOrTransient(pasteboard) {
            EventLog.track(EventLog.clipSkipped, ["reason": "concealed"])
            return
        }

        // 2. 录制暂停
        guard SettingsStore.shared.recordingEnabled else {
            EventLog.track(EventLog.clipSkipped, ["reason": "paused"])
            return
        }

        // 3. 来源捕获 + 忽略 App
        let source = captureSource(since: since)
        if let bundleId = source?.bundleId,
           SettingsStore.shared.ignoredBundleIds.contains(bundleId) {
            EventLog.track(EventLog.clipSkipped, ["reason": "ignored_app", "source": bundleId])
            return
        }

        // 4. 类型判定与提取（优先级：fileURL > image > link > rtf > text）
        guard let content = PasteboardReader.detect(from: pasteboard) else { return }

        // 5. 入库
        ingest(content: content, source: source)
    }

    /// 捕获来源 App：变化必然发生在 (since, now]。
    /// 归因规则：
    /// - 前台 App 在最近约 5 秒的轮询历史中出现过（无净切换；截图工具等后台 App 瞬态激活又退回原 App）→ 直接归因前台；
    /// - 前台是「新出现的 App」（近期未在历史中，如复制后立刻切走）且切换时刻在容差后 → 记未知（nil）；
    /// - 其余情况归因当前前台。
    private func captureSource(since: Date) -> SourceApp? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.bundleIdentifier != nil || app.localizedName != nil else { return nil }
        // 前台在近期历史中出现过：未发生净切换（瞬态激活已退回），归因可靠
        if let front = app.bundleIdentifier, lastFrontmostBundleIds.contains(front) {
            return SourceApp(bundleId: app.bundleIdentifier, name: app.localizedName)
        }
        // 前台是新出现的 App（近期未在历史中）：按切换时刻容差判定是否可靠
        if let switchDate = frontmostSwitchDate,
           switchDate > since.addingTimeInterval(Self.sourceGraceWindow) {
            return nil
        }
        return SourceApp(bundleId: app.bundleIdentifier, name: app.localizedName)
    }

    /// 启动导入当前剪贴板：来源发生在启动前无法归因，记未知
    private func importCurrent() {
        let pasteboard = NSPasteboard.general
        guard !PasteboardReader.isConcealedOrTransient(pasteboard),
              SettingsStore.shared.recordingEnabled,
              let content = PasteboardReader.detect(from: pasteboard) else { return }
        ingest(content: content, source: nil)
    }

    // MARK: 入库

    /// 构建 Clip 并入库（含去重与淘汰）
    private func ingest(content: PasteboardContent, source: SourceApp?) {
        // 来源图标缓存（需要 bundleId 定位 App）
        var iconPath: String? = nil
        if let bundleId = source?.bundleId {
            iconPath = AppIconStore.shared.icon(for: bundleId, appName: source?.name ?? bundleId)
        }

        let clip: Clip
        switch content {
        case let .text(text, isRich):
            // 全文超 1MB 只存前 4KB；preview 取前 200 字；byteSize 记全文 UTF-8 字节数
            clip = Clip(
                kind: .text,
                preview: PasteboardReader.previewText(from: text),
                payloadText: PasteboardReader.truncatedForStorage(text),
                sourceBundleId: source?.bundleId,
                sourceAppName: source?.name,
                sourceIconPath: iconPath,
                byteSize: text.utf8.count,
                format: isRich ? "rtf" : nil
            )
        case let .link(url):
            // payloadText 与 preview 均为完整 URL 原文
            clip = Clip(
                kind: .link,
                preview: url,
                payloadText: url,
                sourceBundleId: source?.bundleId,
                sourceAppName: source?.name,
                sourceIconPath: iconPath,
                byteSize: url.utf8.count
            )
        case let .image(data, format, pixelW, pixelH):
            // 图片内容级去重（须在落盘前）：图片写入剪贴板分多步（清空 + tiff/png 逐类型写入），
            // changeCount 递增多次会跨轮询触发重复捕获；且图片每次落盘都是新 UUID 文件名，
            // 按 payloadRef 比对永远不相等——必须与最新图片条目按数据本身比对
            if let duplicate = duplicateImageLatest(
                data: data, format: format, pixelW: pixelW, pixelH: pixelH
            ) {
                ClipboardStore.shared.touch(clip: duplicate)
                EventLog.track(EventLog.clipCaptured, ["kind": duplicate.kind, "dedup": "true"])
                NotificationCenter.default.post(name: .clipboardHistoryDidUpdate, object: nil)
                return
            }
            // 落盘（原图 + 40×40 缩略图），payloadRef 记原图文件名
            let (originalName, _) = ImageStore.shared.save(data: data, format: format)
            clip = Clip(
                kind: .image,
                preview: PasteboardReader.suggestedImageFileName(format: format),
                payloadRef: originalName,
                sourceBundleId: source?.bundleId,
                sourceAppName: source?.name,
                sourceIconPath: iconPath,
                byteSize: data.count,
                pixelWidth: pixelW,
                pixelHeight: pixelH,
                format: format
            )
        case let .fileURL(url):
            // 多文件只取第一个（MVP）：payloadText 记绝对路径，preview 记文件名
            let path = url.path
            clip = Clip(
                kind: .file,
                preview: url.lastPathComponent,
                payloadText: path,
                sourceBundleId: source?.bundleId,
                sourceAppName: source?.name,
                sourceIconPath: iconPath,
                byteSize: path.utf8.count
            )
        }

        // 去重（文本/链接/文件；图片已在上方按内容提前去重）：
        // 与最近一条历史条目完全相同（kind + payloadText/payloadRef）→ 不重复入库，
        // 刷新其 createdAt 到当前时刻（置顶效果；置顶条目同样刷新位置）
        if let latest = ClipboardStore.shared.latestClip(),
           latest.kind == clip.kind,
           latest.payloadText == clip.payloadText,
           latest.payloadRef == clip.payloadRef {
            ClipboardStore.shared.touch(clip: latest)
            EventLog.track(EventLog.clipCaptured, ["kind": clip.kind, "dedup": "true"])
            NotificationCenter.default.post(name: .clipboardHistoryDidUpdate, object: nil)
            return
        }

        ClipboardStore.shared.insert(clip: clip)
        // 淘汰溢出（pinned / 模板不参与，ClipboardStore 已实现）
        ClipboardStore.shared.purgeOverflow(maxItems: SettingsStore.shared.maxItems)

        EventLog.track(EventLog.clipCaptured, [
            "kind": clip.kind,
            "source": source?.bundleId ?? "unknown",
            "bytes": String(clip.byteSize),
        ])
        // 广播历史变化（面板可见时实时刷新列表；轮询在主线程，通知同步送达）
        NotificationCenter.default.post(name: .clipboardHistoryDidUpdate, object: nil)
    }

    /// 图片内容级去重：最新历史条目为图片且数据逐字节一致时返回该条目
    /// （先比对 byteSize / 像素尺寸 / 格式短路，避免无谓读盘；原图已被 TTL 清理时读不到数据，按不同处理、重新落盘）
    private func duplicateImageLatest(data: Data, format: String, pixelW: Int, pixelH: Int) -> Clip? {
        guard let latest = ClipboardStore.shared.latestClip(),
              latest.kindEnum == .image,
              latest.byteSize == data.count,
              latest.pixelWidth == pixelW,
              latest.pixelHeight == pixelH,
              latest.format == format,
              let ref = latest.payloadRef,
              let latestData = try? Data(contentsOf: ImageStore.shared.fileURL(name: ref)),
              latestData == data else { return nil }
        return latest
    }

    // MARK: 图片 TTL

    /// 图片 TTL 清理（按当前设置）
    private func purgeImageTTL() {
        ImageStore.shared.purgeExpired(ttlDays: SettingsStore.shared.imageTtlDays)
    }
}

// MARK: - 历史变化广播

extension Notification.Name {
    /// 剪贴板历史有新条目入库或置顶刷新（面板可见时实时刷新列表用）
    static let clipboardHistoryDidUpdate = Notification.Name("Repaste.clipboardHistoryDidUpdate")
}
