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

    /// 应用自己写回剪贴板（复制动作）后调用：记录当前 changeCount，
    /// 下一次轮询跳过该写入，避免刚复制的条目再次入库置顶（防自吞；PasteboardService 调用）
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

        let count = pasteboard.changeCount
        // 空闲：changeCount 与上次相同，直接返回（开销≈0）
        guard count != lastChangeCount else { return }
        lastChangeCount = count

        // 防自吞：changeCount 单调递增，相等即应用自己的写回；
        // 更大则说明写回之后又有新复制，标记过期、继续处理新内容
        if let external = externalWriteChangeCount {
            externalWriteChangeCount = nil
            if count == external { return }
        }

        handleChange(pasteboard: pasteboard, since: since)
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
    /// 无法获得前台 App、或前台在「变化窗口起点 + 300ms 容差」之后才切换
    /// （复制后立刻切走，归因不可靠）→ 记未知（nil）；
    /// 窗口早期切换（切换后立刻复制）仍归因当前前台。
    private func captureSource(since: Date) -> SourceApp? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.bundleIdentifier != nil || app.localizedName != nil else { return nil }
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

        // 去重：与最近一条历史条目完全相同（kind + payloadText/payloadRef）→ 不重复入库，
        // 刷新其 createdAt 到当前时刻（置顶效果；置顶条目同样刷新位置）
        if let latest = ClipboardStore.shared.latestClip(),
           latest.kind == clip.kind,
           latest.payloadText == clip.payloadText,
           latest.payloadRef == clip.payloadRef {
            ClipboardStore.shared.touch(clip: latest)
            EventLog.track(EventLog.clipCaptured, ["kind": clip.kind, "dedup": "true"])
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
    }

    // MARK: 图片 TTL

    /// 图片 TTL 清理（按当前设置）
    private func purgeImageTTL() {
        ImageStore.shared.purgeExpired(ttlDays: SettingsStore.shared.imageTtlDays)
    }
}
