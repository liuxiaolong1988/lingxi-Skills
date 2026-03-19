#!/bin/bash
# MindVault 会话结束监听脚本
# 监听会话目录，检测会话结束并触发提炼

# ========== 配置区域（环境变量）==========
SESSIONS_DIR="${OPENCLAW_SESSIONS_DIR:-~/.openclaw/agents/main/sessions}"
EXTRACTED_FILE="${MEMORY_EXTRACTED:-~/.openclaw/workspace/memory/.extracted_sessions}"
LOG_FILE="${MEMORY_LOG:-~/.openclaw/workspace/logs/session_watch.log}"
EXTRACT_SCRIPT="${EXTRACT_SCRIPT:-/path/to/do_extract.sh}"  # 修改为实际路径
# =================================================

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

mkdir -p "$(dirname "$LOG_FILE")"
mkdir -p "$(dirname "$EXTRACTED_FILE")"

log "========== 会话监听启动 =========="

# 使用 inotifywait 监听
inotifywait -m -e moved_to -e create "$SESSIONS_DIR" 2>&1 | while read -r dir action file; do
    log "检测到变化: $action -> $file"
    
    # 检测会话结束 (.jsonl.reset. 或 .jsonl.deleted.)
    if [[ "$file" =~ ^([a-z0-9-]+)\.jsonl\.reset\. ]]; then
        session_id="${BASH_REMATCH[1]}"
        log "检测到会话结束: $session_id"
        
    elif [[ "$file" =~ ^([a-z0-9-]+)\.jsonl\.deleted\. ]]; then
        session_id="${BASH_REMATCH[1]}"
        log "检测到会话删除: $session_id"
    else
        log "  -> 非会话结束事件，跳过"
        continue
    fi
    
    # 获取会话 key（根据实际环境调整）
    SESSION_KEY="agent:main:session:$session_id"
    
    log "会话标识: $SESSION_KEY"
    
    # 检查是否已提炼
    if grep -q "^${SESSION_KEY}$" "$EXTRACTED_FILE" 2>/dev/null; then
        log "  -> 已提炼，跳过"
    else
        log "  -> 触发提炼..."
        # 调用提炼脚本（使用环境变量或默认路径）
        bash "$EXTRACT_SCRIPT" "$SESSION_KEY" "$session_id"
        echo "$SESSION_KEY" >> "$EXTRACTED_FILE"
        log "  -> 提炼完成"
    fi
done
