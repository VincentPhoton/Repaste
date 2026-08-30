# Repaste 项目状态记录

> 本文档记录本工作区（fork）的完整项目情况，便于随时回顾。最后更新：2026-08-30。

## 1. 项目简介

**Repaste（刘海剪贴板）**：macOS 原生剪贴板管理器（SwiftUI + AppKit，零第三方依赖，macOS 15+）。
把鼠标滑到 MacBook 刘海悬停即可呼出剪贴板历史面板（`⌥⇧V` 居中呼出），记录带来源 App、
类型标签，支持模板组、链接一键直开；纯本地存储、零系统权限。

本仓库为 **[klosexf/Repaste](https://github.com/klosexf/Repaste)** 的改进 fork（MIT 许可），
在原作基础上做了性能优化、交互修复与功能增强，并持续独立迭代。

## 2. 仓库与远端

| 远端 | 地址 | 用途 |
| --- | --- | --- |
| `origin` | https://github.com/VincentPhoton/Repaste.git | 本 fork（改进版） |
| `upstream` | https://github.com/klosexf/Repaste.git | 原作者仓库（同步基线） |

## 3. 分支结构

| 分支 | 说明 | 状态 |
| --- | --- | --- |
| `main` | 默认分支，改进版主干 | 领先 upstream 12 个提交 |
| `perf-opt` | 与 main 同步（开发历史分支，保留） | 与 main 一致 |
| `pr-upstream` | 提给作者 PR 的分支（基于 upstream/main + 6 提交） | PR 已创建 |

日常开发在 `main` 上进行；与作者同步：

```bash
git fetch upstream
git merge upstream/main   # 作者新改动合入（冲突一般很少）
git push origin main
```

## 4. 本分支的改动清单（main 领先 upstream 的 12 个提交）

### 性能（3）
- `a1bbfeb` 事件日志改后台串行队列写：消除每次点击/入库的主线程磁盘阻塞（Services/EventLog.swift）
- `d014562` 图片与来源图标线程安全内存缓存：滚动/重复打开预览不再反复解码（ImageStore / AppIconStore）
- `ef3c96a` 列表缩略图与预览大图后台解码：滚动图片行不掉帧（ClipRow / ImagePreviewOverlay）

### 修复（7）
- `9991a6d` 刘海热区 30Hz 光标轮询兜底：快滑/停住也能触发（HotZoneWatcher）
- `035d955` 热区加深（40→96，下沿约 886）+ 上沿含端点：快速滑入可靠触发（HotZoneWatcher）
- `e8797f1` 关闭面板阴影消除顶边白线（中间态，被下一提交取代）
- `9ef3f16` 恢复阴影 + 面板顶部上抬屏外（notchTopOverhang=24）：白线消除且保留底部/两侧层次感（PanelController）
- `410644f` 来源归因抗截图工具瞬态激活（capcap 等后台工具正确归因前台 App）；显示记录条数设置（1-5 行固定显示+滚动）；菜单高度与行高修正
- `fba8d9e` 来源归因增强开关（默认关，按需开启）+ 全局即时悬停提示（TooltipController）+ 面板「未知来源」引导；面板首帧圆角（layer 圆角遮罩）
- `5d50ede` 收尾：忽略会话产物、纳入开发脚本 scripts/run-dev.sh

### 文档（2）
- `85ffadc` 重写 README 为本分支内容（fork 声明 + 本分支改进章节）
- `188bb3b` 路线图改为「按需迭代，无预设规划」（有自身需求或用户反馈再开发）

## 5. Release

- 地址：https://github.com/VincentPhoton/Repaste/releases/tag/v0.1.1
- 资产：`Repaste-v0.1.1.zip`（含 Repaste.app，解压拖入「应用程序」即可）
- 说明：未做 Apple 签名（与原作者一致），首次打开需右键打开或 `xattr -cr`；
  打包因沙箱环境 hdiutil 失败改用 ZIP（不影响下载）。

## 6. 上游 PR

- 地址：https://github.com/klosexf/Repaste/pull/1
- 分支：`pr-upstream`（基于 upstream/main，6 个提交 = 3 性能 + 3 修复）
- 策略：只提无行为争议的性能优化与真实 Bug 修复；**未包含** fork 侧方向性内容
  （显示记录条数、来源归因增强、README 重写等），待作者回应后再视情况另提。
- 迭代方式：在 `pr-upstream` 分支修改 → push，PR 自动更新。

## 7. 本地开发工作流

- **改完代码自动重编译并重启**：`./scripts/run-dev.sh`（结束旧实例 → xcodebuild（禁签名）→ 去 quarantine → 启动本地构建），改完立刻能看到效果。
- **构建**：本机无 Apple 开发者证书，用 `CODE_SIGNING_ALLOWED=NO`；正式构建用
  `xcodebuild -configuration Release -derivedDataPath ./build CODE_SIGNING_ALLOWED=NO build`。
- **运行的是本地构建**：`build/Build/Products/Debug/Repaste.app`（未签名，启动前 `xattr -cr`）。
- ⚠️ 不要与 `/Applications` 里作者原版同跑：bundle id 相同（com.xiaofengchen.Repaste），
  会双份监听剪贴板、双份写日志。
- **事件日志**：`~/Library/Application Support/Repaste/events.jsonl`（诊断用）。

## 8. 已知事项与待办

- [ ] 代码签名 + 公证（需 Apple Developer 账号）——消除 Gatekeeper 提示
- [ ] DMG 打包（沙箱下 hdiutil 失败，可更高权限重试或本地手动执行）
- [ ] App 图标未入库（仓库 .gitignore 排除了 AppIcon png，构建产物图标可能缺失）
- [ ] 未做本地化（UI 字符串硬编码中文）
- [ ] 无测试 target
- [ ] 作者对 PR #1 的回应（合并 / 修改意见）

## 9. 决策记录

- **热区深度 96**：按本机（14" 刘海屏，safeAreaInsets.top=32）实测光标活动区间（898–982）校准；
  不同机型可复用，但具体深度可再评估。
- **阴影方案**：窗口阴影 + 面板顶部上抬屏外（顶边白线来自窗口阴影贴屏合成）。
- **菜单方案**：菜单打开时面板窗口透明扩展给菜单腾位（菜单盖在下方应用上，无黑块无暗框）；
  面板固定「显示记录条数」N 行时用首行实测高度 + 行间距 + 滚动内边距保证每行完整显示。
- **来源归因**：前台 App 在最近约 5 秒轮询历史中出现过即归因（抗瞬态激活）；
  「来源归因增强」为可选项（默认关），仅对截图工具抢焦点的场景按需开启。
- **工具提示**：全局 TooltipController（独立小面板，跟随光标，悬停约 0.12s 弹出），
  替代系统 .help 的长延迟。
