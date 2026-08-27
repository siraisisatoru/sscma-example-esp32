# Patches for the nested `sscma-micro` submodule

`components/sscma-micro/sscma-micro` is pinned to upstream
[Seeed-Studio/SSCMA-Micro](https://github.com/Seeed-Studio/SSCMA-Micro)
(`e830d54`), which we do not fork — fixes to that vendor-neutral core are
carried here as patch files and applied to the nested submodule's working
tree at build time (same pattern the sibling `sscma-example-we2` fork uses
for its third-party TFLM ext-lib patches). The upstream repo itself is never
touched; a fresh `git submodule update --init --recursive` plus one build
reproduces the patched state.

Apply them idempotently from the repo root:

```bash
MICRO=components/sscma-micro/sscma-micro
for p in patches/sscma-micro/*.patch; do
  git -C "$MICRO" apply --reverse --check "$p" 2>/dev/null && continue  # already applied
  git -C "$MICRO" apply "$p"
done
```

(`git -C "$MICRO"` matters: a nested submodule is a separate repo, unreachable
by a `git apply` run from this repo's root.)

## Inventory

### 0001-idf53-build-compat-batchmatmul.patch
Build fixes for IDF v5.3's FreeRTOS kernel (no `uxQueueGetQueueLength()` /
`uxQueueSpacesAvailableFromISR()` there — replaced with a stored capacity +
ISR-safe count), and registers `AddBatchMatMul()` in the TFLite-Micro
`OpsResolver` — LiteRT YOLO11 exports contain BATCH_MATMUL; without it
`AllocateTensors()` fails and the model never loads.

### 0002-nchw-planar-input-yolo11-dispatch.patch
`ma::cv::convert()` gains an RGB565→RGB888_PLANAR path (models exported via
LiteRT/torch.export have NCHW inputs; previously the input tensor stayed
uninitialized), and `setAlgorithmInput()` gains the missing
`MA_MODEL_TYPE_YOLO11` case (a bound YOLO11 model was never fed the frame).

### 0003-yolo11-int8-quant-param-swap-fix.patch
Upstream `Yolo11::postProcessI8()` dequantizes the class score with the *box*
tensor's quant params and the DFL box logits with the *cls* tensor's params
(swapped) — box and cls have genuinely different int8 scales, so every
confidence and coordinate was corrupted regardless of image content.
