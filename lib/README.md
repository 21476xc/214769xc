# lib 说明

`lib/jiuguan.ps1` 和 `lib/jiuguan.sh` 承载两套平台实现的共享行为。两边函数名不完全相同，但能力需要保持一致：

- 路径初始化：默认安装在用户目录下的 `jiuguan`。
- 依赖检测：Git、Node.js 18+、npm。
- 网络策略：官方源优先，npm 失败时切换 npmmirror，Git 仓库可通过环境变量覆盖。
- SillyTavern 管理：安装、更新、启动、停止、重启、状态、日志。
- 数据保护：更新前备份，支持手动备份和恢复。
- 卸载策略：默认只卸载管理工具，用户数据需要显式 `--delete-data` 才删除。

新增命令时，请同时更新：

- `bin/jiuguan.ps1`
- `bin/jiuguan.sh`
- `README.md`