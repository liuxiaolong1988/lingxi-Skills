---
name: openclaw-lingxi-memory
description: |
  OpenClaw Skill - 灵曦记忆系统 / Lingxi Memory
  
  基于 OpenClaw + 飞书的 AI 记忆解决方案，会话级自动提炼与跨会话记忆同步。
  
  适用场景：
  - OpenClaw Agent 需要跨会话记住用户偏好和项目进展
  - AI 助手需要自动从对话中提取任务、项目和知识
  - 会话结束后自动保存到飞书知识库
  
  依赖工具（需安装）：
  - inotify-tools（文件监听）
  - jq（JSON 处理）
  - openclaw CLI（已内置）
  
  环境变量（必须配置）：
  - FEISHU_APP_TOKEN - 飞书应用 Token
  - FEISHU_USER_OPEN_ID - 飞书用户 open_id
  - L2_APP_TOKEN - 飞书多维表格 App Token
  - L2_TABLE_ID - 飞书多维表格 Table ID
  - L3_DOC_ID - 飞书云文档 Doc ID（L3-项目记忆）
  - L4_DOC_ID - 飞书云文档 Doc ID（L4-知识沉淀）
  
  数据安全说明：
  - 本 Skill 会读取本地 OpenClaw 会话文件
  - 对话内容通过 OpenClaw AI 提炼后同步到飞书
  - 请确保你知晓并同意此数据流向
  
  技术栈：
  - OpenClaw（AI Agent 框架）
  - 飞书 IM（消息推送）
  - 飞书多维表格（任务待办 L2）
  - 飞书云文档（项目记忆 L3、知识沉淀 L4）
  - inotify-tools（文件监听）
---

# 灵曦记忆系统 (Lingxi Memory)

基于 OpenClaw + 飞书的 AI 记忆解决方案，实现会话级自动提炼与跨会话记忆同步。

## 系统架构

```
用户对话
    ↓
会话结束（.jsonl.reset 文件生成）
    ↓
session_watch.sh 监听检测
    ↓
do_extract.sh AI 提炼
    ↓
process_extract_queue.sh 队列处理
    ↓
┌─────────┬─────────┬─────────┐
│  L2     │  L3     │  L4     │
│ 任务待办│ 项目记忆│ 知识沉淀│
│多维表格 │ 云文档  │ 云文档  │
└─────────┴─────────┴─────────┘
    ↓
飞书 IM 推送提炼报告
```

## 核心组件

| 脚本 | 功能 |
|------|------|
| `session_watch.sh` | 监听 OpenClaw 会话目录，检测会话结束事件 |
| `do_extract.sh` | 提取对话内容，调用 AI 提炼，生成操作队列 |
| `process_extract_queue.sh` | 处理队列，调用飞书 API 保存到 L2/L3/L4 |

## 五层存储结构

| 层级 | 名称 | 存储位置 | 触发方式 |
|:----:|------|---------|---------|
| L1 | 原始会话 | OpenClaw 本地 jsonl | 自动 |
| L2 | 任务待办 | 飞书多维表格 | AI 提炼 |
| L3 | 项目记忆 | 飞书云文档 | AI 提炼 |
| L4 | 知识沉淀 | 飞书云文档 | AI 提炼 |
| L5 | 全局规则 | 本地 MEMORY.md | 人工 |

## 飞书配置要求

### 1. 飞书多维表格（L2-任务待办）

创建多维表格，包含以下字段：

| 字段名 | 类型 | 说明 |
|--------|------|------|
| 任务名称 | 文本 | 简洁描述 |
| 所属项目 | 单选 | 资产监控/数字人/通用 |
| 状态 | 单选 | 待办/进行中/已完成/阻塞 |
| 优先级 | 单选 | P0/P1/P2/P3 |
| 标签 | 多选 | 类型标签 |
| 截止时间 | 日期 | 提醒触发 |
| 关联文档 | 文本 | 链接 L3/L4 |
| 创建来源 | 单选 | 自动/人工 |

### 2. 飞书云文档（L3/L4）

- L3-项目记忆：按项目分类记录决策和进展
- L4-知识沉淀：记录经验、SOP、踩坑

### 3. 飞书消息推送

配置 OpenClaw feishu 渠道，推送提炼报告到用户。

## 安装步骤

### 1. 安装依赖

```bash
# inotify-tools（文件监听）
apt install inotify-tools

# OpenClaw（已安装则跳过）
# 详见 OpenClaw 官方文档
```

### 2. 配置飞书

```bash
# 配置飞书 OAuth 授权
openclaw auth feishu

# 创建多维表格并记录 App Token 和 Table ID
# 创建云文档并记录 Doc ID
```

### 3. 配置脚本

编辑 `do_extract.sh` 和 `process_extract_queue.sh`：

```bash
# 替换以下配置
USER_OPEN_ID="ou_xxxxxxxx"           # 你的飞书 open_id
L2_APP_TOKEN="xxxxxxxxxxxx"            # 多维表格 App Token
L2_TABLE_ID="tblxxxxxxxxxxxx"          # 多维表格 Table ID
L3_DOC_ID="xxxxxxxxxxxx"               # L3 云文档 ID
L4_DOC_ID="xxxxxxxxxxxx"              # L4 云文档 ID
```

### 4. 启动监听

```bash
# 添加到 crontab（每5分钟检查）
*/5 * * * * bash /path/to/session_watch.sh

# 或使用 systemd 服务
```

### 5. 配置 Heartbeat

在 `HEARTBEAT.md` 中添加队列检查：

```markdown
## 记忆提炼队列检查
1. 检查 /tmp/extract_queue.txt
2. 调用 process_extract_queue.sh
3. 发送报告到飞书
```

## 使用效果

- **自动提炼**：会话结束自动触发，无需手动输入
- **智能分类**：AI 自动识别任务/项目/知识
- **跨会话记忆**：新会话可查看历史提炼报告
- **永久存储**：飞书云端永久保存

## 故障排查

```bash
# 检查监听进程
ps aux | grep session_watch

# 查看日志
tail -50 ~/.openclaw/workspace/logs/session_extract.log

# 检查队列
cat /tmp/extract_queue.txt

# 手动触发提炼
bash do_extract.sh "test-key" "test-session-id"
```

## 扩展定制

- **修改触发条件**：编辑 `session_watch.sh` 中的正则匹配
- **调整 AI Prompt**：编辑 `do_extract.sh` 中的 ANALYSIS_PROMPT
- **自定义分类**：修改 L2 字段或多维表格结构

---

*基于 OpenClaw + 飞书生态实现*
