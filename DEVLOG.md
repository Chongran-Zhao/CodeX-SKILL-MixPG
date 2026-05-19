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
- 2026-05-18：为 skill 增加集中提问规则；当用户未指定多个可选输入时，要求一次性汇总成一个问题并为每项提供默认值，减少来回确认。
- 2026-05-18：进一步收紧 skill 提问样式：集中确认时要求列出所有选项、显式标注默认值、优先使用表格展示，并说明带单位的量默认按国际标准单位制（SI）解释；同时要求 traction case 必须显式确认载荷数值。
- 2026-05-18：补充 skill 的后处理与提问策略：默认列出全部后处理可执行程序并给出 allow/skip 默认值；若启用 `post_surface_force` 或 `vis_3d_mixed`，必须同步更新时间范围、相关输入文件、材料模型一致性以及内变量个数检查；同时“保持当前”类选项要展开为代码中的具体模型名和模板 mesh 大小。
- 2026-05-18：增加新规则：严禁在正在编辑或用于科学算例设置的源文件仓库内创建任何 git commit，避免把自动化过程直接提交到源码仓库。
- 2026-05-18：增加新规则：在思考和执行过程中，terminal 中运行的命令及其输出都不允许折叠或隐藏，应完整展示。
- 2026-05-18：将 skill 的 `build dir policy` 默认值从 `reuse` 改为 `clean`，默认删除原有 `~/build_MixPG` 后重建，以减少旧构建目录残留带来的干扰。
- 2026-05-18：新增 `README.md`，面向用户说明这个 skill 的用途、下载、安装、调用、对话方式、后处理默认值和关键规则，并加入流程图帮助理解。
- 2026-05-18：补充 skill 执行纪律规则：要求单一真相源、单一受控执行入口、预检 `geo_file_base`/`cpu_size`/MPI launcher 一致性，并把运行时 warning 与 fatal failure 明确分级，减少边试边改和双份输入导致的操作性错误。
- 2026-05-18：收紧 skill 的后处理表述与简单双向检查规则：只有 `vis_3d_mixed` 命令真实成功执行后才能宣称已运行；对简单单向加载，`post_surface_force` 默认只校验加载面以及对应方向的位移/traction 分量，不把无关方向当成必要项。
- 2026-05-18：为 skill 增加报告交付规则：运行完成后需在 `~/build_MixPG/report` 下产出科研风格的表面力学图片、可视化图片、Markdown 报告和 PDF 报告，并把这些结果作为完整交付的一部分而不是可选附加项。
- 2026-05-18：根据实际运行中的失误，进一步收紧 skill：禁止把依赖型后处理并行发起；要求 `reanalysis_proj_driver` 的 `vis_m` 先与材料模型内变量组数对齐；要求 `post_surface_force` 后强制检查 `Force_disp_record.txt` 中是否存在 `nan/inf`；同时新增可复用的报告模板，要求后续报告只填充本次结果而不是每次从零生成整篇正文，以减少 token 消耗。
- 2026-05-18：新增固定报告渲染脚本 `scripts/render_mixpg_report.py`，把绘图、模板填充和 PDF 导出收敛成稳定入口；同时在 skill 和 README 中明确后续应优先复用该脚本，而不是每次临时从零组织报告流程。
- 2026-05-19：补充位移加载默认规则：若用户未特别要求，优先选择位移和速度都光滑连续的加载历程，避免突变、折点和速度不连续；默认优先 `sin` 或其他平滑 profile。
- 2026-05-19：补充可视化表述规则：若报告中的云图来自 `vis_3d_mixed` 输出再绘制的图片，应如实描述为生成的可视化图，不能冒充 ParaView 预览；只有真实经过 ParaView 渲染或截图时才能这样表述。

- 2026-05-19：根据当前 MixPG 版本的真实源码行为补充 skill 规则：明确 `geo_file_base` 会被 preprocess 代码追加 HOME 前缀，因此 build 几何应优先使用 `/build_MixPG/patch` 这类 HOME 相对 YAML 写法；要求位移方向切换时同时检查 `mixed_ga_driver_displacement.cpp` 的初始速度基向量和 `PNonlinear_Solver.cpp` 的施加方向；明确 `reanalysis_proj_driver` 不能依赖默认 `-vis_m 1`，必须按当前材料模型的 internal-variable/relaxation 个数显式传参；同时补充大变形默认尝试不等于默认保证收敛、旧运行说明让位于当前源码/可执行程序行为、以及 driver 发散后不得继续包装最终报告等规则。

- 2026-05-19：继续根据实际 rerun/preflight 结果收紧 skill：将位移加载方向在 runtime YAML、init YAML、`mixed_ga_driver_displacement.cpp` 与 `PNonlinear_Solver.cpp` 之间的一致性升级为运行前硬阻断条件；若这几处不一致，则不得继续 build、preprocess 或 driver。同时补充本地根目录入口与具名 skill 目录入口应保持同步的安装说明。
