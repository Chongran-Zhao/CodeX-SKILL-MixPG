#!/usr/bin/env bash
set -euo pipefail

repo_root="${HOME}/MixPERIGEE"
build_dir="${HOME}/build_MixPG"
state_file="state/state.json"
clean_build="false"

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
build_script="${script_dir}/prepare_visco_build.sh"
log_dir=""
build_log=""

example_dir=""
config_file=""
input_dir=""
build_dir_action="unknown"
input_copy_status="pending"
build_status="not_started"
build_exit_code="null"
top_level_status="pending"
next_step="build_pending"
failure_json="null"
build_dir_exists_before="false"
build_command_display=""

usage() {
  cat <<'EOF'
Usage:
  mixpg_executor.sh [--repo-root DIR] [--build-dir DIR] [--state-file FILE] [--clean]

Build-stage tasks only:
  - validate build prerequisites
  - run the repository build preparation flow
  - write/update a state file
  - capture a build log

Guardrails:
  - only build-stage support is implemented
  - does not run preprocess, preprocess_init, solver, or postprocess commands
  - only removes build directory contents when --clean is explicitly provided
EOF
}

resolve_paths() {
  example_dir="${repo_root}/examples/viscoelasticity_NURBS_TaylorHood"
  config_file="${repo_root}/conf/system_lib_loading.cmake"
  input_dir="${example_dir}/input/creep"
  log_dir="$(dirname "$state_file")/logs"
  build_log="${log_dir}/build-stage.log"
}

json_bool() {
  if [[ "$1" == "true" ]]; then
    echo "true"
  else
    echo "false"
  fi
}

record_failure() {
  local message="$1"
  local exit_code="$2"
  failure_json=$(cat <<EOF
{
  "stage": "build",
  "message": "$message",
  "exit_code": $exit_code,
  "log_file": "$build_log"
}
EOF
)
}

validate_prerequisites() {
  if [[ ! -x "$build_script" ]]; then
    echo "Build script is missing or not executable: $build_script" >&2
    record_failure "build script is missing or not executable" 1
    build_status="failed"
    top_level_status="failed"
    next_step="inspect_build_log"
    write_state
    exit 1
  fi

  if ! command -v cmake >/dev/null 2>&1; then
    echo "Required command not found: cmake" >&2
    record_failure "required command not found: cmake" 1
    build_status="failed"
    top_level_status="failed"
    next_step="inspect_build_log"
    write_state
    exit 1
  fi

  if ! command -v make >/dev/null 2>&1; then
    echo "Required command not found: make" >&2
    record_failure "required command not found: make" 1
    build_status="failed"
    top_level_status="failed"
    next_step="inspect_build_log"
    write_state
    exit 1
  fi
}

write_state() {
  local state_dir
  state_dir="$(dirname "$state_file")"
  mkdir -p "$state_dir"

  cat > "$state_file" <<EOF
{
  "version": 1,
  "workflow": "mixpg-build-stage",
  "current_stage": "build",
  "status": "$top_level_status",
  "requested": {
    "clean_build": $(json_bool "$clean_build")
  },
  "paths": {
    "repo_root": "$repo_root",
    "example_dir": "$example_dir",
    "config_file": "$config_file",
    "input_dir": "$input_dir",
    "build_dir": "$build_dir"
  },
  "stages": {
    "safe_prepare": {
      "status": "$([[ "$build_status" == "completed" ]] && echo "completed" || echo "delegated_to_build")",
      "build_dir_action": "$build_dir_action",
      "input_copy": "$input_copy_status"
    },
    "build": {
      "status": "$build_status",
      "script": "$build_script",
      "command": "$build_command_display",
      "log_file": "$build_log",
      "build_dir_exists_before": $(json_bool "$build_dir_exists_before"),
      "exit_code": $build_exit_code
    },
    "preprocess": {
      "status": "not_started"
    },
    "driver": {
      "status": "not_started"
    },
    "postprocess": {
      "status": "not_started"
    }
  },
  "failure": $failure_json,
  "next_step": "$next_step"
}
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo-root)
      repo_root="$2"
      shift 2
      ;;
    --build-dir)
      build_dir="$2"
      shift 2
      ;;
    --state-file)
      state_file="$2"
      shift 2
      ;;
    --clean)
      clean_build="true"
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

resolve_paths
mkdir -p "$log_dir"

if [[ -d "$build_dir" ]]; then
  build_dir_exists_before="true"
  if [[ "$clean_build" == "true" ]]; then
    build_dir_action="cleaned"
  else
    build_dir_action="blocked_existing_dir"
  fi
else
  build_dir_action="created"
fi

if [[ ! -f "$config_file" ]]; then
  echo "Required config file not found: $config_file" >&2
  record_failure "required config file not found" 1
  build_status="failed"
  top_level_status="failed"
  next_step="inspect_build_log"
  write_state
  exit 1
fi

if [[ ! -d "$example_dir" ]]; then
  echo "Example directory not found: $example_dir" >&2
  record_failure "example directory not found" 1
  build_status="failed"
  top_level_status="failed"
  next_step="inspect_build_log"
  write_state
  exit 1
fi

if [[ ! -d "$input_dir" ]]; then
  echo "Input directory not found: $input_dir" >&2
  record_failure "input directory not found" 1
  build_status="failed"
  top_level_status="failed"
  next_step="inspect_build_log"
  write_state
  exit 1
fi

validate_prerequisites

build_status="running"
top_level_status="running"
next_step="build_running"
write_state

build_command=( "$build_script" "--repo-root" "$repo_root" "--build-dir" "$build_dir" )
if [[ "$clean_build" == "true" ]]; then
  build_command+=( "--clean" )
fi
printf -v build_command_display '%q ' "${build_command[@]}"
build_command_display="${build_command_display% }"

{
  printf '[mixpg] build script: %s\n' "$build_script"
  printf '[mixpg] build command:'
  printf ' %q' "${build_command[@]}"
  printf '\n'
} >"$build_log"

if "${build_command[@]}" >>"$build_log" 2>&1; then
  build_status="completed"
  build_exit_code=0
  input_copy_status="copied"
  top_level_status="ready"
  next_step="preprocess_not_implemented"
  failure_json="null"
else
  build_exit_code=$?
  build_status="failed"
  input_copy_status="unknown"
  top_level_status="failed"
  next_step="inspect_build_log"
  record_failure "build stage failed" "$build_exit_code"
fi

write_state

echo "[mixpg] build stage status: $build_status"
echo "[mixpg] state file: $state_file"
echo "[mixpg] build log: $build_log"
