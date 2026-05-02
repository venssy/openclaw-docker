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


install_agent_reach() {
    if [ "${AGENT_REACH_ENABLED:-false}" != "true" ]; then
        return
    fi

    log_section "安装 Agent Reach"

    local github_url="https://github.com/Panniantong/agent-reach/archive/main.zip"
    local pip_mirror=""
    local pip_index_env=""

    if [ "${AGENT_REACH_USE_CN_MIRROR:-false}" = "true" ]; then
        github_url="https://gh.llkk.cc/https://github.com/Panniantong/agent-reach/archive/main.zip"
        pip_mirror="-i https://pypi.tuna.tsinghua.edu.cn/simple"
        pip_index_env="export PIP_INDEX_URL=https://pypi.tuna.tsinghua.edu.cn/simple"
    fi

    if test -f /root/.agent-reach-venv/bin/agent-reach; then
        local check_output
        check_output="$(bash -c "
            export PATH=\$PATH:/root/.local/bin
            $pip_index_env
            if [ -f ~/.agent-reach-venv/bin/activate ]; then
                source ~/.agent-reach-venv/bin/activate
            fi
            /root/.agent-reach-venv/bin/agent-reach check-update 2>&1 || true
        ")"
        echo "$check_output"

        if echo "$check_output" | grep -q '已是最新版本'; then
            echo "Agent Reach 已是最新版本，跳过安装步骤"
            return
        fi

        echo "Agent Reach 检测到可更新版本，开始自动更新..."
        bash -c "
            export PATH=\$PATH:/root/.local/bin
            $pip_index_env
            if [ -f ~/.agent-reach-venv/bin/activate ]; then
                source ~/.agent-reach-venv/bin/activate
            fi
            pip install --upgrade pip $pip_mirror
            pip install --upgrade $github_url $pip_mirror
        "
    else
        bash -c "
            export PATH=\$PATH:/root/.local/bin
            $pip_index_env
            if [ ! -d ~/.agent-reach-venv ]; then
                python3 -m venv ~/.agent-reach-venv
            fi
            source ~/.agent-reach-venv/bin/activate
            pip install --upgrade pip $pip_mirror
            pip install $github_url $pip_mirror
            agent-reach install --env=auto 
        "
    fi

    bash -c "
        export PATH=\$PATH:/root/.local/bin
        $pip_index_env
        if [ -f ~/.agent-reach-venv/bin/activate ]; then
            source ~/.agent-reach-venv/bin/activate
        fi

        # 配置代理（如果提供）
        if [ -n \"\$AGENT_REACH_PROXY\" ]; then
            agent-reach configure proxy \"\$AGENT_REACH_PROXY\"
        fi

        # 配置 Twitter Cookies
        if [ -n \"\$AGENT_REACH_TWITTER_COOKIES\" ]; then
            agent-reach configure twitter-cookies \"\$AGENT_REACH_TWITTER_COOKIES\"
        fi

        # 配置 Groq Key
        if [ -n \"\$AGENT_REACH_GROQ_KEY\" ]; then
            agent-reach configure groq-key \"\$AGENT_REACH_GROQ_KEY\"
        fi
        
        # 配置小红书 Cookies
        if [ -n \"\$AGENT_REACH_XHS_COOKIES\" ]; then
            agent-reach configure xhs-cookies \"\$AGENT_REACH_XHS_COOKIES\"
        fi
    "
    
    # 建立软链接到 /usr/local/bin 以便全局访问（如果需要）
    # 但我们已经在 setup_runtime_env 中处理了 PATH

    # 检查工作空间父目录下的 skills 目录中是否存在 agent-reach，若存在则同步到工作空间（仅删除目标 SKILL.md 并覆盖）
    local workspace_parent
    workspace_parent="$(dirname "$OPENCLAW_WORKSPACE")"
    if [ -d "$workspace_parent/skills/agent-reach" ]; then
        local src="$workspace_parent/skills/agent-reach"
        local dst="$OPENCLAW_WORKSPACE/skills/agent-reach"
        echo "检测到 $src，正在将其同步到工作空间: $dst"
        mkdir -p "$dst"
        rm -f "$dst/SKILL.md"
        cp -af "$src/." "$dst/" || true
        rm -rf "$src"
        if is_root; then
            chown -R node:node "$dst" || true
        fi
    fi
}

start_gateway() {
    log_section "启动 OpenClaw Gateway"

    env HOME=/root DBUS_SESSION_BUS_ADDRESS=/dev/null \
        BUN_INSTALL="/usr/local" AGENT_REACH_HOME="/root/.agent-reach" AGENT_REACH_VENV_HOME="/root/.agent-reach-venv" \
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

start_clawpanel() {
  cd /clawpanel && node scripts/serve.js &
  cd /root
}

HERMES_HOME="${HERMES_HOME:-/opt/data}"
INSTALL_DIR="/opt/hermes"

start_hermes() {
  
# --- Running as hermes from here ---
source "${INSTALL_DIR}/.venv/bin/activate"

# Create essential directory structure.  Cache and platform directories
# (cache/images, cache/audio, platforms/whatsapp, etc.) are created on
# demand by the application — don't pre-create them here so new installs
# get the consolidated layout from get_hermes_dir().
# The "home/" subdirectory is a per-profile HOME for subprocesses (git,
# ssh, gh, npm …).  Without it those tools write to /root which is
# ephemeral and shared across profiles.  See issue #4426.
mkdir -p "$HERMES_HOME"/{cron,sessions,logs,hooks,memories,skills,skins,plans,workspace,home}

# .env
if [ ! -f "$HERMES_HOME/.env" ]; then
    cp "$INSTALL_DIR/.env.example" "$HERMES_HOME/.env"
fi

# config.yaml
if [ ! -f "$HERMES_HOME/config.yaml" ]; then
    cp "$INSTALL_DIR/cli-config.yaml.example" "$HERMES_HOME/config.yaml"
fi

# SOUL.md
if [ ! -f "$HERMES_HOME/SOUL.md" ]; then
    cp "$INSTALL_DIR/docker/SOUL.md" "$HERMES_HOME/SOUL.md"
fi

# Sync bundled skills (manifest-based so user edits are preserved)
if [ -d "$INSTALL_DIR/skills" ]; then
    python3 "$INSTALL_DIR/tools/skills_sync.py"
fi

hermes gateway run &
}

main() {
    log_section "OpenClaw start"

    for dr in ".config" ".tmux"; do
        if [ -d "/root/$dr" ]; then
          mv "/root/$dr" "/root/$dr".bak
        fi

        ln -s $OPENCLAW_HOME/$dr /root/$dr
    done

    setup_runtime_env
    install_agent_reach
    
    start_gateway
    start_hermes
    start_clawpanel

    wait_for_gateway
}

main
