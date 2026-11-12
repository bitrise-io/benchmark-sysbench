#!/usr/bin/env bash
# Not timed. Build sysbench from this repo's bench-fixes branch (checked out by the workflow into $SYSBENCH_SRC).
set -eo pipefail
brew install automake libtool pkg-config
cd "$SYSBENCH_SRC"
export MACOSX_DEPLOYMENT_TARGET="$(sw_vers -productVersion | cut -d. -f1,2)"
./autogen.sh
./configure --without-mysql --prefix="$RUNNER_TEMP/sysbench" CFLAGS="-std=gnu17"
make -j"$(sysctl -n hw.ncpu)"
make install
echo "$RUNNER_TEMP/sysbench/bin" >> "$GITHUB_PATH"
echo "SYSBENCH_COMMIT=$(git rev-parse HEAD)" >> "$GITHUB_ENV"
SB="$RUNNER_TEMP/sysbench/bin/sysbench"; "$SB" --version
"$SB" cpu run --threads=1 --time=5 --cpu-max-prime=20000 | tee "$RUNNER_TEMP/sb_check.log"
EPS=$(awk '/events per second:/ {print int($4)}' "$RUNNER_TEMP/sb_check.log")
if [ "$EPS" -gt 100000 ]; then echo "❌ cpu test is not doing real work ($EPS events/s)"; exit 1; fi
