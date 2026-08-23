//
//  TemplateGroup.swift
//  Repaste
//
//  模板组 SwiftData 模型：固定在模板区的分组
//

import Foundation
import SwiftData

// MARK: - 模板组模型

/// 模板组：用户收藏的固定分组（组内条目为 Clip，通过 Clip.groupId 关联）
@Model
final class TemplateGroup {
    /// 唯一标识（与组内 Clip.groupId 对应）
    @Attribute(.unique) var id: UUID

    /// 组名
    var name: String

    /// 排序序号（升序展示）
    var sortIndex: Int

    init(name: String, sortIndex: Int) {
        self.id = UUID()
        self.name = name
        self.sortIndex = sortIndex
    }
}
