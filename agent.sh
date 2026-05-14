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

# ============================================
# 心跳守护进程 - 防止 Agent 无故停止
# ============================================
start_heartbeat() {
    local name="$1"
    local port="$2"
    local pid_file=$(get_heartbeat_pid_file "$name")
    
    # 如果已有心跳进程在运行，先停止
    stop_heartbeat "$name" 2>/dev/null || true
    
    # 启动后台心跳进程
    (
        local agent_url="${AGENT_BASE_URL}:${port}"
        local fail_count=0
        local max_fail=3
        
        while true; do
            sleep 30
            
            # 检查 tmux session 是否存在
            if ! tmux has-session -t "$name" 2>/dev/null; then
                # Agent 已停止，退出心跳
                break
            fi
            
            # 发送健康检查请求
            if ! curl -s "${agent_url}/global/health" > /dev/null 2>&1; then
                fail_count=$((fail_count + 1))
                if [ $fail_count -ge $max_fail ]; then
                    # 连续失败 3 次，尝试重启 Agent
                    echo "[Heartbeat] Agent '$name' 无响应，正在重启..." >&2
                    tmux kill-session -t "$name" 2>/dev/null || true
                    sleep 2
                    tmux new-session -d -s "$name" -n serve \
                        "cd '$(get_work_dir "$name")' && opencode serve --port $port" 2>/dev/null || true
                    fail_count=0
                fi
            else
                fail_count=0
            fi
        done
    ) &
    
    # 保存 PID
    echo $! > "$pid_file"
    echo -e "  ${GREEN}心跳守护已启动 (PID: $!)${NC}"
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

心跳守护:
  - 启动 Agent 时自动启动心跳守护进程
  - 每 30 秒检查一次 Agent 健康状态
  - 连续 3 次无响应会自动重启 Agent
  - 停止 Agent 时自动停止心跳守护

注意事项:
  - Agent 默认工作目录: ~/agents/<name>
  - Agent 默认端口: 4097(master), 其他通过 hash 计算
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
