# Galaxy S10 (beyond1lte) port

This target combines the S908B GZD7 system with G973F HWC1 vendor inputs.
It requires the explicitly selected user-repartition-20260913 layout;
this is not a universal or stock S10 partition layout.

The six files under layouts/measurement are required build inputs: partition
sizes and mapping captures used by s10_layout.py for digest and consistency
validation. They contain no device serial, account, or host path. Do not replace
these inputs with reports or weaken checks to accept another layout.

Use a matching kernel set with the provenance contract in kernel/README.md.
The installer writes exactly system, vendor, product, boot, dtb, dtbo, ODM,
prism and optics. Data, EFS and up_param remain outside its write contract.
All nine paths and sizes are checked before the first write. Auxiliary targets
must be unmounted and recovery must provide e2fsck and resize2fs.

## Integrated auxiliary inputs

Before building, prepare the pinned 3.1.1 source ZIP once:

```sh
python3 -B scripts/utils/s10_auxiliary_images.py prepare /path/to/ArtisanROM_OFFICIAL_3.1.1_20260428_beyond1lte-sign.zip out/inputs/s10-auxiliary
```

Use the configured OUT_DIR in place of `out` if customized. Python 3.11+ and
brotli are required. The manifest in auxiliary/artisan311.json fixes the source
ZIP hash, raw ext4 hashes, image lengths and measured partition capacities.
Preparation rejects an existing output directory; verification never repairs or
silently replaces inputs. Use the helper's `verify` command to check a cache.

These inputs stay outside WORK_DIR and are staged after OS image conversion and
kernel processing. They are not rebuilt, converted to EROFS or AVB-signed.
Package hooks and the final signed ZIP are checked against the same manifest.
The installer writes their raw bytes, then runs e2fsck -f -p (only exit 0/1
accepted) and resize2fs before writing the kernel. The packaged images retain
their pinned hashes; resizing on the device intentionally changes filesystem
bytes. The final evidence records the source and packaged hashes.

## Installation validation status

The previous 20260920 hotfix preserved auxiliaries and could leave them empty
after Repartition/Cleaner. That released artifact is unchanged. The new source
supplies all three contents inside the normal ROM ZIP, so a separate seed ZIP or
3.1.1 installation is no longer an installer input requirement.

The intended sequence is Repartition → Cleaner → newly built integrated ROM →
normal clean-install data setup → boot. Do not run Cleaner after installing the
ROM: it erases the newly installed partitions. No automatic data wipe is added.

**Integrated clean boot remains unverified.** Prior successful reports involved
booting 3.1.1 first, which may also initialize data/EFS/OMR state. Do not present
this implementation as a confirmed public boot-loop fix before a clean-install
device test. The initial payload deliberately retains 3.1.1's donor ODM identity;
replacing it with a newly constructed S10 ODM is separate work.
