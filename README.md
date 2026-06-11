# claude-code-resilient-wrapper

一个用 `expect` 包住 [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code) 的弹性 wrapper：当 Claude Code 报出 socket 断开 / 网络异常 / 5xx / `overloaded_error` / 429 等可恢复错误时，自动向 PTY 注入「继续」二字，让长任务从断点续上，不需要你手工按键。

适合的场景：让 Claude Code 跑长时间任务（深度搜索、批量改动、workflow 等），中途遇到瞬时 API 抖动还能自动续。

![demo](./docs/demo.gif)

> 如果上面 GIF 没显示，是因为我还没把演示素材录上去 —— 见 [docs/README.md](./docs/README.md) 里的录制说明，欢迎 PR 一段。

## 它解决什么问题

跑长任务时偶发的 API 报错会把对话停在一个尴尬的中间态：模型已经想清楚下一步、工具调用甚至发出去一半，然后 socket 一断，turn 就废了。重新进对话只是 resume 当前会话的尾部，工具结果丢了；想接着干就得手动打「继续」唤醒模型。

这个 wrapper 在终端层做这件事：监听 Claude Code 输出，一旦匹配到典型的可恢复错误，等几秒，自动 `send "继续\r"`。模型大多数情况能从 stuck 的那一步继续往下推。

## 为什么不直接改 Claude Code？

因为这是个**外部封装**，不依赖 Claude Code 内部的任何机制：
- 不需要修改 Claude Code 源码或配置
- 不需要写 hook
- Claude Code 升级也不会影响 wrapper
- 出问题随时 `unfunction claude` 就能绕开

代价是它对 Claude Code 的输出格式有耦合（依赖错误信息文本中的 `API Error:` 等关键字）。如果将来 Claude Code 改了报错措辞，需要回来更新正则。

## 工作原理

```
┌─────────────────┐    ┌──────────────────────────┐    ┌─────────────┐
│  你的终端 (TTY) │ ⇄  │  expect (双向 interact)  │ ⇄  │  claude CLI │
└─────────────────┘    └──────────────────────────┘    └─────────────┘
                                  │
                                  │  匹配 "API Error: ..."
                                  ▼
                          等 3-30s 后注入「继续\r」
```

关键点：用 `expect` 的 `interact -o` 块做**双向透明转发**——只在 Claude → 屏幕方向匹配错误正则，绝不打断你 → Claude 的正常输入。早期单向 `expect/-eof` 实现会卡住 TUI 启动协商（ANSI 序列泄露、按键无响应），切到 `interact` 模式才解决。

## 监听的错误模式

| 类型 | 触发关键字 | 等待时间 |
|---|---|---|
| `socket` | `socket connection was closed` / `socket hang up` / `ECONNRESET` 等 | 3s |
| `network` | `ETIMEDOUT` / `ENOTFOUND` / `fetch failed` / `getaddrinfo` 等 | 3-5s |
| `5xx` | `API Error: 5xx` / `upstream connect error` / `upstream timeout` | 5s |
| `overload` | `overloaded_error` / `overloaded` / `capacity exceeded` | 10s |
| `rate_limit` | `API Error: 429` / `rate limit` | 30s |
| 兜底 | 任何 `API Error:` 行 | 仅记日志，不注入 |

兜底那条不会自动续，只写到日志里——你可以根据日志补充新的错误模式。

## 安装

### 依赖

- macOS / Linux
- `expect`（macOS：`brew install expect`；Debian/Ubuntu：`apt install expect`）
- 已经能在终端跑 `claude` 命令（[Claude Code 官方安装](https://docs.anthropic.com/en/docs/claude-code/quickstart)）

### 一键安装

```bash
git clone https://github.com/gaoshuping99/claude-code-resilient-wrapper.git
cd claude-code-resilient-wrapper
./install.sh
```

安装脚本会：
1. 把 `bin/claude-resilient.exp` 复制到 `~/.local/bin/`
2. 在你的 `~/.zshrc`（或 `~/.bashrc`）追加一段 `claude` shell function，让你以后直接敲 `claude` 就走 wrapper
3. 备份原有 rc 文件到 `~/.zshrc.backup-<时间戳>`

### 手动安装

```bash
# 1. 把脚本放到 PATH 里
mkdir -p ~/.local/bin
cp bin/claude-resilient.exp ~/.local/bin/
chmod +x ~/.local/bin/claude-resilient.exp

# 2. 在 ~/.zshrc 末尾加：
cat >> ~/.zshrc <<'EOF'

# ===== claude resilient wrapper =====
claude() {
    # 非交互式快速命令绕过 wrapper（interact 模式吞瞬时输出）
    case "$1" in
        --version|-v|--help|-h)
            command claude "$@"
            return $?
            ;;
    esac
    if [[ -x ~/.local/bin/claude-resilient.exp ]]; then
        ~/.local/bin/claude-resilient.exp "$@"
    else
        command claude "$@"
    fi
}
EOF

# 3. 重新 source
source ~/.zshrc
```

## 使用

正常用就行，wrapper 完全透明：

```bash
claude              # 启动新对话
claude -c           # 继续最近对话
claude --version    # 这种快速命令会直接走真二进制，跳过 wrapper
```

应急绕过：

```bash
unfunction claude   # 当前 shell 临时禁用
command claude      # 一次性绕过 shell function
```

## 怎么知道 wrapper 在工作？

**触发时**屏幕上会冒出：

```
[claude-resilient] 命中 'socket' 错误，匹配片段: API Error: socket connection was closed unexpectedly...
[claude-resilient] 第 1 次自动续 (3s 后注入「继续」)
```

**事件日志**：`~/.claude/logs/claude-resilient.log`

```
2026-06-11 10:52:13 spawned claude pid=exp6
2026-06-11 11:14:27 match kind=socket retry=1 snippet=API Error: socket connection was closed...
2026-06-11 11:14:30 injected '继续' to PTY
```

**调试模式**：开启全量 stdout 镜像（文件会很大，调试完记得关）

```bash
CLAUDE_RESILIENT_TRACE=1 claude
# 输出落到 ~/.claude/logs/claude-resilient-trace.log
```

## 配置（环境变量）

| 变量 | 作用 | 默认 |
|---|---|---|
| `CLAUDE_BIN` | 指定真实 claude 二进制路径 | 自动从 PATH 探测，回退到 `/opt/homebrew/bin/claude` 等常见位置 |
| `CLAUDE_RESILIENT_TRACE` | 设为 `1` 时把 spawned 输出全量镜像到 trace 日志 | 关 |

脚本内部还有几个常量可以改（直接编辑 `claude-resilient.exp`）：

```tcl
set max_retries 50            # 最大重试次数
set min_gap_seconds 2         # 同种错误的去重窗口
```

## 已知限制

- **错误识别基于文本匹配**：Claude Code 改了报错措辞就需要更新正则。仓库里的兜底逻辑会把"未识别的 API Error"写日志，方便你回过来补。
- **注入「继续」是中文**：因为目前我让 Claude 主要用中文工作。如果你用英文，把脚本里 `send -- "继续\r"` 改成 `send -- "continue\r"` 即可。
- **无法救已经退出的 turn**：如果 Claude Code 自己把 turn 判定为终止（比如 token 用尽），wrapper 没法救，它只能让 stuck 的 turn 续上。
- **interact 模式吞瞬时输出**：所以 `--version` 这类一次性命令会被 shell function 直接转给真二进制，不走 wrapper。
- **macOS / Linux only**：Windows 没测过；理论上 WSL 可用。

## 文件结构

```
.
├── bin/
│   └── claude-resilient.exp     # 主脚本（expect/Tcl）
├── install.sh                   # 安装脚本
├── LICENSE                      # MIT
└── README.md
```

## 卸载

```bash
# 1. 删脚本
rm ~/.local/bin/claude-resilient.exp

# 2. 从 ~/.zshrc 里删掉 "claude resilient wrapper" 那个 function 段
#    （或恢复 install.sh 留下的 ~/.zshrc.backup-<时间戳>）
```

## 贡献

欢迎 PR——尤其是：
- 新错误模式的正则
- bash / fish 安装脚本
- Windows / WSL 适配

提 issue 时贴一下 `~/.claude/logs/claude-resilient.log` 里相关时间段的内容，帮助定位。

## License

MIT — 详见 [LICENSE](./LICENSE)。
