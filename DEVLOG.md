# DEVLOG

- 2026-03-29：新增自动化骨架设计文档，明确 planner、executor 和 state tracking 的最小职责边界。
- 2026-03-29：新增最小 executor 脚本，只负责校验路径、准备 build 目录、拷贝输入文件并写入状态文件。
- 2026-03-29：新增机器可读状态样例文件，作为后续 build 和运行阶段的状态接口占位。
- 2026-03-29：精炼自动化骨架，补充 guardrail 与阶段化状态结构，为后续 build、preprocess、driver、postprocess 和失败上报预留稳定接口。
- 2026-03-29：在骨架上新增 build stage 支持，复用现有 build 准备脚本并把日志、退出码和结果写入状态文件。
- 2026-03-29：补充 build command 到状态文件，方便后续排障和 planner/executor 之间的可追踪交接。
- 2026-03-29：在 build 骨架上新增 preprocess stage，按 YAML 规则保守识别 traction/displacement，并记录命令、日志、退出码和判定原因。
- 2026-03-29：在 preprocess 骨架上新增 driver stage，复用 state 中已记录的 case type 选择 driver，并把命令、日志、cpu_size 和退出码写入状态文件。
- 2026-03-29：新增最小 postprocess stage，按 references 共同支持的顺序运行 reanalysis_proj_driver 和 prepostproc，并写入 time_end、日志与退出码。
- 2026-03-29：对完整 workflow 做保守维护性收敛，提炼共享失败处理与退出码数组 helper，统一各 stage 的失败写回与日志/state 一致性。
- 2026-03-29：新增最小 resume/rerun 机制，通过 `--start-from` 做显式保守恢复，并把恢复意图与决策写入状态文件。
- 2026-03-29：新增最小 stage-level retry policy，仅为 build 提供一次受限重试入口，并把策略、attempts 与决策写入状态文件。
- 2026-03-29：补充原始请求字段到状态样式中，使 `requested`、`resume` 与 `retry` 三层记录更加一致和可追踪。
- 2026-03-30：收紧 MPI launcher 选择规则，禁止隐式依赖 PATH 中的 mpirun，并在 launcher 与可执行文件链接的 MPI 安装不一致时明确失败。
- 2026-03-30：为 preprocess 增加 `geo_file_base` 安全护栏与定向清理，只删除可再生的 preprocess/partition 生成物，并把护栏与清理结果写入状态文件。
- 2026-03-30：明确记录默认 build 配置为 `Release`；现有 build 准备脚本继续使用 `cmake <example_dir> -DCMAKE_BUILD_TYPE=Release`，本次仅补充文档说明，不扩展状态模型。
- 2026-03-30：修正 postprocess 依赖顺序说明，明确 `prepostproc` 先于 `post_surface_force` 和 `vis_3d_mixed`，并在现有 postprocess 流程后校验 `postpart_p*.h5` 是否已生成。
- 2026-03-30：增加 vis_3d_mixed 的保守可视化护栏，校验 `paras_pos_vis.yml.time_end` 不得超过当前实际 `SOL_*.pvtu` 输出范围，并把结果作为下游可视化 readiness 写入状态文件。
