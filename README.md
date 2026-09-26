# ncnn-zig

Prebuilt static [ncnn](https://github.com/Tencent/ncnn) libraries, compiled with Zig as the C/C++ toolchain.

## Variants

What each variant depends on:

|                         | cpu                                  | gpu                                               |
|-------------------------|--------------------------------------|---------------------------------------------------|
| C library + math (libm) | ✅ glibc (shared)                    | ✅ glibc (shared)                                 |
| C++ standard library    | ❌ none (`SIMPLESTL`, `-nostdinc++`) | ✅ libc++, static (from Zig)                      |
| OpenMP runtime          | ❌ none (`SIMPLEOMP`)                | ❌ none (`SIMPLEOMP`)                             |
| Vulkan                  | ❌ not used                          | loaded at runtime (`SIMPLEVK`), nothing to link   |
| Linking it              | any C/Zig toolchain                  | Zig (`linkLibCpp()`), version in `.zigversion`    |

glibc targets are built against an old glibc (2.28) so the result runs on older distros.

## Targets

| Target                   | cpu | gpu | Status                                                                     |
|--------------------------|-----|-----|----------------------------------------------------------------------------|
| `x86_64-linux-gnu.2.28`  | ✅  | ✅  | Built and tested                                                           |
| `aarch64-linux-gnu.2.28` | ➕  | ➕  | Should cross-compile. Untested: to be tested on an ARM CI runner           |
| `x86_64-windows-gnu`     | ➕  | ➕  | Should cross-compile. Untested: to be tested on a Windows CI runner        |
| `aarch64-macos`          | ➕  | ➕  | CPU should work. GPU build probably works, but running it needs MoltenVK   |
| `x86_64-linux-musl`      | ➖  | ❌  | Dropped. GPU is impossible (GPU drivers are glibc libraries)               |

✅ done · ➕ planned · ➖ dropped · ❌ not possible

## Building

Requirements: `cmake`, the Zig version in `.zigversion`, `git`, `tar`/`gzip` (`zip` for Windows targets), `sha256sum`.

```sh
git clone <this repo>
./build.sh cpu x86_64-linux-gnu.2.28
./build.sh gpu x86_64-linux-gnu.2.28
```

`build.sh` fetches ncnn into `ncnn/` at the release pinned in `ncnn.version`, and checks that the tag
still points at the pinned commit. Later builds reuse the checkout.

Archives land in `dist/`:

```
ncnn-<version>-<variant>-<target>/
├── include/ncnn/…
├── lib/libncnn.a            (+ libglslang*.a for gpu)
├── LICENSES/
└── BUILDINFO                ncnn commit, Zig version, target, CMake flags
```

Use `ZIG=/path/to/zig` to pick a specific Zig binary.

## Off-release builds

Build any ncnn tag, branch or commit instead of the pinned release:

```sh
NCNN_REF=master ./build.sh gpu x86_64-linux-gnu.2.28
# -> dist/ncnn-master-20260924-c6b351b-gpu-x86_64-linux-gnu.2.28.tar.gz
```

In CI: Actions → release → Run workflow, with `ncnn_ref` set. The archives are attached to that run;
off-release builds are never published as releases.

## Updating ncnn

A daily workflow (`update-ncnn.yml`) checks for new ncnn releases. When there is one, it builds and
tests it, then opens a PR that updates `ncnn.version`. Merge the PR, then publish with
`git tag <tag> && git push origin <tag>`.

To update by hand, edit `ncnn.version`:

```
tag=<new-tag>
commit=<commit the tag points at>
```

## Releasing

Pushing a tag builds, tests and publishes the archives plus `SHA256SUMS` as a GitHub release.
Use the ncnn version as the tag (e.g. `20260526`), or `20260526-2` for a rebuild of the same version.

## Using from Zig

Add the archive for your target to `build.zig.zon`:

```sh
zig fetch --save=ncnn_gpu_x86_64_linux <release-url>/ncnn-<version>-gpu-x86_64-linux-gnu.2.28.tar.gz
```

Then in `build.zig`:

```zig
if (b.lazyDependency("ncnn_gpu_x86_64_linux", .{})) |ncnn| {
    exe.addIncludePath(ncnn.path("include"));
    exe.addObjectFile(ncnn.path("lib/libncnn.a"));
    exe.addObjectFile(ncnn.path("lib/libglslang.a"));
    exe.linkLibCpp();
    exe.linkLibC();
}
```
