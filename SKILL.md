---
name: lingxi-memory-save
description: "【⚠️ 安全提示】本技能会读取本地 OpenClaw 会话文件，提取对话内容后通过 AI 提炼，并同步至飞书。请确保您已知晓并同意该数据流向。\n\n【核心功能】会话提炼与记忆保存：1) 文件监听触发 2) AI 自动分析 3) L2-L4 保存。L1原始会话由OpenClaw自动保存。\n\n【安全特性】\n- 脱敏处理：仅提取消息关键词，不发送完整对话\n- 最小权限：建议创建飞书专用应用，只给最小数据权限\n- 普通用户运行：不使用root，建议专用低权限用户"
author: 灵曦 (Linxi)
homepage: https://github.com/liuxiaolong1988/lingxi-Skills
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
- **L2-L4 自动提炼**：会话结束自动触发，无需逐次审批
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

### 2. 配置飞书凭证（安全建议）

**推荐：创建专用飞书应用，最小权限**

1. 创建专用飞书应用（仅用于记忆同步）
2. 只授权必要的权限：
   - 多维表格：读写权限
   - 云文档：读写权限  
   - 消息推送：发送权限
3. 定期（建议每90天）轮换 Token

**配置环境变量**：

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

### 3. 配置定时任务（安全建议）

**⚠️ 重要：使用普通用户，不要使用 root**

```bash
# 每5分钟检查会话提炼
# 建议创建专用用户（如 openclaw）运行，不要用 root

# 编辑当前用户的 crontab
crontab -e

# 添加以下行（假设 openclaw 是运行用户）：
*/5 * * * * openclaw /home/openclaw/.openclaw/workspace/scripts/session_extract.sh >> /home/openclaw/.openclaw/workspace/logs/session_extract.log 2>&1
```

**安全要点**：
- 使用非 root 用户运行
- 日志文件放在该用户的目录下
- 确保会话目录对该用户可读

---

## 🔒 脱敏处理说明

### 提取逻辑

脚本只提取以下信息：
- 用户消息的**关键词**
- AI 任务/项目/知识标记
- **不发送**完整对话内容

### 具体处理步骤

1. **过滤元信息**：去除 System、Conversation info、Sender 等元数据
2. **提取正文**：只保留用户实际发送的消息内容
3. **AI 提炼**：调用本地 AI 分析，只提取结构化信息（任务/项目/知识）
4. **结果存储**：只保存提炼结果，不保存原始对话

### 安全约束

- 原始会话文件保留在本地，不外发
- 只外发 AI 提炼后的结构化摘要
- 不发送手机号、邮箱等敏感信息

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
| `/tmp/extract_queue.txt` | 待处理队列（重启后自动清理） |

---

## 🔐 安全说明

### 1. 数据安全
- 原始会话保存在本地，不外发
- 只外发 AI 提炼后的结构化摘要
- 脱敏处理：去除元信息，只提取关键词

### 2. 凭证安全
- 建议创建飞书专用应用，只给最小数据权限
- 定期（建议每90天）轮换 Token
- 不要在代码中硬编码凭证，使用环境变量

### 3. 权限安全
- 使用普通用户运行，不要使用 root
- 确保只授予必要权限
- 定期检查运行日志

### 4. 临时文件
- 队列文件存 /tmp，重启后自动清理
- 日志文件定期轮换

---

## 📝 版本信息

- **作者**: 灵曦 (Linxi)
- **版本**: 1.0.2
- **更新**: 2026-03-19

---

## Related Skills

- `lingxi-memory-program`: Save project content to L3
- `lingxi-memory-knowledge`: Save experience to L4
- `lingxi-memory-todo`: Create tasks in L2
- `lingxi-memory-rules`: Manage L5 rules
