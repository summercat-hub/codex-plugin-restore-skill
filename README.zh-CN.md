# Codex 插件恢复 Skill

[English](README.md)

`codex-plugin-restore-skill` 用来处理 Codex Desktop／CLI 中“插件明明安装过，却突然不显示”的问题。无论插件是从商店、已安装列表、插件选择器，还是 `@` 提及列表中消失，它都会根据本地留下的安装记录找回完整清单。

修复范围包括但不局限于 Chrome、Computer Use、Browser 等浏览器类插件。只要能找到可靠的安装证据，Documents、PDF、Spreadsheets、Presentations、Template Creator、GitHub 集成等官方插件也会一并检查。

如果插件是在 Codex 更新、服务商或配置档切换、ChatGPT 账号与 API Key 登录方式切换、Codex++ 改写配置、缓存重建，或官方 marketplace 注册损坏后消失，可以用这个 Skill 排查。

## 主要功能

- 检查当前配置、历史备份、版本化插件缓存、CLI 状态和所有已注册的 marketplace。
- 根据本地证据，重建原本安装过的插件清单。
- 找出缺失的 manifest、失效或残缺的官方 marketplace 路径、缓存别名和安装状态偏差。
- 修复检测到的官方 marketplace 故障，只恢复有安装记录的插件。
- 修复后再检查一遍，并分别列出已恢复、当前可见、仍未解决、仅存在于历史记录，以及只是可以安装的插件。

## 为什么不是只修浏览器插件

在 Windows 上，Chrome 等浏览器插件往往最先暴露问题，但故障通常不只影响一个插件。某个 marketplace 一旦损坏或只剩下部分内容，Documents、PDF、Spreadsheets、Presentations、Template Creator、GitHub 集成等官方插件也可能同时消失。

这个 Skill 会检查所有 marketplace，先还原完整的预期安装清单，再逐项确认状态。修好第一个显眼的问题不算结束。

它不会把 marketplace 里所有可用插件全部装上。“现在可以安装”不能证明“以前安装过”。

## 常见症状

- Codex Desktop 更新后，原来安装的插件不见了。
- 插件商店、选择器或 `@` 列表变空，或者只显示一部分插件。
- Chrome、Computer Use 或 Browser 还在，其他官方插件却消失了。
- marketplace 指向一个已被删除或内容不完整的临时目录。
- 切换登录方式、服务商或配置档后，`config.toml` 里的插件或 marketplace 配置被清掉了。
- 插件缓存仍在本地，CLI 却不再把对应插件识别为已安装。

## 使用方法

把这个 Skill 放进 Codex 的 skills 目录后，可以直接让 Codex 检查并恢复缺失插件。也可以进入 Skill 目录，手动运行附带脚本。

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

先看预览结果，确认无误后再执行修复。

## 安全边界

- 不会用删除插件缓存、认证文件或 Codex 全局状态的方式碰运气。
- 不会安装 marketplace 中所有可用插件。
- 如果自定义 marketplace 来源不同但状态正常，不会擅自用官方来源覆盖。
- 修改配置前会保留备份，方便回滚和核对。
- 账号权限、订阅、灰度发布、区域限制或服务端控制的问题会单独标明，不会伪装成本地修复成功。

## 仓库结构

- `SKILL.md`：Agent 工作流和安全规则。
- `agents/openai.yaml`：Skill 元数据。
- `references/diagnosis.md`：证据优先级、故障判断和修复边界。
- `scripts/Inspect-CodexPluginInventory.ps1`：只读检查脚本。
- `scripts/Restore-CodexPluginInventory.ps1`：预览并执行修复。

## 适用平台

附带脚本面向 Windows PowerShell、Codex Desktop 和 Codex CLI。账号或服务端控制的可见性问题无法靠修改本地文件解决；遇到这种情况，Skill 会说明原因，不会强行改动本地状态。
