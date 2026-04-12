# 使用构建参数指定基础镜像
ARG BASE_IMAGE=ghcr.io/openclaw/openclaw:latest
FROM ${BASE_IMAGE}

USER root

RUN apt update && apt install -y --no-install-recommends \
    git curl ca-certificates gnupg2 python3 python3-pip cmake g++ && \
    # 添加CUDA源
    curl -fsSL https://developer.download.nvidia.com/compute/cuda/repos/debian12/x86_64/3bf863cc.pub | gpg --dearmor -o /usr/share/keyrings/nvidia-cuda-keyring.gpg && \
    echo "deb [signed-by=/usr/share/keyrings/nvidia-cuda-keyring.gpg] https://developer.download.nvidia.com/compute/cuda/repos/debian12/x86_64/ /" > /etc/apt/sources.list.d/cuda.list && \
    apt update && apt install -y --no-install-recommends cuda-nvcc-13-1 libcudnn9-dev-cuda-13 cuda-toolkit-13-1 && \
    rm -rf /var/lib/apt/lists/*

ENV PATH="/usr/local/cuda-13/bin:$PATH"
ENV LD_LIBRARY_PATH="/usr/local/cuda-13/lib64:$PATH"

    # 安装bun和ModelScope SDK
# RUN curl -fsSL https://bun.sh/install | bash

# RUN mv /usr/local/bin/qmd /usr/local/bin/qmd.bak && \
#     bun install -g https://github.com/tobi/qmd
#    git clone https://github.com/tobi/qmd.git /qmd && cd /qmd && \
#    bun install && bun run build -- --cuda && \
#    rm -rf /qmd

# ENV NODE_LLAMA_CPP_GPU=false

ENV XDG_CONFIG_HOME="/home/node/.openclaw/agents/main/qmd/xdg-config" \
    XDG_CACHE_HOME="/home/node/.openclaw/agents/main/qmd/xdg-cache"

# RUN export PATH="/usr/local/cuda-13/bin:$PATH" && npm install -g qmd && sed -i 's#hf:ggml-org/embeddinggemma-300M-GGUF/embeddinggemma-300M-Q8_0.gguf#hf:chienweichang/jina-embeddings-v2-base-zh-GGUF/jina-embeddings-v2-base-zh-q8_0.gguf#;s#hf:tobil/qmd-query-expansion-1.7B-gguf/qmd-query-expansion-1.7B-q4_k_m.gguf#hf:Qwen/Qwen2.5-0.5B-Instruct-GGUF/qwen2.5-0.5b-instruct-q4_k_m.gguf#' /usr/local/lib/node_modules/@tobilu/qmd/dist/llm.js

RUN npm install -g mcporter pnpm acpx@latest @anthropic-ai/claude-code @openai/codex @openai/codex-sdk && \
    cd /usr/local/lib/node_modules/openclaw/dist/extensions/acpx && \
    npm install acpx

# RUN curl -fsSL https://claude.ai/install.sh | bash

RUN npm config set registry https://registry.npmmirror.com/

ENV PATH="$PATH:/root/.openclaw/extensions/node_modules/.bin"

# RUN mkdir test && cd test && echo hello > test.md && qmd status && qmd collection add . --name test && qmd embed && qmd query "hello"