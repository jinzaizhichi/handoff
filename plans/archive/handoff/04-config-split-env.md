# 阶段 4：配置拆层（backend_types / config.yaml）+ handoff env

> 执行者：/ds-cli pro。前置：阶段 1-3 已提交（HEAD 在 handoff 分支）。
> 产品决策已定，执行时不要重新讨论。

## 设计原则

把配置拆成**机制**与**数据**两层：

- **机制（程序承诺，不可覆盖）**：claude/codex 两种 type 怎么被拉起——flag 数组、PTY。
  随包分发，用户 config 出现同名键时警告并忽略。
- **数据（用户资产，全部可见）**：backends 定义。只存在于 `~/.handoff/config.yaml`，
  **没有隐藏的合并层**——init 生成完整文件，所见即所得。

## 1. 文件改动

```text
cli/backend_types.yaml         # 新建：机制层（含内置 system_prompt 默认值）
cli/user_config_template.yaml  # 新建：init 整份复制 → ~/.handoff/config.yaml
cli/default_config.yaml        # 删除
```

### cli/backend_types.yaml

- 顶部注释：本文件是程序行为的一部分，不可被用户配置覆盖；想理解完整配置逻辑从这里读起。
- `system_prompt:`（现 default_config.yaml 原文**一字不动**平移至此；用户 config.yaml 仍可覆盖此键——它是唯一保留覆盖能力的内置值）。
- `types:` 下 `claude` / `codex` 两节，每节只含：`command`、`pty`、`session_flags`、
  `session_id_flags`、`continue_id_flags`、`resume_flags`。**全部 env 映射删除**
  （`ANTHROPIC_MODEL`、`ANTHROPIC_DEFAULT_*_MODEL`、`CLAUDE_CODE_SUBAGENT_MODEL`、
  `CLAUDE_CONFIG_DIR` 都不在此层；CLAUDE_CONFIG_DIR 兜底已在 backend.py 代码里）。
  flag 内容从现 default_config.yaml 的 type_defaults 平移，占位符机制不变。

### cli/user_config_template.yaml（即 init 生成的 config.yaml）

```yaml
# handoff 配置 — 这是唯一需要你编辑的配置文件。
# 改坏了可从模板恢复：
#   https://github.com/dazuiba/handoff/blob/main/cli/user_config_template.yaml
# claude/codex 的拉起方式（flags、PTY）是程序承诺，不在本文件配置；
# 运行 `handoff env` 可拿到 backend_types.yaml 的路径，了解完整配置逻辑。
#
# backends 里第一个条目就是默认目标（handoff run 不带 --backend 时用它）。
# env 由你全权书写：{model} 会替换为该 backend 解析出的模型（--pro 时取 pro_model），
# "${VAR}" 会展开同名环境变量。

backends:
  deepseek:
    type: claude
    model: deepseek-v4-flash
    pro_model: "deepseek-v4-pro[1m]"
    env:
      ANTHROPIC_BASE_URL: https://api.deepseek.com/anthropic
      ANTHROPIC_AUTH_TOKEN: "${DEEPSEEK_API_KEY}"   # 或直接写 sk-...
      ANTHROPIC_MODEL: "{model}"

  opus:               # 走本机 claude 登录态，零配置
    type: claude
    model: claude-opus-4-8
    pro_model: claude-opus-4-8
    env:
      ANTHROPIC_MODEL: "{model}"

  codex:              # 走本机 codex 登录态，零配置；模型经 -m 传入
    type: codex
    model: gpt-5.5
    pro_model: gpt-5.5
```

注意：**没有 `default_backend` 键**。

## 2. config.py

- 加载：`backend_types.yaml` 独立加载（不进 merge）；用户 `config.yaml`（含 `include:`，
  `${ENV}` 插值保留）是 `backends` 的唯一来源。
- backend 解析 = `types[<type>]` 的机制字段 + backend 自身字段（深合并语义保留，
  但用户已无法触碰机制层）。
- **默认 backend = `backends` 中第一个条目**（dict 插入序）。用户若显式写了
  `default_backend` 键，尊重它（不写进模板、不宣传）。
- `_validate`：用户 config 必须定义非空 `backends`；每个 backend 的 `type` 必须是
  backend_types.yaml 里的已知 type；claude 型必须有 `model` 字段。报错信息附模板 URL。
- 警告并忽略的用户键：`type_defaults`、`backend_types`、`backend_template`、
  `fast_backend`、`default_model`、`pro_model`（顶层）。`system_prompt` 用户可覆盖，不警告。
- 删除 `_DEFAULT_USER_CONFIG` 字符串；init 改为复制 `user_config_template.yaml`
  （注意 editable 与 wheel 两种安装形态都要能定位到包内文件）。
- pyproject 的 package data 核对：两个新 yaml 必须进 wheel，构建后验证。

## 3. 新子命令 handoff env（cli/commands/env.py）

输出 4 行 `key=绝对路径`，供人和脚本使用：

```text
config=/Users/sam/.handoff/config.yaml
backend_types=<安装包内 backend_types.yaml 的实际绝对路径>
tasks=/Users/sam/.handoff/tasks
runs=/Users/sam/.handoff/runs
```

- main.py dispatch 加 `env`（无需初始化 Config——路径信息不该因 config 损坏而不可得），
  usage 文本同步。
- tasks/runs 行尾可括注内容说明（`# prompt/.out/.result files`、`# raw jsonl streams`）——
  可选，保持单行 key=value 在前即可。

## 4. 文档同步（全部）

| 文件 | 改动 |
| --- | --- |
| `README.md` / `README.zh-CN.md` | 配置节重写：init 生成完整 config.yaml、填 token 即用；自定义目标示例改为"直接加一段 backends 条目"（kimi 示例保留，补 `ANTHROPIC_MODEL: "{model}"` 行）；"更多"或合适处提一句 `handoff env`。快速开始节不变。两版逐节对应 |
| `docs/configuration.zh-CN.md` | 重写为新模型：机制/数据两层、第一个 backend 即默认、env 全权自写、`${ENV}` 插值、include、system_prompt 覆盖、backend_types.yaml 只读说明 |
| `docs/cli-reference.zh-CN.md` | 加 `env` 子命令；删除已不存在的 default_backend 描述 |
| `CLAUDE.md` | Config 一节按新加载逻辑重写；Commands 加 `handoff env` |

文案红线沿用阶段 3（不对用户说"后端"；README 痛点格式不动；run/resume vs list/tail 受众区分）。

## 5. 本机真实配置迁移

`~/.handoff/config.yaml` 重写为新格式（先备份为 `config.yaml.bak-pre-0.4`）：
backend `default` 改名 `opencode` 放第一位（即默认），env 自写补全原 backend_template
提供过的映射，行为不变：

```yaml
backends:
  opencode:
    type: claude
    model: deepseek-v4-flash
    pro_model: "deepseek-v4-pro[1m]"
    env:
      ANTHROPIC_BASE_URL: "http://127.0.0.1:4000"
      ANTHROPIC_AUTH_TOKEN: "unused"
      ANTHROPIC_MODEL: "{model}"
      ANTHROPIC_DEFAULT_OPUS_MODEL: "{pro_model}"
      ANTHROPIC_DEFAULT_SONNET_MODEL: "{model}"
      ANTHROPIC_DEFAULT_HAIKU_MODEL: "{model}"
      CLAUDE_CODE_SUBAGENT_MODEL: "{model}"
  opus: （同模板）
  codex: （同模板）
```

## 6. 验证（全部真实跑通）

```bash
python3 -m compileall -q cli/
handoff env                                   # 4 行路径正确（backend_types 指向 worktree 包内）
HOME=$(mktemp -d) handoff init -y             # 生成的 config.yaml == 模板；二次 init 不覆盖
handoff run --text "reply with exactly PONG"  # 默认 backend（第一个=opencode）回归
handoff run --pro --text "reply with exactly PRO-OK"
handoff resume - --text "你刚才回复了什么？只重复那个词"
handoff run --backend codex --text "reply with exactly CODEX-OK"   # 账号已恢复，必须端到端通过
handoff resume <codex-seq> --text "再回复一次同一个词"               # codex 续接端到端
handoff run --backend opus --text "reply with exactly OPUS-OK"
uv build && unzip -l dist/*.whl | grep -E "backend_types|user_config_template"   # 进 wheel
grep -rn "default_config" cli/ docs/ README* CLAUDE.md pyproject.toml            # 0 命中
grep -rn "default_backend" cli/*.yaml docs/ README*                              # 0 命中（代码里兼容逻辑允许）
```

## 7. 收尾

单独 commit（不要 push，push 由主会话审核后执行）：
`refactor: split config into backend_types (mechanism) + user-owned config.yaml; add handoff env`。
报告：改动清单、验证逐项 PASS/FAIL、计划外问题。
