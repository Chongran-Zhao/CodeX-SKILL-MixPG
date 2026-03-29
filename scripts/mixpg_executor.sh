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
preprocess_log=""

example_dir=""
config_file=""
input_dir=""
preprocessor_file=""
preprocessor_init_file=""
build_dir_action="unknown"
input_copy_status="pending"
build_status="not_started"
build_exit_code="null"
preprocess_status="not_started"
preprocess_case_type="unknown"
preprocess_reason="not_determined"
preprocess_command_display="[]"
preprocess_exit_codes_json="[]"
preprocess_geo_file_base=""
preprocess_geo_file_resolved=""
preprocess_runtime_yaml_present="false"
preprocess_init_yaml_present="false"
top_level_status="pending"
next_step="build_pending"
failure_json="null"
build_dir_exists_before="false"
build_command_display=""
current_stage="build"

usage() {
  cat <<'EOF'
Usage:
  mixpg_executor.sh [--repo-root DIR] [--build-dir DIR] [--state-file FILE] [--clean]

Implemented stages:
  - build
  - preprocess

Build/preprocess tasks only:
  - validate build prerequisites
  - run the repository build preparation flow
  - detect preprocess case type conservatively
  - run the required preprocess command(s)
  - write/update a state file
  - capture stage logs

Guardrails:
  - only build and preprocess-stage support are implemented
  - does not run solver, driver, or postprocess commands
  - only removes build directory contents when --clean is explicitly provided
EOF
}

resolve_paths() {
  example_dir="${repo_root}/examples/viscoelasticity_NURBS_TaylorHood"
  config_file="${repo_root}/conf/system_lib_loading.cmake"
  input_dir="${example_dir}/input/creep"
  preprocessor_file="${build_dir}/paras_preprocessor.yml"
  preprocessor_init_file="${build_dir}/paras_preprocessor_init.yml"
  log_dir="$(dirname "$state_file")/logs"
  build_log="${log_dir}/build-stage.log"
  preprocess_log="${log_dir}/preprocess-stage.log"
}

json_bool() {
  if [[ "$1" == "true" ]]; then
    echo "true"
  else
    echo "false"
  fi
}

record_failure() {
  local stage="$current_stage"
  local log_file="$build_log"
  local message="$1"
  local exit_code="$2"
  if [[ "$stage" == "preprocess" ]]; then
    log_file="$preprocess_log"
  fi
  failure_json=$(cat <<EOF
{
  "stage": "$stage",
  "message": "$message",
  "exit_code": $exit_code,
  "log_file": "$log_file"
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

yaml_block_has_entries() {
  local file="$1"
  local block="$2"
  awk -v block="$block" '
    $0 ~ "^" block ":" {
      inblock=1
      next
    }
    inblock {
      if ($0 ~ /^[^[:space:]].*:/) {
        exit found ? 0 : 1
      }
      if ($0 ~ /^[[:space:]]*$/) next
      if ($0 ~ /^[[:space:]]*#/) next
      found=1
    }
    END {
      if (inblock && found) exit 0
      exit 1
    }
  ' "$file"
}

resolve_geo_file_base() {
  local raw_value
  raw_value="$(awk '
    /^[[:space:]]*geo_file_base[[:space:]]*:/ {
      sub(/^[^:]*:[[:space:]]*/, "", $0)
      print $0
      exit
    }
  ' "$preprocessor_file")"

  if [[ -z "$raw_value" ]]; then
    return 1
  fi

  raw_value="${raw_value#"${raw_value%%[![:space:]]*}"}"
  raw_value="${raw_value%"${raw_value##*[![:space:]]}"}"

  if [[ "$raw_value" == \"*\" && "$raw_value" == *\" ]]; then
    raw_value="${raw_value:1:-1}"
  fi
  if [[ "$raw_value" == \'*\' && "$raw_value" == *\' ]]; then
    raw_value="${raw_value:1:-1}"
  fi

  preprocess_geo_file_base="$raw_value"

  if [[ "$raw_value" == /* ]]; then
    preprocess_geo_file_resolved="$raw_value"
  else
    preprocess_geo_file_resolved="${build_dir}/${raw_value}"
  fi

  [[ -f "${preprocess_geo_file_resolved}0.yml" ]]
}

detect_preprocess_case_type() {
  local ebc_has_entries="false"
  local init_count=0
  local dir_block=""

  if yaml_block_has_entries "$preprocessor_file" "EBC"; then
    ebc_has_entries="true"
  fi

  if [[ -f "$preprocessor_init_file" ]]; then
    preprocess_init_yaml_present="true"
    for dir_block in Dirichlet_velo_x Dirichlet_velo_y Dirichlet_velo_z; do
      if yaml_block_has_entries "$preprocessor_init_file" "$dir_block"; then
        init_count=$((init_count + 1))
      fi
    done
  else
    preprocess_init_yaml_present="false"
  fi

  if [[ "$ebc_has_entries" == "true" && "$init_count" -eq 0 ]]; then
    preprocess_case_type="traction"
    preprocess_reason="runtime EBC has entries and init YAML has no displacement-specific Dirichlet entries"
    preprocess_command_display="[\"./preprocess3d\"]"
    return 0
  fi

  if [[ "$ebc_has_entries" == "false" && "$init_count" -eq 1 ]]; then
    preprocess_case_type="displacement"
    preprocess_reason="runtime EBC is empty and init YAML has exactly one displacement-specific Dirichlet block"
    preprocess_command_display="[\"./preprocess3d\", \"./preprocess3d_init\"]"
    return 0
  fi

  preprocess_case_type="unknown"
  preprocess_reason="unable to determine case type safely from EBC and paras_preprocessor_init.yml"
  return 1
}

validate_preprocess_inputs() {
  if [[ ! -f "$preprocessor_file" ]]; then
    echo "Required preprocess file not found: $preprocessor_file" >&2
    current_stage="preprocess"
    record_failure "required preprocess file not found" 1
    preprocess_status="failed"
    top_level_status="failed"
    next_step="inspect_preprocess_log"
    write_state
    exit 1
  fi

  preprocess_runtime_yaml_present="true"

  if ! resolve_geo_file_base; then
    echo "Invalid or unresolved geo_file_base in: $preprocessor_file" >&2
    current_stage="preprocess"
    record_failure "invalid or unresolved geo_file_base" 1
    preprocess_status="failed"
    top_level_status="failed"
    next_step="inspect_preprocess_log"
    write_state
    exit 1
  fi

  if ! detect_preprocess_case_type; then
    echo "Case type could not be determined safely from preprocess YAML files." >&2
    current_stage="preprocess"
    record_failure "case type could not be determined safely" 1
    preprocess_status="failed"
    top_level_status="failed"
    next_step="inspect_preprocess_log"
    write_state
    exit 1
  fi

  if [[ ! -x "${build_dir}/preprocess3d" ]]; then
    echo "Required preprocess executable not found: ${build_dir}/preprocess3d" >&2
    current_stage="preprocess"
    record_failure "required preprocess executable not found: preprocess3d" 1
    preprocess_status="failed"
    top_level_status="failed"
    next_step="inspect_preprocess_log"
    write_state
    exit 1
  fi

  if [[ "$preprocess_case_type" == "displacement" && ! -x "${build_dir}/preprocess3d_init" ]]; then
    echo "Required preprocess executable not found: ${build_dir}/preprocess3d_init" >&2
    current_stage="preprocess"
    record_failure "required preprocess executable not found: preprocess3d_init" 1
    preprocess_status="failed"
    top_level_status="failed"
    next_step="inspect_preprocess_log"
    write_state
    exit 1
  fi
}

run_preprocess_stage() {
  local -a preprocess_commands
  local -a preprocess_exit_codes=()
  local command_exit_code=0

  preprocess_status="running"
  current_stage="preprocess"
  top_level_status="running"
  next_step="preprocess_running"
  write_state

  {
    printf '[mixpg] preprocess case type: %s\n' "$preprocess_case_type"
    printf '[mixpg] preprocess reason: %s\n' "$preprocess_reason"
    printf '[mixpg] preprocess runtime yaml: %s\n' "$preprocessor_file"
    printf '[mixpg] preprocess init yaml present: %s\n' "$preprocess_init_yaml_present"
    printf '[mixpg] geo_file_base: %s\n' "$preprocess_geo_file_base"
    printf '[mixpg] geo_file_base resolved: %s\n' "$preprocess_geo_file_resolved"
  } >"$preprocess_log"

  preprocess_commands=( "./preprocess3d" )
  if [[ "$preprocess_case_type" == "displacement" ]]; then
    preprocess_commands+=( "./preprocess3d_init" )
  fi

  for preprocess_command in "${preprocess_commands[@]}"; do
    {
      printf '[mixpg] preprocess command: %s\n' "$preprocess_command"
      printf '[mixpg] preprocess cwd: %s\n' "$build_dir"
    } >>"$preprocess_log"

    (
      cd "$build_dir"
      "$preprocess_command"
    ) >>"$preprocess_log" 2>&1 || command_exit_code=$?

    preprocess_exit_codes+=( "$command_exit_code" )
    if [[ "$command_exit_code" -ne 0 ]]; then
      preprocess_exit_codes_json="["
      for exit_code in "${preprocess_exit_codes[@]}"; do
        preprocess_exit_codes_json="${preprocess_exit_codes_json}${exit_code}, "
      done
      preprocess_exit_codes_json="${preprocess_exit_codes_json%, }]"
      preprocess_status="failed"
      top_level_status="failed"
      next_step="inspect_preprocess_log"
      build_exit_code=0
      current_stage="preprocess"
      record_failure "preprocess stage failed" "$command_exit_code"
      write_state
      return 1
    fi
    command_exit_code=0
  done

  preprocess_exit_codes_json="["
  for exit_code in "${preprocess_exit_codes[@]}"; do
    preprocess_exit_codes_json="${preprocess_exit_codes_json}${exit_code}, "
  done
  preprocess_exit_codes_json="${preprocess_exit_codes_json%, }]"

  preprocess_status="completed"
  top_level_status="ready"
  next_step="driver_not_implemented"
  current_stage="preprocess"
  failure_json="null"
  write_state
}

write_state() {
  local state_dir
  state_dir="$(dirname "$state_file")"
  mkdir -p "$state_dir"

  cat > "$state_file" <<EOF
{
  "version": 1,
  "workflow": "mixpg-build-preprocess",
  "current_stage": "$current_stage",
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
      "status": "$preprocess_status",
      "case_type": "$preprocess_case_type",
      "reason": "$preprocess_reason",
      "runtime_yaml": "$preprocessor_file",
      "runtime_yaml_present": $(json_bool "$preprocess_runtime_yaml_present"),
      "init_yaml": "$preprocessor_init_file",
      "init_yaml_present": $(json_bool "$preprocess_init_yaml_present"),
      "geo_file_base": "$preprocess_geo_file_base",
      "geo_file_base_resolved": "$preprocess_geo_file_resolved",
      "commands": $preprocess_command_display,
      "log_file": "$preprocess_log",
      "exit_codes": $preprocess_exit_codes_json
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
  top_level_status="running"
  next_step="preprocess_pending"
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

if [[ "$build_status" == "completed" ]]; then
  validate_preprocess_inputs
  run_preprocess_stage
fi

echo "[mixpg] build stage status: $build_status"
echo "[mixpg] preprocess stage status: $preprocess_status"
echo "[mixpg] state file: $state_file"
echo "[mixpg] build log: $build_log"
echo "[mixpg] preprocess log: $preprocess_log"
