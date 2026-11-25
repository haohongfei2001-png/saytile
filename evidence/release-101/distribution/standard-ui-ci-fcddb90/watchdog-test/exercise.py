from pathlib import Path
import importlib.util,json,subprocess,sys,time
root=Path(__file__).resolve().parents[5]
spec=importlib.util.spec_from_file_location("standard_ui",root/"scripts/test-update-standard-ui.py")
probe=importlib.util.module_from_spec(spec);spec.loader.exec_module(probe)
output=Path(__file__).resolve().parent
results=[]
for name,code,expected in [("normal_exit","print('owned success')",0),("failure_exit","import sys;sys.exit(7)",7),("timeout","import time;print('owned timeout fixture',flush=True);time.sleep(60)",-9)]:
    directory=output/name;directory.mkdir()
    result={}
    began=time.monotonic()
    error=None
    try: probe.run_native_probe([sys.executable,"-c",code],directory,result)
    except (subprocess.CalledProcessError,subprocess.TimeoutExpired) as exception: error=type(exception).__name__
    elapsed=time.monotonic()-began
    assert result["native_exit_code"]==expected
    if name=="timeout":
        assert error=="TimeoutExpired" and result["native_process_timed_out"] and 45<=elapsed<47
        assert (directory/"sample.log").exists()
    elif name=="failure_exit": assert error=="CalledProcessError"
    else: assert error is None
    result.update(case=name,status="PASS",observed_exception=error,elapsed_seconds=round(elapsed,3),ui_started=False)
    results.append(result)
(output/"receipt.json").write_text(json.dumps(results,indent=2)+"\n")
print(json.dumps(results))
