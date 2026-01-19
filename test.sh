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

echo "ta=$ta"
echo "bishengir=$bishengir"
