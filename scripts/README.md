# Build + flash scripts (XIAO ESP32S3 Sense)

Standalone build/flash for `examples/sscma_server_at`, targeting the Seeed
XIAO ESP32S3 Sense (8 MB flash, 8 MB PSRAM, native USB-Serial-JTAG). These
scripts are self-contained -- clone this repo, run them, no other repo
needed.

```
./scripts/build_fw.sh              # Docker (espressif/idf:release-v5.3), builds -> build/sscma_server_at/
./scripts/build_fw.sh fullclean    # wipe the build dir first
./scripts/flash_fw.sh              # host esptool, flashes the build above
./scripts/flash_fw.sh --port /dev/cu.usbmodemXXXX   # explicit port
```

## Requirements

- **Docker**, for the build only (macOS Docker Desktop cannot reach USB, so
  building happens in a container and flashing always happens on the host).
- **Python 3 with `venv`** on the host, for flashing. `flash_fw.sh` creates
  `scripts/.venv` on first run and installs `scripts/requirements.txt`
  (`esptool` + `pyserial`) into it automatically -- nothing to install by
  hand.
- `git submodule update --init --recursive` first, so the nested
  `components/sscma-micro/sscma-micro` submodule is checked out (its fixes
  are applied as patches at build time -- see `patches/sscma-micro/README.md`).

## Model weights are separate

The firmware and the `.tflite` model live in different flash partitions
(`factory` app partition vs. a dedicated `models` data partition -- see
`examples/sscma_server_at/partitions.csv`). Flashing firmware here does not
touch the model, and vice versa: once this firmware is on the board, model
weights can be flashed/swapped independently by any AT-protocol-aware tool
(e.g. the `flash_model.py` in the sibling `esp32s3_sense_AtoZ_dev` repo,
which assumes this firmware is already flashed and only manages models).
