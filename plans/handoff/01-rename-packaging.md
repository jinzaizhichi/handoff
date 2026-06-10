# 阶段 1：改名 + PyPI 打包 + init/迁移

> 执行者：/ds-cli pro（DeepSeek V4 pro）
> 前置：工作区干净（基线已 commit）。本阶段**只做机械改造，不新增任何功能行为**。
> 仓库：/Users/sam/dev/github/ds-cli（git 目录名暂不变，repo 改名最后人工做）

## 背景一句话

ds-cli 是一个把编码任务派发给 AI backend 的 CLI（详见 CLAUDE.md）。本阶段把它从
"PEP 723 单脚本 + 手工 symlink 安装" 改造成 "标准 Python 包 `handoff-cli`，命令 `handoff`，
经 `uv tool install` 分发"，同时完成所有 ds-cli → handoff 的更名。

## 任务清单

### 1. 打包结构

- 新建 `pyproject.toml`：
  - `[project]` name = `handoff-cli`，version 从 `0.3.0` 起，requires-python `>=3.9`，
    依赖从根目录 `ds-cli` 脚本的 PEP 723 inline metadata 里抄（pyyaml、textual 等，逐一核对）。
  - entry point：`handoff = "cli.main:main"`。包目录保持 `cli/`（`[tool.hatch]`/setuptools 配置
    `packages = ["cli"]`；选 hatchling 即可）。
  - package data：`cli/default_config.yaml` 必须打进 wheel；`skills/` 目录本阶段还不存在，
    在 pyproject 里预先 include `cli/skills/**`（阶段 3 会创建，放在 `cli/skills/` 以便随包分发）。
- 删除根目录 `ds-cli`（PEP 723 入口脚本）和 `ds-cli-tui`。
- `cli/main.py` 顶部如有 sys.path hack，移除（包安装后是正常 import）。
- 验证：`uv tool install -e .` 后 `which handoff && handoff --help` 正常。

### 2. install → init；删除 update

- `cli/commands/install.py` → `cli/commands/init.py`，子命令名 `init`（`main.py` 的 dispatch 同步改）。
  保留原有职责：创建 `~/.handoff/config.yaml` 样板、链接 skill/agent 文件。
  skill/agent 文件的**源路径**改为包内资源（`importlib.resources` 或 `Path(__file__).parent`，
  注意 `-e` 安装与 wheel 安装两种形态都要能找到）。本阶段链接目标仍是现有的
  `SKILL.md`/`ds-agent.toml`（阶段 3 才换成 skills/ 新文件），但链接落点已用新名：
  `~/.claude/skills/handoff-ds/SKILL.md`、`~/.codex/agents/handoff-ds.toml`。
- 删除 `cli/commands/update.py`、`cli/homebrew.py`、`install.sh`、`install-online.sh`，
  以及 main.py / 其他文件里对它们的全部引用。

### 3. 状态目录与 DB 更名 + 自动迁移

`cli/core.py`：

- 状态根目录常量 `~/.ds-cli` → `~/.handoff`；DB 路径 `runs/dscli.db` → `runs/handoff.db`。
- 在状态目录首次访问处加迁移逻辑：若 `~/.ds-cli` 存在且 `~/.handoff` 不存在 →
  `os.rename(旧, 新)`，随后若 `runs/dscli.db` 存在且 `runs/handoff.db` 不存在 → rename；
  （WAL 模式注意把 `dscli.db-wal` / `dscli.db-shm` 一并 rename）。打一行 stderr 日志说明已迁移。
- run_id 前缀 `ds-` → `hd-`（生成处改；查找处 `find_run()` 不要写死前缀，保证旧 `ds-0608-07`
  仍可作为 resume 句柄查到）。

### 4. 全局更名扫尾

- 所有面向终端的输出前缀 `ds-cli ...` → `handoff: ...`（grep `ds-cli` / `dscli` 逐个处理）。
- `cli/default_config.yaml`、注释、错误信息里的 ds-cli 字样同步改。
- **不要动**：`README*.md`、`readmev2.md`、`docs/`、`SKILL.md`、`ds-agent.toml`、`CLAUDE.md`、
  `plans/`——文档与 skills 是阶段 3 的活，本阶段改了会和阶段 2/3 冲突。
  例外：CLAUDE.md 中 Commands 一节的命令示例如果不改会误导阶段 2 的执行者，
  仅把该节命令更新为 `handoff ...` 形式即可，其余章节不动。

### 5. 验证（必须全部通过才能 commit）

```bash
uv tool install -e . --force
handoff --help
HOME=$(mktemp -d) handoff init -y          # 干净环境初始化
handoff run --text "print hi 冒烟测试"      # 真实跑一发（需已配置 token 的真实 HOME）
handoff list                                # TUI 正常、能看到 hd- 前缀新任务和 ds- 旧任务
handoff resume <刚才的seq> --text "再确认一下"   # 续接可用
handoff tail <run-id>
grep -rn "ds-cli\|dscli\|ds_cli" cli/ pyproject.toml   # 应为 0 命中
```

另外构造迁移测试：把 `~/.handoff` 临时挪走、放一个旧结构 `~/.ds-cli`（可从备份复制），
运行 `handoff list` 确认自动迁移 + 旧任务可见，再恢复现场。

### 6. 收尾

单独 commit，message 以 `refactor: rename ds-cli -> handoff, package for PyPI` 开头。
不要 push。把验证输出摘要写进 commit body。
