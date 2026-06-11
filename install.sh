#!/usr/bin/env bash
# claude-code-resilient-wrapper installer
#
# 1. 复制 bin/claude-resilient.exp 到 ~/.local/bin/
# 2. 在你的 shell rc（zsh / bash）里追加 claude shell function
# 3. 备份原 rc 到 ~/.<rc>.backup-<时间戳>

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_SRC="$REPO_DIR/bin/claude-resilient.exp"
BIN_DIR="$HOME/.local/bin"
SCRIPT_DST="$BIN_DIR/claude-resilient.exp"

# ---- 检查 expect ----
if ! command -v expect >/dev/null 2>&1; then
    echo "✗ 未找到 expect。请先安装：" >&2
    echo "    macOS:        brew install expect" >&2
    echo "    Debian/Ubuntu: sudo apt install expect" >&2
    exit 1
fi

# ---- 检查 claude ----
if ! command -v claude >/dev/null 2>&1; then
    echo "✗ 未找到 claude 二进制。请先安装 Claude Code:" >&2
    echo "    https://docs.anthropic.com/en/docs/claude-code/quickstart" >&2
    exit 1
fi

# ---- 复制脚本 ----
mkdir -p "$BIN_DIR"
cp "$SCRIPT_SRC" "$SCRIPT_DST"
chmod +x "$SCRIPT_DST"
echo "✓ 安装脚本到 $SCRIPT_DST"

# ---- 选 rc 文件 ----
if [[ -n "${ZSH_VERSION:-}" ]] || [[ "$(basename "${SHELL:-}")" == "zsh" ]]; then
    RC_FILE="$HOME/.zshrc"
elif [[ -n "${BASH_VERSION:-}" ]] || [[ "$(basename "${SHELL:-}")" == "bash" ]]; then
    RC_FILE="$HOME/.bashrc"
else
    echo "✗ 不支持的 shell: ${SHELL:-unknown}。请按 README 手动安装。" >&2
    exit 1
fi

# ---- 检查是否已安装 ----
MARKER="# ===== claude resilient wrapper ====="
if [[ -f "$RC_FILE" ]] && grep -qF "$MARKER" "$RC_FILE"; then
    echo "ℹ $RC_FILE 里已经有 wrapper 段，跳过追加"
    echo "  如需重装：先手工删掉那段，再跑本脚本"
    exit 0
fi

# ---- 备份 rc ----
if [[ -f "$RC_FILE" ]]; then
    BACKUP="$RC_FILE.backup-$(date +%Y%m%d-%H%M%S)"
    cp "$RC_FILE" "$BACKUP"
    echo "✓ 备份 $RC_FILE → $BACKUP"
fi

# ---- 追加 function ----
cat >> "$RC_FILE" <<'EOF'

# ===== claude resilient wrapper =====
# https://github.com/gaoshuping99/claude-code-resilient-wrapper
# 把 claude 命令挂到 wrapper 上：API 报错时自动注入「继续」恢复 turn。
claude() {
    # 非交互式快速命令绕过 wrapper（interact 模式吞瞬时输出）
    case "$1" in
        --version|-v|--help|-h)
            command claude "$@"
            return $?
            ;;
    esac
    if [[ -x "$HOME/.local/bin/claude-resilient.exp" ]]; then
        "$HOME/.local/bin/claude-resilient.exp" "$@"
    else
        command claude "$@"
    fi
}
EOF

echo "✓ 已追加 claude function 到 $RC_FILE"
echo ""
echo "下一步：重新加载 shell 配置"
echo "    source $RC_FILE"
echo ""
echo "或者直接开新终端窗口。然后用 claude 启动即可。"
echo ""
echo "查看事件日志：tail -f ~/.claude/logs/claude-resilient.log"
echo "应急绕过：    unfunction claude  # 当前 shell 临时禁用"
