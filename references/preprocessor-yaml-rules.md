# Preprocessor and loading rules for viscoelasticity creep cases

## Mesh refinement

The current default template is a single-patch setup.

- `num_inserted_x: [n]` means `n + 1` elements in x
- `num_inserted_y: [n]` means `n + 1` elements in y
- `num_inserted_z: [n]` means `n + 1` elements in z

Examples:

- `num_inserted_x: [0]` -> 1 element in x
- `num_inserted_x: [3]` -> 4 elements in x

If the user specifies the target element count, convert with:

`num_inserted_dir = target_elements - 1`

Do not infer direction if the user only says "refine the mesh".

## Boundary blocks

- `Dirichlet_velo_x`, `Dirichlet_velo_y`, `Dirichlet_velo_z` define zero-displacement constraints by direction and face
- `EBC` defines traction or Neumann faces only

`EBC` does not carry traction direction. The actual traction vector lives in `LoadData::surface_traction(...)`.

## `LoadData.hpp`

The actual load magnitudes and time profiles live in:

- `initial_velo(...)`
- `body_force(...)`
- `surface_traction(...)`
- `disp_loading(...)`
- `velo_loading(...)`

Boundary declarations and load functions must agree.

In standard usage, only one primary loading mode should be active at a time. When a real case is requested, update the relevant load function group and leave unrelated load functions at zero unless the user explicitly asks for combined loading.

## Traction loading pattern

For traction loading:

- modify only `paras_preprocessor.yml`
- do not modify `paras_preprocessor_init.yml`
- run only `preprocess3d`
- make `surface_traction(...)` nonzero on the requested loaded face and in the requested direction

For top-face traction:

- bottom face fixed in x
- bottom face fixed in y
- bottom face fixed in z
- top face added to `EBC`

## Displacement loading pattern

For displacement loading, whether tensile or shear:

- modify `paras_preprocessor.yml`
- modify `paras_preprocessor_init.yml`
- run `preprocess3d`
- then run `preprocess3d_init`
- make `disp_loading(...)` and `velo_loading(...)` match the requested displacement profile

In displacement-controlled cases:

- `paras_preprocessor.yml` stores the full runtime boundary setup
- `paras_preprocessor_init.yml` stores only the unique loaded direction-face entry

For top-face z displacement:

- `paras_preprocessor.yml`: bottom fixed in x/y/z, top added to `Dirichlet_velo_z`
- `paras_preprocessor_init.yml`: only `Dirichlet_velo_z: 0: [ 0, top ]`

For top-face y shear displacement:

- `paras_preprocessor.yml`: bottom fixed in x/y/z, top added to `Dirichlet_velo_y`
- `paras_preprocessor_init.yml`: only `Dirichlet_velo_y: 0: [ 0, top ]`

Top displacement faces should not be added to `EBC`.

## Consistency checks

Examples of contradictions that should be flagged:

- `EBC` declares top traction, but `surface_traction(...)` is zero on `Orientation::top`
- user asks for y traction, but `surface_traction(...)` returns only a z component
- user asks for top y displacement, but `paras_preprocessor_init.yml` writes `Dirichlet_velo_z`
- user asks for pure displacement loading, but the same face is still present in `EBC`
- user asks for zero initial velocity, but `initial_velo(...)` is nonzero

## `paras_preprocessor_init.yml`

This file is nearly the same as `paras_preprocessor.yml`, but it should remain minimal and is only needed for displacement-controlled cases.

Use it for the initialization-specific loaded direction-face declaration rather than the full runtime boundary declaration.
