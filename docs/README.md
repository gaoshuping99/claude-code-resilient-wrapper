# 演示素材录制说明

`demo.gif` 用来在仓库首页直观展示 wrapper 接管 API 报错的过程。

## 想看到什么

一个理想的演示 GIF（10–15 秒）应当包含：

1. 终端里启动 `claude` 跑一个长任务
2. 屏幕上出现一行 `API Error: ...`（socket / 5xx / overloaded_error）
3. wrapper 立刻打印两行黄字：
   ```
   [claude-resilient] 命中 'socket' 错误，匹配片段: ...
   [claude-resilient] 第 1 次自动续 (3s 后注入「继续」)
   ```
4. 几秒后 Claude 自己回到上下文，继续往下推

## 推荐录制工具

| 工具 | 平台 | 备注 |
|---|---|---|
| [asciinema](https://asciinema.org/) + [agg](https://github.com/asciinema/agg) | macOS / Linux | 文本录制，文件极小，转 GIF 清晰 |
| [`vhs`](https://github.com/charmbracelet/vhs) | 跨平台 | 用脚本声明式录制，输出可复现 |
| Kap / LICEcap | macOS | 直接录屏，体积稍大 |

**推荐 asciinema → agg 流程：**

```bash
# 1. 录制
asciinema rec demo.cast

# 2. 在录制窗口里复现报错（参考下文"如何复现报错"）

# 3. 退出录制（Ctrl-D）

# 4. 转 GIF
agg --speed 1.5 --font-size 16 demo.cast demo.gif
```

## 如何在录制时复现报错

让 Claude 命中真实 API 错误不可控；建议在脚本里**伪造**一段 stdout 给 wrapper 看，专门做演示。在仓库根目录跑：

```bash
# 用 fake-claude 假装是 claude 进程，故意在 stdout 输出一行 "API Error: socket hang up"
cat > /tmp/fake-claude.sh <<'SH'
#!/usr/bin/env bash
echo "正在分析仓库..."
sleep 2
echo "调用工具 Read..."
sleep 2
echo "API Error: socket hang up"
sleep 4
echo "继续"   # 模拟模型恢复
sleep 1
echo "✓ 任务完成"
SH
chmod +x /tmp/fake-claude.sh

# 让 wrapper 跑这个假 claude
CLAUDE_BIN=/tmp/fake-claude.sh ./bin/claude-resilient.exp
```

`CLAUDE_BIN` 环境变量是 wrapper 内置的，会替代真实 claude 二进制；非常适合演示和回归测试。

## 提交 PR

录好的 `demo.gif` 放到 `docs/demo.gif`，提 PR 即可。文件建议 < 2 MB（首页加载体验）。如果太大，可以用 [gifsicle](https://www.lcdf.org/gifsicle/) 压：

```bash
gifsicle -O3 --lossy=80 demo.gif -o demo.gif
```
