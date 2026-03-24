# Lingxi-MindVault - 灵曦记忆系统：自动记忆提炼 & 写入飞书知识库

## 描述

灵曦自动记忆系统，定时扫描 OpenClaw 会话文件，自动提炼有价值的记忆，写入飞书多维表格/云文档知识库。

**v5 新架构**：一次完成，省去队列，bash 调用 agent，agent 直接提炼 + 写入 + 通知，更简洁更实时！

## 功能特点

- ✅ 稳定排除 heartbeat 会话（当前 + 历史自动标记）
- ✅ 支持 `.jsonl` / `.jsonl.reset.*` / `.jsonl.deleted.*` 所有会话格式
- ✅ 自动过滤空会话/小会话（用户消息数 < 1 或内容长度 < 20）
- ✅ 完整的异常处理和通知，每个阶段都有错误通知
- ✅ 超时支持 300 秒（5分钟），适应大会话
- ✅ 开源友好，**所有配置通过环境变量指定**，无硬编码敏感信息
- ✅ 启动检查，如果缺少必需环境变量会立即报错，不会静默使用错误配置
- ✅ 原子进程锁，防止重复运行
- ✅ 过期锁自动清理，不会死锁

## 架构流程图

```plaintext
【阶段 1：定时触发】
    │
    ├─▶ crontab
    │     ├─ 白天（8:00-22:00）：每 1 分钟
    │     └─ 夜间（22:00-次日8:00）：每 5 分钟
    │
【阶段 2：会话检查】
    │
    ├─▶ session_check.sh
    │     │
    │     ├─ 1. 获取进程锁（/tmp/session_check.lock）
    │     │
    │     ├─ 2. 读取 sessions.json
    │     │
    │     ├─ 3. 获取活跃会话
    │     │     ├─ 只保留最近 24 小时内更新的
    │     │     └─ 排除 key 为 "agent:main:main" 的 heartbeat 会话（活跃列表层面排除）
    │     │
    │     ├─ 4. 遍历所有会话文件
    │     │     ├─ .jsonl
    │     │     ├─ .jsonl.reset.*
    │     │     └─ .jsonl.deleted.*
    │     │
    │     ├─ 5. 对每个会话：
    │     │     │
    │     │     ├─ a. 文件存在？
    │     │     │   └─ 否 → 下一个
    │     │     │
    │     │     ├─ b. 已处理过？（/tmp/processed_sessions.tmp）
    │     │     │   └─ 是 → 下一个
    │     │     │
    │     │     ├─ c. 是 heartbeat 会话？
    │     │     │     ├─ 判断逻辑：
    │     │     │     │   1. 从 sessions.json 读取 agent:main:main 的 sessionFile
    │     │     │     │   2. 从 sessionFile 中提取 session_id
    │     │     │     │   3. 如果当前文件的 session_id == heartbeat 会话的 session_id → 跳过
    │     │     │     └─ 是 → 跳过，下一个
    │     │     │     └─ 否 → 继续
    │     │     │
    │     │     ├─ d. 是活跃会话？
    │     │     │   └─ 是 → 下一个
    │     │     │
    │     │     ├─ e. 已提炼过？（memory/.extracted_sessions）
    │     │     │   └─ 是 → 下一个
    │     │     │
    │     │     └─ f. 发现未提炼会话！
    │     │                 │
    │     │                 ├─ 发送通知："发现未提炼会话: <session_id>，正在处理..."
    │     │                 │
    │     │                 ├─ 调用 do_extract_and_write.sh <会话文件路径>
    │     │                 │
    │     │                 └─ 检查结果：
    │     │                     ├─ 成功（退出码 0）→ 标记为已提炼
    │     │                     └─ 失败（退出码非 0）→ 不标记，下次重试
    │     │
    │     └─ 6. 释放进程锁
    │
【阶段 3：AI 提炼 + 写入（一次完成）】
    │
    ├─▶ do_extract_and_write.sh
    │     │
    │     ├─ 1. 完整读取会话文件（无行数限制）
    │     │
    │     ├─ 2. 统计用户消息数和内容长度
    │     │     ├─ 支持 .message.role
    │     │     └─ 支持 .message.content[0].text（数组和字符串两种格式）
    │     │
    │     ├─ 3. 过滤条件检查
    │     │     ├─ 用户消息数 ≥ 1
    │     │     └─ 内容长度 ≥ 20
    │     │
    │     ├─ 4. 过滤通过？
    │     │   ├─ 否 → 发送通知（CLI）→ 标记为已提炼 → 返回 0
    │     │   └─ 是 → 继续
    │     │
    │     ├─ 5. 准备 AI 提炼 prompt（占位符替换，解决多行引号问题）
    │     │
    │     ├─ 6. 调用 openclaw agent 进行 AI 提炼（后台运行，最多等待 300 秒 = 5 分钟）
    │     │
    │     ├─ 7. 检查 AI 调用结果：
    │     │   ├─ a. 超时？（> 300 秒）
    │     │   │   └─ 是 → 发送通知（CLI）→ "❌ 会话 <SESSION_ID> 提炼失败：AI调用超时（300秒）" → 退出 1
    │     │   ├─ b. 退出码非 0？
    │     │   │   └─ 是 → 发送通知（CLI）→ "❌ 会话 <SESSION_ID> 提炼失败：AI调用失败（退出码：<code>）" → 退出 1
    │     │   ├─ c. 输出为空？
    │     │   │   └─ 是 → 发送通知（CLI）→ "❌ 会话 <SESSION_ID> 提炼失败：AI返回为空" → 退出 2
    │     │   ├─ d. 输出包含 "DONE" → AI 已完成所有写入 → 标记为已提炼 → 退出 0
    │     │   ├─ 不包含 "DONE" 但包含错误 → 发送通知（CLI）→ "❌ 会话 <SESSION_ID> 提炼失败：AI返回错误信息" → 退出 1
    │     │   └─ 不包含 "DONE" 也不包含错误 → 发送通知（CLI）→ "❌ 会话 <SESSION_ID> 提炼失败：AI 没有完成写入" → 退出 3
    │     │
    │     └─ 完成，返回 0
    │
【阶段 4：完成】
    │
    └─▶ 结束，agent 已经完成所有提炼 + 写入 + 通知
```

## 文件结构

```
skill/lingxi-memory/
├── SKILL.md                         # 这个文件
├── session_check.sh                  # 会话检查脚本
└── do_extract_and_write.sh           # AI 提炼 + 写入脚本
```

## 环境变量配置（必填）

**你必须在 `workspace/.env` 文件中配置以下环境变量**，否则脚本无法运行：

```bash
# 你的飞书 open_id（必填，用于接收通知）
export FEISHU_USER_OPEN_ID="ou_xxxxxxxxxxxxxxxxxx"
# L2 任务看板：飞书多维表格 app_token（必填）
export L2_APP_TOKEN="your_l2_app_token"
# L2 任务看板：数据表 ID（必填）
export L2_TABLE_ID="your_l2_table_id"
# L3 项目日志：飞书云文档 doc_id（必填）
export L3_DOC_ID="your_l3_doc_id"
# L4 知识沉淀：飞书云文档 doc_id（必填）
export L4_DOC_ID="your_l4_doc_id"

# 可选配置：OpenClaw 会话目录（默认：/root/.openclaw/agents/main/sessions）
# export SESSIONS_DIR="/path/to/your/sessions"
# 可选配置：通知目标（默认：user:$FEISHU_USER_OPEN_ID）
# export NOTIFY_TARGET="user:ou_xxxxxxxxxxxxxxxxxx"
```

**重要安全提示**：
- 不要使用默认提供的示例 ID，那是作者的飞书资源
- 必须替换为你自己的飞书多维表格和文档 ID
- 如果不配置，脚本会启动失败并提示你缺少环境变量，这是正常的安全设计

## 通知格式

| 场景 | 通知内容 | 发起方 |
|------|---------|--------|
| **发现未提炼会话** | `发现未提炼会话: <session_id>，正在处理...` | session_check.sh (bash) |
| **会话文件不存在** | `❌ 会话 <SESSION_ID> 提炼失败：文件不存在` | do_extract_and_write.sh (bash) |
| **过滤跳过** | `ℹ️ 会话 <SESSION_ID> 过滤跳过：<原因>` | do_extract_and_write.sh (bash) |
| **AI 调用超时** | `❌ 会话 <SESSION_ID> 提炼失败：AI调用超时（300秒）` | do_extract_and_write.sh (bash) |
| **AI 调用失败** | `❌ 会话 <SESSION_ID> 提炼失败：AI调用失败（退出码：<code>）` | do_extract_and_write.sh (bash) |
| **AI 返回为空** | `❌ 会话 <SESSION_ID> 提炼失败：AI返回为空` | do_extract_and_write.sh (bash) |
| **AI 返回错误** | `❌ 会话 <SESSION_ID> 提炼失败：AI返回错误信息` | do_extract_and_write.sh (bash) |
| **AI 没有完成写入** | `❌ 会话 <SESSION_ID> 提炼失败：AI 没有完成写入` | do_extract_and_write.sh (bash) |
| **提炼成功（有内容）** | `## 提炼结果\n\n- **L2 任务**: X 条\n- **L3 项目**: X 条\n- **L4 知识**: X 条` | agent (AI) |
| **提炼成功（无内容）** | `ℹ️ 会话 <SESSION_ID> 提炼完成，无内容需要写入` | agent (AI) |

## 安装部署

```bash
# 1. 克隆/复制脚本到你的 workspace/scripts 目录
cp session_check.sh /root/.openclaw/workspace/scripts/
cp do_extract_and_write.sh /root/.openclaw/workspace/scripts/

# 2. 添加执行权限
chmod +x /root/.openclaw/workspace/scripts/*.sh

# 3. 创建已提炼记录文件
mkdir -p /root/.openclaw/workspace/memory
touch /root/.openclaw/workspace/memory/.extracted_sessions

# 4. 配置 crontab
# 编辑 crontab: crontab -e
# 添加以下内容：
# 白天（8:00-22:00）每 1 分钟运行一次
# */1 8-22 * * * /root/.openclaw/workspace/scripts/session_check.sh >> /tmp/session_check.log 2>&1
# 夜间（22:00-次日8:00）每 5 分钟运行一次
# */5 22-23 * * * /root/.openclaw/workspace/scripts/session_check.sh >> /tmp/session_check.log 2>&1
# */5 0-7 * * * /root/.openclaw/workspace/scripts/session_check.sh >> /tmp/session_check.log 2>&1
```

## 依赖

- OpenClaw >= 2026.3.13
- python3 >= 3.8
- bash >= 4.0
- **需要配合 OpenClaw 飞书官方插件使用**
- **需要开通飞书相关用户身份读写权限，完成用户 OAuth 授权后才能正常使用**

## 配置说明

使用前必须完成：

1. 在 OpenClaw 中启用飞书插件，并完成用户 OAuth 授权（获得飞书 API 访问权限）
2. 在 `workspace/.env` 文件中配置以下环境变量：

```bash
# 你的飞书 open_id（必填，用于接收通知）
export FEISHU_USER_OPEN_ID="ou_xxxxxxxxxxxxxxxxxx"
# L2 任务看板：飞书多维表格 app_token
export L2_APP_TOKEN="your_l2_app_token"
# L2 任务看板：数据表 ID
export L2_TABLE_ID="your_l2_table_id"
# L3 项目日志：飞书云文档 doc_id
export L3_DOC_ID="your_l3_doc_id"
# L4 知识沉淀：飞书云文档 doc_id
export L4_DOC_ID="your_l4_doc_id"
```

如果不配置环境变量，会使用默认配置，但默认配置只能在灵曦的记忆空间使用，其他人使用需要修改为自己的飞书资源。

## 安全说明

### 安全扫描结果

| 检查项 | 状态 | 说明 |
|--------|------|------|
| 命令注入 | ✅ 安全 | 所有变量都正确使用引号包裹，文件名使用 `basename` 提取，不会导致命令注入 |
| 路径遍历 | ✅ 安全 | 使用 `basename` 正确提取 session_id，不会路径遍历 |
| 硬编码密钥 | ⚠️ 注意 | 默认配置中包含示例配置，使用前必须修改为你自己的飞书资源配置 |
| 进程锁 | ✅ 安全 | 使用 `mkdir` 原子操作获取锁，支持过期锁（超过 10 分钟）自动清理，不会死锁 |
| 临时文件 | ✅ 安全 | 使用 `$$` PID 隔离临时文件，用完自动删除，不会冲突 |
| 错误处理 | ✅ 安全 | 每个步骤都有错误检查和通知，不会静默失败 |

### 风险声明

- 本 skill 需要访问飞书 API，**必须完成用户 OAuth 授权**才能使用
- 请确保你的飞书 API 权限配置正确，不要泄露 API 密钥给第三方
- 本 skill 会自动读取本地会话文件并提取内容写入你的飞书知识库，请确认你授权本 skill 访问你的会话内容

## 版本历史

- **v1**: 初始版本，cron → check → extract → queue → heartbeat → write，队列架构
- **v2-v4**: 逐步修复 heartbeat 排除、参数解析等问题
- **v5**: 简化架构，移除队列，bash → agent → write 一次完成，更简洁更实时

## 作者

灵曦 / Linxi-MindVault
