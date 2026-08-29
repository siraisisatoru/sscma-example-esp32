#!/usr/bin/env bash
# Build the sscma_server_at firmware for the XIAO ESP32S3 Sense inside Docker.
#
# Usage:
#   ./scripts/build_fw.sh              incremental build
#   ./scripts/build_fw.sh fullclean    wipe the build dir first, then build
#
# Why Docker, and why release-v5.3 specifically:
#   This example is pinned to the ESP-IDF 5.x line -- its idf_component.yml
#   declares idf ">=5.0", upstream tests on 5.2.2/5.3.x, and it deliberately
#   uses the legacy driver/i2c.h. Legacy I2C is EOL in IDF v6 and removed in
#   v7, so a native IDF v6 install is NOT usable here.
#
#   Docker on macOS cannot reach USB, so this script ONLY builds. Flash with
#   scripts/flash_fw.sh on the host.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

DOCKER_IMAGE="espressif/idf:release-v5.3"
# Container-side paths ($REPO_ROOT is mounted at /work).
PROJECT_DIR="/work/examples/sscma_server_at"
BUILD_DIR="/work/build/sscma_server_at"
OVERLAY="/work/scripts/sdkconfig.xiao"

HOST_BUILD_DIR="$REPO_ROOT/build/sscma_server_at"

if [[ "${1:-}" == "fullclean" ]]; then
  echo "[build] fullclean: wiping $HOST_BUILD_DIR"
  rm -rf "$HOST_BUILD_DIR"
  shift
fi
mkdir -p "$HOST_BUILD_DIR"

[[ -f "$REPO_ROOT/components/sscma-micro/sscma-micro/sscma/sscma.h" ]] || {
  echo "Error: nested sscma-micro submodule not checked out."
  echo "Run: git submodule update --init --recursive"
  exit 1
}

# Everything below runs inside the container. Notes on the non-obvious bits:
#
#  * git config safe.directory '*': the mounted repo is owned by the macOS
#    UID, the container runs as root -- without this every git command aborts
#    with "detected dubious ownership".
#
#  * Idempotent patch application for the nested SSCMA-Micro submodule (a
#    separate git repo pinned to untouched upstream Seeed-Studio/SSCMA-Micro,
#    so its fixes can't live as native commits the way this repo's own do --
#    see patches/sscma-micro/README.md for the inventory):
#    reverse-check OK -> already applied; forward-check OK -> apply;
#    neither -> hard error (submodule at wrong commit or hand-edited).
#
#  * SDKCONFIG_DEFAULTS: the example's own sdkconfig.defaults FIRST, then the
#    XIAO overlay -- later files override earlier ones, which is how the
#    overlay wins on flash size / console / stack size / throughput.
#
#  * SDKCONFIG is forced INTO the build dir so the generated sdkconfig never
#    dirties the working tree (and `fullclean` really does reset config state).
#
#  * set-target only on first configure: re-running set-target regenerates
#    sdkconfig from defaults, silently discarding any menuconfig tweaks made
#    in the build dir between runs.
docker run --rm \
  -v "$REPO_ROOT:/work" \
  -w "$PROJECT_DIR" \
  -e BUILD_DIR="$BUILD_DIR" \
  -e OVERLAY="$OVERLAY" \
  "$DOCKER_IMAGE" bash -ec '
    source "$IDF_PATH/export.sh" >/dev/null

    git config --global --add safe.directory "*"

    REPO=/work
    MICRO="$REPO/components/sscma-micro/sscma-micro"
    shopt -s nullglob
    for p in "$REPO"/patches/sscma-micro/*.patch; do
      if git -C "$MICRO" apply --reverse --check "$p" 2>/dev/null; then
        echo "[patch] already applied (sscma-micro): $(basename "$p")"
      elif git -C "$MICRO" apply --check "$p" 2>/dev/null; then
        git -C "$MICRO" apply "$p"
        echo "[patch] applied (sscma-micro): $(basename "$p")"
      else
        echo "[patch] ERROR: sscma-micro/$(basename "$p") matches neither applied"
        echo "        nor unapplied state. Is sscma-micro at the pinned commit?"
        echo "        Try: git submodule update --init --recursive"
        exit 1
      fi
    done
    shopt -u nullglob

    IDF_ARGS=(-B "$BUILD_DIR"
              -DSDKCONFIG="$BUILD_DIR/sdkconfig"
              -DSDKCONFIG_DEFAULTS="sdkconfig.defaults;$OVERLAY")

    if [[ ! -f "$BUILD_DIR/sdkconfig" ]]; then
      echo "[build] first configure: set-target esp32s3"
      idf.py "${IDF_ARGS[@]}" set-target esp32s3
    fi

    idf.py "${IDF_ARGS[@]}" build

    # Print the partition table actually baked into this build so layout
    # mistakes (models partition must end exactly at the 8 MB boundary) are
    # caught by eyeball at build time, not by a boot loop at flash time.
    echo ""
    echo "[build] generated partition table:"
    python "$IDF_PATH/components/partition_table/gen_esp32part.py" \
      "$BUILD_DIR/partition_table/partition-table.bin"
  '

echo ""
echo "[build] done. Artifacts in: $HOST_BUILD_DIR"
echo "[build] flash from the host with: scripts/flash_fw.sh"
