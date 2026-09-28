# nvbringup-mesa

> **Prototype, and a patched copy of upstream Mesa.** This is an unofficial set of patches against
> [Mesa](https://mesa.freedesktop.org), written for the prototype
> [NVBringup](https://github.com/kvarun-p/NVBringup) kext and not meant for anything else. It is
> not part of, endorsed by or supported by the Mesa project. It isn't proposed for upstream, and
> it tracks one Mesa release (see the table below) without promising to follow newer ones.
> **Don't report problems with these patches to Mesa;** they may not exist in upstream Mesa.

These patches make **NVK**, Mesa's Vulkan driver for NVIDIA GPUs, run on macOS on top of the
NVBringup kext. With them, Vulkan compute programs (for example llama.cpp's Vulkan backend) run
on an NVIDIA Turing GPU in an Intel Mac or hackintosh.

This repository holds only the changes, as patches against an upstream Mesa release. It doesn't
contain Mesa itself: you clone Mesa from its home on the
[freedesktop.org GitLab](https://gitlab.freedesktop.org/mesa/mesa), apply the patches and build.

| This repository | Upstream Mesa |
|---|---|
| branch `26.2`, tag `mesa-26.2.3` | tag [`mesa-26.2.3`](https://gitlab.freedesktop.org/mesa/mesa/-/tags/mesa-26.2.3) on branch `26.2` |

Branch and tag names follow Mesa's: branch `26.2` tracks Mesa's 26.2 stable series, and each
tag here names the exact Mesa release its patches apply to.

## What the driver does

- **Vulkan 1.4 compute** on NVIDIA Turing (TU102, TU104, TU106, TU116, TU117) through the
  NVBringup kext: memory, VA binding, compute queues, timeline semaphores, several processes at
  once. Tested on a GTX 1650 (TU117) with llama.cpp: 18,987 of 18,990 backend tests pass (the
  rest are f16 SQRT precision).
- **No window system:** built with `-Dplatforms=`, so no swapchains or presentation. Compute
  and offscreen work only; graphics pipelines are untested.
- **Needs the kext running:** without NVBringup and a booted GSP-RM, NVK reports no device and
  the Vulkan loader moves on to other drivers.

## The patches

| # | Patch | Without it |
|---|---|---|
| 1 | `nvk: macOS port on the NVBringup kext (nvkmd/macos)` | No NVK on macOS: upstream NVK only talks to Linux's nouveau driver |
| 2 | `nak: keep IDP.4A src1 in a register on Turing` | Wrong results from 8-bit integer dot products (llama.cpp's quantized matrix multiplication) |
| 3 | `nak: stall divergent conditional branches for 6 cycles on Turing` | Intermittently wrong results in shaders whose threads branch different ways |
| 4 | `nvkmd/macos: 64 KiB-aligned VAs for VRAM allocations` | Some VRAM allocations can't be mapped by the kext's page tables |
| 5 | `nvkmd/macos: mention the console-user rule in the privilege error` | A permission refusal gives an unhelpful error |
| 6 | `nvkmd/macos: list the GPU without powering it on` | Listing Vulkan devices wakes a GPU the kext has powered off |

Patch 1 adds `src/nouveau/vulkan/nvkmd/macos`, a backend over the kext's IOKit user client.
It also replaces NVK's two OpenCL C helper kernels with hand-written NIR, since macOS has no
`mesa_clc` (LLVM) build, and skips the Linux-only parts of the build. Patches 2 and 3 fix NVK's
shader compiler for Turing on every platform, not only macOS.

## Requirements

- macOS on Intel with an NVIDIA Turing GPU, and the NVBringup kext installed with GSP-RM
  running (see its README).
- Xcode or the Command Line Tools (tested with Apple clang 16), git and CMake.
- From [MacPorts](https://www.macports.org) (or equivalents from Homebrew):
  `sudo port install pkgconfig libelf zlib zstd`.
- Python 3.10 or newer with meson, ninja, mako, PyYAML and packaging (tested: Python 3.12,
  meson 1.12, mako 1.4), and Rust (via [rustup](https://rustup.rs)) with `bindgen` and
  `cbindgen`, which NVK's compiler needs (tested: rustc 1.98, bindgen 0.73, cbindgen 0.29):

```bash
python3 -m venv ~/mesa-venv && ~/mesa-venv/bin/pip install meson ninja mako pyyaml packaging
cargo install bindgen-cli cbindgen
export LIBCLANG_PATH=/Library/Developer/CommandLineTools/usr/lib   # libclang for bindgen
```

## Build

```bash
/path/to/nvbringup-mesa/apply.sh mesa      # clones mesa-26.2.3 and applies the patches
cd mesa
PATH=~/mesa-venv/bin:$PATH meson setup build -Dbuildtype=debugoptimized \
    -Dvulkan-drivers=nouveau -Dgallium-drivers= -Dplatforms= -Dglx=disabled -Degl=disabled \
    -Dgles1=disabled -Dgles2=disabled -Dopengl=false -Dllvm=disabled
PATH=~/mesa-venv/bin:$PATH ninja -C build src/nouveau/vulkan/libvulkan_nouveau.dylib \
    src/nouveau/vulkan/nouveau_devenv_icd.x86_64.json
```

This builds the driver, `build/src/nouveau/vulkan/libvulkan_nouveau.dylib`, and a manifest
that points at it. `debugoptimized` is the tested configuration; it keeps Mesa's assertions
on. To apply the patches to a checkout you already have, check out tag `mesa-26.2.3` and run
`git am /path/to/nvbringup-mesa/patches/*.patch`.

## Install

macOS has no Vulkan loader. Build and install
[Vulkan-Headers](https://github.com/KhronosGroup/Vulkan-Headers) and
[Vulkan-Loader](https://github.com/KhronosGroup/Vulkan-Loader) (tested: v1.4.364):

```bash
git clone -b v1.4.364 https://github.com/KhronosGroup/Vulkan-Headers.git
cmake -S Vulkan-Headers -B build-vkh -DCMAKE_INSTALL_PREFIX=/usr/local && sudo cmake --install build-vkh
git clone -b v1.4.364 https://github.com/KhronosGroup/Vulkan-Loader.git
cmake -S Vulkan-Loader -B build-loader -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr/local \
    -DVULKAN_HEADERS_INSTALL_DIR=/usr/local
cmake --build build-loader && sudo cmake --install build-loader
```

Register NVK for your user by copying the generated manifest, which already carries the
driver's path and API version:

```bash
mkdir -p ~/.config/vulkan/icd.d
cp build/src/nouveau/vulkan/nouveau_devenv_icd.x86_64.json ~/.config/vulkan/icd.d/nouveau_icd.x86_64.json
```

To use NVK for one program only, skip the copy and set
`VK_DRIVER_FILES=/path/to/mesa/build/src/nouveau/vulkan/nouveau_devenv_icd.x86_64.json`.

## Check that NVK works

Ask the loader which drivers it loads, then list devices through a Vulkan app:

```bash
VK_LOADER_DEBUG=driver llama-server --list-devices 2>&1 | grep -E 'Found ICD manifest.*nouveau|Vulkan0'
# expect: Found ICD manifest file .../nouveau_icd.x86_64.json
#         Vulkan0: NVIDIA GeForce GTX 1650 (NVK TU117) (4112 MiB, ...)
```

NVBringup's `tools/verify_install.sh --full` checks the loader and the manifest, and runs a
Vulkan compute test (`vktest`) and a short llama.cpp benchmark on the GPU.

## Troubleshooting

| Symptom | Cause and fix |
|---|---|
| No NVIDIA device listed | GSP-RM isn't running, or NVBringup's power mode is *off* (`nvgsp power status`), or the loader doesn't find the manifest (`VK_LOADER_DEBUG=driver`) |
| `NVBringup: not privileged (...)` | Only root and the user logged in at the console may use the GPU; boot with `nvgpu_users=1` to allow everyone |
| `NVBringup: open failed: ... (unsupported)` | NVK and the kext were built from different `nv_uapi.h` versions; sync the copies (below) and rebuild |
| `Assertion failed: (cache->object_cache->entries == 0), function vk_pipeline_cache_destroy` at exit | Known issue in the debug-optimized build; it happens at teardown, after the work is done, and doesn't affect results |

## Keep the kext interface in sync

`nvkmd/macos` carries copies of NVBringup's user-space interface. When NVBringup changes them,
copy them into the Mesa checkout, rebuild, and export the patches again (below):

```bash
cp /path/to/nvbringup/src/nv_uapi.h /path/to/nvbringup/tools/libnvmac.[ch] \
   src/nouveau/vulkan/nvkmd/macos/
```

## Moving to a newer Mesa

Rebase the branch that `apply.sh` created onto the new tag, fix conflicts, rebuild and rerun
the checks, then export the patches again:

```bash
git fetch --depth 1 origin tag mesa-26.2.4
git rebase --onto mesa-26.2.4 mesa-26.2.3 nvbringup-26.2
git format-patch --no-signature --zero-commit -o /path/to/nvbringup-mesa/patches mesa-26.2.4..
```

Then update `TAG` (and `BRANCH` for a new series) in `apply.sh`, the table at the top, and this
repository's branch and tag.

## License

Mesa's own license applies to the patched files (mostly MIT; see Mesa's `docs/license.rst`).
The patches are MIT licensed; see [LICENSE](LICENSE). "Mesa", "NVK" and "NAK" are parts of the
Mesa project, and NVIDIA, Apple and other names are trademarks of their owners; they are used
only to describe compatibility.
