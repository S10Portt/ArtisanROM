# Galaxy S10 (beyond1lte) port

This target combines the S908B GZD7 system with G973F HWC1 vendor inputs.
It requires the explicitly selected user-repartition-20260913 layout;
this is not a universal or stock S10 partition layout.

The six files under layouts/measurement are required build inputs: partition
sizes and mapping captures used by s10_layout.py for digest and consistency
validation. They contain no device serial, account, or host path. Do not replace
these inputs with reports or weaken checks to accept another layout.

Use a matching kernel set with the provenance contract in kernel/README.md.
Only boot, dtb, dtbo, system, vendor and product are installer write targets.
ODM, prism, optics and up_param are preserved. Recovery must validate actual
write paths before installation. Build success does not certify device behavior.

See CHANGELOG.md for supported changes and known limitations. Session logs,
reviews, device dumps, disassembly and build reports belong outside this source
checkout. Keep only maintained source/configuration and reusable documentation.

The GZD7 SurfaceFlinger legacy-composer port fix is applied after all modules.
It is pinned to an exact input hash and preserves identification-aware duplicate
checks and the two-display legacy limit. Wired DeX video, touchpad operation
and reconnect have been tested on-device. HDMI audio is a separate path.

The HWC1 ARM32 audio HAL HDMI selector is patched to accept GZD7's MULTI_CH
flag. The patch is pinned to an exact input hash and applied only to this
target after modules. Host instruction tests cover output selection. Post-flash
operation was reported working; the full output-switching and playback
regression matrix is not yet verified.

Bluetooth A2DP hardware offload remains unresolved. Keep "Disable Bluetooth
A2DP hardware offload" enabled for the validated software playback path.
An audioserver restart experiment has not been added to this target.
