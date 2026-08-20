//
//  AutoPaster.swift
//  Repaste
//
//  「粘贴到正在使用的应用」：AX 辅助功能授权检测 + 向前台 App 发送 ⌘V 合成事件
//

import AppKit
import ApplicationServices
import Carbon.HIToolbox
import CoreGraphics
import Foundation

// MARK: - 自动粘贴器

/// 自动粘贴器：基于 AX 辅助功能权限，向当前前台 App 合成发送 ⌘V 键盘事件，
/// 实现「点条目 → 内容直接出现在目标 App」（内容需先写入剪贴板，再由目标 App 自行 ⌘V）
enum AutoPaster {
    /// 当前进程是否已获得辅助功能（AX）授权
    static func isAuthorized() -> Bool {
        AXIsProcessTrusted()
    }

    /// 请求辅助功能授权：弹出系统授权引导（打开系统设置 > 隐私与安全性 > 辅助功能）。
    /// 引导为异步呈现，不影响返回值；返回值为请求时刻的授权状态。
    @discardableResult
    static func requestAuthorization() -> Bool {
        // kAXTrustedCheckOptionPrompt 以 Unmanaged<CFString> 形式导入，需 takeUnretainedValue 取值
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// 是否存在有效粘贴目标：前台 App 存在且不是本 App
    /// （本 App 的面板为 nonactivating 面板，正常情况下前台始终是用户的目标 App；
    /// 前台为空或切到了本 App 自身时无粘贴目标）
    static func hasValidPasteTarget() -> Bool {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return false }
        if let ownBundleId = Bundle.main.bundleIdentifier,
           frontApp.bundleIdentifier == ownBundleId {
            return false
        }
        return true
    }

    /// 向前台 App 发送 ⌘V（keyDown + keyUp 成对）：内容需已先写入系统剪贴板
    /// - Returns: 是否成功（无权限 / 无前台 App / 前台是本 App / 事件创建失败 → false）
    @discardableResult
    static func pasteToFocusedApp() -> Bool {
        guard isAuthorized() else { return false }
        guard hasValidPasteTarget() else { return false }
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return false }

        // ⌘V 合成事件（kVK_ANSI_V = 9）：keyDown 与 keyUp 成对，均携带 command 修饰位
        guard
            let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true),
            let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false)
        else { return false }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand

        let pid = frontApp.processIdentifier
        keyDown.postToPid(pid)
        keyUp.postToPid(pid)
        return true
    }
}
