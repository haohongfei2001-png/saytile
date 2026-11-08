"""Snapshot observed machine evidence. Uses only the isolated run and fixed delivery receipts."""
import datetime
import json
import hashlib
from pathlib import Path
from zoneinfo import ZoneInfo
import shutil
import sys

here = Path(__file__).resolve().parent
stamp = sys.argv[1]
if stamp not in {'start','hosted','24h','48h','72h','2h','interrupted'}: raise ValueError('unknown checkpoint')
snap = here/'snapshots'/stamp
snap.mkdir(parents=True,exist_ok=False)
def read(path):
    return json.loads(path.read_text())
def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()
def stream(path):
    return [json.loads(line) for line in path.read_bytes().splitlines(keepends=True) if line.endswith(b'\n')]
def copyfile(source,destination):
    (snap/destination).write_bytes(source.read_bytes())
def save(name,obj):
    (snap/name).write_text(json.dumps(obj,ensure_ascii=False,indent=2)+'\n')
def now():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()
def local(ts):
    return datetime.datetime.fromtimestamp(ts,ZoneInfo('Asia/Shanghai')).strftime('%Y-%m-%d %H:%M:%S')
source='dc26fe3c59ba55994d29e99ada8d2f0b49ad9886'
package=read(here.parent/'final/package-identity.json')
dmg=here.parents[2]/'deliverables/no-api.9'/Path(package['dmg_path']).name
assert package['source_revision']==source and digest(dmg)==package['dmg_sha256']
def fixed(name):
    return read(here/name)
mic=fixed('microphone.json');route=fixed('private-route.json');ins=fixed('installation.json');policy=fixed('policy.json')
owned=fixed('target-input/owned-summary.json'); interval=fixed('soak/interval.json')
assert mic['binary']==interval['binary_sha256']==ins['binary_sha256']==package['binary_sha256']
assert mic['source']==route['source']==owned['head']==policy['source']==interval['source']==source
assert owned['status']=='PASS' and len(owned['scenarios_passed'])==9
c=stream(here/'controlled-wake.jsonl')
assert any(r['controller_state']=='interrupted("Mac 已睡眠")' for r in c) and c[-1]['controller_state']=='paused'
for name in ['soak/samples.jsonl','process-resource.jsonl','passive-wake.jsonl','soak/launch.log']:
    copyfile(here/name,Path(name).name)
if (here/'soak/result.json').exists():copyfile(here/'soak/result.json','result.json')
samples=stream(snap/'samples.jsonl');energy=stream(snap/'process-resource.jsonl');wake=stream(snap/'passive-wake.jsonl')
units=fixed('counter-units.json')
for row in energy:
    for prefix in ('user','system'):
        value=row.get(prefix+'_ticks',row.get(prefix+'_ns'))
        row[prefix+'_ticks']=value
        row[prefix+'_ns']=round(value*units['mach_timebase_numer']/units['mach_timebase_denom'])
save('process-resource-normalized.json',energy)
assert samples and energy and wake
# Only count an observed pair corroborated by kernel sleep and wake timestamps during our own observation.
pairs=[r for r in wake if r['event']=='didWakeSettled' and r['same_app_pid_alive'] and r['kernel_wake']>r['kernel_sleep']>=wake[0]['unix'] and any(s['event']=='willSleep' and s['unix']<=r['unix'] for s in wake)]
cloudfile=here/'hosted-foreground.json'
hosted=read(cloudfile) if cloudfile.is_file() else None
rfile=snap/'result.json';soak=read(rfile) if rfile.is_file() else None
rows=[]
def add(case,status,detail):
    assert status in {'PASS','FAIL','BLOCKED'}
    rows.append(dict(case=case,status=status,detail=detail))
add('内建麦克风 / 打包 App', 'PASS' if mic['exit']==0 and mic['recordings']==mic['wavs']==0 and any('hardware_frames=240000' in x for x in mic['output']) else 'FAIL','48 kHz，50 个缓冲、240,000 帧。仅计数，隔离 Store 零录音。')
add('进程私有 Core Audio 路由切换和移除','PASS' if 'PASS aggregate input backend' in route['output'] and route['wav_count']==0 else 'FAIL','A→私有双工聚合 B→A 各自读取帧计数，移除 B 后产品拒绝回落到默认输入。初次只含输入的聚合 B 零帧，原始记录单独保存。采集计数由冻结库回调完成，选路与丢失检查使用产品 AudioController。')
add('显式选择内建输入的 tap 装配','FAIL','五秒默认路由计数有帧；随后显式绑定同一内建设备，以读取的 48 kHz 格式装配冻结版本同款 tap。AVFAudio 格式不匹配使计数进程两次 SIGABRT。P1 需根治。此为无内容的硬件复现。')
add('第二支独立物理麦克风 / 热拔插','BLOCKED','本机只报告一个物理输入。聚合路由与 A 共享转换器。')
add('受控睡眠/唤醒通知','PASS','真实 AudioController 收到进程内通知，进入“Mac 已睡眠”，唤醒重新检查缺席设备，显式暂停不重开。内核时间单独保存。')
paused=fixed('paused-wake.json')
add('手动暂停后睡眠 / 唤醒的状态显示','PASS' if paused['pause_label_preserved'] else 'FAIL','受控真实通知复现：初始暂停，唤醒后仍显示“Mac 已睡眠”。没有开麦、写录音或丢失已有文字。限定为 P2 状态显示，按本轮范围保留。')
add('内核睡眠与唤醒期间的驻留、缺席设备恢复','PASS' if any(r['issue'].startswith('所选麦克风未连接') and not r['is_running'] for r in pairs) else 'BLOCKED',f'有内核时间佐证的观察对 {len(pairs)}。独立被动观察器使用不存在的明确 UID。宿主目前无免交互的定时唤醒权限。')
add('睡眠中断后恢复真实语音内容','BLOCKED','共享物理环境没有隔离声源，测试没有保存环境声音。')
log=(here/'target-input/input-native-coordinator.log').read_text(); web=(here/'target-input/input-webkit-observer.log').read_text()
add('AppKit 范围所有权、换目标、用户改字、重启','PASS' if 'RC_AX_COORDINATOR_PASS 9' in log and 'TARGET_MUTATION_PASS 5' in log and 'no_replay=true' in log else 'FAIL','真实后台 NSTextView 的 9 个基础项、5 个改字项，加 9 个范围修订场景。')
add('后台 WKWebView 的不确定投递保护','PASS' if 'WEB_INSERT_RESULT unverified' in web and 'PASS real WKWebView fixture never sends' in web else 'FAIL','后台 setter 应答但 DOM 未变。账本未确认，未重放，发送数为零。')
add('后台 WKWebView 的实际文字投递','FAIL' if 'unchanged_fixture=true expected_inserted=false' in web else 'BLOCKED','此目标未收到预期插入。产品安全拒绝把它记作成功。')
add('隔离前台目标的完整生产选择路径',hosted['status'] if hosted else 'BLOCKED',hosted['detail'] if hosted else '等待独立 GitHub macOS runner；共享用户当前窗口不作为目标。')
if hosted:
    add('前台 WKWebView 投递',hosted['foreground_wk_dispatch'],'正式 resolver 到达自有网页编辑器，实际插入未确认；未达到该目标的投递要求。')
    add('前台 WKWebView 换目标 / 自动发送保护',hosted['foreground_wk_safety'],'silentContext 更换页面后拒绝旧投递，发送计数为零。')
add('独立安装、升级和回退','PASS' if ins['status']=='PASS' and ins['count']==8 else 'FAIL','重新下载公开 RC1 DMG 并核验指纹。实际临时安装、升级、回退、崩溃重启和三次重开均保留测试档案；未读取用户的已安装 RC1。')
add('卸载重装保留数据','PASS' if len(read(here.parent/'final/uninstall-reinstall.json')['checks'])==2 else 'FAIL','同一源码和安装包的既有独立实测，两项。')
add('普通 Gatekeeper 执行','FAIL' if policy['gatekeeper']['exit']!=0 else 'PASS','严格 codesign 校验通过；启用的 Gatekeeper 返回 rejected，退出码 3。Developer ID 签名及公证需要发行身份。')
add('72 小时驻留和资源占用',soak['status'] if soak else 'BLOCKED',f"最近采样 {samples[-1]['wall_seconds']/3600:.2f} 小时，共 {len(samples)} 点；RSS {min(i['rss_kib'] for i in samples):,}–{max(i['rss_kib'] for i in samples):,} KiB。预计到期 {local(datetime.datetime.fromisoformat(interval['due_utc']).timestamp())}（北京时间）。")
active=here/'active/result.json'
active_data=read(active) if active.is_file() else None
if active_data is not None:
    save('active-speech.json', active_data)
add('两小时真实本地 VAD / ASR 间歇负载',active_data['status'] if active_data else 'BLOCKED',
    (f"实际时钟 {active_data['elapsed']:.1f} 秒，归档 {active_data.get('records')} 笔、完成 {active_data.get('completed')} 笔，丢帧 {active_data.get('drops')}。" if active_data else '两个已验证合成句子每三分钟重放一组，通过同一默认 worker 处理；等待完整 2 小时终态。'))
add('整机功耗归因','BLOCKED','powermetrics 在当前权限下拒绝运行。已采集 macOS 的单进程 CPU、物理内存、能量计数和空闲唤醒；不能据此推算整机耗电。')
add('真实云服务与识别质量','BLOCKED','Qwen、AssemblyAI、GPT-6 Astra 的真实账户连接、真人音频准确率、相对最强单模型收益及额外确认延迟仍待独立授权。')
summary={'source':source,'source_tree':package['tree'],'binary_sha256':package['binary_sha256'],'dmg_sha256':package['dmg_sha256'],'version':package['version'],'host':'Apple Silicon, macOS 27.0 (26A428)','stamp':stamp,'utc':now(),'results':rows,'counts':{status:sum(r['status']==status for r in rows) for status in ['PASS','FAIL','BLOCKED']},'soak_completed':bool(soak and soak['status']=='PASS'),'real_provider_calls':0,'runtime_changed':False,'references':{str(f.relative_to(here)):digest(f) for f in sorted(list(snap.iterdir())+[here/n for n in ('private-route.json','private-route-initial.json','microphone.json','installation.json','policy.json','paused-wake.json','counter-units.json','wake-identity.json','controlled-wake.jsonl','target-input/owned-summary.json','target-input/input-native-coordinator.log','target-input/input-webkit-observer.log')]) if f.is_file()}}
summary['soak_observation']={'points':len(samples),'elapsed_wall_seconds':samples[-1]['wall_seconds'],'largest_sampling_gap_seconds':max((b['wall_seconds']-a['wall_seconds'] for a,b in zip(samples,samples[1:])),default=0),'max_footprint_bytes':max(r['footprint_bytes'] for r in energy),'last_energy_nj':energy[-1]['reported_energy_nj'],'first_energy_nj':energy[0]['reported_energy_nj'],'earliest_energy_sample_unix':energy[0]['unix'],'latest_energy_sample_unix':energy[-1]['unix'],'scope':'Kernel per-process counters. The samples measure this PID, not total power or the Apple recognizer service.'}
save('machine.json',summary)
doc=['# no-api.9 实机验收','',f'检查点 `{stamp}`，生成于 {local(datetime.datetime.fromisoformat(summary["utc"]).timestamp())}（北京时间）。', '',f'冻结源码 `{source}`，安装包 SHA-256 `{package["dmg_sha256"]}`。[固定 DMG](https://raw.githubusercontent.com/haohongfei2001-png/saytile/0aa51620c63612246395d8f2a83e1eb96c9e94c4/deliverables/no-api.9/Saytile-1.0.0-rc.2-no-api.9-arm64.dmg) · [机器结果与收据指纹](snapshots/'+stamp+'/machine.json)。','','| 项目 | 结果 | 实测范围 |','| --- | --- | --- |']
doc += [f"| {r['case']} | **{r['status']}** | {r['detail']} |" for r in rows]
doc+=['','需要跟进的 FAIL 和尚欠前提的 BLOCKED 项均列在表中。实测原始输入均为合成夹具或不读取声音样本的硬件计数。','']
(here/'README.md').write_text('\n'.join(doc))
print(stamp,summary['counts'])
