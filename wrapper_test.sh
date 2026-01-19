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

exec "$script_dir/test.sh" --ta "$ta" --bishengir "$bishengir"
