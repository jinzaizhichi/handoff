# handoff 迁移总计划（ds-cli → handoff）

## 目标

把 ds-cli（单向派活给 DeepSeek 的工具）升级为 **handoff**：多 coding agent 之间的任务调度层。
三大变化：**改名 + PyPI 打包**、**多 backend（claude 型 / codex 型）**、**skills 拆分 + 全部文档重写**。

## 已锁定的决策（执行时不要重新讨论）

| 项 | 决定 |
| --- | --- |
| 命令名 | `handoff` |
| PyPI 包名 | `handoff-cli`（已确认未被占用；`handoff` 被占用） |
| GitHub repo | `dazuiba/handoff`（GitHub 改名自动 301，最后人工操作） |
| 状态目录 | `~/.handoff/`；检测到旧 `~/.ds-cli/` 且新目录不存在时**自动整目录 rename 迁移**（原子操作），并把 `runs/dscli.db` 改名为 `runs/handoff.db` |
| run_id 前缀 | 新 run 用 `hd-<MMDD>-<SEQ>`；旧 `ds-` 前缀的历史记录**不迁移**，按 seq/run-id 查找继续有效 |
| 安装方式 | `uv tool install handoff-cli` + `handoff init`。**删除** brew formula 维护（`cli/homebrew.py`）、`install.sh`、`install-online.sh`、`update` 子命令、`ds-cli-tui` |
| `install` 子命令 | 改名为 `init` |
| CLI 标志 | 新增 `--backend <name>`；**删除 `--fast`** 和 `fast_backend` 配置；**保留 `--pro`**（语义：用当前 backend 的 `pro_model`） |
| backend 类型 | `type: claude \| codex`。默认配置三个 backend：`deepseek`（claude 型，DeepSeek 端点）、`codex`（codex 型）、`opus`（claude 型，官方端点 + opus 模型）。`backend_template` 改为按 type 的 `type_defaults` |
| skills | `skills/handoff-ds/SKILL.md`、`skills/handoff-codex/SKILL.md`、`skills/handoff-opus/SKILL.md`、`skills/handoff-ds.toml`（Codex subagent）。接受三份 SKILL.md 内容高度重复 |
| README | 以 `readmev2.md` 为最终蓝本（提升为 README.md，再删除 readmev2.md） |

## 阶段与分派

三个阶段**严格串行**（都动同一批文件），每阶段结束必须通过冒烟验证并独立 commit。

| 阶段 | 内容 | 执行者 | 文件 |
| --- | --- | --- | --- |
| 1 | 改名 + PyPI 打包 + init/迁移（纯机械，零行为新增） | **/ds-cli pro** | `01-rename-packaging.md` |
| 2 | 多 backend 架构：type 抽象、codex exec 集成、流解析器、--backend/--pro | **Opus 4.8 agent** | `02-multi-backend.md` |
| 3 | skills 目录 + 全部文档重写 + 清理 | **/ds-cli pro** | `03-skills-docs-cleanup.md` |

分派理由：阶段 2 是唯一需要设计判断和外部调研（codex CLI 行为）的部分，给 Opus；阶段 1/3 是大面积、规则明确的机械工程，给 DeepSeek pro。

## 开始前（人工）

1. 当前工作区有未提交改动（`ds-agent.toml`、`CLAUDE.md`、`README*.md`、`readmev2.md`）——先 commit 现状作为基线。
2. 阶段 1 开始前不需要先改 GitHub repo 名；repo 改名放在全部完成后（见下）。

## 全部完成后（人工）

1. GitHub repo 改名 `ds-cli` → `handoff`。
2. PyPI 首次发布 `handoff-cli`（`uv build && uv publish`，需要 PyPI token）。
3. Homebrew tap 旧 formula 加 `deprecate!` 指向 PyPI 安装方式。
4. 重拍 README 里全部截图（assets/ 下的占位注释标明了每张的要求）。
5. 本机自测：`uv tool install` 装一遍，跑通 `/handoff-ds` 派发 → resume 续接 → `/handoff-codex` 咨询全链路。

## 验收总标准

- `uv tool install`（本地 `-e .`）后 `handoff init`、`handoff run --text "smoke"`、`handoff run --backend codex --text "smoke"`、`handoff resume <seq> --text "follow-up"`、`handoff list`、`handoff tail` 全部可用。
- 存在旧 `~/.ds-cli/` 的机器上首次运行自动完成迁移，旧任务在 `handoff list` 中可见、可 resume。
- 仓库内（含 docs/、skills/、CLAUDE.md）不再出现 `ds-cli` 字样，除了"迁移自 ds-cli"性质的说明。
