# DEVLOG

- 2026-03-29：新增自动化骨架设计文档，明确 planner、executor 和 state tracking 的最小职责边界。
- 2026-03-29：新增最小 executor 脚本，只负责校验路径、准备 build 目录、拷贝输入文件并写入状态文件。
- 2026-03-29：新增机器可读状态样例文件，作为后续 build 和运行阶段的状态接口占位。
- 2026-03-29：精炼自动化骨架，补充 guardrail 与阶段化状态结构，为后续 build、preprocess、driver、postprocess 和失败上报预留稳定接口。
- 2026-03-29：在骨架上新增 build stage 支持，复用现有 build 准备脚本并把日志、退出码和结果写入状态文件。
- 2026-03-29：补充 build command 到状态文件，方便后续排障和 planner/executor 之间的可追踪交接。
- 2026-03-29：在 build 骨架上新增 preprocess stage，按 YAML 规则保守识别 traction/displacement，并记录命令、日志、退出码和判定原因。
