#!/usr/bin/env bash
#
# Agent 管理脚本 - CLI 版
# 功能：创建、停止、管理 OpenCode Agent，支持通过 HTTP API 发送指令
#
# 用法:
#   ./agent.sh start <name> [--workdir <dir>] [--port <port>]   创建并启动 Agent
#   ./agent.sh stop <name>                                       停止 Agent
#   ./agent.sh send <name> <instruction>                         发送指令到 Agent
#   ./agent.sh status [name]                                     查看 Agent 状态
#   ./agent.sh list                                              列出所有 Agent
#   ./agent.sh attach <name>                                     附加到 Agent 的 tmux session
#   ./agent.sh destroy <name>                                    销毁 Agent（停止并删除工作目录）
#

set -euo pipefail

# 默认配置
DEFAULT_MASTER_PORT=4097
DEFAULT_BASE_DIR="${HOME}/agents"
AGENT_BASE_URL="http://localhost"
MASTER_URL="http://localhost:${DEFAULT_MASTER_PORT}"

# 颜色输出（使用 printf 避免转义问题）
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 获取 Agent 端口
get_agent_port() {
    local name="$1"
    if [ "$name" = "master" ]; then
        echo "$DEFAULT_MASTER_PORT"
    else
        # 使用 hash 计算端口，避免冲突
        local hash_val=$(echo -n "$name" | md5sum | head -c 8)
        local offset=$((16#$hash_val % 1000))
        echo $((DEFAULT_MASTER_PORT + 1 + offset))
    fi
}

# 检查 Agent 是否运行
check_agent_running() {
    local name="$1"
    tmux has-session -t "$name" 2>/dev/null
}

# 获取 Agent 工作目录
get_work_dir() {
    local name="$1"
    echo "${DEFAULT_BASE_DIR}/${name}"
}

# 获取心跳进程 PID 文件路径
get_heartbeat_pid_file() {
    local name="$1"
    echo "/tmp/agent_heartbeat_${name}.pid"
}

# 获取 Agent 启动时间戳文件
get_agent_start_file() {
    local name="$1"
    echo "/tmp/agent_start_${name}"
}

# 生成 Agent 向 Master 汇报的 curl 命令
get_report_curl_cmd() {
    local name="$1"
    local port="$2"
    local master_port="$3"
    
    cat << EOF
#!/usr/bin/env bash
# Agent '$name' 向 Master 汇报状态的 curl 命令
# 用法: 直接执行此脚本，或复制下面的 curl 命令

MASTER_URL="http://localhost:${master_port}"

curl -X POST "\${MASTER_URL}/tui/append-prompt" \
  -H "Content-Type: application/json" \
  -d '{"text": "[Agent心跳] Agent: ${name} (port: ${port}) 汇报: 我还活着，运行正常。请检查是否有需要我处理的任务。"}'

curl -X POST "\${MASTER_URL}/tui/submit-prompt"
EOF
}

# 创建 Agent 心跳说明文件（放在工作目录供 Agent 参考）
create_heartbeat_info() {
    local name="$1"
    local port="$2"
    local workdir="$3"
    
    if [ "$name" = "master" ]; then
        return 0
    fi
    
    local master_port=$(get_agent_port "master")
    local report_cmd=$(get_report_curl_cmd "$name" "$port" "$master_port")
    
    cat > "${workdir}/HEARTBEAT.md" << EOF
# Agent 心跳说明

## 自动心跳
本 Agent 已配置自动心跳守护进程，会定期执行以下操作：

### 1. 自身健康检查
每 15 分钟检查一次 /global/health，确保服务正常。
连续 3 次失败会自动重启 Agent。

### 2. 向 Master 汇报状态
每 15 分钟向 Master (port: ${master_port}) 汇报一次状态。

## 手动汇报命令
如需手动向 Master 汇报，请执行：

\`\`\`bash
${report_cmd}
\`\`\`

## Master 地址
- Master URL: http://localhost:${master_port}
- 本 Agent URL: http://localhost:${port}
EOF
}

# ============================================
# 心跳守护进程 - 双心跳机制
# 
# Master 心跳（每 5 分钟）:
#   1. 检查自身健康 (/global/health)
#   2. 给自己发 keepalive 消息，防止无故停机
# 
# Worker 心跳（每 15 分钟）:
#   1. 检查自身健康 (/global/health)
#   2. 向 Master 汇报状态 (curl /tui/append-prompt)
#   3. 连续 3 次失败会自动重启 Agent
# ============================================
start_heartbeat() {
    local name="$1"
    local port="$2"
    local pid_file=$(get_heartbeat_pid_file "$name")
    local start_file=$(get_agent_start_file "$name")
    
    # 记录启动时间
    date +%s > "$start_file"
    
    # 如果已有心跳进程在运行，先停止
    stop_heartbeat "$name" 2>/dev/null || true
    
    # 确定心跳间隔
    local heartbeat_interval
    local is_master=false
    if [ "$name" = "master" ]; then
        heartbeat_interval=300   # Master: 5 分钟
        is_master=true
    else
        heartbeat_interval=900   # Worker: 15 分钟
    fi
    
    # 启动后台心跳进程
    (
        local agent_url="${AGENT_BASE_URL}:${port}"
        local master_url="${AGENT_BASE_URL}:${DEFAULT_MASTER_PORT}"
        local fail_count=0
        local max_fail=3
        local cycle_count=0
        
        while true; do
            sleep "$heartbeat_interval"
            cycle_count=$((cycle_count + 1))
            
            # 检查 tmux session 是否存在
            if ! tmux has-session -t "$name" 2>/dev/null; then
                echo "[Heartbeat] Agent '$name' session 已消失，退出心跳守护" >&2
                break
            fi
            
            # 步骤 1: 发送健康检查请求
            if ! curl -s "${agent_url}/global/health" > /dev/null 2>&1; then
                fail_count=$((fail_count + 1))
                echo "[Heartbeat] Agent '$name' 健康检查失败 ($fail_count/$max_fail) ($(date '+%Y-%m-%d %H:%M:%S'))" >&2
                
                if [ $fail_count -ge $max_fail ]; then
                    # 连续失败 3 次，尝试重启 Agent
                    echo "[Heartbeat] Agent '$name' 无响应，正在重启..." >&2
                    tmux kill-session -t "$name" 2>/dev/null || true
                    sleep 2
                    tmux new-session -d -s "$name" -n serve \
                        "cd '$(get_work_dir "$name")' && opencode serve --port $port" 2>/dev/null || true
                    fail_count=0
                    cycle_count=0
                    echo "[Heartbeat] Agent '$name' 已重启 ($(date '+%Y-%m-%d %H:%M:%S'))" >&2
                fi
                continue
            else
                fail_count=0
            fi
            
            # 步骤 2: 发送心跳消息
            if [ "$is_master" = true ]; then
                # ============================================
                # Master 心跳: 给自己发 keepalive，防止无故停机
                # ============================================
                local keepalive_text="心跳检测：请检查是否有待处理的任务。如果当前没有任务或所有子 Agent 的任务已完成，无需响应，保持待机即可。"
                
                curl -s -X POST \
                    "${agent_url}/tui/append-prompt" \
                    -H "Content-Type: application/json" \
                    -d "{\"text\": \"$keepalive_text\"}" > /dev/null 2>&1 || true
                
                curl -s -X POST \
                    "${agent_url}/tui/submit-prompt" > /dev/null 2>&1 || true
                
                echo "[Heartbeat] Master keepalive sent #${cycle_count} ($(date '+%Y-%m-%d %H:%M:%S'))" >&2
            else
                # ============================================
                # Worker 心跳: 向 Master 汇报状态
                # ============================================
                local report_text="[Agent心跳] Agent: '${name}' (port: ${port}) 状态汇报: 运行正常。请 Master 检查是否有需要分配给我的新任务。"
                
                curl -s -X POST \
                    "${master_url}/tui/append-prompt" \
                    -H "Content-Type: application/json" \
                    -d "{\"text\": \"$report_text\"}" > /dev/null 2>&1 || true
                
                curl -s -X POST \
                    "${master_url}/tui/submit-prompt" > /dev/null 2>&1 || true
                
                echo "[Heartbeat] Agent '$name' reported to Master #${cycle_count} ($(date '+%Y-%m-%d %H:%M:%S'))" >&2
            fi
        done
        
        # 清理启动时间文件
        rm -f "$start_file"
    ) &
    
    # 保存 PID
    echo $! > "$pid_file"
    echo -e "  ${GREEN}心跳守护已启动 (PID: $!)${NC}"
    
    if [ "$is_master" = true ]; then
        echo -e "  ${BLUE}类型: Master 自心跳${NC}"
        echo -e "  ${BLUE}间隔: 5 分钟${NC}"
        echo -e "  ${BLUE}功能: 防止 Master 无故停机${NC}"
    else
        echo -e "  ${BLUE}类型: Worker 状态汇报${NC}"
        echo -e "  ${BLUE}间隔: 15 分钟${NC}"
        echo -e "  ${BLUE}目标: Master (port: ${DEFAULT_MASTER_PORT})${NC}"
        echo -e "  ${BLUE}功能: 定期向 Master 汇报状态${NC}"
    fi
}

# 停止心跳守护进程
stop_heartbeat() {
    local name="$1"
    local pid_file=$(get_heartbeat_pid_file "$name")
    
    if [ -f "$pid_file" ]; then
        local pid=$(cat "$pid_file" 2>/dev/null)
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            kill "$pid" 2>/dev/null || true
            wait "$pid" 2>/dev/null || true
        fi
        rm -f "$pid_file"
    fi
}

# ============================================
# 命令: start - 启动 Agent
# ============================================
cmd_start() {
    local name=""
    local workdir=""
    local port=""
    
    # 解析参数
    if [ $# -lt 1 ]; then
        echo -e "${RED}错误: 请指定 Agent 名称${NC}"
        echo "用法: ./agent.sh start <name> [--workdir <dir>] [--port <port>]"
        exit 1
    fi
    
    name="$1"
    shift
    
    # 解析可选参数
    while [ $# -gt 0 ]; do
        case "$1" in
            --workdir)
                workdir="$2"
                shift 2
                ;;
            --port)
                port="$2"
                shift 2
                ;;
            *)
                echo -e "${RED}错误: 未知参数 $1${NC}"
                exit 1
                ;;
        esac
    done
    
    # 使用默认值
    if [ -z "$workdir" ]; then
        workdir=$(get_work_dir "$name")
    fi
    
    if [ -z "$port" ]; then
        port=$(get_agent_port "$name")
    fi
    
    # 检查是否已运行
    if check_agent_running "$name"; then
        echo -e "${YELLOW}Agent '$name' 已经在运行 (port: $port)${NC}"
        echo -e "查看执行: ${BLUE}tmux attach -t $name${NC}"
        return 0
    fi
    
    # 创建工作目录
    mkdir -p "$workdir"
    echo -e "${BLUE}工作目录: $workdir${NC}"
    
    # 创建心跳说明文件（供 Agent 参考）
    create_heartbeat_info "$name" "$port" "$workdir"
    
    # 创建 tmux session 启动 opencode serve
    echo -e "${BLUE}启动 Agent '$name' (port: $port)...${NC}"
    tmux new-session -d -s "$name" -n serve \
        "cd '$workdir' && opencode serve --port $port" 2>/dev/null || {
        echo -e "${RED}错误: 启动 tmux session 失败${NC}"
        exit 1
    }
    
    # 等待服务启动
    local agent_url="${AGENT_BASE_URL}:${port}"
    echo -n "等待服务就绪"
    local retries=15
    local count=0
    while [ $count -lt $retries ]; do
        if curl -s "${agent_url}/global/health" > /dev/null 2>&1; then
            echo -e "\n${GREEN}Agent '$name' 启动成功！${NC}"
            echo -e "  服务地址: ${BLUE}$agent_url${NC}"
            echo -e "  工作目录: ${BLUE}$workdir${NC}"
            echo -e "  查看执行: ${BLUE}./agent.sh attach $name${NC}"
            
            # 启动心跳守护（防止 Agent 无故停止）
            start_heartbeat "$name" "$port"
            
            return 0
        fi
        echo -n "."
        sleep 1
        count=$((count + 1))
    done
    
    echo -e "\n${RED}错误: Agent 启动超时${NC}"
    echo -e "请检查日志: ${BLUE}tmux attach -t $name${NC}"
    exit 1
}

# ============================================
# 命令: stop - 停止 Agent
# ============================================
cmd_stop() {
    local name="$1"
    
    if [ -z "$name" ]; then
        echo -e "${RED}错误: 请指定 Agent 名称${NC}"
        echo "用法: ./agent.sh stop <name>"
        exit 1
    fi
    
    if ! check_agent_running "$name"; then
        echo -e "${YELLOW}Agent '$name' 未运行${NC}"
        return 0
    fi
    
    echo -e "${BLUE}停止 Agent '$name'...${NC}"
    
    # 先停止心跳守护
    stop_heartbeat "$name"
    
    tmux kill-session -t "$name" 2>/dev/null || true
    
    # 等待进程退出
    sleep 1
    if ! check_agent_running "$name"; then
        echo -e "${GREEN}Agent '$name' 已停止${NC}"
    else
        echo -e "${YELLOW}Agent '$name' 可能还在关闭中${NC}"
    fi
}

# ============================================
# 命令: send - 发送指令
# ============================================
cmd_send() {
    local name="$1"
    shift
    local instruction="$*"
    
    if [ -z "$name" ] || [ -z "$instruction" ]; then
        echo -e "${RED}错误: 请指定 Agent 名称和指令${NC}"
        echo "用法: ./agent.sh send <name> <instruction>"
        echo "示例: ./agent.sh send coder '写一个 Python 爬虫'"
        exit 1
    fi
    
    if ! check_agent_running "$name"; then
        echo -e "${RED}错误: Agent '$name' 未运行${NC}"
        echo -e "先启动: ${BLUE}./agent.sh start $name${NC}"
        exit 1
    fi
    
    local port=$(get_agent_port "$name")
    local agent_url="${AGENT_BASE_URL}:${port}"
    
    echo -e "${BLUE}发送指令到 '$name'...${NC}"
    
    # 1. 发送提示词
    local resp
    resp=$(curl -s -w "\n%{http_code}" -X POST \
        "${agent_url}/tui/append-prompt" \
        -H "Content-Type: application/json" \
        -d "{\"text\": \"$instruction\"}" 2>/dev/null)
    
    local http_code=$(echo "$resp" | tail -n1)
    
    if [ "$http_code" != "200" ]; then
        echo -e "${RED}错误: 发送指令失败 (HTTP $http_code)${NC}"
        exit 1
    fi
    
    # 2. 提交执行
    resp=$(curl -s -w "\n%{http_code}" -X POST \
        "${agent_url}/tui/submit-prompt" 2>/dev/null)
    
    http_code=$(echo "$resp" | tail -n1)
    
    if [ "$http_code" != "200" ]; then
        echo -e "${RED}错误: 提交执行失败 (HTTP $http_code)${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}指令已发送到 '$name'${NC}"
    echo -e "  指令: ${YELLOW}$instruction${NC}"
    echo -e "  查看: ${BLUE}./agent.sh attach $name${NC}"
}

# ============================================
# 命令: status - 查看状态
# ============================================
cmd_status() {
    local name="${1:-}"
    
    if [ -n "$name" ]; then
        # 查看单个 Agent
        local port=$(get_agent_port "$name")
        local agent_url="${AGENT_BASE_URL}:${port}"
        
        echo -e "${BLUE}Agent: $name${NC}"
        
        if check_agent_running "$name"; then
            echo -e "  状态: ${GREEN}运行中${NC}"
            
            # 检查 HTTP 服务
            if curl -s "${agent_url}/global/health" > /dev/null 2>&1; then
                echo -e "  HTTP: ${GREEN}正常${NC} (${agent_url})"
            else
                echo -e "  HTTP: ${RED}异常${NC} (${agent_url})"
            fi
        else
            echo -e "  状态: ${RED}未运行${NC}"
        fi
        
        echo -e "  端口: ${BLUE}$port${NC}"
        echo -e "  目录: ${BLUE}$(get_work_dir $name)${NC}"
        echo -e "  操作: ${BLUE}./agent.sh attach $name${NC}"
    else
        # 查看所有 Agent
        echo -e "${BLUE}Agent 状态列表:${NC}"
        echo ""
        
        local found=0
        for session in $(tmux list-sessions -F "#{session_name}" 2>/dev/null); do
            # 只显示 agents 目录下的 session
            local workdir=$(get_work_dir "$session")
            if [ -d "$workdir" ]; then
                local port=$(get_agent_port "$session")
                local agent_url="${AGENT_BASE_URL}:${port}"
                
                if curl -s "${agent_url}/global/health" > /dev/null 2>&1; then
                    echo -e "${GREEN}●${NC} $session (port: $port, HTTP: OK)"
                else
                    echo -e "${YELLOW}●${NC} $session (port: $port, HTTP: 异常)"
                fi
                found=1
            fi
        done
        
        if [ $found -eq 0 ]; then
            echo -e "${YELLOW}没有运行中的 Agent${NC}"
            echo -e "创建: ${BLUE}./agent.sh start <name>${NC}"
        fi
    fi
}

# ============================================
# 命令: list - 列出所有 Agent
# ============================================
cmd_list() {
    echo -e "${BLUE}已创建的 Agent:${NC}"
    echo ""
    
    if [ -d "$DEFAULT_BASE_DIR" ]; then
        for dir in "$DEFAULT_BASE_DIR"/*; do
            if [ -d "$dir" ]; then
                local name=$(basename "$dir")
                local port=$(get_agent_port "$name")
                
                if check_agent_running "$name"; then
                    echo -e "  ${GREEN}●${NC} $name (运行中, port: $port)"
                else
                    echo -e "  ${RED}○${NC} $name (已停止, port: $port)"
                fi
            fi
        done
    else
        echo -e "${YELLOW}没有已创建的 Agent${NC}"
    fi
}

# ============================================
# 命令: attach - 附加到 tmux session
# ============================================
cmd_attach() {
    local name="$1"
    
    if [ -z "$name" ]; then
        echo -e "${RED}错误: 请指定 Agent 名称${NC}"
        echo "用法: ./agent.sh attach <name>"
        exit 1
    fi
    
    if ! check_agent_running "$name"; then
        echo -e "${RED}错误: Agent '$name' 未运行${NC}"
        exit 1
    fi
    
    echo -e "${BLUE}正在附加到 Agent '$name'...${NC}"
    echo -e "${YELLOW}提示: 按 Ctrl+B 然后 D 退出（保留后台运行）${NC}"
    sleep 1
    tmux attach -t "$name"
}

# ============================================
# 命令: destroy - 销毁 Agent
# ============================================
cmd_destroy() {
    local name="$1"
    
    if [ -z "$name" ]; then
        echo -e "${RED}错误: 请指定 Agent 名称${NC}"
        echo "用法: ./agent.sh destroy <name>"
        exit 1
    fi
    
    local workdir=$(get_work_dir "$name")
    
    if check_agent_running "$name"; then
        echo -e "${YELLOW}Agent '$name' 正在运行，先停止...${NC}"
        cmd_stop "$name"
    fi
    
    if [ -d "$workdir" ]; then
        echo -e "${RED}删除工作目录: $workdir${NC}"
        read -p "确认删除? [y/N] " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            rm -rf "$workdir"
            echo -e "${GREEN}Agent '$name' 已销毁${NC}"
        else
            echo -e "${YELLOW}取消删除${NC}"
        fi
    else
        echo -e "${YELLOW}Agent '$name' 工作目录不存在${NC}"
    fi
}

# ============================================
# 帮助信息
# ============================================
show_help() {
    cat << 'EOF'
Agent 管理脚本 - CLI 版

用法:
  ./agent.sh <command> [options]

命令:
  start <name> [--workdir <dir>] [--port <port>]  创建并启动 Agent（自动启动心跳守护）
  stop <name>                                      停止 Agent（同时停止心跳守护）
  send <name> <instruction>                        发送指令到 Agent
  status [name]                                    查看 Agent 状态
  list                                             列出所有 Agent
  attach <name>                                    附加到 Agent 的 tmux session
  destroy <name>                                   销毁 Agent（停止并删除工作目录）

示例:
  # 启动一个名为 coder 的 Agent（自动启动心跳守护）
  ./agent.sh start coder --workdir ~/agents/coder

  # 发送指令
  ./agent.sh send coder "写一个 Python 爬虫"

  # 查看所有 Agent 状态
  ./agent.sh status

  # 进入 Agent 查看执行过程
  ./agent.sh attach coder

  # 停止 Agent（同时停止心跳守护）
  ./agent.sh stop coder

  # 销毁 Agent（删除工作目录）
  ./agent.sh destroy coder

双心跳机制:
  Master 自心跳 (每 5 分钟):
    - 检查自身健康 (/global/health)
    - 给自己发 keepalive 消息，防止无故停机
    - 消息: "请检查是否有待处理的任务，如无则保持待机"

  Worker 状态汇报 (每 15 分钟):
    - 检查自身健康 (/global/health)
    - 向 Master 汇报状态 (curl /tui/append-prompt)
    - 消息: "Agent 'xxx' 运行正常，请检查是否有新任务"
    - 连续 3 次无响应会自动重启 Agent

  停止 Agent 时自动停止心跳守护
  Worker Agent 工作目录会生成 HEARTBEAT.md 说明文件

注意事项:
  - Agent 默认工作目录: ~/agents/<name>
  - Agent 默认端口: 4097(master), 其他通过 hash 计算
  - Master 地址: http://localhost:4097
  - 需要提前安装 tmux 和 opencode

EOF
}

# ============================================
# 主入口
# ============================================
main() {
    if [ $# -lt 1 ]; then
        show_help
        exit 1
    fi
    
    local cmd="$1"
    shift
    
    case "$cmd" in
        start)
            cmd_start "$@"
            ;;
        stop)
            cmd_stop "$@"
            ;;
        send)
            cmd_send "$@"
            ;;
        status)
            cmd_status "$@"
            ;;
        list)
            cmd_list "$@"
            ;;
        attach)
            cmd_attach "$@"
            ;;
        destroy)
            cmd_destroy "$@"
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            echo -e "${RED}错误: 未知命令 '$cmd'${NC}"
            show_help
            exit 1
            ;;
    esac
}

main "$@"
