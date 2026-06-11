# Release notes

## v0.1.0 — 2026-06-11

首个公开版本。

### 功能

- **PTY 弹性 wrapper**：用 `expect` 的 `interact -o` 模式包住 `claude` CLI，监听 spawned→屏幕方向的输出，命中可恢复错误时自动注入「继续」让 turn 续上。双向透明转发，对 TUI 无感。
- **覆盖的错误模式**（默认正则）：
  - `socket`：socket close / hang up / ECONNRESET / ECONNREFUSED / ECONNABORTED — 等 3s
  - `network`：ETIMEDOUT / ENOTFOUND / EAI_AGAIN / fetch failed — 等 3–5s
  - `5xx`：`API Error: 5xx` / upstream connect/timeout — 等 5s
  - `overload`：`overloaded_error` / capacity exceeded — 等 10s
  - `rate_limit`：`API Error: 429` / `rate limit` — 等 30s
  - 兜底：未分类 `API Error:` 行只写日志，不注入
- **同种错误 2 秒去重**：防刷屏（按 kind 分桶，不同 kind 不互相影响）
- **重试限额**：默认 50 次封顶，防代理彻底挂时无限重试
- **路径自动探测**：优先 `CLAUDE_BIN` 环境变量 → `which -a claude`（排除自身防递归）→ 常见 brew 路径
- **快速命令直通**：`claude --version` / `--help` 这类一次性命令不走 wrapper（interact 模式会吞瞬时输出）
- **事件日志**：`~/.claude/logs/claude-resilient.log` 默认开启，记录 spawn / 命中 / 注入 / 退出
- **trace 模式**：`CLAUDE_RESILIENT_TRACE=1` 镜像全量 stdout 到独立日志（调试用）

### 安装

- `install.sh` — zsh / bash 双 rc 自动识别，备份旧 rc 到 `~/.<rc>.backup-<时间戳>`，幂等（重跑会跳过已安装）
- 检测 `expect` 和 `claude` 缺失并给出提示

### CI

- **lint**：`bash -n install.sh` + `shellcheck install.sh` + `tclsh info-complete` Tcl 块完整性 + 可执行位检查
- **smoke**：用 `CLAUDE_BIN` 把真实 claude 替换成假脚本（输出 `API Error: socket hang up`），通过 `script(1)` 分配 PTY 跑 wrapper，断言：
  1. wrapper 屏幕上能匹配到错误模式
  2. 「继续」字符串确实送到了子进程 stdin

### 已知限制

- 错误识别基于文本正则，Claude Code 改报错措辞需要更新
- 注入文案是中文「继续」；英文用户需把脚本里 `send -- "继续\r"` 改成 `send -- "continue\r"`
- 仅在 macOS（Apple Silicon）和 Linux（Ubuntu CI runner）验证，Windows 未测
- demo.gif 占位待补 — 见 [docs/README.md](./docs/README.md)
