#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
mkdir -p build/tests
export CLANG_MODULE_CACHE_PATH="$PWD/build/module-cache"
clang -DDDL_TESTING=1 -fobjc-arc -fblocks -Wall -Wextra -Werror -O2 -mmacosx-version-min=13.0 -framework Foundation -framework Security Sources/DDLCore.m Sources/SSLocalData.m Tests/QualityTests.m -o build/tests/quality-tests
quality_directory=$(mktemp -d "$PWD/build/tests/quality.XXXXXX")
AM_TEST_DATA="$quality_directory" build/tests/quality-tests
