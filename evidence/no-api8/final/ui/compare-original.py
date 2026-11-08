#!/usr/bin/env python3
"""Compare the committed Saytile JPEG with the approved-size native speech capture, without resampling. macOS; uses ImageIO/ColorSync and Python's standard library."""
import argparse
import hashlib
import json
import statistics
import struct
import subprocess
import tempfile
import zlib
from pathlib import Path

JPEG_COMMIT = "870e1f64c4adc26209931bcc8e83562421b5c46f"
JPEG_NAME = "design/approved/Saytile-original-visual-reference-20261107.jpeg"
JPEG_SHA256 = "58be88a019cf0241b1c540f799d0944ed294e650b8c119923a434a6e4889a7c5"
SIZE = (688, 468)
# Card-relative pixel centers, frozen before comparison. Each patch is 7x7.
PATCHES = {
    "surface_upper_left": (110, 17), "surface_upper_right": (598, 17),
    "surface_lower_left": (90, 306), "surface_lower_middle": (344, 306), "surface_lower_right": (600, 306),
    "copy_fill_top_left": (60, 380), "copy_fill_bottom_right": (110, 420),
    "voice_fill_top_left": (507, 379), "voice_fill_bottom_right": (627, 417),
    "copy_shadow_below": (82, 440), "voice_shadow_below": (566, 440),
}
DECODER = r"""
import Foundation
import CoreGraphics
import ImageIO
import CryptoKit

let data = FileHandle.standardInput.readDataToEndOfFile()
guard let source = CGImageSourceCreateWithData(data as CFData, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
      let srgb = CGColorSpace(name: CGColorSpace.sRGB) else { exit(2) }
let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString:Any] ?? [:]
let orientation = properties[kCGImagePropertyOrientation] as? Int ?? 1
guard orientation == 1 else { exit(3) }  // Coordinates here assume the verified source orientation.
let w = image.width, h = image.height
var bytes = Data(count:w*h*4)
let ok = bytes.withUnsafeMutableBytes { dst -> Bool in
    guard let ctx = CGContext(data:dst.baseAddress,width:w,height:h,bitsPerComponent:8,bytesPerRow:w*4,space:srgb,
        bitmapInfo:CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
    ctx.interpolationQuality = .none
    ctx.setRenderingIntent(.relativeColorimetric)
    ctx.setBlendMode(.copy)
    ctx.draw(image,in:CGRect(x:0,y:0,width:w,height:h))
    return true
}
guard ok else { exit(4) }
let name = (properties[kCGImagePropertyProfileName] as? String) ?? ""
let profile = name.lowercased().contains("srgb") ? "embedded sRGB" : (name.isEmpty ? "not declared by ImageIO" : "embedded non-sRGB profile")
let iccDigest = (image.colorSpace?.copyICCData() as Data?).map { SHA256.hash(data:$0).map { String(format:"%02x",$0) }.joined() }
let header:[String:Any]=["width":w,"height":h,"orientation":orientation,"source_space":(image.colorSpace?.name as String?) ?? "unnamed",
    "source_profile":profile, "source_icc_sha256":iccDigest ?? "",
    "target_space":"sRGB","rendering_intent":"relativeColorimetric","layout":"RGBA8 associated alpha, first decoded row at top"]
let out = FileHandle.standardOutput
out.write(try JSONSerialization.data(withJSONObject:header,options:[.sortedKeys]))
out.write(Data([10]))
out.write(bytes)
"""

def sha(data):
    return hashlib.sha256(data).hexdigest()

def decode(decoder, data):
    res = subprocess.run([decoder],input=data,stdout=subprocess.PIPE,check=True)
    header, rgba = res.stdout.split(b"\n", 1)
    info = json.loads(header)
    if len(rgba) != info["width"]*info["height"]*4:
        raise ValueError("unexpected converted image size")
    return info, rgba

class Card:
    def __init__(self, info, rgba, offset):
        self.info = info
        self.offset = offset
        self.raw = rgba
    def pixel(self, x, y):
        i = 4*((self.offset[1]+y)*self.info["width"] + self.offset[0]+x)
        r,g,b,a = self.raw[i:i+4]
        if 0<a<255:
            return tuple(min(255,round(c*255/a)) for c in (r,g,b))+(a,)
        return r,g,b,a

def linear(v):
    t=v/255
    return t/12.92 if t<=.04045 else ((t+.055)/1.055)**2.4

def luminance(rgb):
    return sum(weight*linear(value) for weight,value in zip((.2126,.7152,.0722),rgb[:3]))

def patch(card, x, y):
    vals = [card.pixel(dx,dy) for dy in range(y-3,y+4) for dx in range(x-3,x+4)]
    return {"rgb":[statistics.median(p[k] for p in vals) for k in range(3)],
            "Y":round(statistics.median(luminance(p) for p in vals),6),
            "minimum_alpha":min(p[3] for p in vals)}

def components(coords, min_pixels=3):
    pts=set(coords);result=[]
    while pts:
        start=pts.pop(); q=[start];group={start}
        while q:
            x,y=q.pop()
            for other in ((x-1,y),(x+1,y),(x,y-1),(x,y+1)):
                if other in pts:
                    pts.remove(other);group.add(other);q.append(other)
        if len(group)>=min_pixels:
            xs,ys=zip(*group)
            result.append({"bounds":[min(xs),min(ys),max(xs)+1,max(ys)+1],"pixels":len(group)})
    return sorted(result,key=lambda g:g["bounds"])

def geometric_features(card):
    def violet(px):
        r,g,b,a=px
        return a>=230 and b>160 and b-r>55 and b-g>75
    def gray(px):
        r,g,b,a=px
        return a>=230 and max(r,g)<165 and b<178 and max(r,g,b)-min(r,g,b)<60
    def points(test,box):
        x0,y0,x1,y1=box
        return [(x,y)for y in range(y0,y1)for x in range(x0,x1)if test(card.pixel(x,y))]
    lines=[]
    for y in range(18,294):
        xs=[x for x in range(20,666)if max(card.pixel(x,y)[:3])<115]
        if len(xs)<3: continue
        if not lines or lines[-1][3]!=y:lines.append([min(xs),y,max(xs)+1,y+1])
        else:
            b=lines[-1];b[0]=min(min(xs),b[0]);b[2]=max(max(xs)+1,b[2]);b[3]=y+1
    return dict(dark_text_line_boxes=lines,
                gray_copy_components=components(points(gray,(56,375,110,423))),
                voice_violet_components=components(points(violet,(506,372,630,427))),
                trailing_caret_components=components(points(violet,(190,228,281,290))))
def protected_interior(x,y):
    # Inset only for area error; the wallpaper outside rounded corners is not a like-for-like sample.
    if not (6<=x<SIZE[0]-6 and 6<=y<SIZE[1]-6):return False
    cx=min(max(x,56),SIZE[0]-57);cy=min(max(y,56),SIZE[1]-57)
    return (x-cx)**2+(y-cy)**2<50**2

def overall(ref, actual):
    absrgb=[0,0,0]; absY=0.;n=0
    lut=[linear(i)for i in range(256)]
    for y in range(SIZE[1]):
        for x in range(SIZE[0]):
            if not protected_interior(x,y):continue
            a=ref.pixel(x,y);b=actual.pixel(x,y)
            if min(a[3],b[3])<253:continue
            for k in range(3):absrgb[k]+=abs(a[k]-b[k])
            absY+=abs(sum(w*(lut[b[k]]-lut[a[k]])for k,w in enumerate((.2126,.7152,.0722))))
            n+=1
    return {"pixels":n,"mean_abs_channel_error_sRGB8":[round(s/n,4) for s in absrgb],"mean_abs_relative_Y_error":round(absY/n,6),
        "scope":"Descriptive only. Includes typesetting, JPEG artifacts and edge anti-aliasing; not an acceptance threshold."}

def write_sheet(path,ref,actual):
    # Left = registered JPEG crop, right = actual window crop. Composite transparent edges on a neutral background.
    w,h=SIZE;gap=16;data=bytearray()
    def rgb(px):
        a=px[3]/255
        return bytes(round(c*a+237*(1-a))for c in px[:3])
    for y in range(h):
        data.append(0)
        for card in (ref,actual):
            if card is actual:data.extend(bytes((237,237,237))*gap)
            for x in range(w): data.extend(rgb(card.pixel(x,y)))
    def chunk(tag,value):
        return struct.pack("!I",len(value))+tag+value+struct.pack("!I",zlib.crc32(tag+value))
    path.write_bytes(b"\x89PNG\r\n\x1a\n"+chunk(b"IHDR",struct.pack("!2I5B",2*w+gap,h,8,2,0,0,0))+chunk(b"sRGB",bytes([1]))+chunk(b"IDAT",zlib.compress(data,9))+chunk(b"IEND",b""))

def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--repo",default=".",type=Path,help="Saytile git checkout with verified original blob")
    ap.add_argument("--screenshots",type=Path,required=True,help="Native controls-mode UI output directory containing run.log, manifest.json, approved-reference")
    ap.add_argument("--output",type=Path,required=True,help="New comparison JSON path")
    ap.add_argument("--contact-sheet",type=Path,help="Optional new 1:1 sRGB card-pair PNG; original crop on left")
    args=ap.parse_args()
    if args.output.exists() or args.contact_sheet and args.contact_sheet.exists():ap.error("choose new output files; existing receipts are preserved")
    jpeg=subprocess.check_output(["git","-C",str(args.repo),"cat-file","blob",f"{JPEG_COMMIT}:{JPEG_NAME}"])
    if sha(jpeg)!=JPEG_SHA256:ap.error("original JPEG digest differs from user-authorized source")
    path=args.screenshots/"approved-reference/reference-recognizing.png"
    packed=path.read_bytes()
    manifest=json.loads((args.screenshots/"manifest.json").read_text())
    if manifest.get("source_dirty") or not manifest.get("passed"):ap.error("the native capture lacks a clean passing run identity")
    identity_path=args.screenshots.parent/"package-identity.json"
    identity=json.loads(identity_path.read_text())
    if (identity.get("source_revision")!=manifest["source_revision"] or identity.get("source_dirty") or
        identity.get("binary_sha256")!=manifest["binary_sha256"]):
        ap.error("UI and formal package identity disagree")
    log_path=args.screenshots/"run.log"
    if "REFERENCE_GEOMETRY state=recognizing window=408x298 card=344x234" not in log_path.read_text():
        ap.error("selected run does not contain the measured recognizing reference window")
    with tempfile.TemporaryDirectory(prefix="saytile-color-managed-")as td:
        swift=Path(td)/"Colors.swift";exe=Path(td)/"decode"
        swift.write_text(DECODER)
        subprocess.run(["swiftc",swift,"-o",exe],check=True)
        ri,rb=decode(exe,jpeg);pi,pb=decode(exe,packed)
    if (ri["width"],ri["height"],pi["width"],pi["height"])!=(1536,1024,816,596):ap.error("source or native reference image dimensions changed")
    ref=Card(ri,rb,(130,250));actual=Card(pi,pb,(64,64))
    samples={}
    for name,(x,y) in PATCHES.items():
        r=patch(ref,x,y);a=patch(actual,x,y)
        samples[name]={"center_px":[x,y],"reference":r,"actual":a,"signed_rgb_delta":[a["rgb"][k]-r["rgb"][k]for k in range(3)],"signed_Y_delta":round(a["Y"]-r["Y"],6)}
    geometry={"reference":geometric_features(ref),"actual":geometric_features(actual)}
    result={"source_revision":manifest["source_revision"],"binary_sha256":manifest["binary_sha256"],
            "package_tree":identity["tree"],"package_identity_sha256":sha(identity_path.read_bytes()),"capture_run_log_sha256":sha(log_path.read_bytes()),
            "original_commit":JPEG_COMMIT,"original_path":JPEG_NAME,"original_sha256":JPEG_SHA256,
            "native_capture":str(path),"native_capture_sha256":sha(packed),"capture_manifest_sha256":sha((args.screenshots/"manifest.json").read_bytes()),
            "original_decode":ri,"capture_decode":pi,"reference_rect_px":[130,250,688,468],"capture_rect_px":[64,64,688,468],
            "sampling":"Apple ImageIO decode then Core Graphics conversion to sRGB8, relative colorimetric. Top-left unscaled coordinates. Fixed 7x7 patch medians. Relative luminance Y uses linear sRGB D65 (0.2126, 0.7152, 0.0722), unit range. Signed differences are candidate minus reference.",
            "pixel_features":"Thresholds approximate bounds of dark text, gray squares and saturated violet ink; no OCR or font identity inference from a threshold.",
            "patches":samples,"geometry":geometry,"opaque_interior":overall(ref,actual),
            "limits":"Reference is a JPEG concept image and native PNG is a composited synthetic speaking-state view on one Mac. Pipeline color conversion, JPEG artifacts, text rasterization and instantaneous bar amplitudes affect differences. Static images do not establish motion, wallpaper blur, hearing accuracy or user visual approval."}
    if args.contact_sheet:
        write_sheet(args.contact_sheet,ref,actual)
        result["contact_sheet"]={"file":str(args.contact_sheet),"sha256":sha(args.contact_sheet.read_bytes()),"layout":"original crop left; 16px neutral gutter; native crop right; no resampling"}
    args.output.write_text(json.dumps(result,ensure_ascii=False,indent=2,sort_keys=True)+"\n")
    print("compared",manifest["source_revision"],"original",JPEG_SHA256,"capture",sha(packed),"text lines",len(geometry["reference"]["dark_text_line_boxes"]),len(geometry["actual"]["dark_text_line_boxes"]))
if __name__=="__main__":main()
