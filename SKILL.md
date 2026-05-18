---
name: mixpg-case-runner
description: Prepare and run MixPERIGEE or MixPG viscoelasticity example builds and executions. Use this skill whenever the user wants to automate MixPG setup on their machine, verify `MixPERIGEE/conf/system_lib_loading.cmake`, recreate `~/build_MixPG`, run CMake for `examples/viscoelasticity_NURBS_TaylorHood`, compile with `make -j`, stage the `input/creep` files into the build directory, or edit `paras_preprocessor.yml`, `paras_preprocessor_init.yml`, `paras_driver.yml`, `LoadData.hpp`, and `MaterialModelData.hpp` for mesh, loading, time stepping, constitutive-model setup, MPI driver execution, and postprocessing.
---

# MixPG Case Runner

Use this skill as a task-friendly execution guide. Do not simulate a separate product-level task system inside the skill. Instead:

- keep progress updates short
- use simple stage labels
- make checkpoints explicit
- stop immediately on blocking failures
- never create git commits inside the source-file repository that is being edited or used for the scientific case setup
- do not collapse or hide any terminal commands or terminal outputs during reasoning or execution; show the exact commands and their outputs in full

## User Input Policy

When the user request leaves multiple selectable inputs unspecified, ask for them
once in a single consolidated question instead of asking them one by one.

The consolidated question should:

- group all missing selectable inputs in one message
- show the default value for each item when a safe default exists
- list all available options for categorical inputs
- let the user answer by accepting defaults or overriding only the items they care about
- use a clean table when the input list is long enough to benefit from structured display
- mark the default choice explicitly in the table
- state that quantities with units use SI units unless the user explicitly says otherwise
- avoid repeating follow-up clarification questions unless a later blocker is truly new

Use the consolidated question only for inputs that materially affect case setup,
for example:

- loading mode
- load direction and loaded face
- mesh resolution
- `cpu_size`
- `initial_time`
- `initial_step`
- `final_time`
- traction magnitude or displacement magnitude when the loading mode requires it
- constitutive model choice
- whether to reuse the current build directory or clean it
- which postprocess executables are enabled

Suggested style:

```md
请一次性确认这些输入；不改的项可直接用默认值。带单位的量默认按国际标准单位制（SI）解释。

| 项目 | 可选值 | 默认值 | 单位/说明 |
| --- | --- | --- | --- |
| loading mode | traction / displacement | traction | 主加载模式 |
| load direction | x / y / z | z | 方向 |
| loaded face | top / bot / left / right / front / back | top | 施加载荷的面 |
| traction magnitude | 用户填写 | 无默认值 | Pa |
| time law | constant / ramp | constant | traction 或 displacement 时间形式 |
| cpu_size | 用户填写 | 6 | 无量纲 |
| initial_time | 用户填写 | 0.0 | s |
| initial_step | 用户填写 | 0.01 | s |
| final_time | 用户填写 | 1.0 | s |
| constitutive model | 保持当前 / 用户指定 | 保持当前 | 这里要写出当前代码里的具体模型名称 |
| build dir policy | reuse / clean | clean | 默认删除原有 `~/build_MixPG` 后重建 |
| reanalysis_proj_driver | allow / skip | allow | 后处理第一步 |
| prepostproc | allow / skip | allow | 后处理第二步 |
| post_surface_force | allow / skip | allow | 默认运行 |
| vis_3d_mixed | allow / skip | allow | 默认运行 |
| divV_calculator | allow / skip | skip | 默认不运行 |
```

Traction cases must explicitly confirm the traction magnitude. Do not invent a
traction value silently.

When presenting "keep current" choices, always resolve them to concrete current
values from the code or template first:

- for constitutive model, write the actual currently integrated model name
- for mesh, write the actual current template element counts such as `4 x 4 x 4`
- for postprocess executables, list each executable explicitly with allow/skip
  and mark its default
- for traction loading, allow the user to provide a traction expression, not
  only a scalar magnitude

Good progress labels:

- `Build Setup`
- `Input Setup`
- `Material And Load Setup`
- `Preprocess`
- `Driver`
- `Postprocess`

At each checkpoint, briefly report:

- what changed
- what command ran
- what files or outputs now exist
- what the next step is

## Core Defaults

Use these defaults unless the user overrides them:

- `cpu_size: 6`
- `initial_time: 0.0`
- `initial_step: 0.01`
- `final_time: 1.0`
- default constitutive model: keep the currently integrated model in `MaterialModelData.hpp`
- default build directory policy: clean existing `~/build_MixPG` before rebuild
- default postprocess enablement:
  `reanalysis_proj_driver = allow`,
  `prepostproc = allow`,
  `post_surface_force = allow`,
  `vis_3d_mixed = allow`,
  `divV_calculator = skip`

Compute postprocess step index with:

`time_end = (final_time - initial_time) / initial_step`

Example:

- `initial_time = 0.0`
- `initial_step = 0.01`
- `final_time = 1.0`
- therefore `time_end = 100`

If this is not an integer, stop and ask the user to reconcile `final_time` and `initial_step`.

## Execution Discipline

Keep execution conservative and reproducible.

### Single source of truth

Do not maintain the same case input in both the source example tree and the
build directory at the same time.

Default rule:

- edit the source example inputs and source files first
- then rebuild or restage into `~/build_MixPG`
- then run from the build directory

Only use build-directory-only hotfixes in an explicit debug or recovery mode,
and if you do:

- say clearly that the build copy has diverged from the source template
- list exactly which build-directory files were changed
- do not also change the corresponding source files in the same pass unless the
  user explicitly asks to reconcile them

### Single execution entrypoint

After input confirmation and file edits are done, prefer one controlled workflow
path instead of scattering manual stage runs.

Default rule:

- use the existing build-preparation script for build setup
- then run preprocess, driver, and postprocess in the documented order
- do not mix ad hoc extra commands into the middle of the workflow unless you
  explicitly label the session as manual debugging

### Preflight before execution

Before running any preprocess or MPI stage, validate the key operational inputs
first instead of discovering them by trial and error.

Required checks:

- `geo_file_base + "0.yml"` must resolve to a real file before preprocess
- `cpu_size` must be consistent across preprocess, driver, and MPI postprocess
- the chosen MPI launcher must match the MPI installation linked by the target
  executable

Do not "try several path variants" during normal execution. If the resolved
path is unsafe or ambiguous, stop and explain the blocker.

### Build-script invocation rule

Do not rely on the executable bit of the build-preparation script.

Preferred form:

```bash
bash /Users/chongran/CodeX-SKILL-MixPG/scripts/prepare_visco_build.sh ...
```

### Warning vs fatal rule

Do not treat every noisy runtime message as a solver failure, but do not ignore
it either.

Classify outcomes as:

- `fatal`: nonzero exit code, missing required artifacts, missing executables,
  inconsistent inputs, or violated stage dependencies
- `warning`: the main stage exits with code `0` and produces the required
  outputs, but logs contain post-run cleanup warnings or similar non-blocking
  messages

If a warning occurs:

- report it explicitly
- keep it separate from scientific-result success or failure
- only continue if the required outputs for the next stage actually exist

## Build Setup

Check:

- `~/MixPERIGEE/conf/system_lib_loading.cmake`
- `~/MixPERIGEE/examples/viscoelasticity_NURBS_TaylorHood`
- `~/build_MixPG`

Build flow:

```bash
cmake ~/MixPERIGEE/examples/viscoelasticity_NURBS_TaylorHood -DCMAKE_BUILD_TYPE=Release
make -j
cp -R ~/MixPERIGEE/examples/viscoelasticity_NURBS_TaylorHood/input/creep/. ~/build_MixPG/
```

Rules:

- if `~/build_MixPG` exists, do not silently clear it
- ask before destructive cleanup
- stop on CMake or compile errors
- warnings are allowed but should be summarized

## Input Setup

Files you may need to edit:

- `paras_preprocessor.yml`
- `paras_preprocessor_init.yml`
- `paras_driver.yml`
- `LoadData.hpp`
- `MaterialModelData.hpp`

### Geometry path rule

`geo_file_base` is sensitive and must be validated before preprocessing.

Rules:

- if the user gives an absolute path, use it exactly as given
- do not prepend `HOME` or any other root to an absolute path
- if the user gives a relative path, resolve it explicitly and report the resolved absolute path
- before running preprocessing, verify that `geo_file_base + "0.yml"` exists

Example:

- correct base: `/Users/chongran/build_MixPG/patch`
- expected file: [`/Users/chongran/build_MixPG/patch0.yml`](/Users/chongran/build_MixPG/patch0.yml)

Do not generate broken paths like:

- `/Users/chongran/Users/chongran/build_MixPG/patch0.yml`

### Mesh rule

For single-patch cases:

- `num_inserted_x: [n]` means `n + 1` elements in x
- `num_inserted_y: [n]` means `n + 1` elements in y
- `num_inserted_z: [n]` means `n + 1` elements in z

### Boundary rule

- `Dirichlet_velo_x`, `Dirichlet_velo_y`, `Dirichlet_velo_z` define displacement constraints by direction and face
- `EBC` defines traction faces only

### Loading mode rule

Pick exactly one primary loading mode unless the user explicitly asks for coupling:

- traction
- displacement
- body force
- initial velocity

Keep unrelated loads at zero in `LoadData.hpp`.

### Traction rule

If traction loading:

- edit only `paras_preprocessor.yml`
- do not edit `paras_preprocessor_init.yml`
- put the loaded face in `EBC`
- encode the actual traction vector and time law in `surface_traction(...)`
- later run `preprocess3d` only

### Displacement rule

If displacement loading:

- edit `paras_preprocessor.yml`
- edit `paras_preprocessor_init.yml`
- edit `examples/viscoelasticity_NURBS_TaylorHood/src/PNonlinear_Solver.cpp` if the loaded direction changes
- in `paras_preprocessor.yml`, keep the full runtime boundary setup
- in `paras_preprocessor_init.yml`, keep only the unique loaded direction-face entry
- encode the displacement time law in `disp_loading(...)`
- encode its derivative in `velo_loading(...)`
- in `PNonlinear_Solver.cpp`, make sure the imposed basis vector matches the requested direction:
  use `base_x` for x displacement, `base_y` for y displacement, and `base_z` for z displacement
- if the case is uniaxial displacement tension, constrain the other two directions on the loaded face to zero in `paras_preprocessor.yml`
- later run `preprocess3d` then `preprocess3d_init`

Example for bottom fixed, top z displacement:

`paras_preprocessor.yml`

```yml
Dirichlet_velo_x:
  0: [ 0, bot ]

Dirichlet_velo_y:
  0: [ 0, bot ]

Dirichlet_velo_z:
  0: [ 0, bot ]
  1: [ 0, top ]
```

`paras_preprocessor_init.yml`

```yml
Dirichlet_velo_x:

Dirichlet_velo_y:

Dirichlet_velo_z:
  0: [ 0, top ]
```

For uniaxial z-tension on the top face, the runtime file should also lock the other two directions on the top face:

```yml
Dirichlet_velo_x:
  0: [ 0, bot ]
  1: [ 0, top ]

Dirichlet_velo_y:
  0: [ 0, bot ]
  1: [ 0, top ]

Dirichlet_velo_z:
  0: [ 0, bot ]
  1: [ 0, top ]
```

## Material And Load Setup

Use:

- `examples/viscoelasticity_NURBS_TaylorHood/include/MaterialModelData.hpp`
- `examples/viscoelasticity_NURBS_TaylorHood/include/LoadData.hpp`

Material rule:

- if the user only names a model, search `~/MixPERIGEE/include`
- choose the closest compatible model already supported by the current factory structure
- preserve current parameter scale unless the user asks otherwise
- report the defaults you assumed

Load rule:

- traction case: make `surface_traction(...)` nonzero and keep other load modes zero
- displacement case: make `disp_loading(...)` and `velo_loading(...)` nonzero and keep other load modes zero
- body-force case: make `body_force(...)` nonzero and keep other load modes zero

Consistency checks:

- displacement-loaded face must not also appear in `EBC`
- traction-loaded face must be declared in `EBC`
- requested displacement direction must match the edited `Dirichlet_velo_*` block
- requested displacement direction must also match the `base_*` vector used in `PNonlinear_Solver.cpp`
- for uniaxial displacement tension, the loaded face must also be constrained to zero in the other two directions
- requested load duration must match the time law and `paras_driver.yml`

## Driver Time Setup

Use `paras_driver.yml` to control physical time:

- `initial_time`
- `initial_step`
- `final_time`

Default if unspecified:

```yml
initial_time: 0.0
initial_step: 0.01
final_time: 1.0
```

Do not accidentally keep sample defaults such as `0.1` and `200.0`.

Check:

- `initial_step > 0`
- `initial_time <= final_time`
- computed `time_end` is integral

## Preprocess

Use the same `cpu_size` everywhere. Default is `6`.

Rules:

- if traction loading:
  run `./preprocess3d`
- if displacement loading:
  run `./preprocess3d`
  then run `./preprocess3d_init`

Before running, make sure:

- `geo_file_base` resolves to a valid file base on the current machine
- `cpu_size` in the preprocessor file matches the intended MPI size

## Driver

Choose the executable by loading type:

- non-displacement-driven case: `./mixed_ga_driver`
- displacement-driven case: `./mixed_ga_driver_displacement`

Run with:

```bash
<matched_mpi_launcher> -np <cpu_size> <driver_executable> | tee driver_log.txt
```

Rules:

- `-np` must match preprocessor `cpu_size`
- default `cpu_size` is `6`
- always save output to `driver_log.txt`
- do not use whichever `mpirun` or `mpiexec` appears first in `PATH`
- use an explicitly chosen launcher that matches the MPI installation linked by
  the driver executable

## Postprocess

Use the actual built names:

- `./reanalysis_proj_driver`
- `./prepostproc`
- `./vis_3d_mixed`
- `./post_surface_force`
- `./divV_calculator`

Standard order:

1. `<matched_mpi_launcher> -np <cpu_size> ./reanalysis_proj_driver -time_end <time_end>`
2. `./prepostproc`
3. `<matched_mpi_launcher> -np <cpu_size> ./post_surface_force`
4. whichever downstream tool the user wants, for example:
   `<matched_mpi_launcher> -np <cpu_size> ./vis_3d_mixed -time_end <time_end>`

Default enablement when the user does not override it:

- `reanalysis_proj_driver`: allow
- `prepostproc`: allow
- `post_surface_force`: allow
- `vis_3d_mixed`: allow
- `divV_calculator`: skip

Rules:

- the driver and all postprocess executables have strict data dependencies and must be run serially
- do not start `reanalysis_proj_driver`, `post_surface_force`, `prepostproc`, or `vis_3d_mixed` before the driver has finished successfully
- do not run postprocess executables in parallel with each other
- `reanalysis_proj_driver` must use the same MPI size as preprocessing and driver
- `post_surface_force` and `vis_3d_mixed` depend on files such as `postpart_p*.h5`, which are generated by `prepostproc`
- do not run `post_surface_force` or `vis_3d_mixed` before `prepostproc` has finished and produced the required dependency artifacts
- `post_surface_force` should be run before `vis_3d_mixed`
- do not say that `vis_3d_mixed` has been run unless its command was actually executed and finished successfully
- use `prepostproc`, not the old `prepost` name
- `-time_end` is a step index, not physical time
- before running `vis_3d_mixed`, update `paras_pos_vis.yml` so `time_start`, `time_step`, and `time_end` match the finished run
- if `paras_pos_vis.yml.time_end` exceeds the highest available `SOL_*.pvtu` index from the current run, treat visualization as not ready and fail clearly instead of attempting `vis_3d_mixed`
- if `post_surface_force` or `vis_3d_mixed` is enabled, update the corresponding inputs before execution instead of assuming the template is already correct
- if `post_surface_force` or `vis_3d_mixed` is enabled, synchronize their processed time-step range with the finished run
- if `vis_3d_mixed` is enabled, check that its material-model-related settings and the expected number of internal variables are consistent with the finished run before treating visualization as safe

### Surface-force postprocess rule

If `post_surface_force` is requested or part of the default postprocess chain:

- edit `examples/viscoelasticity_NURBS_TaylorHood/post_surface_traction.cpp`
- update `target_surface_list.emplace_back(...)` so the selected patch id and face match the current loading boundary condition
- if the case uses multiple loaded faces or patches, add one entry per target surface
- update the output record so the reported displacement and force components match the loaded direction
- synchronize the post-surface-force time range with the finished run so it processes the full intended index range, for example `time_end = 100` for `1.0 / 0.01`

For simple single-direction loading, keep the surface-force output minimal:

- only the loaded face needs to be processed
- only the loaded direction needs to be reported as displacement and traction
- do not require unrelated direction components unless the user explicitly asks for them

Direction mapping for the output record:

- x loading: write `sum_dispx/sum_area` and `sum_Fx/sum_area`
- y loading: write `sum_dispy/sum_area` and `sum_Fy/sum_area`
- z loading: write `sum_dispz/sum_area` and `sum_Fz/sum_area`

Consistency checks:

- the target face in `post_surface_traction.cpp` must match the traction or displacement loading face
- the recorded component in `Force_disp_record.txt` must match the requested loading direction
- for simple single-direction loading, it is sufficient to validate only the loaded face and the loaded direction component
- the time range used by `post_surface_force` must match the computed run range instead of stopping at the example default

### Visualization postprocess rule

If `vis_3d_mixed` is requested or part of the default postprocess chain:

- update `paras_pos_vis.yml`
- make `time_start`, `time_step`, and `time_end` match the finished run
- make sure the visualization input is consistent with the finished material model
- make sure the expected number of internal variables matches the finished run

Consistency checks:

- `paras_pos_vis.yml.time_end` must not exceed the highest available `SOL_*.pvtu` index
- the visualization time range must match the finished run instead of an example template
- the material-model-related visualization settings must match the actual solved case
- the expected internal-variable count must match the generated outputs for the solved case

## Failure Policy

Stop immediately and explain the issue if you see any of these:

- bad geometry path expansion
- non-integral `time_end`
- inconsistent `cpu_size`
- compile errors
- load setup contradicts YAML boundary setup
- requested driver executable does not match loading type

## References

Read these only when needed:

- `references/mixperigee-mixed-workflows.md`
- `references/preprocessor-yaml-rules.md`
- `references/material-model-notes.md`
