#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/Platform.sh
ocbAction="${1:?command required}"
ocbProfile="${BUILD_TYPE:-Release}"
[[ "$ocbProfile" == Release || "$ocbProfile" == Debug ]] || { echo 'BUILD_TYPE must be Debug or Release'; exit 1; }
export PATH="$PWD/build/TestTools/bin:$PATH"
ocbTauri=(node ../../Frontend/node_modules/@tauri-apps/cli/tauri.js)
invokeFrontend() { (cd Frontend && npm "$@"); }
invokeCargo() { (cd Backend && cargo "$@"); }
invokeTauri() { (cd Backend/Desktop && "${ocbTauri[@]}" "$@"); }
ocbBuildArgs=(build --no-bundle)
[[ "$ocbProfile" == Debug ]] && ocbBuildArgs+=(--debug)
ocbBenchmarkArgs=()
read -r -a ocbBenchmarkArgs <<< "${CORE_BENCHMARK_ARGS:-}"
case "$ocbAction" in
 check-platform) rustc -vV; node --version;;
 format) invokeCargo fmt --all;;
 test-tools) cargo install tauri-driver --locked --root build/TestTools;;
 frontend-build) invokeFrontend run build;;
 init) invokeFrontend ci; invokeCargo fetch --locked --target "$(rustc --print host-tuple)";;
 build) invokeTauri "${ocbBuildArgs[@]}";;
 run)
  if [[ "$ocbProfile" == Debug ]]; then invokeTauri dev; else
   invokeTauri build --no-bundle
   exec Backend/target/release/OpenCircuitBoard
  fi;;
 package) invokeTauri build --bundles appimage;;
 core-test) invokeCargo test --locked -p ocb-core;;
 core-benchmark) invokeCargo run --locked --release -p ocb-core --bin ocb-benchmark -- "${ocbBenchmarkArgs[@]}";;
 board-benchmark)
  [[ -n "${BOARD_PATH:-}" ]] || { echo 'BOARD_PATH is required'; exit 1; }
  ocbBoardPath="$BOARD_PATH"
  [[ "$ocbBoardPath" = /* ]] || ocbBoardPath="$PWD/$ocbBoardPath"
  read -r -a ocbBoardArgs <<< "${BOARD_BENCHMARK_ARGS:-}"
  invokeCargo run --locked --release -p ocb-core --bin ocb-board-benchmark -- "$ocbBoardPath" "${ocbBoardArgs[@]}";;
 frontend-test) invokeFrontend run build; invokeFrontend test; read -r -a ocbFilter <<< "${FRONTEND_TEST:-}"; invokeFrontend run test:browser -- --config Playwright.config.ts "${ocbFilter[@]}";;
 browser-test) invokeFrontend run build; read -r -a ocbFilter <<< "${FRONTEND_TEST:-}"; invokeFrontend run test:browser -- --config Playwright.config.ts "${ocbFilter[@]}";;
 native-ui-test) [[ -f Backend/target/release/OpenCircuitBoard ]] || { echo "Build the release app first."; exit 1; }; invokeFrontend run test:desktop;;
 native-test)
  command -v tauri-driver >/dev/null || { echo 'Install tauri-driver and the matching platform WebDriver; see README.md.'; exit 1; }
  invokeTauri build --no-bundle
  invokeFrontend run test:desktop;;
 test) invokeCargo test --locked --workspace; invokeFrontend run build; invokeFrontend test; invokeFrontend run test:browser -- --config Playwright.config.ts;;
 clean) invokeCargo clean; rm -rf -- build Frontend/dist Frontend/test-results Frontend/playwright-report;;
 *) echo "Unknown command $ocbAction" >&2; exit 1;;
esac
