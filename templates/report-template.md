# MixPG Report: {{case_title}}

## Case Summary

- Loading mode: {{loading_mode}}
- Loaded face: {{loaded_face}}
- Loaded direction: {{loaded_direction}}
- Prescribed loading: {{loading_expression}}
- Time range: {{initial_time}} to {{final_time}} s
- Time step: {{initial_step}} s
- MPI size: {{cpu_size}}

## Geometry And Mesh

- Geometry: {{geometry_shape}}
- Physical size: {{geometry_size}}
- Mesh: {{mesh_summary}}
- Loaded-face area: {{loaded_face_area}}

## Constitutive Model

- Total model: {{constitutive_model}}
- Volumetric part: {{volumetric_model}}
- Isochoric elastic part: {{elastic_model}}
- Viscous part: {{visco_model}}
- Number of viscoelastic internal-variable groups: {{num_visco}}

## Solver And Postprocess Notes

- Driver outcome: {{driver_status}}
- Reanalysis setting: {{reanalysis_setting}}
- Postprocess outcome: {{postprocess_status}}

## Key Quantitative Observations

- Maximum loaded-direction displacement: {{disp_max}}
- Minimum loaded-direction displacement: {{disp_min}}
- Maximum loaded-direction traction or force: {{traction_max}}
- Minimum loaded-direction traction or force: {{traction_min}}

## Surface Traction Figure

![Surface traction response]({{surface_traction_figure}})

## Visualization Figure

![Visualization figure]({{visualization_figure}})

## Interpretation

{{interpretation}}
