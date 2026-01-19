#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

tmp_dir="$(mktemp -d)"
cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

fake_conda_base="$tmp_dir/fake_conda"
mkdir -p "$fake_conda_base/bin" "$fake_conda_base/etc/profile.d"

cat > "$fake_conda_base/bin/conda" <<EOF1
#!/usr/bin/env bash
if [[ "\${1-}" == "info" && "\${2-}" == "--base" ]]; then
  echo "$fake_conda_base"
  exit 0
fi
echo "fake conda: unsupported args: \$*" >&2
exit 1
EOF1
chmod +x "$fake_conda_base/bin/conda"

cat > "$fake_conda_base/etc/profile.d/conda.sh" <<'EOF2'
conda() {
  if [[ "${1-}" == "activate" ]]; then
    export CONDA_DEFAULT_ENV="${2-}"
    return 0
  fi
  return 0
}
EOF2

bishengir_src="$tmp_dir/bishengir/src/bin"
bishengir_dst="$tmp_dir/bishengir/dst/bin"
mkdir -p "$bishengir_src" "$bishengir_dst"

cat > "$tmp_dir/test_env.sh" <<EOF3
TA_SRC_ENV="ta_src_env"
TA_DST_ENV="ta_dst_env"
BISHENGIR_SRC_DIR="$bishengir_src"
BISHENGIR_DST_DIR="$bishengir_dst"
EOF3

if ! output="$(PATH="$fake_conda_base/bin:$PATH" TEST_ENV_FILE="$tmp_dir/test_env.sh" "$repo_dir/wrapper_test.sh" --ta src --bishengir dst)"; then
  echo "Wrapper failed" >&2
  exit 1
fi

if [[ "$output" != *"ta=src"* || "$output" != *"bishengir=dst"* ]]; then
  echo "Unexpected output:" >&2
  echo "$output" >&2
  exit 1
fi

echo "E2E OK"
