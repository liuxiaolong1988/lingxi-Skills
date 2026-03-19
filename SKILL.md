---
name: lingxi-memory-save
description: "【⚠️ 安全提示】本技能会读取本地 OpenClaw 会话文件，提取对话内容后通过 AI 提炼，并同步至飞书。请确保您已知晓并同意该数据流向。\n\n【核心功能】会话提炼与记忆保存：1) 文件监听触发 2) AI 自动分析 3) L2-L4 保存。L1原始会话由OpenClaw自动保存。"
author: 灵曦 (Linxi)
homepage: https://github.com/your-repo/lingxi-memory-save
required_envs:
  - FEISHU_USER_OPEN_ID  # 飞书用户ID，用于推送消息
  - L2_APP_TOKEN        # 飞书多维表格App Token（L2任务看板）
  - L2_TABLE_ID         # 飞书多维表格Table ID
  - L3_DOC_ID           # 飞书云文档Doc ID（L3项目记忆）
  - L4_DOC_ID           # 飞书云文档Doc ID（L4知识沉淀）
required_tools:
  - jq                  # JSON处理工具
  - inotify-tools       # 文件监听工具（inotifywait）
  - openclaw            # OpenClaw CLI
---

# ⚠️ 安全提示

> **重要**：本技能会读取本地 OpenClaw 会话文件，提取对话内容后通过 AI 提炼，并同步至飞书。请确保您已知晓并同意该数据流向。

---

# Lingxi Memory Save - 会话提炼与记忆保存

## 📋 功能概述

**核心功能**：文件监听触发 + AI 自动分析 + L2-L4 保存

- **L1 原始会话**：OpenClaw 自动保存在本地 `sessions/` 目录，append-only
- **L2-L4 自动提炼**：会话结束自动触发，无需审批
- **L5 规则审批**：识别到规则变更时，需用户审批后生效

---

## 🚀 快速开始

### 1. 环境准备

安装依赖工具：
```bash
# Ubuntu/Debian
sudo apt-get install -y jq inotify-tools

# 验证安装
which jq inotifywait
```

### 2. 配置环境变量

在 `.env` 或 shell 配置文件中设置：

```bash
# 飞书用户ID（必需）
export FEISHU_USER_OPEN_ID="ou_xxxxxxxx"

# L2 任务看板（必需）
export L2_APP_TOKEN="xxxxxxxxxxxx"
export L2_TABLE_ID="tblxxxxxxxxxxxx"

# L3 项目记忆（必需）
export L3_DOC_ID="xxxxxxxxxxxx"

# L4 知识沉淀（必需）
export L4_DOC_ID="xxxxxxxxxxxx"
```

### 3. 配置定时任务

```bash
# 每5分钟检查会话提炼
*/5 * * * * bash /root/.openclaw/workspace/scripts/session_extract.sh >> /root/.openclaw/workspace/logs/session_extract.log 2>&1
```

---

## 📦 环境变量说明

| 变量名 | 必填 | 说明 | 示例 |
|--------|------|------|------|
| FEISHU_USER_OPEN_ID | ✅ | 飞书用户ID，用于推送消息 | `ou_xxx` |
| L2_APP_TOKEN | ✅ | 飞书多维表格App Token | `J37xxx` |
| L2_TABLE_ID | ✅ | 飞书多维表格Table ID | `tblxxx` |
| L3_DOC_ID | ✅ | 飞书云文档Doc ID（项目记忆） | `Dxxx` |
| L4_DOC_ID | ✅ | 飞书云文档Doc ID（知识沉淀） | `Xxxx` |

---

## 🔧 技术实现

### 文件监听触发

**触发条件**：OpenClaw 生成 `.jsonl.reset` 文件

**技术方案**：
- 使用 `inotifywait` 监听会话目录
- 检测 `.jsonl.reset.*` 或 `.jsonl.deleted.*` 文件
- 触发自动提炼

### 处理流程

```
OpenClaw 会话结束
    ↓
生成 .jsonl.reset 文件
    ↓
inotifywait 监听检测
    ↓
正则匹配 .jsonl.reset.
    ↓
检查是否已提炼（避免重复）
    ↓
触发 AI 分析会话
    ↓
保存到队列
    ↓
HEARTBEAT 处理队列 → 飞书 API
    ↓
推送报告给用户
```

---

## 📂 相关文件

| 文件 | 说明 |
|------|------|
| `session_watch.sh` | 文件监听脚本 |
| `do_extract.sh` | AI 提炼脚本 |
| `process_extract_queue.sh` | 队列处理脚本 |
| `memory/.extracted_sessions` | 已提炼记录 |
| `/tmp/extract_queue.txt` | 待处理队列 |

---

## 🔐 安全说明

1. **数据流向**：本地会话 → AI提炼 → 飞书
2. **权限控制**：仅读取指定目录，临时文件存 /tmp
3. **脱敏处理**：查询结果自动隐藏敏感信息
4. **无自启动**：仅通过 cron 定时触发

---

## 📝 版本信息

- **作者**: 灵曦 (Linxi)
- **版本**: v4.0
- **更新**: 2026-03-19

---

## Related Skills

- `lingxi-memory-program`: Save project content to L3
- `lingxi-memory-knowledge`: Save experience to L4
- `lingxi-memory-todo`: Create tasks in L2
- `lingxi-memory-rules`: Manage L5 rules
