import hashlib,json,subprocess,datetime,sys
from pathlib import Path
root=Path('/Users/hhf/.codex/worktrees/saytile-release-candidate'); names=subprocess.check_output(['git','ls-files','Sources','tests','scripts','packaging','Package.swift','Package.resolved'],cwd=root,text=True).splitlines()
files={n:hashlib.sha256((root/n).read_bytes()).hexdigest() for n in names if (root/n).is_file()}
result={'head':subprocess.check_output(['git','rev-parse','HEAD'],cwd=root,text=True).strip(),'tree':subprocess.check_output(['git','rev-parse','HEAD^{tree}'],cwd=root,text=True).strip(),'dirty_tracked_inputs':bool(subprocess.check_output(['git','diff','--name-only','HEAD','--','Sources','tests','scripts','packaging','Package.swift','Package.resolved'],cwd=root,text=True).strip()),'input_digest':hashlib.sha256(json.dumps(files,sort_keys=True,separators=(',',':')).encode()).hexdigest(),'files':files,'utc':datetime.datetime.now(datetime.timezone.utc).isoformat()}
Path(sys.argv[1]).write_text(json.dumps(result,indent=2)+'\n')
print(result['head'],len(files),result['input_digest'],result['dirty_tracked_inputs'])
