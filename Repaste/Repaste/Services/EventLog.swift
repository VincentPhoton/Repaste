//
//  EventLog.swift
//  Repaste
//
//  本地 JSONL 事件日志：纯本地文件，不联网
//

import Foundation

// MARK: - 事件日志

/// 本地 JSONL 事件日志：Application Support/Repaste/events.jsonl
/// 每行一个 JSON 对象：{"event": "...", "time": "ISO8601", ...自定义字段}
enum EventLog {
    /// 日志文件 URL（目录自动创建）
    private static let fileURL: URL = {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = support.appendingPathComponent("Repaste", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("events.jsonl")
    }()

    /// ISO8601 时间格式化器
    private static let formatter = ISO8601DateFormatter()

    /// 后台串行队列：磁盘追加写不在主线程执行，避免每次鼠标点击 / 剪贴板入库都同步阻塞主线程。
    /// 串行保证写入顺序；日志为最佳努力诊断数据，异步写入不改变任何应用行为。
    private static let queue = DispatchQueue(
        label: "com.xiaofengchen.Repaste.eventlog",
        qos: .utility
    )

    /// 追加一条事件（写失败静默忽略，绝不影响主流程）
    /// - Parameters:
    ///   - event: 事件名（使用下方预定义常量）
    ///   - fields: 附加字段（扁平 String 键值对）
    static func track(_ event: String, _ fields: [String: String] = [:]) {
        var payload: [String: String] = [
            "event": event,
            "time": formatter.string(from: Date()),
        ]
        for (key, value) in fields {
            payload[key] = value
        }

        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]) else { return }
        var line = data
        line.append(0x0A) // 行尾换行

        // 在主线程先取好文件 URL 与队列引用，再切后台队列执行磁盘写（行为与原先一致，仅不阻塞主线程）
        let url = fileURL
        let queue = Self.queue
        queue.async {
            // 追加写；文件不存在则创建
            if let handle = FileHandle(forWritingAtPath: url.path) {
                defer { try? handle.close() }
                do {
                    try handle.seekToEnd()
                    try handle.write(contentsOf: line)
                } catch {
                    // 静默忽略
                }
            } else {
                try? line.write(to: url)
            }
        }
    }
}

// MARK: - 预定义事件名

extension EventLog {
    /// 面板打开（字段 trigger: "notch" / "hotkey"）
    static let panelOpen = "panel_open"
    /// 条目被使用（字段 kind: text / image / file / link；paste_target: clipboard / app）
    static let itemUsed = "item_used"
    /// 链接被打开（字段 kind: menu（⌥ 浏览器浮层）/ inline（行内按钮）/ hotkey（⌘⏎））
    static let linkOpened = "link_opened"
    /// 模板组创建
    static let groupCreated = "group_created"
    /// 模板条目使用
    static let templateUsed = "template_used"
    /// 条目加入模板组
    static let itemToGroup = "item_to_group"
    /// 来源应用筛选使用
    static let appFilterUsed = "app_filter_used"
    /// 置顶状态切换
    static let pinToggled = "pin_toggled"
    /// 普通复制使用（面板内复制到剪贴板）
    static let plainCopyUsed = "plain_copy_used"
    /// 首次引导完成
    static let onboardingCompleted = "onboarding_completed"
    /// 首次引导跳过
    static let onboardingSkipped = "onboarding_skipped"
    /// 粘贴目标切换（clipboard / app）
    static let pasteTargetChanged = "paste_target_changed"
    /// 自动粘贴被拒绝（字段 kind + reason: unauthorized（未授权）/ no_target（无前台目标）/ send_failed）
    static let autoPasteDenied = "auto_paste_denied"
    /// 刘海悬停呼出被关闭
    static let hoverDisabled = "hover_disabled"
    /// 全局快捷键注册失败（字段 status：OSStatus 数值）
    static let hotkeyRegisterFailed = "hotkey_register_failed"
    /// 剪贴板条目入库（字段 kind / source / bytes；去重命中时 dedup）
    static let clipCaptured = "clip_captured"
    /// 剪贴板内容被跳过（字段 reason: concealed / paused / ignored_app）
    static let clipSkipped = "clip_skipped"
    /// 条目被删除（字段 kind；⌫ / 行内菜单）
    static let clipDeleted = "clip_deleted"
    /// 图片放大查看（字段 kind）
    static let imageViewed = "image_viewed"
    /// 面板点击穿透失联被看门狗自愈（字段 alpha：触发时面板透明度）
    static let panelClickThroughHealed = "panel_click_through_healed"
    /// 鼠标按下实际投递到面板窗口（诊断：与 item_used 构成投递->动作漏斗，字段 alpha、ovl 浮层标记）
    static let panelMouseDelivered = "panel_mouse_delivered"
    /// 启动就绪动效播放结束（字段 variant: notch（苏醒+把手）/ fallback（无刘海退化把手）；outcome: completed / interrupted）
    static let startupWakePlayed = "startup_wake_played"
    /// 浮层状态迁移（诊断：M菜单/T模板菜单/B浏览器选择/P预览/D弹窗/o toast/g拖拽，字段 from、to）
    static let panelOverlayChanged = "panel_overlay_changed"
    /// SwiftUI 手势层收到的点击（诊断：与 panel_mouse_delivered 构成三层漏斗，字段 ovl）
    static let panelSwiftUITap = "panel_swiftui_tap"
}
