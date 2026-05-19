#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${1:-${SCRIPT_DIR}/env.b200.local.sh}"

if [[ -f "$ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$ENV_FILE"
elif [[ -f "${SCRIPT_DIR}/env.b200.example.sh" ]]; then
  # shellcheck disable=SC1091
  source "${SCRIPT_DIR}/env.b200.example.sh"
fi

if [[ -z "${SGLANG_DIR:-}" ]]; then
  SGLANG_DIR="$(cd "${SCRIPT_DIR}/../sglang" && pwd)"
fi

PYTHON_BIN="${PYTHON_BIN:-python3}"
VENV_DIR="${VENV_DIR:-${SCRIPT_DIR}/.venv}"
INSTALL_SGLANG_FROM_SOURCE="${INSTALL_SGLANG_FROM_SOURCE:-1}"
INSTALL_ROUTER_FROM_SOURCE="${INSTALL_ROUTER_FROM_SOURCE:-1}"
INSTALL_TRANSFER_DEPS="${INSTALL_TRANSFER_DEPS:-1}"
TRANSFER_BACKEND="${TRANSFER_BACKEND:-mooncake}"

echo "Creating virtualenv: ${VENV_DIR}"
"$PYTHON_BIN" -m venv "$VENV_DIR"
# shellcheck disable=SC1091
source "${VENV_DIR}/bin/activate"

python -m pip install --upgrade pip uv

if [[ "$INSTALL_SGLANG_FROM_SOURCE" == "1" ]]; then
  echo "Installing SGLang from source: ${SGLANG_DIR}/python"
  uv pip install -e "${SGLANG_DIR}/python"
else
  echo "Installing SGLang from PyPI"
  uv pip install sglang
fi

if [[ "$INSTALL_ROUTER_FROM_SOURCE" == "1" && -x "$(command -v cargo || true)" ]]; then
  echo "Installing sglang-router from source"
  uv pip install maturin
  uv pip install -e "${SGLANG_DIR}/sgl-model-gateway/bindings/python"
else
  echo "Installing sglang-router from PyPI"
  uv pip install sglang-router
fi

if [[ "$INSTALL_TRANSFER_DEPS" == "1" ]]; then
  case "$TRANSFER_BACKEND" in
    mooncake)
      uv pip install mooncake-transfer-engine
      ;;
    nixl)
      uv pip install nixl
      ;;
    fake|"")
      ;;
    *)
      echo "No automatic transfer dependency install for TRANSFER_BACKEND=${TRANSFER_BACKEND}"
      ;;
  esac
fi

python - <<'PY'
import importlib

for module in ("sglang", "sglang_router"):
    importlib.import_module(module)
    print(f"import ok: {module}")
PY

echo "Activate with: source ${VENV_DIR}/bin/activate"
