#!/bin/sh
# Unpack a release archive, build test/smoke.c against it with Zig, and run it.
# usage: test/run.sh dist/ncnn-<version>-<variant>-<target>.tar.gz
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
ARCHIVE=$(realpath "$1")
ZIG=${ZIG:-zig}

NAME=$(basename "$ARCHIVE" .tar.gz)
NAME=${NAME%.zip}
# ncnn-<label>-<variant>-<target>; the label may contain dashes (e.g. master-20260927-e54f7b1)
VARIANT=$(printf '%s\n' "$NAME" | sed -E 's/.*-(cpu|gpu)-.*/\1/')
TARGET=${NAME#*-"$VARIANT"-}

MODELS=$ROOT/test/models
mkdir -p "$MODELS"
for f in squeezenet_v1.1.param squeezenet_v1.1.bin; do
    [ -f "$MODELS/$f" ] || curl -fsSL -o "$MODELS/$f" "https://github.com/nihui/ncnn-assets/raw/master/models/$f"
done

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
tar xzf "$ARCHIVE" -C "$WORK"
PKG=$WORK/$NAME

BIN=$WORK/smoke
case "$VARIANT" in
    cpu)
        STATIC=
        case "$TARGET" in *-musl*) STATIC=-static ;; esac
        "$ZIG" cc -target "$TARGET" -O2 -s $STATIC "$ROOT/test/smoke.c" \
            -I"$PKG/include" "$PKG/lib/libncnn.a" -lpthread -o "$BIN"
        "$BIN" "$MODELS/squeezenet_v1.1.param" "$MODELS/squeezenet_v1.1.bin"
        ;;
    gpu)
        "$ZIG" c++ -target "$TARGET" -O2 -s -x c "$ROOT/test/smoke.c" -x none \
            -I"$PKG/include" "$PKG/lib/libncnn.a" "$PKG/lib/libglslang.a" -lpthread -ldl -o "$BIN"
        status=0
        "$BIN" "$MODELS/squeezenet_v1.1.param" "$MODELS/squeezenet_v1.1.bin" gpu > "$WORK/gpu.log" 2>&1 || status=$?
        cat "$WORK/gpu.log"
        [ "$status" = 0 ] || exit "$status"
        # ncnn silently falls back to CPU without a Vulkan device; REQUIRE_VULKAN=1 makes that an error.
        # ncnn prints "[0 <device name>] ..." once it initializes a device.
        if [ "${REQUIRE_VULKAN:-0}" = 1 ]; then
            grep -q '^\[0 ' "$WORK/gpu.log" || { echo "error: no Vulkan device was used" >&2; exit 1; }
            echo "vulkan: $(grep -m1 -o '^\[0 [^]]*\]' "$WORK/gpu.log")"
        fi
        ;;
esac

# glibc targets must not need a newer glibc than the one they were built for
case "$TARGET" in
    *-gnu.*)
        WANT=${TARGET##*-gnu.}
        HAVE=$(objdump -T "$BIN" | grep -o 'GLIBC_[0-9.]*' | sed 's/GLIBC_//' | sort -V | tail -1)
        [ "$(printf '%s\n%s\n' "$HAVE" "$WANT" | sort -V | tail -1)" = "$WANT" ] \
            || { echo "error: needs glibc $HAVE, target is $WANT" >&2; exit 1; }
        echo "glibc: needs $HAVE (target $WANT)"
        ;;
    *-musl*)
        file "$BIN" | grep -q 'statically linked' || { echo "error: musl binary is not static" >&2; exit 1; }
        echo "musl: statically linked"
        ;;
esac
echo "ok: $NAME"
