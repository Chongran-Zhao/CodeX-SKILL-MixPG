#!/usr/bin/env python3
"""Render a MixPG report package from an existing build directory."""

from __future__ import annotations

import argparse
import glob
import os
import subprocess
from pathlib import Path

import matplotlib.pyplot as plt
import meshio
import numpy as np


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--build-dir", required=True, help="MixPG build directory")
    parser.add_argument("--template", required=True, help="Markdown template path")
    parser.add_argument("--report-dir", help="Output report directory; defaults to <build-dir>/report")
    parser.add_argument("--case-title", required=True)
    parser.add_argument("--loading-mode", required=True)
    parser.add_argument("--loaded-face", required=True)
    parser.add_argument("--loaded-direction", required=True)
    parser.add_argument("--loading-expression", required=True)
    parser.add_argument("--initial-time", required=True)
    parser.add_argument("--final-time", required=True)
    parser.add_argument("--initial-step", required=True)
    parser.add_argument("--cpu-size", required=True)
    parser.add_argument("--geometry-shape", required=True)
    parser.add_argument("--geometry-size", required=True)
    parser.add_argument("--mesh-summary", required=True)
    parser.add_argument("--loaded-face-area", required=True)
    parser.add_argument("--constitutive-model", required=True)
    parser.add_argument("--volumetric-model", required=True)
    parser.add_argument("--elastic-model", required=True)
    parser.add_argument("--visco-model", required=True)
    parser.add_argument("--num-visco", required=True)
    parser.add_argument("--driver-status", required=True)
    parser.add_argument("--reanalysis-setting", required=True)
    parser.add_argument("--postprocess-status", required=True)
    parser.add_argument("--peak-step", type=int, default=25)
    parser.add_argument("--time-scale", type=float, default=0.01, help="Physical time per recorded step")
    parser.add_argument("--interpretation", required=True)
    return parser.parse_args()


def check_exists(path: Path, label: str) -> None:
    if not path.exists():
        raise FileNotFoundError(f"Missing {label}: {path}")


def render_surface_traction_figure(force_file: Path, out_path: Path, time_scale: float) -> dict[str, str]:
    data = np.loadtxt(force_file)
    if data.ndim != 2 or data.shape[1] < 4:
      raise ValueError(f"Unexpected force record shape: {data.shape}")

    time_idx = data[:, 0]
    disp = data[:, 2]
    traction = data[:, 3]

    if not np.all(np.isfinite(traction)):
        raise ValueError("Invalid traction values found in Force_disp_record.txt")

    time_s = time_idx * time_scale

    plt.rcParams.update(
        {
            "font.size": 11,
            "axes.titlesize": 12,
            "axes.labelsize": 11,
            "legend.fontsize": 10,
            "figure.dpi": 180,
        }
    )

    fig, axes = plt.subplots(1, 2, figsize=(11, 4.6), constrained_layout=True)

    ax = axes[0]
    ax.plot(disp, traction, color="#1f4e79", lw=2.2)
    ax.scatter(disp[::10], traction[::10], color="#c23b22", s=16, zorder=3)
    ax.set_xlabel("Average top-surface displacement in x [m]")
    ax.set_ylabel("Average top-surface traction in x [Pa]")
    ax.set_title("Shear traction-displacement response")
    ax.grid(True, alpha=0.25)

    ax = axes[1]
    ax.plot(time_s, disp, color="#1f4e79", lw=2.0, label="u_x")
    ax2 = ax.twinx()
    ax2.plot(time_s, traction, color="#c23b22", lw=1.8, label="t_x")
    ax.set_xlabel("Time [s]")
    ax.set_ylabel("Average top-surface displacement in x [m]", color="#1f4e79")
    ax2.set_ylabel("Average top-surface traction in x [Pa]", color="#c23b22")
    ax.set_title("Time histories on the loaded top surface")
    ax.grid(True, alpha=0.25)
    lines = ax.get_lines() + ax2.get_lines()
    labels = [line.get_label() for line in lines]
    ax.legend(lines, labels, loc="upper right", frameon=False)

    fig.suptitle("Top-face x-shear postprocess summary", fontsize=13)
    fig.savefig(out_path, facecolor="white", bbox_inches="tight")
    plt.close(fig)

    i_max = int(np.argmax(disp))
    i_min = int(np.argmin(disp))
    i_tmax = int(np.argmax(traction))
    i_tmin = int(np.argmin(traction))

    return {
        "disp_max": f"{disp[i_max]:.6e} m at step {int(time_idx[i_max])}",
        "disp_min": f"{disp[i_min]:.6e} m at step {int(time_idx[i_min])}",
        "traction_max": f"{traction[i_tmax]:.6e} Pa at step {int(time_idx[i_tmax])}",
        "traction_min": f"{traction[i_tmin]:.6e} Pa at step {int(time_idx[i_tmin])}",
    }


def render_visualization_figure(build_dir: Path, peak_step: int, out_path: Path) -> None:
    vtus = sorted(glob.glob(str(build_dir / f"SOL_{peak_step:08d}_p*.vtu")))
    if not vtus:
        raise FileNotFoundError(f"No VTU files found for step {peak_step}")

    all_points = []
    all_ux = []
    for path in vtus:
        mesh = meshio.read(path)
        if "Displacement" not in mesh.point_data:
            raise KeyError(f"Displacement point_data missing in {path}")
        points = mesh.points[:, :3]
        disp = mesh.point_data["Displacement"]
        all_points.append(points + disp)
        all_ux.append(disp[:, 0])

    pts = np.vstack(all_points)
    ux = np.hstack(all_ux)

    stride = max(1, len(pts) // 2500)
    pts = pts[::stride]
    ux = ux[::stride]

    fig = plt.figure(figsize=(7.0, 6.0), constrained_layout=True)
    ax = fig.add_subplot(111, projection="3d")
    sc = ax.scatter(pts[:, 0], pts[:, 1], pts[:, 2], c=ux, cmap="coolwarm", s=8, alpha=0.9)
    ax.set_xlabel("x [m]")
    ax.set_ylabel("y [m]")
    ax.set_zlabel("z [m]")
    ax.set_title(f"Deformed configuration at peak positive shear (step {peak_step})")
    ax.view_init(elev=22, azim=-58)
    cb = fig.colorbar(sc, ax=ax, shrink=0.72, pad=0.08)
    cb.set_label("u_x [m]")
    fig.savefig(out_path, facecolor="white", bbox_inches="tight")
    plt.close(fig)


def fill_template(template_text: str, values: dict[str, str]) -> str:
    rendered = template_text
    for key, value in values.items():
        rendered = rendered.replace(f"{{{{{key}}}}}", value)
    return rendered


def main() -> int:
    args = parse_args()

    build_dir = Path(args.build_dir).expanduser().resolve()
    template_path = Path(args.template).expanduser().resolve()
    report_dir = Path(args.report_dir).expanduser().resolve() if args.report_dir else build_dir / "report"
    report_dir.mkdir(parents=True, exist_ok=True)

    force_file = build_dir / "Force_disp_record.txt"
    check_exists(template_path, "report template")
    check_exists(force_file, "Force_disp_record.txt")

    traction_fig = report_dir / "surface_traction_response.png"
    vis_fig = report_dir / f"visualization_peak_step{args.peak_step}.png"
    report_md = report_dir / "report.md"
    report_pdf = report_dir / "report.pdf"

    stats = render_surface_traction_figure(force_file, traction_fig, args.time_scale)
    render_visualization_figure(build_dir, args.peak_step, vis_fig)

    values = {
        "case_title": args.case_title,
        "loading_mode": args.loading_mode,
        "loaded_face": args.loaded_face,
        "loaded_direction": args.loaded_direction,
        "loading_expression": args.loading_expression,
        "initial_time": args.initial_time,
        "final_time": args.final_time,
        "initial_step": args.initial_step,
        "cpu_size": args.cpu_size,
        "geometry_shape": args.geometry_shape,
        "geometry_size": args.geometry_size,
        "mesh_summary": args.mesh_summary,
        "loaded_face_area": args.loaded_face_area,
        "constitutive_model": args.constitutive_model,
        "volumetric_model": args.volumetric_model,
        "elastic_model": args.elastic_model,
        "visco_model": args.visco_model,
        "num_visco": args.num_visco,
        "driver_status": args.driver_status,
        "reanalysis_setting": args.reanalysis_setting,
        "postprocess_status": args.postprocess_status,
        "surface_traction_figure": traction_fig.name,
        "visualization_figure": vis_fig.name,
        "interpretation": args.interpretation,
        **stats,
    }

    template_text = template_path.read_text(encoding="utf-8")
    report_md.write_text(fill_template(template_text, values), encoding="utf-8")

    subprocess.run(
        ["pandoc", report_md.name, "-o", report_pdf.name, "--pdf-engine=xelatex"],
        cwd=report_dir,
        check=True,
    )

    print("WROTE", report_md)
    print("WROTE", report_pdf)
    print("WROTE", traction_fig)
    print("WROTE", vis_fig)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
