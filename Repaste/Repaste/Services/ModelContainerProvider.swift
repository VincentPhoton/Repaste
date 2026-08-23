//
//  ModelContainerProvider.swift
//  Repaste
//
//  全局共享 SwiftData 容器（Clip + TemplateGroup）
//

import Foundation
import SwiftData

// MARK: - 模型容器提供者

/// 静态共享 ModelContainer：数据库存于默认位置（~/Library/Application Support/）
/// 设置窗口与后续刘海面板共用同一容器，保证数据一致
enum ModelContainerProvider {
    /// 共享容器（首次访问时懒加载创建）
    static let shared: ModelContainer = {
        do {
            let schema = Schema([Clip.self, TemplateGroup.self])
            let configuration = ModelConfiguration(schema: schema)
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            // 容器创建失败意味着数据层完全不可用，无法降级运行
            fatalError("ModelContainer 创建失败: \(error)")
        }
    }()
}
