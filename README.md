# Lingxi Memory - 灵曦记忆系统

> 基于 OpenClaw + 飞书的 AI 记忆解决方案
> 实现会话级自动提炼与跨会话记忆同步

## 简介

Lingxi Memory（灵曦记忆系统）是一套专为 AI Agent 设计的记忆解决方案，结合飞书 IM 和飞书官方插件实现自动记忆功能。

### 核心特性

- 🤖 **自动提炼** - 会话结束自动触发 AI 提炼，无需手动操作
- 📊 **五层存储** - L1 原始会话 → L5 全局规则，结构化沉淀
- 🔄 **跨会话记忆** - 新会话可查看历史提炼报告
- 💾 **永久存储** - 飞书云端永久保存

### 技术栈

- [OpenClaw](https://github.com/openclaw/openclaw) - AI Agent 框架
- 飞书 IM - 消息推送
- 飞书多维表格 - 任务待办（L2）
- 飞书云文档 - 项目记忆（L3）、知识沉淀（L4）
- inotify-tools - 文件监听

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

## 快速开始

### 1. 安装依赖

```bash
# inotify-tools（文件监听）
apt install inotify-tools
```

### 2. 配置飞书

```bash
# 配置飞书 OAuth 授权
openclaw auth feishu
```

### 3. 配置脚本

编辑 `scripts/do_extract.sh`：

```bash
# 替换配置
USER_OPEN_ID="ou_xxxxxxxx"
L2_APP_TOKEN="xxxxxxxxxxxx"
L2_TABLE_ID="tblxxxxxxxxxxxx"
L3_DOC_ID="xxxxxxxxxxxx"
L4_DOC_ID="xxxxxxxxxxxx"
```

### 4. 启动监听

```bash
# 添加到 crontab
*/5 * * * * bash /path/to/session_watch.sh
```

详细安装说明见 [SKILL.md](./SKILL.md)

## 目录结构

```
lingxi-memory/
├── SKILL.md                    # Skill 定义
├── README.md                   # 项目说明
├── LICENSE                     # MIT 协议
└── scripts/                    # 核心脚本
    ├── session_watch.sh        # 会话监听
    ├── do_extract.sh           # AI 提炼
    └── process_extract_queue.sh # 队列处理
```

## 五层存储

| 层级 | 名称 | 存储位置 | 说明 |
|:----:|------|---------|------|
| L1 | 原始会话 | OpenClaw 本地 | 完整会话记录 |
| L2 | 任务待办 | 飞书多维表格 | 待办/阻塞事项 |
| L3 | 项目记忆 | 飞书云文档 | 决策/进展/配置 |
| L4 | 知识沉淀 | 飞书云文档 | 经验/SOP/踩坑 |
| L5 | 全局规则 | 本地文件 | 系统规则 |

## 故障排查

```bash
# 检查监听进程
ps aux | grep session_watch

# 查看日志
tail -50 ~/.openclaw/workspace/logs/session_extract.log

# 检查队列
cat /tmp/extract_queue.txt
```

## 开源协议

MIT License - See [LICENSE](./LICENSE)

---

⭐ 如果这个项目对你有帮助，欢迎 star！
