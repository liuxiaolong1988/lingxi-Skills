#!/bin/bash
# MindVault 提炼脚本 - 执行会话内容 AI 提炼并保存到 L2-L4
# 版本: v1.1 - 环境变量版
# 
# 使用前提：
# 1. 安装依赖: apt install inotify-tools jq
# 2. 配置环境变量（必须）
# 3. 配置飞书多维表格和云文档

# ========== 环境变量配置（必需）==========
# 飞书用户 ID
FEISHU_USER_OPEN_ID="${FEISHU_USER_OPEN_ID:?请设置 FEISHU_USER_OPEN_ID 环境变量}"

# 飞书多维表格（L2-任务待办）
L2_APP_TOKEN="${L2_APP_TOKEN:?请设置 L2_APP_TOKEN 环境变量}"
L2_TABLE_ID="${L2_TABLE_ID:?请设置 L2_TABLE_ID 环境变量}"

# 飞书云文档（L3/L4）
L3_DOC_ID="${L3_DOC_ID:?请设置 L3_DOC_ID 环境变量}"
L4_DOC_ID="${L4_DOC_ID:?请设置 L4_DOC_ID 环境变量}"

# OpenClaw 目录
OPENCLAW_DIR="${OPENCLAW_DIR:-$HOME/.openclaw}"

# 日志目录
LOG_FILE="${MEMORY_LOG:-$OPENCLAW_DIR/workspace/logs/session_extract.log}"
# ==========================================

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# 获取参数
SESSION_KEY="$1"
SESSION_ID="$2"

mkdir -p "$(dirname "$LOG_FILE")"

# 获取会话文件
SESSION_FILE=""
for ext in "" ".reset."; do
    if [ -z "$ext" ]; then
        f="$OPENCLAW_DIR/agents/main/sessions/${SESSION_ID}.jsonl"
    else
        f=$(ls "$OPENCLAW_DIR/agents/main/sessions/${SESSION_ID}.jsonl.reset."* 2>/dev/null | head -1)
    fi
    [ -f "$f" ] && SESSION_FILE="$f" && break
done

[ -z "$SESSION_FILE" ] && { log "错误：找不到会话文件"; exit 1; }

log "========== 开始提炼: $SESSION_KEY =========="

# 提取对话内容（过滤用户消息）
CONTENT=""
while read -r line; do
    role=$(echo "$line" | jq -r '.message.role // empty' 2>/dev/null)
    msg=$(echo "$line" | jq -r '.message.content[0].text // empty' 2>/dev/null)
    # 只处理用户消息
    if [ "$role" = "user" ] && [ -n "$msg" ]; then
        # 清理消息：去掉 System 和 Sender 元信息块
        clean_msg=$(echo "$msg" | sed '1{/^System:/d}' | awk '/^Sender/{found=1; next} found{print}' | tail -n +2)
        if [ -n "$clean_msg" ]; then
            echo "$clean_msg"
        fi
    fi
done < "$SESSION_FILE" > /tmp/extract_content.txt

CONTENT=$(cat /tmp/extract_content.txt | head -30)

# 如果内容太短，跳过提炼
if [ -z "$CONTENT" ] || [ $(echo "$CONTENT" | wc -c) -lt 50 ]; then
    log "对话内容太短或无实际对话，跳过提炼"
    exit 0
fi

log "对话内容: $(echo "$CONTENT" | head -c 200)..."

# 构建 AI Prompt
ANALYSIS_PROMPT="你是一个记忆提取助手。请从对话中提取需要保存的信息。

要求：只输出每行的内容，不要任何解释或标记。

任务格式（每行）：T|任务名|项目|优先级
项目格式（每行）：P|项目名|类型|摘要
知识格式（每行）：K|类型|内容

示例：
T|实现自动提炼|通用|P1
P|资产监控|技术配置|升级服务器配置
K|经验|飞书权限开通最佳实践

如果没有对应内容，该行输出：无

对话内容：
$CONTENT"

log "调用 AI 分析..."

# 调用 AI（根据实际环境调整命令）
AI_RESULT=$(openclaw agent --local --agent main --message "$ANALYSIS_PROMPT" 2>&1)

# 清理 AI 结果
AI_CLEAN=$(echo "$AI_RESULT" | grep -v "^\\[" | grep -v "^Config" | grep -v "^(" | grep -v "^$" | tail -20)

log "AI 分析完成"
log "结果: $AI_CLEAN"

# 解析并保存
L2_COUNT=0
L3_COUNT=0
L4_COUNT=0

# 提取任务
TASKS=$(echo "$AI_CLEAN" | grep -E "^T\|" | head -5)
if [ -n "$TASKS" ]; then
    echo "$TASKS" | while IFS='|' read -r flag name project priority; do
        name=$(echo "$name" | xargs)
        project=$(echo "$project" | xargs)
        priority=$(echo "$priority" | xargs)
        [ -n "$name" ] && [ "$name" != "无" ] && {
            log "创建 L2 任务: $name ($project, $priority)"
            echo "L2|$name|${project:-通用}|${priority:-P2}" >> /tmp/extract_actions.txt
        }
    done
    L2_COUNT=$(echo "$TASKS" | grep -vE "无$" | wc -l)
fi

# 提取项目
PROJS=$(echo "$AI_CLEAN" | grep -E "^P\|" | head -5)
if [ -n "$PROJS" ]; then
    echo "$PROJS" | while IFS='|' read -r flag project type content; do
        project=$(echo "$project" | xargs)
        type=$(echo "$type" | xargs)
        content=$(echo "$content" | xargs)
        [ -n "$project" ] && [ "$project" != "无" ] && {
            log "保存 L3: $project - $type"
            echo "L3|$project|$type|$content" >> /tmp/extract_actions.txt
        }
    done
    L3_COUNT=$(echo "$PROJS" | grep -vE "无$" | wc -l)
fi

# 提取知识
KNOWS=$(echo "$AI_CLEAN" | grep -E "^K\|" | head -5)
if [ -n "$KNOWS" ]; then
    echo "$KNOWS" | while IFS='|' read -r flag type content; do
        type=$(echo "$type" | xargs)
        content=$(echo "$content" | xargs)
        [ -n "$type" ] && [ "$type" != "无" ] && {
            log "保存 L4: $type"
            echo "L4|$type|$content" >> /tmp/extract_actions.txt
        }
    done
    L4_COUNT=$(echo "$KNOWS" | grep -vE "无$" | wc -l)
fi

# 保存操作到队列
log "保存操作到队列..."

if [ -f /tmp/extract_actions.txt ] && [ -s /tmp/extract_actions.txt ]; then
    cat /tmp/extract_actions.txt >> /tmp/extract_queue.txt
    log "已加入处理队列"
fi

# 生成报告
SUMMARY=""
[ "$L2_COUNT" -gt 0 ] && SUMMARY="${SUMMARY}📌 任务：
$(echo "$TASKS" | grep -vE "无$" | head -3)
"
[ "$L3_COUNT" -gt 0 ] && SUMMARY="${SUMMARY}📁 项目：
$(echo "$PROJS" | grep -vE "无$" | head -3)
"
[ "$L4_COUNT" -gt 0 ] && SUMMARY="${SUMMARY}💡 知识：
$(echo "$KNOWS" | grep -vE "无$" | head -3)
"

REPORT="📋 会话提炼报告

会话：$SESSION_KEY

提炼结果：
• L2 任务: $L2_COUNT 条
• L3 项目: $L3_COUNT 条
• L4 知识: $L4_COUNT 条

${SUMMARY}"

log "========== 提炼完成 =========="
log "$REPORT"

# 保存报告
echo "$REPORT" > "/tmp/extract_report_${SESSION_ID}.txt"

# 发送消息提醒（通过 OpenClaw message 接口）
openclaw message send --channel feishu --target "$FEISHU_USER_OPEN_ID" --message "$REPORT" 2>&1 || true

# 清理
rm -f /tmp/extract_actions.txt

exit 0
