#!/usr/bin/env bash
set -euo pipefail

variant="${1:?usage: smoke_test.sh <arkjsvm|arkvm>}"
work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT

assert_contains() {
  local output="$1"
  local expected="$2"
  if grep -Fq "$expected" <<<"$output"; then
    echo "PASS: output contains '$expected'"
  else
    echo "FAIL: expected output to contain '$expected'"
    echo "Actual output:"
    echo "$output"
    exit 1
  fi
}

find_tool_file() {
  local root="$1"
  local name="$2"
  find "$root" -type f -name "$name" | head -n 1
}

write_arktsconfig() {
  local static_core_root="$1"
  local out_file="$2"

  cat > "$out_file" <<JSON
{
  "compilerOptions": {
    "baseUrl": "${static_core_root}",
    "paths": {
      "std": ["${static_core_root}/plugins/ets/stdlib/std"],
      "escompat": ["${static_core_root}/plugins/ets/stdlib/escompat"],
      "api": ["${static_core_root}/plugins/ets/sdk/api"],
      "arkts": ["${static_core_root}/plugins/ets/sdk/arkts"]
    }
  }
}
JSON
}

run_arkvm_compiled_ets() {
  local static_core_root="$1"
  local etsstdlib_path="$2"
  local arktsconfig_path="$work_dir/arktsconfig.json"

  write_arktsconfig "$static_core_root" "$arktsconfig_path"
  cp example/hello.ets "$work_dir/hello.ets"

  (
    cd "$work_dir"
    es2panda --arktsconfig "$arktsconfig_path" --extension ets --output hello.abc hello.ets
    if ! output="$(ark --boot-panda-files="$etsstdlib_path" --load-runtimes=ets hello.abc hello/ETSGLOBAL::main 2>&1)"; then
      echo "$output"
      exit 1
    fi
    echo "$output"
    assert_contains "$output" "Hello World"
  )
}

run_arkvm_bundled_abc() {
  local arkvm_root="$1"
  local etsstdlib_path="$2"
  local hello_abc_path="$3"

  es2panda --help >/dev/null 2>&1 || true
  if ! output="$(ark --boot-panda-files="$etsstdlib_path" --load-runtimes=ets "$hello_abc_path" hello/ETSGLOBAL::main 2>&1)"; then
    echo "$output"
    exit 1
  fi
  echo "$output"
  assert_contains "$output" "Hello world!"
}

case "$variant" in
  arkjsvm)
    echo "--- Running arkjsvm smoke test ---"
    command -v es2abc >/dev/null
    command -v ark_js_vm >/dev/null
    cp example/hello.ts "$work_dir/hello.ts"
    (
      cd "$work_dir"
      es2abc hello.ts --output hello.abc
      if ! output="$(ark_js_vm hello.abc 2>&1)"; then
        echo "$output"
        exit 1
      fi
      echo "$output"
      assert_contains "$output" "Hello World"
    )
    ;;
  arkvm)
    echo "--- Running arkvm smoke test ---"
    : "${ARKVM_ROOT:?ARKVM_ROOT needs to point to the extracted arkvm root}"
    command -v es2panda >/dev/null
    command -v ark >/dev/null

    hello_abc_path="$(find_tool_file "$ARKVM_ROOT" 'hello.abc')"
    etsstdlib_path="$(find_tool_file "$ARKVM_ROOT" 'etsstdlib.abc')"

    if [[ -z "$hello_abc_path" ]]; then
      echo "FAIL: hello.abc not found under $ARKVM_ROOT"
      exit 1
    fi
    if [[ -z "$etsstdlib_path" ]]; then
      echo "FAIL: etsstdlib.abc not found under $ARKVM_ROOT"
      exit 1
    fi

    if [[ -n "${ARK_SRC_ROOT:-}" ]] && [[ -d "$ARK_SRC_ROOT/plugins/ets/stdlib/std" ]] && [[ -d "$ARK_SRC_ROOT/plugins/ets/stdlib/escompat" ]] && [[ -d "$ARK_SRC_ROOT/plugins/ets/sdk/api" ]] && [[ -d "$ARK_SRC_ROOT/plugins/ets/sdk/arkts" ]]; then
      echo "Using ARK_SRC_ROOT for arkvm compile test: $ARK_SRC_ROOT"
      run_arkvm_compiled_ets "$ARK_SRC_ROOT" "$etsstdlib_path"
    else
      echo "ARK_SRC_ROOT not set or incomplete; falling back to bundled hello.abc"
      run_arkvm_bundled_abc "$ARKVM_ROOT" "$etsstdlib_path" "$hello_abc_path"
    fi
    ;;
  *)
    echo "Unknown variant: $variant"
    exit 1
    ;;
esac
