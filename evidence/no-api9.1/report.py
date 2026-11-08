"""Summarize only inspections and process results observed on the frozen .9.1 source."""
from pathlib import Path
import hashlib,json,datetime,sys,shutil,subprocess,statistics,ctypes
from zoneinfo import ZoneInfo

base=Path(__file__).resolve().parent
phase=sys.argv[1]
assert phase in ('package','public','2h','repeat-start','2h-verified','72h','interrupted','repeat-interrupted','fd-start','fd-interrupted')
snap=base/'snapshots'/phase
snap.mkdir(parents=True,exist_ok=False)
def load(path): return json.loads(path.read_text())
def digest(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def data(name):return load(base/name)
def lines(path):
    return [json.loads(s) for s in path.read_bytes().splitlines(keepends=True) if s.endswith(b'\n')]
def local(ts):
    return datetime.datetime.fromtimestamp(ts,ZoneInfo('Asia/Shanghai')).strftime('%Y-%m-%d %H:%M:%S')
def snapfile(rel,name):
    path=base/rel
    if path.is_file():shutil.copyfile(path,snap/name)
m=data('app/identity.json');source=m['source_revision'];binary=m['binary_sha256']
assert source=='0a0cdecab8eb099e1dc3bb21b4c15ba5c30c93f0'
assert digest(Path(m['dmg_path']))==m['dmg_sha256'] and digest(Path(m['app_path'])/'Contents/MacOS/Saytile')==binary
entries=[]
def row(case,status,detail,files):
    assert status in ('PASS','FAIL','BLOCKED')
    entries.append(dict(case=case,status=status,detail=detail,evidence=files))
mic=data('hardware/packaged-microphone.json'); assert mic['source']==source and mic['binary']==binary
row('安装包连接内建麦克风',mic['status'],'同一签名 App 的两段五秒硬件计数。'+mic['log'][0]+'。数据库录音与 WAV 均为零。',['hardware/packaged-microphone.json'])
for mode,title in [('duplex','双工聚合设备'),('input-only','纯输入聚合设备')]:
    h=data('hardware/'+mode+'.json')
    assert h['source']==source and len(h['source_changes'])==0
    ok=h['exit']==0 and not h['wavs'] and any(s.startswith('REMOVAL') for s in h['trace']) and 'PASS aggregate input backend' in h['trace']
    row('切换并在采集中移除'+title,'PASS' if ok else 'FAIL','使用真实 Core Audio 私有设备与产品选路代码。移除触发明确中断，恢复内建输入，系统默认输入保持一致。', ['hardware/'+mode+'.json'])
row('第二支独立物理麦克风拔插','BLOCKED','本次 Mac 只有一支物理输入；两个私有聚合路由均借用该输入。', ['hardware/duplex.json','hardware/input-only.json'])
wakeID=data('sustained/wake-identity.json'); assert wakeID['source']==source
c=lines(base/'sustained/controlled-wake.jsonl')
row('受控睡眠和唤醒通知','PASS' if any('Mac 已睡眠' in s['controller_state'] for s in c) and c[-1]['controller_state']=='paused' else 'FAIL','生产 AudioController 转入中断，唤醒后重新检查明确的缺席设备，手动暂停时保持关闭。',['sustained/controlled-wake.jsonl','sustained/wake-identity.json'])
paused=data('sustained/paused-wake.json'); assert paused['source_revision']==source
row('暂停状态经历睡眠、唤醒后显示','PASS' if paused['pause_label_preserved'] else 'FAIL','P2：原本暂停时，受控唤醒后仍显示“Mac 已睡眠”，没有开麦或新增录音。',['sustained/paused-wake.json'])
idle_root = 'sustained'
if phase in ('72h','fd-start','fd-interrupted') and (base/'sustained/idle-fd-fixed/soak/interval.json').exists():
    idle_root = 'sustained/idle-fd-fixed'
elif phase in ('72h','repeat-interrupted'):
    idle_root = 'sustained/idle-repeat'
repeat_idle = idle_root != 'sustained'
for file, name in [('passive-wake.jsonl', 'passive-wake.jsonl'), ('soak/samples.jsonl', 'idle-samples.jsonl'),
                   ('process-resource.jsonl', 'process-resource.jsonl'), ('soak/result.json', 'idle-result.json')]:
    snapfile(idle_root + '/' + file, name)
for file, name in [('samples.jsonl','speech-resources.jsonl'), ('result.json','speech-result.json'),
                   ('observations.json.gz','speech-observations.json.gz')]:
    snapfile('sustained/active/' + file, name)
wake_logs = ['snapshots/' + phase + '/passive-wake.jsonl']
if repeat_idle:
    snapfile('sustained/passive-wake.jsonl', 'first-run-passive-wake.jsonl')
    wake_logs.append('snapshots/' + phase + '/first-run-passive-wake.jsonl')
pairs = {}
rechecked_device = False
for log in wake_logs:
    events = lines(base/log)
    previous_sleep = None
    for event in events:
        if event['event'] == 'willSleep':
            previous_sleep = event
        if event['event'] != 'didWakeSettled' or previous_sleep is None:
            continue
        if (event['same_app_pid_alive'] and
            previous_sleep['unix'] - 1 <= event['kernel_sleep'] < event['kernel_wake'] <= event['unix'] and
            event['kernel_wake'] > previous_sleep['kernel_wake']):
            pairs[(event['kernel_sleep'], event['kernel_wake'])] = event
            rechecked_device |= event['issue'].startswith('所选麦克风未连接') and not event['is_running']
        previous_sleep = None
row('真实系统睡醒时进程存活、保持停采', ('PASS' if all(not r['is_running'] for r in pairs.values()) else 'FAIL') if pairs else 'BLOCKED',
    f'共 {len(pairs)} 对独立的内核睡醒时间与 Workspace 通知吻合。候选进程在对应唤醒记录中存活；另一个使用生产 AudioController 的观察进程只检查停采状态。',
    wake_logs)
row('真实唤醒后重新检查指定的缺席输入', 'PASS' if rechecked_device else 'BLOCKED',
    '在真实唤醒后观察到缺席设备检查。' if rechecked_device else '未观察到可重新开麦的登录会话中完成缺席设备检查。锁屏、TCC 与会话许可会影响恢复，受控通知结果另列。',
    wake_logs)
row('真实睡眠后继续物理语音','BLOCKED','没有隔离物理声源及可安全保存的环境讲话。缺席设备检查不能证明恢复真实讲话。',[])
ui=data('app/ui/manifest.json')
focus=(base/'app/focus.log').read_text()
ui_run=(base/'app/ui/run.log').read_text()
row('成品原生操作和非激活启动','PASS' if ui['passed'] and ui['source_revision']==source and ui['binary_sha256']==binary and 'candidate_activated=true' not in ui_run and 'frontmost_unchanged=true' in focus else 'FAIL',f"{ui['native_ax_press']} 次原生按钮操作、{ui['native_menu_select']} 次菜单选择。UI 过程中观察到 {ui['outside_foreground_observations']} 次外部前台变化，日志均显示候选未激活；另一次专门的启动检查保持前台不变。",['app/ui/manifest.json','app/ui/run.log','app/focus.log','app/focus-hashes.txt'])
native=(base/'targets/input-native-coordinator.log').read_text()
owned=data('targets/ranges.json'); assert owned['head']==source
row('本机 NSTextView 所有权与错投防护','PASS' if owned['status']=='PASS' and len(owned['scenarios_passed'])==9 and 'RC_AX_COORDINATOR_PASS 9' in native and 'TARGET_MUTATION_PASS 5' in native else 'FAIL','覆盖稳定范围去重、外部改字、新目标、选区变化、窗口关闭及重启。',['targets/input-native-coordinator.log','targets/ranges.json'])
host=data('targets/hosted.json'); assert host['source']==source
row('生产前台选择 / 真实 TextEdit',host['textedit'],'独立托管 Mac 上，仅新开的合成文档。核对首写、emoji、原有前后缀、连续增量、重复修订及选区变化。',['targets/hosted.json','targets/hosted/textedit.txt'])
row('前台 WKWebView 实际投递',host['wk_delivery'],host['wk_delivery_detail'],['targets/hosted/input-foreground-batch.log'])
row('前台 WKWebView 目标变化、发送与重放',host['wk_safety'],host['wk_safety_detail'],['targets/hosted/input-foreground-batch.log'])
upgrade=data('installation/upgrade.json');reinstall=data('installation/uninstall-reinstall.json')
assert upgrade['source_revision']==reinstall['source_revision']==source and upgrade['binary_sha256']==reinstall['binary_sha256']==binary
row('隔离安装、升级、回退、卸载重装','PASS' if upgrade['status']==reinstall['status']=='PASS' and upgrade['count']==8 and len(reinstall['checks'])==2 else 'FAIL','公开 RC1 安装包仅用于临时目录中的模拟用户档案。未读取用户的已安装 RC1 或资料。',['installation/upgrade.json','installation/uninstall-reinstall.json'])
policy=data('app/distribution-policy.json')['checks']
row('普通 Gatekeeper 执行','PASS' if policy['assess'][0]==0 else 'FAIL',f"严格代码签名校验 exit {policy['integrity'][0]}，Gatekeeper 执行评估 exit {policy['assess'][0]}。个人工程包未取得 Developer ID 公证。",['app/distribution-policy.json'])
apple=data('app/apple.json');assert apple['source']==source and apple['binary']==binary
row('成品 Apple 本机识别',apple['status'],'包内 App 识别合成中文、保存 WAV 并形成正式文字。',['app/apple.json'])
wire=data('protocol/wire-audit.json')
dlog=(base/'protocol/driver.log').read_text()
row('原生、AppModel 和协议回归','PASS' if '393 tests in 48 suites passed' in dlog and 'WIRE_AUDIT cases=50 protocol_violations=0' in dlog and 'APP_MODEL_PROBE_PASS 104' in (base/'app/app-model.log').read_text() else 'FAIL','393 个原生测试函数，104 项 AppModel 检查，50 个本机协议用例。',['protocol/driver.log','protocol/wire-audit.json','app/app-model.log'])
active=data('sustained/active/start.json');assert active['source']==source
ar=load(snap/'speech-result.json') if (snap/'speech-result.json').exists() else None
repeat=base/'sustained/active-repeat'
if ar and ar.get('unchanged') is False:
    row('首次两小时试验的档案指纹','FAIL','首次运行正常退出，80 段均定稿、原音有效、零丢帧；同一 Swift 构建目录被存储验证重用，试验后静态库指纹改变，原始 FAIL 保留。复测单独构建并核对实际执行文件、静态库、输入语料和源码。',['sustained/active/provenance-diagnosis.json','snapshots/2h/speech-result.json'])
    if repeat.is_dir():
        snapfile('sustained/active-repeat/samples.jsonl','repeat-resources.jsonl')
        snapfile('sustained/active-repeat/result.json','repeat-result.json')
        snapfile('sustained/active-repeat/observations.json.gz','repeat-observations.json.gz')
    ar=load(snap/'repeat-result.json') if (snap/'repeat-result.json').exists() else None
row('两小时真实本地识别负载',ar['status'] if ar else 'BLOCKED',f"实际 {ar['elapsed']:.2f} 秒，{ar.get('completed')} 笔定稿、{ar.get('drops')} 丢帧。" if ar else '每三分钟输入两个固定合成句子，同一进程持续采集、保存、Apple 定稿，等待两小时实时时钟。',['sustained/active/start.json','snapshots/'+phase])
iv=data(idle_root+'/soak/interval.json');assert iv['source']==source and iv['binary_sha256']==binary
rs=lines(snap/'idle-samples.jsonl');energy=lines(snap/'process-resource.jsonl')
ir=load(snap/'idle-result.json') if (snap/'idle-result.json').exists() else None
duration=rs[-1]['wall_seconds'];max_gap=max((b['wall_seconds']-a['wall_seconds'] for a,b in zip(rs,rs[1:])),default=0)
interruption_file = base/'sustained/soak/interruption.json'
if interruption_file.exists():
    first = load(interruption_file)
    assert first['source'] == source and first['binary_sha256'] == binary
    row('首轮驻留观察中断', 'BLOCKED',
        f"同一 PID 最后一次记录为 {first['last_observed']['wall_seconds']/3600:.2f} 小时，共 {first['observed_samples']} 次。未取得退出原因或终态收据。独立测试库完整性 {first['isolated_database_integrity']}，录音 {first['isolated_recordings']}。复测独立计时。",
        ['sustained/soak/interruption.json','sustained/soak/interval.json'])
if idle_root == 'sustained/idle-fd-fixed':
    failed_observer = data('snapshots/repeat-interrupted/idle-result.json')
    fd_check = data('sustained/idle-repeat/fd-reproduction.json')
    assert failed_observer['source'] == fd_check['source'] == source and 'Errno 24' in failed_observer['cause']
    row('第二轮驻留采样器文件描述符', 'FAIL',
        f"采样器在 {failed_observer['elapsed_wall_seconds']/3600:.2f} 小时报 Errno 24 并主动终止当时仍在运行的候选。只读 SQLite 连接未逐次关闭；隔离重现在文件限额 64 时第 61 次采样失败。修正后 5,000 次采样全过，最多 4 个描述符。此次运行时间单独保留。",
        ['snapshots/repeat-interrupted/idle-result.json', 'sustained/idle-repeat/fd-reproduction.json'])
if ir and ir['status'] == 'PASS':
    assert ir['source'] == source and ir['binary_sha256'] == binary
    assert ir['samples'] == len(rs) and ir['wall_seconds'] >= 72 * 3600 and duration >= 72 * 3600
    assert rs[0]['wall_seconds'] < 60 and len({r['start_abstime'] for r in energy}) == 1
    assert all(r['recordings'] == 0 for r in rs)
row('72 小时实际 App 驻留和进程资源',ir['status'] if ir else 'BLOCKED',f"{duration/3600:.2f} 小时，{len(rs)} 次采样，RSS {min(r['rss_kib'] for r in rs):,}–{max(r['rss_kib'] for r in rs):,} KiB，最大采样间隔 {max_gap:.1f} 秒。到期 {local(datetime.datetime.fromisoformat(iv['due_utc']).timestamp())}。",[idle_root+'/soak/interval.json','snapshots/'+phase])
row('整机功耗归因','BLOCKED','仅取得当前测试 PID 的内核能量、CPU、唤醒和物理内存计数，整机 powermetrics 需要管理员权限。',['snapshots/'+phase+'/process-resource.jsonl'])
row('真实云端认证、转写、质量收益及确认延迟','BLOCKED','真实调用为零。三项有效账户、相应模型权限和处理/费用授权、同一经许可的人声材料仍是前提。',[])
summary={'source':source,'tree':m['tree'],'version':m['version'],'binary_sha256':binary,'dmg_sha256':m['dmg_sha256'],'stamp':phase,'utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'host':'macOS 27.0 (26A428), Apple Silicon','checks':entries,'status_counts':{k:sum(r['status']==k for r in entries) for k in ('PASS','FAIL','BLOCKED')},'real_cloud_calls':0,'production_ready':False,'producer_clock_complete':bool(ir and ir['status']=='PASS' and ar and ar['status']=='PASS'),'max_sample_gap':max_gap,'raw_files':{}}
class MachTimebase(ctypes.Structure):
    _fields_=[('numer',ctypes.c_uint32),('denom',ctypes.c_uint32)]
tb=MachTimebase()
assert ctypes.CDLL('/usr/lib/libSystem.B.dylib').mach_timebase_info(ctypes.byref(tb))==0
if len(energy)>=2:
    start,end=energy[0],energy[-1]
    seconds=end['unix']-start['unix']
    if seconds>0:
        cpu_ticks=(end['user_ticks']+end['system_ticks'])-(start['user_ticks']+start['system_ticks'])
        summary['kernel_process_usage']={'observation_seconds':seconds,'samples':len(energy),'source_pid':iv['pid'],'same_start_abstime':len({r['start_abstime'] for r in energy})==1,'timebase_numer':tb.numer,'timebase_denom':tb.denom,
            'cpu_percent_one_core':cpu_ticks*tb.numer/tb.denom/1e9/seconds*100,'mean_cpu_energy_mW':(end['reported_energy_nj']-start['reported_energy_nj'])/seconds/1e6,
            'footprint_max_bytes':max(r['footprint_bytes'] for r in energy),'footprint_first_decile_median_bytes':statistics.median(r['footprint_bytes'] for r in energy[:max(1,len(energy)//10)]),'footprint_last_decile_median_bytes':statistics.median(r['footprint_bytes'] for r in energy[-max(1,len(energy)//10):]),
            'scope':'App process only. CPU energy attributed by the kernel; excludes system ASR services and other devices.'}
for r in entries:
    for name in r['evidence']:
        f=base/name
        if f.is_file():summary['raw_files'][name]=digest(f)
for f in snap.iterdir():
    if f.is_file():summary['raw_files'][str(f.relative_to(base))]=digest(f)
(snap/'machine.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2)+'\n')
download=data('app/public.json')['url'] if (base/'app/public.json').exists() else '../../'+m['repo_dmg']
doc=['# Saytile no-api.9.1 实机验收','','冻结源码 `'+source+'`。DMG SHA-256 `'+m['dmg_sha256']+'`。[下载候选]('+download+') · [机器结果与收据指纹](snapshots/'+phase+'/machine.json)。','','基线 no-api.9 显式选定内建麦克风时，计数探针复现了与产品相同的 AVAudioEngine 装配顺序导致的 SIGABRT。修补版只更改显式选定输入的硬件采集，默认设备和后续识别、存储、直接输入逻辑继承冻结基线。[修复提交](https://github.com/haohongfei2001-png/saytile/commit/'+source+')。','','| 项目 | 判定 | 实测与边界 |','| --- | --- | --- |']
doc += ['| '+r['case']+' | **'+r['status']+'** | '+r['detail']+' |' for r in entries]
if interruption_file.exists() and not repeat_idle:
    next_interval=data('sustained/idle-repeat/soak/interval.json')
    doc+=['',f"首轮未满 72 小时。复测使用同一安装包与全新隔离库，自北京时间 {local(datetime.datetime.fromisoformat(next_interval['start_utc']).timestamp())} 单独计时，预定结束 {local(datetime.datetime.fromisoformat(next_interval['due_utc']).timestamp())}。"]
usage=summary.get('kernel_process_usage')
if usage:
    doc+=['',f"在 {usage['observation_seconds']/3600:.2f} 小时内，这个暂停驻留进程的 CPU 时间占单核墙钟 {usage['cpu_percent_one_core']:.3f}%，内核归因的平均 CPU 能量折算为 {usage['mean_cpu_energy_mW']:.3f} mW。物理内存占用的首、末十分位区间中位数分别为 {usage['footprint_first_decile_median_bytes']/1048576:.1f}、{usage['footprint_last_decile_median_bytes']/1048576:.1f} MiB。整机功耗单独列为 BLOCKED。"]
doc+=['','真实云端待验证事项包括 Qwen 地域及 Workspace、AssemblyAI 模型权限、GPT-6 Astra 接收候选和结束定稿、同音频四阶段准确率及额外确认延迟。未进行付费调用或上传私人录音。','']
(base/'README.md').write_text('\n'.join(doc))
print(phase,summary['status_counts'])
