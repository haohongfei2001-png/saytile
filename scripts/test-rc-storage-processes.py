#!/usr/bin/env python3
"""Real child-process termination and actual beta-source upgrade, isolated under /tmp."""
import json, os, pathlib, signal, subprocess, tempfile, time
ROOT = pathlib.Path(__file__).resolve().parents[1]
SCRATCH = pathlib.Path('/tmp/saytile-rc-storage')
SCRATCH.mkdir(exist_ok=True)
(ROOT/'evidence/rc').mkdir(exist_ok=True)
BETA = SCRATCH / 'beta'
BETA.mkdir(exist_ok=True)
for name in ('Models.swift', 'Store.swift', 'StoreSQLite.swift'):
    (BETA/name).write_bytes(subprocess.check_output(['git','show',f'v1.0.0-beta.1:Sources/SaytileKit/{name}'],cwd=ROOT))
base = ['swiftc','-O','-swift-version','6','-parse-as-library','-I','Sources/CSQLite']
fixture = 'tests/fixtures/StoreProcessProbe.swift'
subprocess.run(base + [f'Sources/SaytileKit/{n}.swift' for n in ('Models','Store','StoreSQLite','StoreLock')] + [fixture,'-o',str(SCRATCH/'probe')],cwd=ROOT,check=True)
subprocess.run(base + [str(BETA/n) for n in ('Models.swift','Store.swift','StoreSQLite.swift')] + [fixture,'-o',str(SCRATCH/'beta-probe')],cwd=ROOT,check=True)
checks=[]
def run(binary,mode,directory,good=True):
    p=subprocess.run([str(SCRATCH/binary),mode,str(directory)],text=True,capture_output=True)
    if (p.returncode == 0) != good: raise RuntimeError(f'{mode}: {p.returncode}\n{p.stdout}\n{p.stderr}')
    print(p.stdout,end=''); return p

def killed(mode,directory,marker,check_lock=False):
    proc=subprocess.Popen([str(SCRATCH/'probe'),mode,str(directory)],stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
    try:
        deadline=time.monotonic()+15
        while not (directory/marker).exists():
            if proc.poll() is not None: raise RuntimeError(proc.communicate())
            if time.monotonic()>deadline: raise TimeoutError(mode)
            time.sleep(.02)
        if check_lock:
            rejected=run('probe','open',directory,False)
            assert '另一个 Saytile' in rejected.stdout
            checks.append('second_process_rejected_without_mutating_live_store')
        os.kill(proc.pid,signal.SIGKILL);proc.wait(timeout=5)
        assert proc.returncode == -signal.SIGKILL
        checks.append(mode+'_sigkill')
    finally:
        if proc.poll() is None: proc.kill();proc.wait()
        proc.communicate()

with tempfile.TemporaryDirectory(prefix='process-fixtures-',dir=SCRATCH) as tmp:
    parent=pathlib.Path(tmp)
    run('probe','disk-fault',parent/'disk-fault');checks.append('real_kernel_write_failure_is_atomic_and_recoverable')
    upgrade=parent/'upgrade'
    run('beta-probe','seed-beta',upgrade)
    run('probe','verify',upgrade); checks.append('actual_beta_1_to_rc_2_upgrade_preserves_all_layers')
    crash=parent/'crash'
    killed('crash-seed',crash,'receipt.json',True)
    run('probe','verify',crash);checks.append('wal_durable_data_and_nonreplay_after_sigkill')
    killed('crash-transaction',crash,'transaction-ready')
    run('probe','verify',crash);checks.append('uncommitted_transaction_rolled_back_after_sigkill')
    killed('crash-delete',crash,'delete-ready')
    run('probe','verify-delete',crash);checks.append('erasure_intent_survives_sigkill_without_losing_text')
report={'scope':'Real SIGKILL subprocess and compiled v1.0.0-beta.1 storage-source upgrade; synthetic private fixture data only','checks':checks,'passed':len(checks),'status':'PASS','baseline':subprocess.check_output(['git','rev-parse','v1.0.0-beta.1'],cwd=ROOT,text=True).strip()}
(ROOT/'evidence/rc/storage-processes.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
print('RC_STORAGE_PROCESS_PASS',len(checks),'checks')
