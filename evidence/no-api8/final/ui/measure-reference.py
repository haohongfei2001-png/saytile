"""Measure the owned, packaged reference captures. No screen or original image access."""
from collections import Counter
from pathlib import Path
import hashlib,json,statistics,struct,zlib

base=Path('evidence/no-api8/final')
identity=json.loads((base/'package-identity.json').read_text())
sha_file=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
def png(path):
    data=path.read_bytes(); start=8; image=[]
    assert data[:8]==b'\x89PNG\r\n\x1a\n'
    while start<len(data):
        count=int.from_bytes(data[start:start+4],'big')
        typ=data[start+4:start+8]; payload=data[start+8:start+8+count]
        if typ==b'IHDR':
            width,height,depth,color,compression,filtering,interlace=struct.unpack('!2I5B',payload)
            assert (depth,color,compression,filtering,interlace)==(8,6,0,0,0)
        if typ==b'IDAT':image.append(payload)
        start+=count+12
    raw=zlib.decompress(b''.join(image));stride=4*width; rows=[]
    for y in range(height):
        begin=(stride+1)*y; f=raw[begin]
        row=bytearray(raw[begin+1:begin+1+stride]);last=rows[-1] if rows else bytes(stride)
        for x in range(stride):
            a=row[x-4] if x>=4 else 0;b=last[x];c=last[x-4] if x>=4 else 0
            if f==0:p=0
            elif f==1:p=a
            elif f==2:p=b
            elif f==3:p=(a+b)//2
            else:
                assert f==4
                estimate=a+b-c
                ds=[abs(estimate-d) for d in (a,b,c)];p=(a,b,c)[ds.index(min(ds))]
            row[x]=(row[x]+p)&255
        rows.append(row)
    return rows
def pixel(rows,x,y):return list(rows[y][x*4:x*4+4])
def groups(points):
    remaining=set(points); groups=[]
    while remaining:
        seed=remaining.pop();stack=[seed];component={seed}
        while stack:
            x,y=stack.pop()
            for nxt in ((x-1,y),(x+1,y),(x,y-1),(x,y+1)):
                if nxt in remaining:remaining.remove(nxt);component.add(nxt);stack.append(nxt)
        if len(component)>=3:
            xs,ys=zip(*component);groups.append({'pixels':len(component),'bounds':[min(xs),min(ys),max(xs)+1,max(ys)+1]})
    return sorted(groups,key=lambda g:g['bounds'])
def violet(p):
    r,g,b,a=p
    return b>170 and b-r>65 and b-g>82 and a>=192
def bounds(a):return [min(x for x,y in a),min(y for x,y in a),max(x for x,y in a)+1,max(y for x,y in a)+1] if a else None
def dark(p):
    r,g,b,a=p;return max(r,g,b)<112 and a>220
def text_bands(rows):
    result=[]
    for y in range(78,395):
        coords=[x for x in range(84,735) if dark(pixel(rows,x,y))]
        if not coords:continue
        if not result or result[-1]['end_y']!=y:
            result.append(dict(start_y=y,end_y=y+1,min_x=min(coords),max_x=max(coords)))
        else:
            band=result[-1];band.update(end_y=y+1,min_x=min(band['min_x'],min(coords)),max_x=max(band['max_x'],max(coords)))
    return result
def inspect(mode):
    path=base/mode; log=(path/'run.log').read_text().splitlines()
    frames=[json.loads(s.removeprefix('UI_IMAGE_GEOMETRY '))for s in log if s.startswith('UI_IMAGE_GEOMETRY ') and 'reference-' in s]
    ax=[json.loads(s.removeprefix('NATIVE_UI_PANEL_INSPECT '))for s in log if s.startswith('NATIVE_UI_PANEL_INSPECT ')]
    ax_sizes=[]
    for snap in ax:
        ax_sizes.append({c['identifier']:{'size':[c['width'],c['height']],'bottom_gap':snap['window_y']+snap['window_height']-c['y']-c['height']}for c in snap['controls']})
    folder=path/'approved-reference'; images={}
    for f in sorted(folder.glob('*.png')):
        info=next(s for s in frames if s['name']==f.stem); rows=png(f)
        assert (len(rows[0])//4,len(rows))==(info['width_pixels'],info['height_pixels'])
        assert [info['width_points'],info['height_points']]==[408,298] and [info['width_pixels'],info['height_pixels']]==[816,596]
        # Determine painted card extent on horizontal and vertical center rays,
        # separately from the translucent exterior shadow on this window.
        hspan=[x for x in range(816) if pixel(rows,x,280)[3]>=200]
        vspan=[y for y in range(596) if pixel(rows,408,y)[3]>=200]
        alpha_points=[{'x':408,'y':y,'rgba':pixel(rows,408,y)} for y in [0,16,32,48,62,64,72,524,530,534,540,548,556,565,578,595]]
        gray=[]
        for y in range(437,488):
            for x in range(120,174):
                r,g,b,a=pixel(rows,x,y)
                if a>=192 and max(r,g)<160 and b<178 and max(r,g,b)-min(r,g,b)<52:gray.append((x,y))
        gray_ink=Counter(tuple(pixel(rows,x,y))for x,y in gray)
        glyph={(x,y)for y in range(430,491)for x in range(590,676)if violet(pixel(rows,x,y))}
        caret={(x,y)for y in range(67,401)for x in range(84,731)if violet(pixel(rows,x,y))}
        images[f.name]={'capture':info,'sha256':sha_file(f),'painted_card_alpha200_center_scan_edges':[min(hspan),min(vspan),max(hspan)+1,max(vspan)+1],'vertical_center_shadow_rgba':alpha_points,'gray_copy_core_pixels':len(gray),'gray_copy_bounds':bounds(gray),'most_frequent_gray_rgba':gray_ink.most_common(1),'voice_violet_4connected':groups(glyph),'text_violet_4connected':groups(caret),'dark_text_ink_bands':text_bands(rows),'surface_rgba_at_x154_408_664_y389':[pixel(rows,x,389)for x in (154,408,664)],'corner_rgba':pixel(rows,0,0)}
    return {'ax_sizes':ax_sizes,'images':images}
result={'source_revision':identity['source_revision'],'source_tree':identity['tree'],'binary_sha256':identity['binary_sha256'],'project_measurements':json.loads(Path('design/approved/original-reference-20261107.measurements.json').read_text()),'reference_source':'Project rule 21 identifies supplied 1536x1024 JPEG SHA256 58be88a019cf0241b1c540f799d0944ed294e650b8c119923a434a6e4889a7c5. Only project-documented measurements are used here.','scope':'PNG coordinates and 4-neighbor components in owned synthetic captures. Colors are decoded file channel levels; not a wallpaper/wide-gamut measurement or an exact comparison to original pixels. Font measured separately in diagnostic.','controls':inspect('ui'),'render_only':inspect('ui-render-only')}
(base/'ui'/'reference-measurements.json').write_text(json.dumps(result,ensure_ascii=False,indent=2,sort_keys=True)+'\n')
for mode in ('controls','render_only'):
 print(mode,'AX',len(result[mode]['ax_sizes']),result[mode]['ax_sizes'][:1])
 for name,v in result[mode]['images'].items():
  print(name, v.get('gray_copy_bounds'),len(v.get('voice_violet_4connected',[])),v.get('text_violet_4connected',[]),len(v.get('dark_text_ink_bands',[])))
