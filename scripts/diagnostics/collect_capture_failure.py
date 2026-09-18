#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Read diagnostics only: no capture start, root, log clearing, settings or reboot."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import re
import subprocess
import tempfile
import time

PROCESSES = ('system_server', 'surfaceflinger', 'mediaserver', 'media.codec')
COMMANDS = {
    'uname': ['uname', '-a'],
    'incremental': ['getprop', 'ro.build.version.incremental'],
    'bootreason': ['getprop', 'ro.boot.bootreason'],
    'sys_bootreason': ['getprop', 'sys.boot.reason'],
    'sdk': ['getprop', 'ro.build.version.sdk'],
    'selinux': ['getenforce'],
    'display': ['dumpsys', 'display'],
    'projection': ['dumpsys', 'media_projection'],
    'codec': ['dumpsys', 'media.codec'],
    'surfaceflinger': ['dumpsys', 'SurfaceFlinger'],
    'repeater': ['ls', '-lZ', '/dev/repeater'],
    'tsmux': ['ls', '-lZ', '/dev/tsmux'],
    'wfd_running': ['getprop', 'secmm.wfd.running'],
    'wfd_engine': ['getprop', 'secmm.wfd.engine'],
    'kernel': ['dmesg'],
    'tombstone_index': ['ls', '-lt', '/data/tombstones'],
    'dropbox_index': ['dumpsys', 'dropbox'],
}


def now():
    return datetime.now(timezone.utc).isoformat()


def collect(args, runner=subprocess.run):
    args.output.mkdir(parents=True, exist_ok=True)
    output = Path(tempfile.mkdtemp(prefix='capture-'+args.label+'-', dir=args.output))
    report = {'label': args.label, 'scope': __doc__, 'started': now(), 'commands': {}}

    def command(name, argv):
        started, clock = now(), time.monotonic()
        try:
            proc = runner([args.adb, '-s', args.serial, *argv],
                          stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20)
            data, error, rc = proc.stdout, proc.stderr, proc.returncode
        except subprocess.TimeoutExpired as exc:
            data, error, rc = exc.stdout or b'', exc.stderr or b'', 'timeout'
        except OSError as exc:
            data, error, rc = b'', str(exc).encode(), 'host_error'
        record = {'argv': argv, 'status': rc, 'started': started, 'finished': now(),
                  'duration_seconds': time.monotonic()-clock}
        for kind, content in (('stdout',data), ('stderr',error)):
            filename = name+'.'+kind
            (output/filename).write_bytes(content)
            record[kind] = {'file': filename, 'bytes':len(content), 'sha256': hashlib.sha256(content).hexdigest()}
        report['commands'][name] = record
        return data if rc == 0 else None

    def identity(phase):
        boot = command(phase+'-boot_id', ['shell','-T','cat','/proc/sys/kernel/random/boot_id'])
        command(phase+'-uptime', ['shell','-T','cat','/proc/uptime'])
        value = boot.decode('ascii', errors='replace').strip() if boot else ''
        return value if re.fullmatch(r'[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12}',value) else None

    def processes(phase):
        found = {}
        for name in PROCESSES:
            prefix = phase+'-'+name
            data = command(prefix+'-pidof', ['shell','pidof',name])
            if data is None:
                found[name] = {'state':'query_failed_or_absent', 'pids':None}
                continue
            pids = data.decode('ascii',errors='replace').split()
            if any(not re.fullmatch(r'[1-9][0-9]*',pid) for pid in pids) or len(pids)!=len(set(pids)):
                found[name] = {'state':'invalid_pid_output', 'pids':None}
                continue
            found[name] = {'state':'observed' if pids else 'empty_output', 'pids':{}}
            for pid in pids:
                key = prefix+'-'+pid
                first = command(key+'-stat-before', ['shell','-T','cat',f'/proc/{pid}/stat'])
                cmdline = command(key+'-cmdline', ['shell','-T','cat',f'/proc/{pid}/cmdline'])
                command(key+'-exe', ['shell','readlink',f'/proc/{pid}/exe'])
                last = command(key+'-stat-after', ['shell','-T','cat',f'/proc/{pid}/stat'])
                def start(data):
                    try:
                        tail = data.rsplit(b') ',1)[1].split()
                        return int(tail[19])  # field 22, with state at tail[0]
                    except (AttributeError,IndexError,ValueError):
                        return None
                a,b = start(first),start(last)
                found[name]['pids'][pid] = {
                    'starttime_ticks': a,
                    'stable_during_read': a is not None and a==b,
                    'cmdline_bytes':len(cmdline) if cmdline is not None else None,
                    'first_argument_bytes':len(cmdline.split(b'\0',1)[0]) if cmdline is not None else None,
                }
        return found

    beginning = identity('begin')
    command('logcat', ['logcat','-b','all','-d','-v','threadtime','-t','4000'])
    first_processes = processes('begin')
    for name, argv in COMMANDS.items():
        command(name, ['shell', *argv])
    listing = command('pstore-list', ['shell','ls','-1','/sys/fs/pstore'])
    if listing is not None:
        for index, name in enumerate(listing.decode('utf-8',errors='replace').splitlines()):
            if re.fullmatch(r'[A-Za-z0-9_][A-Za-z0-9_.-]*',name) and name not in ('.','..'):
                command('pstore-'+str(index), ['shell','-T','cat','/sys/fs/pstore/'+name])
    for index,name in enumerate(args.tombstone):
        command('selected-tombstone-'+str(index), ['shell','-T','cat',name])
    last_processes = processes('end')
    ending = identity('end')
    def ids(values):
        return {name: {pid: info['starttime_ticks'] for pid,info in item['pids'].items()}
                if item['pids'] is not None else None for name,item in values.items()}
    process_known = all(item['pids'] and all(p['stable_during_read'] for p in item['pids'].values())
                        for group in (first_processes,last_processes) for item in group.values())
    boot_known = beginning is not None and ending is not None
    essential = boot_known and report['commands']['logcat']['status']==0
    report.update({'finished':now(), 'procedure_completed':True, 'essential_diagnostics_available':essential,
                   'root_cause_established':False, 'boot_id_begin':beginning, 'boot_id_end':ending,
                   'boot_changed':beginning!=ending if boot_known else None,
                   'processes_begin':first_processes, 'processes_end':last_processes,
                   'process_identity_changed':ids(first_processes)!=ids(last_processes) if process_known else None,
                   'snapshot_consistency':'changed' if boot_known and beginning!=ending else
                     'unknown' if not boot_known or not process_known else
                     'changed' if ids(first_processes)!=ids(last_processes) else 'no_change_observed'})
    (output/'collection.json').write_text(json.dumps(report,indent=2)+'\n')
    return output, 0 if essential else 2


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--adb',default='adb')
    parser.add_argument('--serial',required=True)
    parser.add_argument('--label',choices=('before','after'),required=True)
    parser.add_argument('--output',type=Path,required=True)
    parser.add_argument('--tombstone',action='append',default=[],help='Explicit /data/tombstones/tombstone_NN file to read')
    args = parser.parse_args()
    if any(not re.fullmatch(r'/data/tombstones/tombstone_[0-9]+(?:\.pb)?',name) for name in args.tombstone):
        parser.error('unsupported tombstone path')
    output, status = collect(args)
    print(output)
    return status


if __name__ == '__main__':
    raise SystemExit(main())
