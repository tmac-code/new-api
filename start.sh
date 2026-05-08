#!/usr/bin/env bash
# ==========================================
# New API 生产环境启动脚本 (跨主机非 Docker 版)
# ==========================================
# 用法: ./start.sh {start|stop|restart|status|logs|daemon|check} [实例 ID]
# ==========================================

set -e

# --- 配置区 ---
APP_NAME="new-api"
WORK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_FILE="$WORK_DIR/new-api"
ENV_FILE="$WORK_DIR/.env"
PID_DIR="$WORK_DIR/pids"
LOG_DIR="$WORK_DIR/logs"

# 颜色
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO] $(date +%H:%M:%S)${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN] $(date +%H:%M:%S)${NC} $1"; }
log_error() { echo -e "${RED}[ERROR] $(date +%H:%M:%S)${NC} $1"; }

# --- 核心功能 ---

init_dirs() { mkdir -p "$PID_DIR" "$LOG_DIR"; }

# 验证关键环境变量
validate_env() {
    local instance_id=$1
    local suffix=${instance_id:+-$instance_id}
    local target_env="$ENV_FILE"
    
    # 优先加载 .env.{id}
    [ -n "$instance_id" ] && [ -f "$WORK_DIR/.env.$instance_id" ] && target_env="$WORK_DIR/.env.$instance_id"

    log_info "Loading config: $target_env"
    if [ -f "$target_env" ]; then
        export $(grep -v '^#' "$target_env" | grep -v '^$' | xargs)
    fi

    local fail=0
    [ -z "$SQL_DSN" ] && log_error "Missing: SQL_DSN" && fail=1
    [ -z "$SESSION_SECRET" ] && log_error "Missing: SESSION_SECRET" && fail=1
    
    if [ "$fail" -eq 1 ]; then
        log_error "Environment check failed."
        return 1
    fi
    # 处理端口
    export PORT="${PORT:-3000}"
    
    # 非 Docker 跨主机部署，需要确认端口可用（简单检查）
    if command -v ss &>/dev/null; then
        if ss -tuln | grep -q ":$PORT\b"; then
            log_warn "Port $PORT is already in use!"
        fi
    fi
}

get_suffix() { [ -n "$1" ] && echo "-$1" || echo ""; }

get_pid() {
    local pid_file="$PID_DIR/$APP_NAME$(get_suffix $1).pid"
    [ -f "$pid_file" ] && cat "$pid_file" || echo ""
}

is_running() { [ -n "$1" ] && ps -p "$1" > /dev/null 2>&1; }

# 启动主程序 (单次运行)
run_app() {
    local instance_id=$1
    local suffix=$(get_suffix $instance_id)
    
    # 1. 加载与校验
    validate_env "$instance_id" || return 1

    local pid_file="$PID_DIR/$APP_NAME${suffix}.pid"
    local log_file="$LOG_DIR/$APP_NAME${suffix}.log"
    local err_log="$LOG_DIR/$APP_NAME${suffix}-err.log"

    # 2. 清理死锁 ID
    local old_pid=$(get_pid "$instance_id")
    if [ -n "$old_pid" ] && ! is_running "$old_pid"; then
        rm -f "$pid_file"
    fi

    # 3. 检查运行状态
    if is_running "$old_pid"; then
        log_error "Instance${suffix} ALREADY RUNNING (PID: $old_pid)"
        exit 1
    fi

    # 4. 启动进程
    log_info "Starting Instance${suffix} on $PORT..."
    nohup "$BIN_FILE" >> "$log_file" 2>> "$err_log" &
    local new_pid=$!
    echo "$new_pid" > "$pid_file"
    log_info "Instance${suffix} spawned (PID: $new_pid)"

    # 5. 短暂停留确认存活
    sleep 3
    if is_running "$new_pid"; then
        log_info "Instance${suffix} UP and healthy."
    else
        log_error "Instance${suffix} CRASHED immediately!"
        tail -n 20 "$err_log"
        exit 1
    fi
}

# 停止程序
stop_app() {
    local instance_id=$1
    local suffix=$(get_suffix $instance_id)
    local pid_file="$PID_DIR/$APP_NAME${suffix}.pid"
    local pid=$(get_pid "$instance_id")

    if ! is_running "$pid"; then
        log_warn "Instance${suffix} NOT running (Stale PID file removed)"
        rm -f "$pid_file"
        return 0
    fi

    log_info "Stopping Instance${suffix} (PID: $pid)..."
    kill "$pid"

    # 优雅等待 (最多 15s)
    local count=0
    while [ $count -lt 15 ] && is_running "$pid"; do
        sleep 1
        count=$((count+1))
    done

    if is_running "$pid"; then
        log_warn "Force killing PID: $pid"
        kill -9 "$pid"
    fi
    rm -f "$pid_file"
    log_info "Instance${suffix} stopped."
}

# 守护模式 (崩溃自动重启)
run_daemon() {
    local instance_id=$1
    local suffix=$(get_suffix $instance_id)
    local pid_file="$PID_DIR/$APP_NAME${suffix}.pid"

    # 防止重复启动 daemon
    local old_pid=$(get_pid "$instance_id")
    if is_running "$old_pid"; then
        # 判断是否是守护进程父壳 (通过 ps 检查)
        # 简化处理：如果 PID 文件存在就认为在运行
        log_error "Instance${suffix} is already running."
        exit 1
    fi
    rm -f "$pid_file"
    
    # PID 写入当前 shell
    echo $$ > "$pid_file"

    log_warn "Entering DAEMON mode for Instance${suffix}. (Ctrl+C to stop)"
    
    # 捕获信号以便清理 PID
    trap "rm -f $pid_file; exit 1" INT TERM

    while true; do
        log_warn "Starting subprocess..."
        run_app "$instance_id" &
        local child_pid=$!
        
        # 等待子进程退出
        wait $child_pid
        local code=$?
        
        log_warn "Instance${suffix} exited with $code. Restarting in 5s..."
        sleep 5
    done
}

# 工具命令
status_app() {
    local pid=$(get_pid $1)
    local suffix=$(get_suffix $1)
    if is_running "$pid"; then
        log_info "Instance${suffix} RUNNING (PID: $pid)"
        ps -p $pid -o pid,pcpu,pmem,rss,etime 2>/dev/null || true
    else
        log_error "Instance${suffix} STOPPED"
    fi
}

logs_app() {
    local suffix=$(get_suffix $1)
    local log_file="$LOG_DIR/$APP_NAME${suffix}.log"
    [ -f "$log_file" ] && tail -f "$log_file" || log_error "No logs."
}

# --- 交互入口 ---

ACTION=${1:-"help"}
ID=${2:-""}

case $ACTION in
    start)   init_dirs && run_app "$ID" ;;
    stop)    stop_app "$ID" ;;
    restart) stop_app "$ID"; sleep 2; init_dirs && run_app "$ID" ;;
    status)  status_app "$ID" ;;
    logs)    logs_app "$ID" ;;
    daemon)  init_dirs && run_daemon "$ID" ;;
    check)   init_dirs && validate_env "$ID" ;;
    *)
        echo -e "Usage: $0 {start|stop|restart|status|logs|daemon|check} [id]"
        ;;
esac
