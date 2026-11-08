#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"
export CLANG_MODULE_CACHE_PATH="$PROJECT_DIR/.build/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PROJECT_DIR/.build/ModuleCache"
swift build --disable-sandbox --scratch-path .build --cache-path .swiftpm/cache --product LiuBaiChecks
.build/debug/LiuBaiChecks "$@"
