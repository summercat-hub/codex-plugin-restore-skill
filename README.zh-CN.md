# Codex 插件恢复 Skill

[English](README.md)

`codex-plugin-restore-skill` 专门修复 Codex Desktop／CLI 中“已经安装过的插件突然不显示”的问题，包括插件商店、已安装列表、插件选择器或 `@` 提及列表缺失。它恢复的是有本地证据支持的完整原装插件集合，并非只处理 Chrome、Computer Use、Browser 等浏览器类插件。

它适用于 Codex 更新、服务商或配置档切换、ChatGPT／API Key 登录方式切换、Codex++ 改写配置、缓存重建、官方 marketplace 注册损坏或安装状态漂移之后出现的插件丢失问题。

## 主要功能

- 审计当前与历史配置、版本化插件缓存、CLI 状态，以及所有已配置的 marketplace。
- 根据可靠的本地证据，重建原本应该存在的已安装插件清单。
- 检测 manifest 缺失、官方 marketplace 路径失效或不完整、缓存别名和安装状态漂移。
- 修复全部检测到的已知官方 marketplace 故障，并且只恢复确有历史安装证据的插件。
- 修复后重新核对完整清单，分别报告已恢复、可见、未解决、仅历史记录及仅可安装的插件。

## 为什么不是只修浏览器插件

这个 Skill 以“完整插件库存”为修复对象，而不是针对某一个插件打补丁。在 Windows 上，损坏或残缺的 marketplace 可能让 Chrome 等浏览器插件成为最明显的症状，但同时消失的也可能包括 Documents、PDF、Spreadsheets、Presentations、Template Creator、GitHub 集成等其他官方插件。

因此，它会遍历所有 marketplace，重建完整的预期安装清单，再逐项验证，而不会修好第一个显眼的问题就停止。

它也不会把 marketplace 中所有“当前可安装”的插件一股脑装上，因为“可安装”并不等于“以前安装过”。

## 常见症状

- Codex Desktop 更新后，已安装插件消失。
- 插件商店、插件选择器或 `@` 列表为空或不完整。
- Chrome、Computer Use 或 Browser 仍可见，但其他官方插件不见了。
- marketplace 指向已经不存在或内容残缺的临时目录。
- 切换登录、服务商或配置档后，`config.toml` 中的插件或 marketplace 配置被移除。
- 本地仍保留插件缓存，但 CLI 不再将它们识别为已安装。

## 使用方法

将此 Skill 安装或复制到 Codex skills 目录后，可以直接让 Codex 审计并恢复缺失插件。也可以在 Skill 目录中直接运行附带脚本。

检查完整插件库存：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/Inspect-CodexPluginInventory.ps1 -Json
```

预览修复方案：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/Restore-CodexPluginInventory.ps1 -InspectOnly
```

修复 marketplace 并恢复缺失的插件状态：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/Restore-CodexPluginInventory.ps1 -Repair -RestoreMissingPluginStates
```

执行修复模式前，请先检查预览结果。

## 安全边界

- 不会把删除插件缓存、认证文件或 Codex 全局状态当作通用修复手段。
- 不会安装 marketplace 中所有可用插件。
- 不会自动用官方来源覆盖一个来源不同但健康的自定义 marketplace。
- 修改配置前保留备份和回滚证据。
- 会区分本地可修复故障与账号权限、订阅、灰度、区域或服务端控制的可见性问题。

## 仓库结构

- `SKILL.md` — Agent 工作流与强制安全规则。
- `agents/openai.yaml` — Skill 元数据。
- `references/diagnosis.md` — 证据优先级、故障矩阵与修复边界。
- `scripts/Inspect-CodexPluginInventory.ps1` — 只读的完整库存检查脚本。
- `scripts/Restore-CodexPluginInventory.ps1` — 修复预览与执行脚本。

## 适用平台

附带的自动化脚本面向 Windows PowerShell 以及 Codex Desktop／CLI。部分由账号或服务端控制的插件可见性问题无法在本地修复；遇到此类情况时，Skill 会明确分类，而不是强行修改本地状态。
