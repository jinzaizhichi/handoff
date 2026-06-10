# 阶段 2：多 backend 架构（claude 型 / codex 型）

> 执行者：Opus 4.8 agent
> 前置：阶段 1 已合入（命令已叫 `handoff`，包结构已就位）。
> 本阶段是整个迁移中唯一需要设计判断的部分。先读 CLAUDE.md 的 Architecture 一节再动手。

## 目标

handoff 目前只会拉起 `claude -p`（指向任意 anthropic 兼容端点）。本阶段引入 backend
`type` 概念，使 `codex exec` 成为第二种执行引擎，并暴露 `--backend` 标志。完成后：

```bash
handoff run --backend deepseek --text "..."   # 现状路径，行为不变
handoff run --backend codex --text "..."      # 新：经 codex exec 执行
handoff run --backend opus --text "..."       # 新：claude 型 + 官方端点 + opus 模型
handoff resume <seq> --text "..."             # 对三种 backend 都能续接
```

## 0. 前置调研（写进 docs/design notes 或 PR 描述，结论决定后面实现）

用本机已安装的 `codex` CLI 实测确认（不要凭记忆写代码）：

1. `codex exec` 的机器可读输出：`--json` 输出哪些事件类型？最终结果文本和
   session/thread id 分别在哪个事件里？
2. 非交互续接：`codex exec resume <id>` 是否存在、id 用哪个、续接是否 fork
   （决定我们能否像 claude 一样用首次 id 做稳定句柄；若 fork，需要在每轮续接后
   更新 runs 表的 session_id —— claude 路径不变，仍用首次 id）。
3. 免确认执行用哪个旗标（`--full-auto` / `--dangerously-bypass-approvals-and-sandbox` 等），
   与我们的用例（独立 cwd 全自动干活）匹配的最小权限组合。
4. 是否需要 PTY 包装（claude 路径需要 `script -q /dev/null`；codex exec 可能不需要）。

## 1. 配置 schema（cli/default_config.yaml + cli/config.py）

设计原则：**两层 deep-merge（内置默认 → `~/.handoff/config.yaml`）机制保留不动**；
重构的是各层装什么——内置默认必须开箱可用，用户文件的最小形态只剩 token。

现状的三个结构性问题，本节逐一修复：
(a) `default_model`/`pro_model` 是全局顶层键，多 backend 下必须下沉为每个 backend 的字段，
`{model}`/`{pro_model}` 占位符改为按 backend 解析（全局 `{default_model}` 占位符废除）；
(b) `backend_template` 把 DeepSeek 的 `ANTHROPIC_BASE_URL` 烤死在模板里——type 级共性
（CLI 怎么拉起：flag 数组、PTY、env 变量名）与 backend 实例个性（端点、token、模型）要拆开；
(c) `_validate` 强制用户 config 定义 backends——删除，内置默认已含可用 backend。

新 `default_config.yaml` 结构：

```yaml
default_backend: deepseek
system_prompt: |
  （原文保留）

type_defaults:        # type 级共性：CLI 如何被拉起。高级用户可整体覆盖
  claude:             # 现 backend_template 的内容平移至此，但去掉 ANTHROPIC_BASE_URL
    command: claude   # 和 AUTH_TOKEN；ANTHROPIC_DEFAULT_*_MODEL 等映射改用 {model}/{pro_model}
    pty: [script, -q, /dev/null]
    env: { ... }
    session_flags: [ ... ]
    session_id_flags: [ ... ]
    continue_id_flags: [ ... ]
    resume_flags: [ ... ]
  codex:              # 按第 0 节调研结论填写
    command: codex
    ...

backends:             # 三个内置实例，开箱可用
  deepseek:
    type: claude
    model: deepseek-v4-flash
    pro_model: "deepseek-v4-pro[1m]"
    env:
      ANTHROPIC_BASE_URL: https://api.deepseek.com/anthropic
      ANTHROPIC_AUTH_TOKEN: "${DEEPSEEK_API_KEY}"   # 见下方 env 插值
  opus:               # 无 env 覆盖 — 走本机 claude 登录态，零配置可用
    type: claude
    model: claude-opus-4-8
    pro_model: claude-opus-4-8
  codex:              # 走本机 codex 登录态，零配置可用
    type: codex
    model: gpt-5.5
    pro_model: gpt-5.5
```

- 合并顺序：`type_defaults[<type>]` → 内置 `backends.<name>` → 用户 config 同名深合并覆盖。
  深合并实现沿用现有 `_deep_merge`；列表是整体替换语义（不拼接）——这是有意的，写进配置文档。
- **新增 `${ENV_VAR}` 插值**：配置字符串值在 backend 解析时展开 `${...}` 环境变量；
  未设置时展开为空串（随后被 `ensure_backend_token_ready` 拦下，报错信息要提示两种配法）。
  token 检查只对实际需要 token 的 backend 生效（opus/codex 走登录态，跳过）。
- `init` 生成的用户 config 样板相应缩水：注释 + deepseek token 一段即可
  （或注明用 `DEEPSEEK_API_KEY` 环境变量则文件可为空）。
- 删除 `fast_backend`、`backend_template`、顶层 `default_model`/`pro_model` 及
  config.py 中对应 property/校验。用户旧 config 读到这些键时打一行 stderr 警告并忽略，
  不要 crash。

## 2. CLI 标志（cli/main.py、cli/commands/run.py、cli/commands/resume.py）

- `run` / `resume` 新增 `--backend <name>`（缺省：run 用 `default_backend`；
  resume 用该会话 runs 表里保存的 backend，`--backend` 可显式覆盖——覆盖时这是新会话语义，
  直接报错拒绝更稳妥：续接必须用原 backend。二选一，倾向报错）。
- 删除 `--fast` 及其全部下游逻辑。保留 `--pro`（取当前 backend 的 `pro_model`）。

## 3. backend 构建层（cli/backend.py）

按 `type` 分支：

- `set_env()`：claude 型设 ANTHROPIC_*；codex 型设 codex 所需 env（调研结论）。
- `build_args()`：claude 型沿用 `build_claude_args()`（含 resume=True 的
  `--resume {session_id}` 路径）；新增 codex 型构建 `codex exec --json ... <prompt>`
  与对应的续接命令。占位符机制（`{model}` `{prompt}` `{session_id}` 等）复用。
- 交互式 resume（`handoff resume <seq>` 无 prompt）：claude 型沿用 `build_resume_args()`；
  codex 型若 CLI 支持交互续接（`codex resume <id>`?）则同样 execvp，否则打印
  明确的不支持提示并退出 1。
- `wrap_with_pty()` 仅对需要的 type 应用（按调研结论）。

## 4. 流解析层（cli/stream.py）

这是本阶段核心。要求：

- 抽出统一的事件接口，建议三个回调/事件：`progress(text)`（写 `.out.txt` + stderr）、
  `result(text, is_error)`（写 `.result.md`）、`session(id)`（回填 runs 表）。
- 现有 claude JSONL 解析逻辑收进 `ClaudeStreamParser`（行为零变化——这是回归红线）。
- 新增 `CodexStreamParser` 解析 `codex exec --json` 事件流（按调研结论映射到上述三个事件）。
- `execute_run()` 按 backend type 选 parser，其余管线（落盘 `.jsonl`、状态机
  running/success/error/interrupted、`RESULT=` 打印协议）保持公共。
- 原始输出无论哪种 type 都完整落盘（codex 的 `.jsonl` 同名同位）。

## 5. DB（cli/core.py）

- runs 表已有 `backend` 列；确认 codex 型 run 的 `session_id` 写入的是调研确定的
  续接 id。如调研发现 codex 续接 id 每轮变化，在 resume 路径加"完成后更新父会话
  session_id"的逻辑（仅 codex 型）。

## 6. 验证（必须全部真实跑通才能 commit）

```bash
# 回归红线：claude 路径行为与阶段 1 完全一致
handoff run --text "在 /tmp/hf-test 写一个 hello.py 并运行"      # deepseek
handoff resume <seq> --text "再加一个 goodbye.py"                # 续接，确认上下文保留

# 新路径
handoff run --backend codex --text "解释 cli/stream.py 的结构"    # codex exec
handoff resume <codex-run-seq> --text "那 backend.py 呢"          # codex 续接
handoff run --backend opus --text "print hi"                      # opus（本机 claude 登录态）

handoff list      # 三种 backend 的 run 都正常显示、tail 可用
handoff run --backend nonexistent --text x   # 报错信息可读
```

## 7. 收尾

- 把调研结论（第 0 节的四个问题的答案）写成 `docs/design-notes-codex.md`，阶段 3 写
  正式文档时要引用。
- 单独 commit：`feat: backend types (claude/codex), --backend flag, codex exec integration`。
  不要 push。
