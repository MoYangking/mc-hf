# syntax=docker/dockerfile:1.7-labs
FROM ghcr.io/itzg/minecraft-server:java21-graalvm

ARG TARGETOS=linux
ARG TARGETARCH=amd64
ARG TARGETVARIANT=
ARG FRP_VERSION=v0.65.0
ARG FB_ADMIN_USER=admin
ARG FB_ADMIN_PASS=adminadminadmin
ARG GOTTY_VERSION=1.6.0

USER root

# 安装 supervisord + envsubst + python3 + git；创建目录并放宽权限（不使用 /etc）
RUN set -eux; \
    if command -v apt-get >/dev/null 2>&1; then \
      apt-get update && apt-get install -y --no-install-recommends supervisor gettext-base ca-certificates curl jq git gnupg lsb-release python3 python3-pip python3-venv && \
      rm -rf /var/lib/apt/lists/*; \
    elif command -v microdnf >/dev/null 2>&1; then \
      microdnf install -y supervisor gettext ca-certificates curl jq python3 python3-pip && microdnf clean all; \
    else \
      echo "Unsupported base for package install"; exit 1; \
    fi; \
    mkdir -p /home/user/supervisor /home/user/run /home/user/frp /home/user/logs /data /tmp; \
    chmod -R 777 /home/user /data /tmp

# 统一提供 Python >=3.10（某些发行版默认仅有 3.6，会触发 __future__.annotations 语法错误）
# 逻辑：若系统 python3 版本 <3.10，则安装 Miniforge，并将其放到 PATH 与 /usr/local/bin 覆盖系统 python3
RUN set -eux; \
    PYV=$(python3 -c 'import sys; print("%d.%d" % sys.version_info[:2])' 2>/dev/null || echo "0.0"); \
    MAJOR=${PYV%%.*}; MINOR=${PYV##*.}; \
    if [ "${MAJOR}" -lt 3 ] || [ "${MINOR}" -lt 10 ]; then \
      echo "Installing Miniforge (Python >=3.10) to /opt/conda..."; \
      ARCH=$(uname -m); \
      case "$ARCH" in \
        x86_64) MF=Miniforge3-Linux-x86_64.sh ;; \
        aarch64) MF=Miniforge3-Linux-aarch64.sh ;; \
        ppc64le) MF=Miniforge3-Linux-ppc64le.sh ;; \
        *) MF=Miniforge3-Linux-x86_64.sh ;; \
      esac; \
      curl -fsSL "https://github.com/conda-forge/miniforge/releases/latest/download/${MF}" -o /tmp/miniforge.sh; \
      bash /tmp/miniforge.sh -b -p /opt/conda; \
      rm -f /tmp/miniforge.sh; \
      ln -sf /opt/conda/bin/python /usr/local/bin/python3; \
      ln -sf /opt/conda/bin/pip /usr/local/bin/pip3; \
      /usr/local/bin/python3 -V; \
    fi

# Python 3.6 兼容：按需安装 dataclasses 回填包
RUN python3 - <<'PY'
import sys, subprocess
if sys.version_info < (3,7):
    subprocess.check_call([sys.executable, '-m', 'pip', 'install', '--no-cache-dir', 'dataclasses<0.9'])
PY

# 安装 OpenResty（内置 LuaJIT/ngx_lua），以支持动态路由的 nginx.conf
RUN set -eux; \
    if command -v apt-get >/dev/null 2>&1; then \
      . /etc/os-release; \
      curl -fsSL https://openresty.org/package/pubkey.gpg | gpg --dearmor -o /usr/share/keyrings/openresty.gpg; \
      if [ "${ID:-ubuntu}" = "ubuntu" ]; then DIST=ubuntu; else DIST=debian; fi; \
      echo "deb [signed-by=/usr/share/keyrings/openresty.gpg] http://openresty.org/package/${DIST} $(lsb_release -sc) main" > /etc/apt/sources.list.d/openresty.list; \
      apt-get update && apt-get install -y --no-install-recommends openresty && rm -rf /var/lib/apt/lists/*; \
      mkdir -p /etc/nginx && ln -sf /usr/local/openresty/nginx/conf/mime.types /etc/nginx/mime.types; \
    elif command -v microdnf >/dev/null 2>&1 || command -v dnf >/dev/null 2>&1 || command -v yum >/dev/null 2>&1; then \
      . /etc/os-release; \
      if [ "${ID}" = "fedora" ]; then OS_PATH=fedora; else OS_PATH=centos; fi; \
      printf '%s\n' \
        '[openresty]' \
        'name=Official OpenResty Open Source Repository' \
        "baseurl=https://openresty.org/package/${OS_PATH}/"'$releasever/$basearch' \
        'gpgcheck=1' \
        'enabled=1' \
        'gpgkey=https://openresty.org/package/pubkey.gpg' \
        > /etc/yum.repos.d/openresty.repo; \
      if command -v microdnf >/dev/null 2>&1; then \
        microdnf install -y openresty && microdnf clean all; \
      elif command -v dnf >/dev/null 2>&1; then \
        dnf install -y openresty && dnf clean all; \
      else \
        yum install -y openresty && yum clean all; \
      fi; \
      mkdir -p /etc/nginx && ln -sf /usr/local/openresty/nginx/conf/mime.types /etc/nginx/mime.types; \
    else \
      echo "OpenResty install not implemented for this base image" >&2; exit 1; \
    fi

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


COPY --chown=1000:1000 frpc.toml.template /home/user/frp/frpc.toml.template
COPY --chown=1000:1000 frp-entry.sh /home/user/frp/frp-entry.sh

# Supervisor and Nginx config + logs
RUN mkdir -p /home/user/logs && chown -R 1000:1000 /home/user/logs
COPY --chown=1000:1000 supervisor/supervisord.conf /home/user/supervisord.conf
RUN mkdir -p /home/user/nginx && chown -R 1000:1000 /home/user/nginx
COPY --chown=1000:1000 nginx/nginx.conf /home/user/nginx/nginx.conf
COPY --chown=1000:1000 nginx/default_admin_config.json /home/user/nginx/default_admin_config.json
COPY --chown=1000:1000 nginx/route-admin /home/user/nginx/route-admin
RUN mkdir -p \
      /home/user/nginx/tmp/body \
      /home/user/nginx/tmp/proxy \
      /home/user/nginx/tmp/fastcgi \
      /home/user/nginx/tmp/uwsgi \
      /home/user/nginx/tmp/scgi \
    && chown -R 1000:1000 /home/user/nginx

# Sync service (daemon + web)
COPY --chown=1000:1000 sync /home/user/sync
RUN chown -R 1000:1000 /home/user/sync


# NapCat runtime dirs and launcher
RUN mkdir -p /home/user/scripts && chown -R 1000:1000 /home/user/scripts
COPY --chown=1000:1000 scripts/wait-sync-ready.sh /home/user/scripts/wait-sync-ready.sh
RUN chmod +x /home/user/scripts/wait-sync-ready.sh
 
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
    /home/user/filebrowser config init --address 0.0.0.0 --port 8000 --root /data --database /home/user/filebrowser.db; \
    if [ "${#FB_ADMIN_PASS}" -lt 12 ]; then echo "ERROR: FB_ADMIN_PASS must be at least 12 characters" >&2; exit 1; fi; \
    /home/user/filebrowser users add "${FB_ADMIN_USER}" "${FB_ADMIN_PASS}" --perm.admin --database /home/user/filebrowser.db

# 再次放宽权限，确保普通用户可写
RUN mkdir -p /home/user/nginx/tmp/body /home/user/nginx/tmp/proxy /home/user/nginx/tmp/fastcgi /home/user/nginx/tmp/uwsgi /home/user/nginx/tmp/scgi && \
    chmod -R 777 /home/user/nginx && \
    chmod -R 777 /home/user /data && chmod +x /home/user/frp/frp-entry.sh /home/user/filebrowser

RUN python3 -m pip install --no-cache-dir --upgrade pip
RUN python3 -m pip install --no-cache-dir fastapi uvicorn[standard]

## Install GoTTY lightweight web terminal
RUN set -eux; \
    case "${TARGETARCH}${TARGETVARIANT}" in \
      amd64)   G_ARCH=linux_amd64 ;; \
      *)       echo "[gotty] Unsupported arch: ${TARGETARCH}${TARGETVARIANT}, skipping install" >&2; G_ARCH="" ;; \
    esac; \
    if [ -n "$G_ARCH" ]; then \
      curl -fsSL "https://github.com/sorenisanerd/gotty/releases/download/v${GOTTY_VERSION}/gotty_v${GOTTY_VERSION}_${G_ARCH}.tar.gz" -o /tmp/gotty.tgz && \
      tar -xzf /tmp/gotty.tgz -C /tmp && \
      install -m 0755 /tmp/gotty /home/user/gotty || { cp /tmp/gotty /home/user/gotty && chmod 0755 /home/user/gotty; } && \
      chown 1000:1000 /home/user/gotty && \
      rm -f /tmp/gotty.tgz /tmp/gotty; \
    fi

RUN set -eux; \
    mkdir -p /home/user/.git-backup/data; \
    rm -rf /data; \
    ln -sfnT /home/user/.git-backup/data /data
RUN chmod -R 777 /home/user/.git-backup/data

# 切换为普通用户；运行期不使用 root
RUN useradd -m -d /home/user -s /bin/bash user || true && chmod -R 777 /home/user
#USER user


# 以我们自己的配置启动 supervisord（不读 /etc）
ENTRYPOINT ["supervisord","-n","-c","/home/user/supervisord.conf"]

# 确保优先使用我们安装的 Python（如已安装 Miniforge），并保留 OpenResty 在 PATH 中
ENV PATH=/opt/conda/bin:/usr/local/openresty/bin:$PATH

EXPOSE 7860
