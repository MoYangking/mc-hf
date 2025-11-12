#!/usr/bin/env bash
set -euo pipefail

# Entry script to run either official frpc (TOML) or sakura-frpc (-f token:nodeid)
# Switch via env var FRP_IMPL: "frpc" (default) or "sakura"

IMPL="${FRP_IMPL:-frpc}"
WORKDIR="/home/user/frp"

case "${IMPL}" in
  frpc|toml)
    # Render TOML from template and run official frpc
    if [[ ! -f "${WORKDIR}/frpc.toml.template" ]]; then
      echo "frpc.toml.template not found in ${WORKDIR}" >&2
      exit 1
    fi
    mkdir -p "${WORKDIR}"
    envsubst < "${WORKDIR}/frpc.toml.template" > "${WORKDIR}/frpc.toml"
    exec frpc -c "${WORKDIR}/frpc.toml"
    ;;

  sakura|sakura-frpc)
    # Download sakura-frpc (amd64) on first run and execute with -f token:nodeid
    mkdir -p "${WORKDIR}"
    BIN="${WORKDIR}/frpc_sakura"
    if [[ ! -x "${BIN}" ]]; then
      echo "Downloading sakura-frpc binary (linux amd64)..."
      curl -fsSL "https://nya.globalslb.net/natfrp/client/frpc/0.51.0-sakura-12.3/frpc_linux_amd64" -o "${BIN}"
      chmod +x "${BIN}"
    fi

    AUTH="${FRP_AUTH:-}"
    if [[ -z "${AUTH}" ]]; then
      echo "ERROR: FRP_IMPL=sakura requires FRP_AUTH set to 'token:nodeid' (e.g. 9685g0r...:24152888)" >&2
      exit 1
    fi

    # Allow extra flags via FRP_ARGS (optional)
    ARGS="${FRP_ARGS:-}"
    exec "${BIN}" -f "${AUTH}" ${ARGS}
    ;;

  *)
    echo "Unknown FRP_IMPL: ${IMPL}. Use 'frpc' or 'sakura'." >&2
    exit 1
    ;;
esac

