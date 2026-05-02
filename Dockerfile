FROM node:22-slim AS clawpanel-builder

# 安装构建依赖
RUN apk add --no-cache \
    git \
    python3 \
    make \
    g++

RUN git clone https://github.com/qingchencloud/clawpanel /tmp/clawpanel

WORKDIR /build

# 复制项目文件
RUN cp /tmp/clawpanel/package*.json ./
RUN cp /tmp/clawpanel/vite.config.js ./
RUN cp /tmp/clawpanel/index.html ./
RUN cp -r /tmp/clawpanel/scripts/ ./scripts/
RUN cp -r /tmp/clawpanel/src/ ./src/

# 安装依赖并构建
RUN npm ci --prefer-offline --registry https://registry.npmmirror.com && \
    npm run build

FROM node:22-slim

COPY --from=python:3.12-slim-bookworm /usr/local /usr/local

WORKDIR /root
ENV HOME=/root

# 设置环境变量
ENV BUN_INSTALL="/usr/local" \
    PATH="/usr/local/cuda-13/bin:/usr/local/bin:$PATH" \
    DEBIAN_FRONTEND=noninteractive \
    LD_LIBRARY_PATH="/usr/local/cuda-13/lib64:$PATH" \
    XDG_CONFIG_HOME="/root/.openclaw/agents/main/qmd/xdg-config" \
    XDG_CACHE_HOME="/root/.openclaw/agents/main/qmd/xdg-cache"

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    bash ca-certificates chromium curl docker.io build-essential ffmpeg \
    fonts-liberation fonts-noto-cjk fonts-noto-color-emoji git jq locales \
    openssh-client procps socat tini unzip gnupg2 tmux && \
    # 添加CUDA源
    curl -fsSL https://developer.download.nvidia.com/compute/cuda/repos/debian12/x86_64/3bf863cc.pub | gpg --dearmor -o /usr/share/keyrings/nvidia-cuda-keyring.gpg && \
    echo "deb [signed-by=/usr/share/keyrings/nvidia-cuda-keyring.gpg] https://developer.download.nvidia.com/compute/cuda/repos/debian12/x86_64/ /" > /etc/apt/sources.list.d/cuda.list && \
    apt update && apt install -y --no-install-recommends \
    cuda-nvcc-13-1 libcudnn9-dev-cuda-13 cuda-toolkit-13-1 && \
    
    sed -i 's/^# *en_US.UTF-8 UTF-8$/en_US.UTF-8 UTF-8/' /etc/locale.gen && \
    locale-gen && \
    # update-locale 在部分 slim 基础镜像中会返回 invalid locale settings，这里改为直接写入默认 locale 配置
    printf 'LANG=en_US.UTF-8\nLANGUAGE=en_US:en\nLC_ALL=en_US.UTF-8\n' > /etc/default/locale && \
    # 配置 git 使用 HTTPS 替代 SSH
    git config --system url."https://github.com/".insteadOf ssh://git@github.com/ && \
    
    # 设置 npm 镜像并安装全局包
    npm config set registry https://registry.npmmirror.com && \
    npm install -g openclaw opencode-ai@latest clawhub playwright playwright-extra \
                   puppeteer-extra-plugin-stealth @steipete/bird \
                   acpx@latest @anthropic-ai/claude-code @openai/codex @openai/codex-sdk && \
    
    # 安装 bun、uv 和 qmd
    curl -fsSL https://bun.sh/install | BUN_INSTALL=/usr/local bash && \
    curl -LsSf https://astral.sh/uv/install.sh | env UV_INSTALL_DIR=/usr/local/bin sh && \
    
    # 建立 python3 -> python 链接并安装 websockify
    ln -sf /usr/local/bin/python3 /usr/local/bin/python && \
    /usr/local/bin/python3 -m pip install --no-cache-dir websockify && \

    npm install -g @tobilu/qmd && \
    sed -i 's#hf:ggml-org/embeddinggemma-300M-GGUF/embeddinggemma-300M-Q8_0.gguf#hf:chienweichang/jina-embeddings-v2-base-zh-GGUF/jina-embeddings-v2-base-zh-q8_0.gguf#;s#hf:tobil/qmd-query-expansion-1.7B-gguf/qmd-query-expansion-1.7B-q4_k_m.gguf#hf:Qwen/Qwen2.5-0.5B-Instruct-GGUF/qwen2.5-0.5b-instruct-q4_k_m.gguf#' /usr/local/lib/node_modules/@tobilu/qmd/dist/llm.js && \

    # 安装 Playwright 浏览器依赖
    npx playwright install chromium --with-deps && \

    # 清理 apt 缓存
    apt-get purge -y --auto-remove && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /root/.npm /root/.cache


# 安装linuxbrew（Homebrew 的 Linux 版本），并配置环境变量
RUN mkdir -p /root/.linuxbrew/Homebrew && \
    git clone --depth 1 https://github.com/Homebrew/brew /root/.linuxbrew/Homebrew && \
    mkdir -p /root/.linuxbrew/bin && \
    ln -s /root/.linuxbrew/Homebrew/bin/brew /root/.linuxbrew/bin/brew && \
    chmod -R g+rwX /root/.linuxbrew

WORKDIR /clawpanel

# 复制clawpanel
COPY --from=builder /build/dist ./dist
COPY --from=builder /build/scripts ./scripts
COPY --from=builder /build/package*.json ./
COPY --from=builder /build/node_modules ./node_modules

WORKDIR /root

COPY ./init.sh /usr/local/bin/init.sh
RUN sed -i 's/\r$//' /usr/local/bin/init.sh && \
    chmod +x /usr/local/bin/init.sh


# 设置环境变量
ENV HOME=/root \
    TERM=xterm-256color \
    NODE_PATH=/usr/local/lib/node_modules \
    LANG=en_US.UTF-8 \
    LANGUAGE=en_US:en \
    LC_ALL=en_US.UTF-8 \
    NODE_ENV=production \
    PATH="/root/.openclaw/extensions/node_modules/.bin:/root/.linuxbrew/bin:/root/.linuxbrew/sbin:/usr/local/lib/node_modules/.bin:${PATH}" \
    HOMEBREW_NO_AUTO_UPDATE=1 \
    HOMEBREW_NO_INSTALL_CLEANUP=1

# 暴露端口
EXPOSE 18789

# 使用初始化脚本作为入口点
ENTRYPOINT ["/bin/bash", "/usr/local/bin/init.sh"]
