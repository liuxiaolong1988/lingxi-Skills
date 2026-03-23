#!/bin/bash
# 会话检查脚本 - 最终完善版
# 功能: 定期检查未提炼的会话，通知用户并触发提炼
# 特点: 
# - 从sessions.json获取所有活跃会话ID（私聊+群聊）
# - 跳过所有活跃会话
# - 跳过已提炼会话
# - 进程锁防止多个实例同时运行
# - 会话去重（避免同一个会话被处理多次）

# 加载环境变量
WORKSPACE="/root/.openclaw/workspace"
if [ -f "$WORKSPACE/.env" ]; then
    source "$WORKSPACE/.env"
fi

# 配置
SESSIONS_DIR="/root/.openclaw/agents/main/sessions"
EXTRACTED_FILE="$WORKSPACE/memory/.extracted_sessions"
SCRIPT_DIR="$WORKSPACE/scripts"
DO_EXTRACT_SCRIPT="$SCRIPT_DIR/do_extract_and_write.sh"
SESSIONS_JSON="$SESSIONS_DIR/sessions.json"
LOCK_FILE="/tmp/session_check.lock"
PROCESSED_SESSIONS="/tmp/processed_sessions.tmp"

# 消息发送目标（从环境变量读取，默认发送给 FEISHU_USER_OPEN_ID）
NOTIFY_TARGET="${NOTIFY_TARGET:-user:${FEISHU_USER_OPEN_ID}}"

# 日志函数
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# 进程锁函数（使用mkdir原子操作）
acquire_lock() {
    # 尝试创建锁目录（原子操作）
    if ! mkdir "$LOCK_FILE" 2>/dev/null; then
        # 锁已存在，检查是否过期（超过10分钟认为是死锁）
        local lock_mtime=$(stat -c %Y "$LOCK_FILE" 2>/dev/null || echo 0)
        local now=$(date +%s)
        local lock_age=$((now - lock_mtime))
        
        if [ "$lock_age" -gt 600 ]; then
            log "警告: 锁文件已过期（${lock_age}秒），强制删除"
            rm -rf "$LOCK_FILE"
            if ! mkdir "$LOCK_FILE" 2>/dev/null; then
                log "错误: 无法获取锁，另一个进程正在运行"
                return 1
            fi
        else
            log "跳过: 另一个进程正在运行（锁年龄: ${lock_age}秒）"
            return 1
        fi
    fi
    
    # 记录锁创建时间
    touch "$LOCK_FILE"
    log "已获取进程锁"
    return 0
}

# 释放锁函数
release_lock() {
    rm -rf "$LOCK_FILE"
    rm -f "$PROCESSED_SESSIONS" 2>/dev/null
    log "已释放进程锁"
}

# 确保脚本退出时释放锁
trap 'release_lock' EXIT

# 从sessions.json获取所有活跃会话ID（包括私聊和群聊，只保留最近24小时更新的，排除heartbeat会话）
get_active_sessions() {
    if [ ! -f "$SESSIONS_JSON" ]; then
        log "错误: sessions.json不存在: $SESSIONS_JSON"
        return 1
    fi
    
    python3 -c "
import json
import time
try:
    data = json.load(open('$SESSIONS_JSON'))
    now = time.time() * 1000  # 当前时间（毫秒）
    one_day = 24 * 60 * 60 * 1000  # 24小时（毫秒）
    # 遍历所有key，提取最近24小时更新的sessionId，排除heartbeat会话
    for key in data:
        if key == 'agent:main:main':
            continue  # 跳过heartbeat会话
        if 'sessionId' in data[key] and 'updatedAt' in data[key]:
            updated_at = data[key]['updatedAt']
            if now - updated_at < one_day:
                print(data[key]['sessionId'])
except Exception as e:
    print(f'Error: {e}')
" 2>/dev/null
}

# 发送通知（直接用 openclaw CLI 发送）
send_notification() {
    local message="$1"
    log "通知: $message"
    
    # 用 openclaw CLI 发送消息
    if command -v openclaw &>/dev/null; then
        log "使用 openclaw CLI 发送消息到: $NOTIFY_TARGET"
        openclaw message send --channel feishu --target "$NOTIFY_TARGET" --message "$message" 2>&1 || {
            log "警告: openclaw CLI 发送失败"
        }
    else
        log "警告: openclaw CLI 不可用，无法发送通知"
    fi
}

# ============== 主程序开始 ==============

# 获取进程锁
if ! acquire_lock; then
    exit 1
fi

# 确保目录和文件存在
mkdir -p "$(dirname "$EXTRACTED_FILE")"
touch "$EXTRACTED_FILE"
rm -f "$PROCESSED_SESSIONS" 2>/dev/null
touch "$PROCESSED_SESSIONS"

# 获取所有活跃会话ID
ACTIVE_SESSIONS=$(get_active_sessions)
if [ -z "$ACTIVE_SESSIONS" ]; then
    log "提示: 未检测到活跃会话"
else
    log "活跃会话ID:"
    echo "$ACTIVE_SESSIONS" | while read -r session_id; do
        [ -n "$session_id" ] && log "  - $session_id"
    done
fi

# 检查提炼脚本是否存在
if [ ! -f "$DO_EXTRACT_SCRIPT" ]; then
    log "错误: 提炼脚本不存在: $DO_EXTRACT_SCRIPT"
    exit 1
fi
chmod +x "$DO_EXTRACT_SCRIPT"

# 遍历所有会话文件（包括 .jsonl、.jsonl.reset.*、.jsonl.deleted.*）
for session_file in "$SESSIONS_DIR"/*.jsonl "$SESSIONS_DIR"/*.jsonl.*; do
    # 跳过不存在的文件（避免*.jsonl匹配失败）
    [ -e "$session_file" ] || continue
    
    # 获取session_id（去掉路径和所有后缀：.jsonl、.jsonl.reset.*、.jsonl.deleted.*等）
    session_id=$(basename "$session_file" | sed -E 's/\.jsonl(\..*)?$//')
    
    # 跳过空的session_id
    [ -z "$session_id" ] && continue
    
    # 去重：检查是否已经处理过这个session_id
    if grep -q "^${session_id}$" "$PROCESSED_SESSIONS" 2>/dev/null; then
        log "跳过重复会话: $session_id"
        continue
    fi
    
    # 标记为已处理
    echo "$session_id" >> "$PROCESSED_SESSIONS"
    
    # 获取当前 heartbeat 会话的 sessionFile，并跳过对应的文件
    HEARTBEAT_SESSION_FILE=$(python3 -c "
import json
import os
try:
    data = json.load(open('$SESSIONS_JSON'))
    if 'agent:main:main' in data:
        session_file = data['agent:main:main'].get('sessionFile', '')
        if session_file:
            # 从完整路径中提取 session_id
            filename = os.path.basename(session_file)
            # 去掉 .jsonl 后缀（如果文件是 /path/to/xxx.jsonl）
            if filename.endswith('.jsonl'):
                print(filename[:-6])
            else:
                # 如果已经是 session_id 格式（没有 .jsonl 后缀）
                print(filename)
        else:
            print('')
    else:
        print('')
except:
    print('')
" 2>/dev/null)
    
    # 跳过 heartbeat 会话（当前和历史）
    # 1. 跳过当前 heartbeat 会话
    if [ -n "$HEARTBEAT_SESSION_FILE" ] && [ "$session_id" = "$HEARTBEAT_SESSION_FILE" ]; then
        log "跳过 heartbeat 会话: $session_id"
        # 把当前 heartbeat 会话标记为已提炼，这样下次它被重置后就不会被处理
        if ! grep -q "^agent:main:session:${session_id}$" "$EXTRACTED_FILE" 2>/dev/null; then
            echo "agent:main:session:${session_id}" >> "$EXTRACTED_FILE"
            log "已将历史 heartbeat 会话标记为已提炼: $session_id"
        fi
        continue
    fi
    
    # 跳过所有活跃会话
    if echo "$ACTIVE_SESSIONS" | grep -q "^${session_id}$" 2>/dev/null; then
        log "跳过活跃会话: $session_id"
        continue
    fi
    
    # 检查是否已提炼过
    if grep -q "^agent:main:session:${session_id}$" "$EXTRACTED_FILE" 2>/dev/null; then
        continue
    fi
    
    # 发现未提炼会话！
    log "发现未提炼会话: $session_id"
    
    # 发送通知（只在第一次发现时）
    send_notification "发现未提炼会话: $session_id，正在处理..."
    
    # ========== 真实调用 ==========
    # 静默调用提炼脚本（不输出到stdout）
    log "调用提炼脚本处理会话: $session_id"
    "$DO_EXTRACT_SCRIPT" "$session_file" >/dev/null 2>&1
    extract_exit_code=$?
    # =============================
    
    # 检查提炼结果
    if [ $extract_exit_code -eq 0 ]; then
        # 返回0：成功或跳过，都标记为已处理
        log "会话处理完成: $session_id"
        echo "agent:main:session:${session_id}" >> "$EXTRACTED_FILE"
    else
        # 返回非0：错误，不标记，下次再试
        log "会话处理失败，下次重试: $session_id (退出码: $extract_exit_code)"
    fi
done

log "会话检查完成"
exit 0
