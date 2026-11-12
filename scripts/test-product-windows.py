#!/usr/bin/env python3
"""Real WindowServer composition at 2x. Only the named design app and its own known backdrop.
Scenes are native; speech, permission and archives are fixtures. No user desktop is captured."""
import argparse, hashlib, json, os, plistlib, subprocess, tempfile, time
from pathlib import Path
from PIL import Image, ImageFilter, ImageStat
parser=argparse.ArgumentParser(); parser.add_argument('--app',type=Path,required=True); parser.add_argument('--output',type=Path,required=True)
parser.add_argument('--scenes',nargs='+',help='Capture only these scenes; never earns a full PASS')
a=parser.parse_args(); root=Path(__file__).resolve().parent.parent; out=a.output.resolve(); app=a.app.resolve()
if any(app.is_relative_to(base.resolve()) for base in (Path('/Applications'), Path.home()/'Applications')):
    raise SystemExit('Use a staging build, never the installed application.')
out.mkdir(parents=True,exist_ok=True)
if any(out.iterdir()): raise SystemExit('Output must be empty')
original=root/'design/approved/Saytile-original-visual-reference-20261107.jpeg'; im=Image.open(original).convert('RGB')
assert im.size==(1536,1024)
# Reconstruct the obstructed gradient exclusively from unobstructed scene pixels either side of the panel.
# Reference card starts at (130,250), captured app card starts at (64,64), both at two pixels per pt.
crop=(66,186,882,782); W,H=816,596
im.crop(crop).save(out/'original.png'); blur=im.filter(ImageFilter.GaussianBlur(10))
bg=Image.new('RGB',(W,H)); pixels=bg.load()
for y in range(H):
    l=blur.getpixel((55,y+186)); r=blur.getpixel((856,y+186))
    for x in range(W):
        f=min(1,max(0,(x+66-55)/(856-55))); pixels[x,y]=tuple(round(left*(1-f)+right*f) for left,right in zip(l,r))
bg.save(out/'environment.png')
scenes=['first-use','first-denied','first-authorized','panel-paused','panel-standby','panel-speaking','settings','models','models-manual','models-recovery','input-compact-dark','storage','about','cloud','byok','archive-empty','archive','archive-detail','archive-detail-compact-dark']
if a.scenes:
    assert set(a.scenes)<=set(scenes); scenes=[n for n in scenes if n in a.scenes]
info=plistlib.loads((app/'Contents/Info.plist').read_bytes()); assert info['CFBundleIdentifier']=='app.saytile.mac'
receipt={'source':info['SaytileSourceRevision'],'source_dirty':info['SaytileSourceDirty'],'binary_sha256':hashlib.sha256((app/'Contents/MacOS/Saytile').read_bytes()).hexdigest(),'reference_sha256':hashlib.sha256(original.read_bytes()).hexdigest(),'scope':'Two named windows of same isolated process; controlled environment sampled from exterior of original; capture/permission states injected, not a physical microphone or an OS permission change.','scenes':{}}
with tempfile.TemporaryDirectory(prefix='saytile-product-capture-') as td:
    t=Path(td); helper=t/'capture'
    subprocess.run(['swiftc','-parse-as-library','-swift-version','6',str(root/'tests/fixtures/ProductWindowCapture.swift'),'-o',str(helper)],check=True)
    with (out/'run.log').open('a') as logs:
        proc=subprocess.Popen([str(app/'Contents/MacOS/Saytile'),'--data-directory',str(t/'empty'),'--ui-review',str(out)],stdout=logs,stderr=subprocess.STDOUT,env=dict(os.environ,SAYTILE_PRODUCT_WINDOWS='1',SAYTILE_PRODUCT_WINDOW_SUBSET=','.join(scenes)))
        try:
            for name in scenes:
                end=time.monotonic()+22; req={}
                while time.monotonic()<end and proc.poll() is None:
                    f=out/'request.json'
                    if f.exists():
                        req=json.loads(f.read_text())
                        if req['scene']==name: break
                    time.sleep(.05)
                if req.get('scene')!=name or req['pid']!=proc.pid: raise RuntimeError('Native scene did not arrive: '+name+' exit='+str(proc.poll()))
                png=out/(name+'.png')
                result=subprocess.run([str(helper),str(proc.pid),str(app),str(req['window']),str(req['backdrop']),str(png),name],capture_output=True,text=True,timeout=12)
                logs.write(result.stdout+result.stderr); logs.flush()
                (out/(name+'.done')).write_text('captured' if result.returncode==0 else 'failed')
                if result.returncode: raise RuntimeError('WindowServer '+name+': '+result.stdout+result.stderr)
                with Image.open(png) as shot:
                    assert tuple(shot.size)==tuple(round(x*2) for x in req['points'])
                    assert min(ImageStat.Stat(shot.convert('RGB')).stddev)>4,'empty or uniform window'
                receipt['scenes'][name]={'points':req['points'],'display_scale':req['scale'],'sha256':hashlib.sha256(png.read_bytes()).hexdigest()}
            if proc.wait(timeout=12)!=0: raise RuntimeError('Review app reported failure')
            receipt['status']='PARTIAL_PASS' if a.scenes else 'PASS'
        finally:
            if proc.poll() is None: proc.terminate(); proc.wait(timeout=12)
            receipt.setdefault('status','INCOMPLETE'); (out/'receipt.json').write_text(json.dumps(receipt,ensure_ascii=False,indent=2)+'\n')
if receipt['status']=='PASS':
    pair=Image.new('RGB',(W*2,H)); pair.paste(im.crop(crop)); pair.paste(Image.open(out/'panel-speaking.png').convert('RGB'),(W,0)); pair.save(out/'reference-and-native.png')
    print('PASS real composited native windows:',len(receipt['scenes']))
