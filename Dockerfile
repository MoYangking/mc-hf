# syntax=docker/dockerfile:1.7-labs
FROM ghcr.io/itzg/minecraft-server:java21-graalvm

ARG TARGETOS=linux
ARG TARGETARCH=amd64
ARG TARGETVARIANT=
ARG FRP_VERSION=v0.65.0
ARG FB_ADMIN_USER=admin
ARG FB_ADMIN_PASS=adminadminadmin

USER root

# 安装 supervisord + envsubst + python3；创建目录并放宽权限（不使用 /etc）
RUN set -eux; \
    if command -v apt-get >/dev/null 2>&1; then \
      apt-get update && apt-get install -y --no-install-recommends supervisor gettext-base ca-certificates curl jq python3 python3-pip python3-venv && \
      rm -rf /var/lib/apt/lists/*; \
    elif command -v microdnf >/dev/null 2>&1; then \
      microdnf install -y supervisor gettext ca-certificates curl jq python3 python3-pip && microdnf clean all; \
      else \
      echo "Unsupported base for package install"; exit 1; \
    fi; \
    mkdir -p /home/user/supervisor /home/user/run /home/user/frp /home/user/logs /data /tmp; \
    chmod -R 777 /home/user /data /tmp

# 下载并安装 frp 到 /usr/local/bin（运行期以普通用户执行）
RUN set -eux; \
    case "${TARGETARCH}${TARGETVARIANT}" in \
      amd64)   FRP_ARCH=amd64 ;; \
      arm64*)  FRP_ARCH=arm64 ;; \
      armv7)   FRP_ARCH=arm ;; \
      arm)     FRP_ARCH=arm ;; \
      386)     FRP_ARCH=386 ;; \
      *)       FRP_ARCH=amd64 ;; \
    esac; \
    LATEST_URL=$(curl -sL https://api.github.com/repos/fatedier/frp/releases/latest | jq -r --arg os "${TARGETOS}" --arg arch "${FRP_ARCH}" '.assets[] | select(.name | endswith("_\($os)_\($arch).tar.gz")) | .browser_download_url' | head -1); \
    [ -n "$LATEST_URL" ] || { echo "Failed to determine latest frp asset for ${TARGETOS}/${FRP_ARCH}" >&2; exit 1; }; \
    curl -fsSL "$LATEST_URL" -o /tmp/frp.tgz; \
    FRP_DIR=$(tar -tzf /tmp/frp.tgz | head -1 | cut -d/ -f1); \
    tar -xzf /tmp/frp.tgz -C /tmp; \
    install -m 0755 "/tmp/${FRP_DIR}/frpc" /usr/local/bin/frpc || true; \
    install -m 0755 "/tmp/${FRP_DIR}/frps" /usr/local/bin/frps || true; \
    rm -rf /tmp/frp.tgz "/tmp/${FRP_DIR}"

# 拷贝配置到 /home/user（不使用 /etc）
COPY supervisord.conf /home/user/supervisor/supervisord.conf
COPY frpc.toml.template /home/user/frp/frpc.toml.template
COPY frp-entry.sh /home/user/frp/frp-entry.sh
 
# 安装 filebrowser 二进制到 /home/user，并通过 GitHub API 获取最新版本；初始化管理员(admin/admin)
RUN set -eux; \
    case "${TARGETARCH}${TARGETVARIANT}" in \
      amd64)   FB_ARCH=amd64 ;; \
      arm64*)  FB_ARCH=arm64 ;; \
      armv7)   FB_ARCH=armv7 ;; \
      armv6)   FB_ARCH=armv6 ;; \
      arm)     FB_ARCH=armv7 ;; \
      386)     FB_ARCH=386 ;; \
      riscv64) FB_ARCH=riscv64 ;; \
      *)       FB_ARCH=amd64 ;; \
    esac; \
    LATEST_URL=$(curl -sL https://api.github.com/repos/filebrowser/filebrowser/releases/latest | jq -r --arg arch "${FB_ARCH}" '.assets[] | select(.name == "linux-\($arch)-filebrowser.tar.gz") | .browser_download_url' | head -1); \
    [ -n "$LATEST_URL" ] || { echo "Failed to determine latest filebrowser asset for arch: ${FB_ARCH}" >&2; exit 1; }; \
    curl -fsSL "$LATEST_URL" -o /tmp/fb.tgz; \
    tar -xzf /tmp/fb.tgz -C /tmp; \
    install -m 0755 /tmp/filebrowser /home/user/filebrowser || { cp /tmp/filebrowser /home/user/filebrowser && chmod 0755 /home/user/filebrowser; }; \
    rm -f /tmp/fb.tgz /tmp/filebrowser; \
    /home/user/filebrowser config init --address 0.0.0.0 --port 7860 --root /data --database /home/user/filebrowser.db; \
    if [ "${#FB_ADMIN_PASS}" -lt 12 ]; then echo "ERROR: FB_ADMIN_PASS must be at least 12 characters" >&2; exit 1; fi; \
    /home/user/filebrowser users add "${FB_ADMIN_USER}" "${FB_ADMIN_PASS}" --perm.admin --database /home/user/filebrowser.db

# 再次放宽权限，确保普通用户可写
RUN chmod -R 777 /home/user /data && chmod +x /home/user/frp/frp-entry.sh /home/user/filebrowser

# 切换为普通用户；运行期不使用 root
RUN useradd -m -d /home/user -s /bin/bash user || true && chmod -R 777 /home/user
USER user

# 以我们自己的配置启动 supervisord（不读 /etc）
ENTRYPOINT ["supervisord","-n","-c","/home/user/supervisor/supervisord.conf"]

EXPOSE 25565 7860
