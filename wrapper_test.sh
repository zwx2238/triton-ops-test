#!/usr/bin/env bash
set -euo pipefail

ta=""
bishengir=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --ta)
      ta="${2-}"
      shift 2
      ;;
    --bishengir)
      bishengir="${2-}"
      shift 2
      ;;
    *)
      echo "Unknown arg: $1" >&2
      echo "Usage: $0 --ta <src|dst> --bishengir <src|dst>" >&2
      exit 1
      ;;
  esac
done

if [[ -z "$ta" || -z "$bishengir" ]]; then
  echo "Missing required args." >&2
  echo "Usage: $0 --ta <src|dst> --bishengir <src|dst>" >&2
  exit 1
fi

if [[ "$ta" != "src" && "$ta" != "dst" ]]; then
  echo "--ta must be src or dst" >&2
  exit 1
fi

if [[ "$bishengir" != "src" && "$bishengir" != "dst" ]]; then
  echo "--bishengir must be src or dst" >&2
  exit 1
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
env_file="${TEST_ENV_FILE:-$script_dir/test_env.sh}"
if [[ ! -f "$env_file" ]]; then
  echo "Test env file not found: $env_file" >&2
  exit 1
fi
# shellcheck source=/dev/null
source "$env_file"

# Resolve TA conda env
if [[ "$ta" == "src" ]]; then
  ta_env="$TA_SRC_ENV"
else
  ta_env="$TA_DST_ENV"
fi

if [[ -z "${ta_env:-}" ]]; then
  echo "TA conda env name is not configured in $env_file" >&2
  exit 1
fi

# Resolve bishengir dir
if [[ "$bishengir" == "src" ]]; then
  bishengir_dir="$BISHENGIR_SRC_DIR"
else
  bishengir_dir="$BISHENGIR_DST_DIR"
fi

if [[ -z "${bishengir_dir:-}" ]]; then
  echo "Bishengir dir is not configured in $env_file" >&2
  exit 1
fi

if [[ ! -d "$bishengir_dir" ]]; then
  echo "Bishengir dir not found: $bishengir_dir" >&2
  exit 1
fi

# Resolve DUMP_DIR for Triton IR dumps
if [[ -z "${DUMP_BASE_DIR:-}" ]]; then
  echo "DUMP_BASE_DIR is not configured in $env_file" >&2
  exit 1
fi

if [[ -e "$DUMP_BASE_DIR" && ! -d "$DUMP_BASE_DIR" ]]; then
  echo "DUMP_BASE_DIR is not a directory: $DUMP_BASE_DIR" >&2
  exit 1
fi

dump_base_dir="$DUMP_BASE_DIR"
if [[ "$dump_base_dir" != "/" ]]; then
  dump_base_dir="${dump_base_dir%/}"
fi

if [[ "$dump_base_dir" != /* ]]; then
  echo "DUMP_BASE_DIR must be an absolute path: $dump_base_dir" >&2
  exit 1
fi

if [[ "$dump_base_dir" == "/" ]]; then
  echo "DUMP_BASE_DIR cannot be '/'" >&2
  exit 1
fi

export DUMP_BASE_DIR
export TRITON_DUMP_SUFFIX="ta_${ta}_bishengir_${bishengir}"
export TRITON_KERNEL_DUMP="${TRITON_KERNEL_DUMP:-1}"

# Activate conda env for TA
if ! command -v conda >/dev/null 2>&1; then
  echo "conda not found in PATH" >&2
  exit 1
fi

conda_base="$(conda info --base 2>/dev/null || true)"
if [[ -z "$conda_base" || ! -f "$conda_base/etc/profile.d/conda.sh" ]]; then
  echo "Unable to locate conda.sh" >&2
  exit 1
fi

# shellcheck source=/dev/null
source "$conda_base/etc/profile.d/conda.sh"
conda activate "$ta_env"

# Prepend bishengir dir to PATH
export PATH="$bishengir_dir:$PATH"

status=0
"$script_dir/test.sh" --ta "$ta" --bishengir "$bishengir" || status=$?

simplify_failed=0
while IFS= read -r -d '' mlir_file; do
  if [[ "$mlir_file" == *-simplify.mlir ]]; then
    continue
  fi
  simplify_out="${mlir_file%.mlir}-simplify.mlir"
  if ! python3 "$script_dir/simplify_mlir.py" "$mlir_file" -o "$simplify_out"; then
    echo "simplify_mlir failed: $mlir_file" >&2
    simplify_failed=1
  fi
done < <(find "$dump_base_dir" -type f -name "*.mlir" -print0)

if [[ "$status" -eq 0 && "$simplify_failed" -ne 0 ]]; then
  status=1
fi

exit "$status"
