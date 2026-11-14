#!/usr/bin/env python3
"""Observe actual AppKit runs of a particular candidate on the paired licensed audio."""
import argparse, hashlib, json, pathlib, shutil, subprocess, tempfile
p=argparse.ArgumentParser()
for name in ["app","weights","audio","out","paired"]:p.add_argument("--"+name,type=pathlib.Path,required=True)
p.add_argument("--models",nargs="+",default=["apple","sherpa","nemotron-metal","qwen-small"])
p.add_argument("--limit",type=int,default=10)
p.add_argument("--automatic", action="store_true", help="Leave engine selection to Saytile and verify the expected model")
a=p.parse_args()
samples=json.loads(a.paired.read_text())["samples"][:a.limit]
a.out.mkdir(exist_ok=True,parents=True)
for model in a.models:
    run_name = ("auto-" if a.automatic else "") + model
    with tempfile.TemporaryDirectory(prefix="saytile-local-panels-") as tmp:
        for index,item in enumerate(samples):
            root=pathlib.Path(tmp)/str(index);root.mkdir()
            if model!="apple":
                (root/"LocalModels").mkdir()
                # APFS clone only our approved, hash-pinned model directory.
                subprocess.run(["cp","-cR",str(a.weights/model),str(root/"LocalModels")+"/"],check=True)
            src=a.audio/(item["id"]+".wav")
            assert hashlib.sha256(src.read_bytes()).hexdigest()==item["audio_sha256"]
            shutil.copyfile(src,root/"fixture.wav")
            r=subprocess.run([str(a.app/"Contents/MacOS/Saytile"),"--data-directory",str(root),"--local-stream-probe","auto" if a.automatic else model],
                             capture_output=True,text=True,timeout=130)
            receipt=root/"visible.json"
            if not receipt.exists(): raise RuntimeError(model+":"+item["id"]+" "+r.stdout[-350:])
            result=json.loads(receipt.read_text())
            result.update(id=item["id"],audio_sha256=item["audio_sha256"],exit_code=r.returncode)
            if a.automatic:
                provider = "apple-speech-analyzer" if model == "apple" else model
                valid = (r.returncode == 0 and result.get("automatic") is True and result["model"] == model
                         and result["providers"] == [provider] and result["recordStates"]
                         and all(state == "completed" for state in result["recordStates"]))
            (a.out/(run_name+"-"+item["id"]+".json")).write_text(json.dumps(result,ensure_ascii=False,indent=2)+"\n")
            if index == min(5, len(samples)-1) and (root/"partial.png").exists():
                shutil.copyfile(root/"partial.png", a.out/(run_name+"-mid-speech.png"))
            if a.automatic and not valid:
                raise RuntimeError(f"Automatic routing did not recognize the complete clip with {model}; see {a.out}")
            shutil.rmtree(root)

