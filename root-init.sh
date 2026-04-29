#!/bin/bash

set -e

OPENCLAW_HOME="/root/.openclaw"
OPENCLAW_WORKSPACE_ROOT="${OPENCLAW_WORKSPACE_ROOT:-$OPENCLAW_HOME}"
OPENCLAW_WORKSPACE_ROOT="${OPENCLAW_WORKSPACE_ROOT%/}"
OPENCLAW_WORKSPACE="${OPENCLAW_WORKSPACE_ROOT}/workspace"
NODE_UID="$(id -u node)"
NODE_GID="$(id -g node)"
GATEWAY_PID=""

log_section() {
    echo "=== $1 ==="
}

setup_runtime_env() {
    export BUN_INSTALL="/usr/local"
    export PATH="$BUN_INSTALL/bin:$PATH"
    export AGENT_REACH_HOME="/root/.agent-reach"
    export AGENT_REACH_VENV_HOME="/root/.agent-reach-venv"
    export PATH="$AGENT_REACH_HOME/bin:$PATH"
    
    if [ -d "$AGENT_REACH_VENV_HOME/bin" ]; then
        export PATH="$AGENT_REACH_VENV_HOME/bin:$PATH"
    fi

    # 创建一个全局包装脚本，确保交互式 shell 也能直接使用 agent-reach
    if [ -x "$AGENT_REACH_VENV_HOME/bin/agent-reach" ]; then
        cat > /usr/local/bin/agent-reach <<EOF
#!/bin/bash
source $AGENT_REACH_VENV_HOME/bin/activate
exec $AGENT_REACH_VENV_HOME/bin/agent-reach "\$@"
EOF
        chmod +x /usr/local/bin/agent-reach
    fi
    
    export DBUS_SESSION_BUS_ADDRESS=/dev/null
}

start_gateway() {
    log_section "启动 OpenClaw Gateway"

    gosu node env HOME=/root DBUS_SESSION_BUS_ADDRESS=/dev/null \
        BUN_INSTALL="/usr/local" AGENT_REACH_HOME="/root/.agent-reach" AGENT_REACH_VENV_HOME="/home/node/.agent-reach-venv" \
        PATH="/root/.agent-reach-venv/bin:/usr/local/bin:$PATH" \
        openclaw gateway run \
        --bind "$OPENCLAW_GATEWAY_BIND" \
        --port "$OPENCLAW_GATEWAY_PORT" \
        --token "$OPENCLAW_GATEWAY_TOKEN" \
        --verbose &
    GATEWAY_PID=$!

    echo "=== OpenClaw Gateway 已启动 (PID: $GATEWAY_PID) ==="
}

wait_for_gateway() {
    wait "$GATEWAY_PID"
    local exit_code=$?
    echo "=== OpenClaw Gateway 已退出 (退出码: $exit_code) ==="
    exit "$exit_code"
}

main() {
    log_section "OpenClaw start"
    setup_runtime_env
    ln -s /root/.config $OPENCLAW_HOME/.config
    start_gateway
    wait_for_gateway
}

main
