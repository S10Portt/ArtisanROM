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
