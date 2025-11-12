# syntax=docker/dockerfile:1.7-labs
FROM ghcr.io/itzg/minecraft-server:java21-graalvm

ARG TARGETOS=linux
ARG TARGETARCH=amd64
ARG TARGETVARIANT=
ARG FRP_VERSION=v0.65.0

USER root

# 安装 supervisord + envsubst + python3；创建目录并放宽权限（不使用 /etc）
RUN set -eux; \
    if command -v apt-get >/dev/null 2>&1; then \
      apt-get update && apt-get install -y --no-install-recommends supervisor gettext-base ca-certificates curl python3 python3-pip && \
      rm -rf /var/lib/apt/lists/*; \
    elif command -v microdnf >/dev/null 2>&1; then \
      microdnf install -y supervisor gettext ca-certificates curl python3 python3-pip && microdnf clean all; \
    else \
      echo "Unsupported base for package install"; exit 1; \
    fi; \
    mkdir -p /home/user/supervisor /home/user/run /home/user/frp /home/user/logs /home/user/web /data /tmp; \
    chmod -R 777 /home/user /data /tmp

# 下载并安装 frp 到 /usr/local/bin（运行期以普通用户执行）
RUN set -eux; \
    case "${TARGETARCH}${TARGETVARIANT}" in \
      amd64)   FRP_ARCH=amd64 ;; \
      arm64*)  FRP_ARCH=arm64 ;; \
      armv7)   FRP_ARCH=arm ;; \
      arm)     FRP_ARCH=arm ;; \
      *)       FRP_ARCH=amd64 ;; \
    esac; \
    FRP_BALL="frp_${FRP_VERSION#v}_${TARGETOS}_${FRP_ARCH}.tar.gz"; \
    curl -fsSL "https://github.com/fatedier/frp/releases/download/${FRP_VERSION}/${FRP_BALL}" -o /tmp/frp.tgz; \
    tar -xzf /tmp/frp.tgz -C /tmp; \
    FRP_DIR="/tmp/frp_${FRP_VERSION#v}_${TARGETOS}_${FRP_ARCH}"; \
    install -m 0755 "${FRP_DIR}/frpc" /usr/local/bin/frpc || true; \
    install -m 0755 "${FRP_DIR}/frps" /usr/local/bin/frps || true; \
    rm -rf /tmp/frp.tgz "${FRP_DIR}"

# 拷贝配置到 /home/user（不使用 /etc）
COPY supervisord.conf /home/user/supervisor/supervisord.conf
COPY frpc.toml.template /home/user/frp/frpc.toml.template
COPY frp-entry.sh /home/user/frp/frp-entry.sh
COPY requirements.txt /home/user/requirements.txt
COPY web/ /home/user/web/

# 安装Python依赖
RUN pip3 install --no-cache-dir -r /home/user/requirements.txt

# 再次放宽权限，确保普通用户可写
RUN chmod -R 777 /home/user /data && chmod +x /home/user/frp/frp-entry.sh

# 切换为普通用户；运行期不使用 root
RUN useradd -m -d /home/user -s /bin/bash user || true && chmod -R 777 /home/user
USER user

# 以我们自己的配置启动 supervisord（不读 /etc）
ENTRYPOINT ["supervisord","-n","-c","/home/user/supervisor/supervisord.conf"]

EXPOSE 25565 7860
