#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/Platform.sh
ocbAction="${1:?command required}"
ocbProfile="${BUILD_TYPE:-Release}"
[[ "$ocbProfile" == Release || "$ocbProfile" == Debug ]] || { echo 'BUILD_TYPE must be Debug or Release'; exit 1; }
export PATH="$PWD/build/TestTools/bin:$PATH"
ocbTauri=(node ../node_modules/@tauri-apps/cli/tauri.js)
ocbBuildArgs=(build --no-bundle)
[[ "$ocbProfile" == Debug ]] && ocbBuildArgs+=(--debug)
ocbBenchmarkArgs=()
read -r -a ocbBenchmarkArgs <<< "${CORE_BENCHMARK_ARGS:-}"
case "$ocbAction" in
 check-platform) rustc -vV; node --version;;
 format) cargo fmt --all;;
 test-tools) cargo install tauri-driver --locked --root build/TestTools;;
 frontend-build) npm run build;;
 init) npm ci; cargo fetch --locked;;
 build) (cd Desktop && "${ocbTauri[@]}" "${ocbBuildArgs[@]}");;
 run)
  if [[ "$ocbProfile" == Debug ]]; then (cd Desktop && "${ocbTauri[@]}" dev); else
   (cd Desktop && "${ocbTauri[@]}" build --no-bundle)
   exec target/release/OpenCircuitBoard
  fi;;
 package) (cd Desktop && "${ocbTauri[@]}" build --bundles appimage);;
 core-test) cargo test --locked -p ocb-core;;
 core-benchmark) cargo run --locked --release -p ocb-core --bin ocb-benchmark -- "${ocbBenchmarkArgs[@]}";;
 board-benchmark)
  [[ -n "${BOARD_PATH:-}" ]] || { echo 'BOARD_PATH is required'; exit 1; }
  read -r -a ocbBoardArgs <<< "${BOARD_BENCHMARK_ARGS:-}"
  cargo run --locked --release -p ocb-core --bin ocb-board-benchmark -- "$BOARD_PATH" "${ocbBoardArgs[@]}";;
 frontend-test) npm run build; npm test; read -r -a ocbFilter <<< "${FRONTEND_TEST:-}"; npm run test:browser -- --config Playwright.config.ts "${ocbFilter[@]}";;
 browser-test) npm run build; read -r -a ocbFilter <<< "${FRONTEND_TEST:-}"; npm run test:browser -- --config Playwright.config.ts "${ocbFilter[@]}";;
 native-ui-test) [[ -f target/release/OpenCircuitBoard ]] || { echo "Build the release app first."; exit 1; }; npm run test:desktop;;
 native-test)
  command -v tauri-driver >/dev/null || { echo 'Install tauri-driver and the matching platform WebDriver; see README.md.'; exit 1; }
  (cd Desktop && "${ocbTauri[@]}" build --no-bundle)
  npm run test:desktop;;
 test) cargo test --locked --workspace; npm run build; npm test; npm run test:browser -- --config Playwright.config.ts;;
 clean) cargo clean; rm -rf -- build dist test-results playwright-report;;
 *) echo "Unknown command $ocbAction" >&2; exit 1;;
esac
