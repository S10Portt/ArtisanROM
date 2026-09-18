# S10 kernel input

Selected mode: `source`.
Repository: https://github.com/ArtisanRomS10/android_kernel_samsung_exynos9820.git
Commit: `bf6931b605aacb7f434d6ff440344a0c3e1f92e1` (KernelSU integration removed; two selected LOS fixes).
Selected local branch: `port/los-fixes-20260915`. This revision has not been pushed by this task; remote main remains a separate reference. See `target/beyond1lte/README.md`.

Required user-built inputs:
- boot.img, dtb.img, dtbo.img: one consistent set from the selected source.
- SHA256SUMS: the three actual image hashes and filenames, exactly once each.
- source.commit: the actual source commit used to produce that set.
- source.patch.sha256: SHA-256 of `git diff --binary HEAD --` of the build source.

The selected revision is now committed and clean. The expected diff digest in
source.patch.sha256.expected is therefore the SHA-256 of empty content. The old
9a0a792 + removal patch contract is superseded; do not stamp old images with the
new commit. Untracked source additions must not be used in the selected clean build.
These records are provenance claims, not cryptographic proof of how images were built.
No image files or actual build provenance have been generated here.

`artisan311` remains a separate, unselected prebuilt mode. It requires the exact
three hashes in artisan311.json and rejects source.commit/source.patch.sha256.
Stock boot is not a replacement for either input mode.

The ROM builder does not compile the kernel. Common fs/proca processing may change
input boot afterward. Final ramdisk, dtb/dtbo, AVB, partition sizes and GZD7 boot
compatibility remain to be validated. Installer abort remains active.
