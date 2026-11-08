import json,sys
from pathlib import Path
phase=sys.argv[1];e=Path('evidence/no-api9.1');m=json.loads((e/'app/identity.json').read_text());r=json.loads((e/'snapshots'/phase/'machine.json').read_text())
repo='https://github.com/haohongfei2001-png/saytile'
public=e/'app/public.json'
url=json.loads(public.read_text())['url'] if public.is_file() else '../'+m['repo_dmg']
for name,title in [('docs/V1-NO-API-DELIVERY.md','Saytile V1 无密钥交付'),('docs/V1-DEV-STATUS.md','V1 开发状态'),('docs/00-DELIVERY-STATUS.md','Saytile 交付状态'),('docs/V1-TEST-RESULTS.md','V1 测试结果'),('docs/V1-USER-ACTIONS.md','用户事项')]:
    body=f"# {title} · no-api.9.1\n\n当前设备修补候选来自[运行源码 `0a0cdeca`]({repo}/commit/{m['source_revision']})。[固定安装包]({url}) · [完整实机报告](../evidence/no-api9.1/README.md) · [逐项机器验收](../evidence/no-api9.1/snapshots/{phase}/machine.json)。\n\n"
    body+="基线 no-api.9 的显式设备装配路径在同款计数探针中触发 AVFAudio 格式异常，直接中止进程。修补版明确选麦时按 UID 打开系统输入队列，继续使用原有音频日志和识别工作线程。设备移除会中断采集，必须明确选择可用设备才会恢复。\n\n"
    body+=f"本阶段 {r['status_counts']['PASS']} 项 PASS，{r['status_counts']['FAIL']} 项 FAIL，{r['status_counts']['BLOCKED']} 项 BLOCKED。正常 TextEdit 前台投递已实测；WKWebView 投递未确认，目标改变后没有重试或发送。受控睡眠后暂停标签仍旧是 P2。普通 Gatekeeper 执行拒绝；本包仅为 ad-hoc 工程候选。\n\n"
    if name.endswith('USER-ACTIONS.md'):body+="本轮无需用户录音、调试或提供日志。将来选择启用云端时，在「AI 识别 → 连接识别服务」填写 Qwen 凭据／地域／Workspace、AssemblyAI 和 OpenAI 凭据，并分别授权合成样本上传和费用。使用麦克风或跨应用直接输入时才授予相应系统权限。\n\n"
    body+="三家真实云服务、真人准确率、相比最强单模型的收益与确认延迟均待凭据与授权。实际系统睡眠与第二支独立物理麦克风保留各自状态。标准公开分发需要发行方 Developer ID 签名和公证。\n\n"
    if phase in ['package','public','2h','repeat-start','2h-verified']:
        body+='72 小时实时时钟的计划终点为北京时间 2026-11-10 19:54；终态以实际收据为准。\n\n'
    if phase in ['interrupted','72h','repeat-interrupted','fd-start','fd-interrupted']:
        end=json.loads((e/'sustained/idle-repeat/soak/interval.json').read_text())['due_utc']
        body+="首轮驻留取得 22.32 小时、1,340 次真实采样和两对内核睡醒记录。观察中断，未取得退出原因。复测时间独立，状态见同一源码的逐项机器验收。\n\n"
        if phase=='interrupted':body+=f"复测预定结束 {end}（UTC）。\n\n"
    if phase in ['72h','fd-start','fd-interrupted']:
        last=json.loads((e/'sustained/idle-fd-fixed/soak/interval.json').read_text())
        body+="第二轮在 3.05 小时后因采样脚本未关闭只读 SQLite 连接而中止；修正后在同样的 64 文件限额下完成 5,000 次采样。连续驻留再次从零计时，应用源码与安装包均保持冻结。\n\n"
        if phase=='fd-start':body+=f"本轮预定结束 {last['due_utc']}（UTC）。\n\n"
    body+=f"[原冻结版记录]({repo}/blob/45256e38fb2d52d1c583965bb259d3c27edafc79/docs/V1-NO-API-DELIVERY.md) · [安装与数据回退](V1-INSTALL.md)。\n"
    Path(name).write_text(body)
read=Path('README.md');s=read.read_text();token='<!-- frozen-machine-current:end -->'
if token in s:s=s.split(token,1)[1].lstrip()
# Keep the approved original and product documentation; retire the old current status banner.
import re
s=re.sub(r'<!-- no-api9-current:begin -->.*?<!-- no-api9-current:end -->\s*','',s,flags=re.S)
s=s.replace('本分支的 no-api.9 候选及证据见','本分支的 no-api.9.1 候选及证据见')
read.write_text(f'# Saytile\n\nApple Silicon / macOS 26+。显式选麦的 P1 修复已进入 no-api.9.1。已有源代码、可下载 DMG 及按 PASS、FAIL、BLOCKED 区分的[实机验收](evidence/no-api9.1/README.md)。正式公开安装和真实云端识别仍待各自条件。\n{token}\n\n'+s)
Path('deliverables/no-api.9.1/README.md').write_text(f"# Saytile 1.0.0-rc.2-no-api.9.1\n\n[DMG]({Path(m['repo_dmg']).name}) · [校验和](SHA256SUMS.txt) · [实机报告](../../evidence/no-api9.1/README.md)。\n\n运行源码 `{m['source_revision']}`；DMG SHA-256 `{m['dmg_sha256']}`。Apple Silicon / macOS 26+。签名为 ad-hoc，本机 Gatekeeper 执行评估拒绝，普通分发仍需 Developer ID 签名与公证。无需覆盖 RC1。\n")
