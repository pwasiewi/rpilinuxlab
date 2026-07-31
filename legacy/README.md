# legacy/

Historical labs superseded in 2026 — kept for reference, moved here 2026-07-31.

| Directory | Was | Superseded by |
|---|---|---|
| `android.nougat/` | LineageOS CM-14.1 build guide | `../android.baklava/` + `xandroid` |
| `android.oreo/` | ResurrectionRemix Oreo, LG G3 | `../android.baklava/` + `xandroid` |
| `android.q/` | LineageOS 17.1, LG G6 | `../android.baklava/` + `xandroid` |
| `android.kernel/` | phone kernel-only builds | `../android.baklava/` |
| `make.aarch64/` | RPi 3 qemu kernel lab Makefile | `../xlab aarch64` |
| `make.armhfp/` | RPi 2 qemu kernel lab Makefile | `../xlab armhfp` |
| `make.arm/` | ARM926 versatile qemu lab | `../xlab arm` |
| `make.x86_64/` | native qemu kernel lab | `../xlab x86_64` |
| `make.tomato/` | Tomato router firmware notes | — (hardware retired) |
| `qemu-binfmt/` | qemu-user binfmt setup notes | crossdev/systemd-binfmt (see `../xarm`) |

`xlab` still reuses tarballs from `make.*/dl/` here and falls back to the
prebuilt DTBs in `make.aarch64/dtb/`, `make.armhfp/dtb/` — do not delete those.
