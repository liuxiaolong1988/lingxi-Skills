#!/bin/bash
# 记忆提炼队列处理器
# 由 HEARTBEAT 调用，处理 L2-L4 保存
# 
# 使用前提：
# 1. 配置飞书多维表格和云文档 token
# 2. 配置 OpenClaw feishu_bitable 和 feishu_update_doc 接口

# ========== 配置区域（请根据实际情况修改）==========
QUEUE_FILE="/tmp/extract_queue.txt"

# 飞书配置
L2_APP_TOKEN="xxxxxxxxxxxx"            # 飞书多维表格 App Token
L2_TABLE_ID="tblxxxxxxxxxxxx"          # 飞书多维表格 Table ID
L3_DOC_ID="xxxxxxxxxxxx"               # 飞书云文档 Doc ID（L3-项目记忆）
L4_DOC_ID="xxxxxxxxxxxx"              # 飞书云文档 Doc ID（L4-知识沉淀）
# =================================================

echo "检查提炼队列..."

if [ ! -f "$QUEUE_FILE" ] || [ ! -s "$QUEUE_FILE" ]; then
    echo "队列为空，无需处理"
    exit 0
fi

echo "发现待处理操作:"

# 处理队列
while IFS='|' read -r action data1 data2 data3; do
    echo "处理: $action | $data1 | $data2 | $data3"
    
    case "$action" in
        "L2")
            echo "创建 L2 任务: $data1 ($data2, $data3)"
            # 调用飞书多维表格 API（使用 feishu_bitable 工具）
            feishu_bitable_app_table_record action="create" \
                app_token="$L2_APP_TOKEN" \
                table_id="$L2_TABLE_ID" \
                fields="{\"任务名称\":\"$data1\",\"所属项目\":\"$data2\",\"状态\":\"待办\",\"优先级\":\"$data3\",\"创建来源\":\"自动\"}" 2>&1
            ;;
        "L3")
            echo "更新 L3 项目: $data1 - $data2"
            # 调用飞书文档 API（使用 feishu_update_doc 工具）
            feishu_update_doc doc_id="$L3_DOC_ID" mode="append" \
                markdown="\n### $data1 | $data2\n- $data3" 2>&1
            ;;
        "L4")
            echo "更新 L4 知识: $data1"
            # 调用飞书文档 API
            feishu_update_doc doc_id="$L4_DOC_ID" mode="append" \
                markdown="\n## $data1\n- $data2" 2>&1
            ;;
    esac
done < "$QUEUE_FILE"

# 清空队列
> "$QUEUE_FILE"
echo "队列处理完成"

exit 0
