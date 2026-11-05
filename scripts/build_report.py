from pathlib import Path
import subprocess,base64,os,shutil
from playwright.sync_api import sync_playwright
R=Path(__file__).resolve().parents[1]
sections=['01-PRODUCT-AND-ROADMAP.md','02-V1-ARCHITECTURE.md','03-REBUILT-REVIEW-CONTRACTS.md','04-ACCEPTANCE.md','05-IMPLEMENTATION-HANDOFF.md','06-PROVENANCE.md']
md='# Saytile · V1 产品与技术设计\n\n恢复修订版 · 2026-11-06\n\n'
for f in sections:md+=(R/'docs'/f).read_text()+'\n\n'
(R/'docs/Saytile-V1-Design-Revision.md').write_text(md)
css='''
@page{size:A4;margin:19mm 17mm 20mm}*{box-sizing:border-box}body{font-family:"Noto Sans CJK SC","Noto Sans",sans-serif;font-size:10pt;line-height:1.5;color:#26322c;margin:0}h1,h2,h3{font-weight:650;color:#24392e;break-after:avoid}h1{font-size:22pt;line-height:1.25;margin:0 0 5mm}h2{font-size:13pt;margin:5mm 0 2mm}h3{font-size:11pt;margin:5mm 0 2mm}p{margin:0 0 2.5mm;orphans:3;widows:3}li{margin:1.2mm 0}ul,ol{padding-left:6mm;margin:2mm 0 4mm}table{border-collapse:collapse;width:100%;font-size:8.6pt;margin:5mm 0;break-inside:avoid}th,td{padding:2.5mm 2mm;border-bottom:1px solid #d9e0d8;text-align:left;vertical-align:top}th{background:#edf1e9}tr{break-inside:avoid}code{font-family:"DejaVu Sans Mono",monospace;font-size:.88em;background:#f1f3ef;word-break:break-word}pre{font-size:8pt;white-space:pre-wrap;background:#f1f3ef;padding:3mm;border-radius:2mm}a{color:#3e614a;overflow-wrap:anywhere;text-decoration:none}blockquote{border-left:3px solid #779479;padding-left:4mm;margin:4mm 0;color:#5a685d}.chapter{margin-top:9mm}.cover+.chapter{break-before:page;margin-top:0}.prototype-chapter{break-before:page;margin-top:0}.eyebrow{letter-spacing:.2em;color:#6a7d6e;font-size:9pt;margin-bottom:14mm}.cover h1{font-size:48pt;margin:0 0 5mm;letter-spacing:-.02em}.subtitle{font-size:23pt;line-height:1.4;margin-bottom:8mm}.lede{font-size:13pt;color:#607261;max-width:145mm}.cover-note{padding:6mm;background:#f0f3ed;border-left:3px solid #6d856a;margin-top:13mm}.metric-grid{display:grid;grid-template-columns:repeat(3,1fr);gap:4mm;margin:13mm 0}.metric{padding:5mm;background:#f7f8f5;border-top:1px solid #b8c9b5}.metric b{display:block;font-size:23pt;color:#385b42}.metric span{font-size:9pt;color:#657566}.muted{font-size:9pt;color:#718071}.figure{width:100%;border:1px solid #dce2d7;border-radius:2mm}.caption{font-size:8.5pt;color:#6b796c;margin-top:2mm}.section-label{font-size:8.5pt;letter-spacing:.15em;color:#7b8b7d;margin-bottom:3mm}
'''
body='''<section class="cover"><div class="eyebrow">HOLDSNOW / PRODUCT DESIGN</div><h1>Saytile</h1><div class="subtitle">V1 产品与技术设计<br>恢复修订版</div><p class="lede">自然开口，随时取用。<br>把已完成的研究恢复成可验证、可接续的工程基础。</p><div class="metric-grid"><div class="metric"><b>10 / 10</b><span>继承合成故障实验</span></div><div class="metric"><b>37 / 37</b><span>重建数据契约检查</span></div><div class="metric"><b>48 / 48</b><span>浏览器 DOM 交互</span></div></div><div class="cover-note"><strong>本轮交付边界</strong><p>产品路线、SQL/Swift 接口、可运行参考模型、高保真原型与验证证据。不是已完成的原生 macOS App。</p><p>两项关键修订已重建：只删原音仍保留文字；连续输入按稳定前缀增量派发。</p><p>原始 35 页研究及技术包按原件保留。最后未上传的 Pro 文件没有原件级找回，本报告不冒充旧稿。</p></div><p class="muted" style="margin-top:10mm">2026-11-06 · V1 唯一当前研发重点<br>V2：轻声识别　/　V3：个人词库与文字输入法</p></section>'''
for idx,f in enumerate(sections,1):
 html=subprocess.run(['pandoc','-f','gfm','-t','html5'],input=(R/'docs'/f).read_text(),text=True,capture_output=True,check=True).stdout
 body+=f'<section class="chapter"><div class="section-label">SAYTILE / {idx:02d}</div>{html}</section>'
body+='<section class="chapter prototype-chapter"><div class="section-label">SAYTILE / PROTOTYPE</div><h1>可交互的修订原型</h1><p>七个主场景均保留。新增删除原音确认、文字保留状态、稳定前缀重复/改写演示与演示重置。此处使用测试截图，不是已经运行的 Mac App。</p>'
for filename,title in [('prototype-standby.png','常驻待命与即时输入板'),('prototype-audio-deleted.png','仅删除原音后：文字、修改稿与复用仍在')]:
 data=base64.b64encode((R/'evidence'/filename).read_bytes()).decode()
 body+=f'<h2>{title}</h2><img class="figure" src="data:image/png;base64,{data}"><p class="caption">浏览器演示；没有真实录音、ASR、系统权限或跨应用输入。</p>'
body+='</section>'
html='<!doctype html><html lang="zh-CN"><meta charset="utf-8"><title>Saytile V1 恢复修订报告</title><style>'+css+'</style><body>'+body+'</body></html>'
(R/'docs/Saytile-V1-Design-Revision.html').write_text(html)
with sync_playwright() as p:
 b=p.chromium.launch(executable_path=os.getenv('SAYTILE_BROWSER_PATH') or shutil.which('chromium') or None,headless=True,args=['--no-sandbox'])
 page=b.new_page();page.set_content(html,wait_until='load');page.emulate_media(media='print')
 page.pdf(path=str(R/'docs/Saytile-V1-Design-Revision.pdf'),format='A4',print_background=True,display_header_footer=True,
  header_template='<div style="font-size:8px;width:100%;margin:0 17mm;color:#7a8579">SAYTILE · V1 DESIGN RECOVERY</div>',
  footer_template='<div style="font-size:8px;width:100%;margin:0 17mm;color:#7a8579;display:flex;justify-content:space-between"><span>设计验证不等于原生产品验收</span><span><span class="pageNumber"></span> / <span class="totalPages"></span></span></div>')
 b.close()
print('PDF bytes',(R/'docs/Saytile-V1-Design-Revision.pdf').stat().st_size)
