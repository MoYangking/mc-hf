"""统一入口：同时启动“同步守护进程 + Web 管理页面”。

运行效果：
- 后台线程运行同步守护：自动初始化/拉取/对齐、迁移与符号链接、空目录跟踪、周期提交推送；
- 主线程运行 Web 管理页面：端口 5321，前缀 `/sync`（包含状态展示和手动操作）。
"""

import threading
import time

from sync.daemon import SyncDaemon
from sync.server import serve


def run_all() -> int:
    """拉起守护线程，并在主线程启动 Web 服务。

    若缺少 Web 依赖（例如 Python 3.6 无法安装 fastapi/uvicorn），将仅运行守护进程并阻塞主线程，避免进程退出。
    """
    daemon = SyncDaemon()
    t = threading.Thread(target=daemon.run, daemon=True)
    t.start()
    # 在主线程启动 Web 服务，若不可用则返回后保持阻塞
    code = serve(daemon=daemon)
    if code != 0:
        # 无 Web 时保持前台阻塞，确保 supervisord 看到进程存活
        while True:
            time.sleep(3600)
    return code
