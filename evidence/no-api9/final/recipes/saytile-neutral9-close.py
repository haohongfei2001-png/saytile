"""Assemble the no-api.9 engineering manifest from local receipts, derived from the independently closed no-api.8 receipts.

Run from the no-api.9 worktree. Default verification is read-only. --write performs
the same verification and atomically installs the completed manifest. No test,
network request, installation or user-database access is performed here.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile

if not __debug__:
    raise SystemExit("Run without Python optimization. Integrity assertions must remain active.")

parser = argparse.ArgumentParser(description=__doc__)
mode = parser.add_mutually_exclusive_group()
mode.add_argument("--check-current", action="store_true", help="check available short receipts only, never close")
mode.add_argument("--write", action="store_true", help="write delivery-manifest.json after every receipt verifies")
args = parser.parse_args()
root = Path.cwd()
out = root / "evidence/no-api9/final"
sha = "dc26fe3c59ba55994d29e99ada8d2f0b49ad9886"
tree = "f138f6733a642a2e53da22b3647aaf5744cb308b"
version = "1.0.0-rc.2-no-api.9"
references = set()

def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()

def read(rel):
    references.add(rel)
    return json.loads((out / rel).read_bytes())

def verified_hashes(directory, mapping):
    assert mapping, f"Empty hash receipt at {directory}"
    for name, expected in mapping.items():
        assert digest(directory / name) == expected, f"File hash differs: {name}"

def git(*arguments):
    return subprocess.check_output(["git", *arguments], text=True).strip()

# This acknowledgement belongs to this exact production presentation. The prior
# no-op and the two disposable hypotheses remain separate explanatory records.
def compositor_evidence():
    base="../compositor/final/"
    source=read(base+"source-identity.json")
    execution=read(base+"execution.json")
    data=read(base+"measurements.json")
    summary=read(base+"summary.json")
    assert source["source_revision"]==source["library_source_revision"]==execution["source_revision"]==sha and source["source_tree"]==tree
    assert source["presentation_scope"]=="exact committed product source" and not source["working_style_selected"] and not source["disposable_material_opacity"]
    assert source["committed_style_sha256"]==digest(root/"Sources/SaytileApp/ReferencePanelStyle.swift")
    assert execution["exit"]==0 and not execution["owned_process_timeout"] and execution["probe_sha256_before"]==execution["probe_sha256_after"]
    assert source["runner_sha256"]==digest(out/base/"executed-runner.py") and source["diagnostic_sha256"]==digest(out/base/"OwnedGlassProbe.swift")
    assert data["status"]=="MEASURED" and data["window_count"]==data["filter"]["include_window_count"]==2
    assert data["filter"]["every_included_window_owner_matches_process"] and data["filter"]["crop_within_opaque_backdrop"]
    assert data["foreground_continuity"] and data["foreground_activation_notifications"]==0 and not data["probe_became_active"]
    assert not any(data[k] for k in ["whole_display_capture","system_permissions_requested","wallpaper_modified","window_pixel_files_written","audio_capture","microphone"])
    assert data["capture_state_stayed_paused"] and not data["reduce_transparency"]
    assert data["production_text"]=={"synthetic_string_intact":True,"editable":False,"selectable":True,"font_size_points":19.5}
    prod=summary["production"];delta=prod["interior_warm_minus_cool_srgb8"]
    assert prod["cool_mean_stable_on_return"] and delta[0]>0 and delta[1]<0 and delta[2]<0
    assert 0 < prod["interior_stripe_contrast_cool"] < prod["exposed_stripe_contrast_cool"]
    assert summary["clear"]["interior_warm_minus_cool_srgb8"]==summary["clear"]["exposed_warm_minus_cool_srgb8"]
    observed=[m for m in data["measurements"] if m["mode"]=="production"]
    assert [m["synthetic_backdrop"] for m in observed]==["cool","warm","cool"] and all(m["dark_neutral_ink_pixels"]>0 and m["sampled_surface_to_ink_contrast"]>1 for m in observed)
    references.update([base+"OwnedGlassProbe.swift",base+"executed-runner.py","../compositor/README.md"])
    return {"scope":"Two process-owned windows, filtered ScreenCaptureKit crop and synthetic backdrops. Isolated full production view compiled at the release revision. Pixel samples establish color transmission and stripe attenuation in this controlled composition; arbitrary wallpaper appearance or physical blur is unmeasured.",
            "source_revision":source["source_revision"],"source_tree":source["source_tree"],"material_alpha":0.35,"white_wash_alpha":0.46,
            "warm_minus_cool_srgb8":delta,"interior_stripe_contrast":prod["interior_stripe_contrast_cool"],"exposed_stripe_contrast":prod["exposed_stripe_contrast_cool"],
            "sampled_text_contrast_cool_warm_return":[m["sampled_surface_to_ink_contrast"] for m in observed],"foreground_activation_notifications":0,"saved_window_frames":0}

assert git("rev-parse", sha + "^{tree}") == tree
before = read("source-before.json")
assert before["head"] == sha and before["tree"] == tree and not before["runtime_diff"]
# Additional docs or evidence commits may already have landed. Compare actual inputs.
verified_hashes(root, before["source_sha256"])
pack = read("package-identity.json")
assert pack["source_revision"] == sha and pack["tree"] == tree and pack["source_dirty"] is False
assert pack["version"] == version and pack["installed_rc1_replaced"] is False and pack["cloud_calls"] == 0
binary = pack["binary_sha256"]
dmg = pack["dmg_sha256"]
paths = read("delivery-paths.json")
assert (paths["source_revision"], paths["runtime_tree"], paths["binary_sha256"], paths["dmg_sha256"]) == (sha, tree, binary, dmg)
assert paths["rc1_replaced"] is False and paths["dmg_bytes"] == pack["dmg_bytes"]
assert paths["github_path"] == "deliverables/no-api.9/Saytile-1.0.0-rc.2-no-api.9-arm64.dmg"
for file in (Path(pack["dmg_path"]), root / paths["github_path"], Path(paths["canonical_dmg"])):
    assert file.stat().st_size == pack["dmg_bytes"] and digest(file) == dmg, f"DMG differs: {file.name}"
assert digest(Path(pack["app_path"]) / "Contents/MacOS/Saytile") == binary
links = read("package-check-linkage.json")
assert (links["source_revision"], links["executable_sha256"], links["dmg_sha256"]) == (sha, binary, dmg)
assert {"apple/signed-app.json","install-upgrade.json","uninstall-reinstall.json","cloud-probe-cli.json",
        "connection-setup-cli.json","app-idle.json","ui/manifest.json","ui-render-only/manifest.json",
        "startup-focus.log","startup-focus-identities.txt"} <= links["checks"].keys()
verified_hashes(out, links["checks"])
references.update(links["checks"])

policy = read("gatekeeper.json")
assert policy["source_revision"] == sha and policy["binary_sha256"] == binary and policy["dmg_sha256"] == dmg
assert policy["system_assessment"]["stdout"] == "assessments enabled" and policy["code_integrity"]["exit"] == 0
assert policy["executable_assessment"]["exit"] == 3 and policy["executable_assessment"]["stderr"].endswith("rejected")

native = read("protocol/run-after.json")
native_before = read("protocol/run-before.json")
assert (native["result"], native["head"], native["tree"], native["head_unchanged"], native["tree_unchanged"]) == ("PASS",sha,tree,True,True)
assert native["source_sha256"] == native_before["source_sha256"] and not native["source_changes_during_run"]
assert all(before["source_sha256"].get(p) == h for p,h in native["source_sha256"].items())
assert (native["native_test_functions"],native["native_suites"],native["native_effective_scenarios"],native["protocol_test_functions"],native["protocol_scenarios"],native["network_cases"]) == (393,48,513,12,52,50)
assert not native["skip_or_not_run_lines"] and not native["protocol_violations"]
verified_hashes(out / "protocol", native["artifacts_sha256"])
wire = read("protocol/wire-audit.json")
assert wire["scope"] == "SIMULATED_PROTOCOL_NOT_LIVE_CLOUD" and len(wire["cases"]) == 50 and not any(v["violations"] for v in wire["cases"].values())

ci = read("protocol/ci-snapshot.json")
merge = read("protocol/ci-merge-identity.json")
assert ci["head"] == sha and ci["tree"] == tree and ci["checkout_merge_sha"] == merge["sha"]
assert ci["same_tree"] and ci["checkout_tree"] == merge["tree"] == tree and merge["parents"][-1] == sha
conclusions = {r["name"]:r["conclusion"] for r in ci["runs"]}
assert conclusions["Saytile design contracts"] == "success" and conclusions["Saytile native"] in ("success","cancelled")
assert (ci["native_functions"],ci["native_expanded_scenarios"],ci["native_test_skip_or_not_run_lines"]) == (393,513,[])
assert any(l.startswith("WIRE_AUDIT cases=50 protocol_violations=0") for l in ci["summary_lines"])
verified_hashes(out/"protocol",ci["artifacts_sha256"])
steps = {s["name"]:s["conclusion"] for j in ci["jobs"] if j["name"]=="native" for s in j["steps"]}
assert steps["Real localhost provider protocols (no API keys)"] == "success"
if conclusions["Saytile native"] == "success":
    assert steps["Run scripts/test-app-model.sh"] == steps["Native windows with synthetic data"] == "success"
    assert ci["ui_captures"] >= 27 and ci["ci_ui_controls"] == "NOT_RUN_RENDER_ONLY" and not ci["failure_lines"]
assert ci["ax_press"] == 0
ui = read("ui/manifest.json")
render = read("ui-render-only/manifest.json")
assert all(m["passed"] and m["source_revision"] == sha and m["binary_sha256"] == binary and not m["source_dirty"] for m in (ui,render))
assert (len(ui["images"]),ui["native_ax_press"],ui["native_menu_select"],ui["control_groups"],ui["outside_foreground_observations"],len(render["images"]),render["native_ax_press"]) == (37,45,10,15,0,27,0)
ui_run = read("ui/execution-receipt.json")
glyph = read("ui/voice-glyph-audit.json")
assert all(r["source_revision"] == sha and r["source_tree"] == tree and r["tracked_inputs_unchanged"] for r in (ui_run,glyph))
assert (ui_run["binary_sha256"],ui_run["dmg_sha256"]) == (binary,dmg)
for folder, prefix in [("ui","controls"),("ui-render-only","render_only")]:
    motion = read(folder + "/voice-glyph-motion/manifest.json")
    assert len(motion["frames"]) == len(glyph[prefix+"_png_sha256"]) == 71
    verified_hashes(out / folder / "voice-glyph-motion", glyph[prefix+"_png_sha256"])
    verified_hashes(out / folder, ui_run[prefix+"_png_sha256"])
    assert digest(out/folder/"manifest.json")==ui_run[prefix+"_manifest_sha256"]
    verified_hashes(out/folder/"approved-reference",ui_run[prefix+"_reference_png_sha256"])
assert ui_run["reference_images_per_mode"]==ui_run["reference_font_and_viewport_checks_per_mode"]==3
approval_path = root/"design/approved/original-reference-20261107.measurements.json"
approval = json.loads(approval_path.read_bytes())
assert approval["source_sha256"] == "58be88a019cf0241b1c540f799d0944ed294e650b8c119923a434a6e4889a7c5"
assert approval["source_image_pixels"]==[1536,1024] and approval["main_card_points"]==[344,234] and approval["native_window_points"]==[408,298]
assert approval["copy_points"]==[42,33.5] and approval["voice_points"]==[92.5,33.5] and approval["footer_bottom_points"]==18
assert approval["transparent_shadow_perimeter_points"]==32 and approval["body_font_points"]==19.5 and approval["line_height_points"]==26
evidence_ref = read("reference-source.json")
approved_jpeg = root/"design/approved/Saytile-original-visual-reference-20261107.jpeg"
assert evidence_ref["source_revision"]==sha and approved_jpeg.is_file()
assert digest(approved_jpeg)==approval["source_sha256"] and approval["source_image_pixels"]==[1536,1024]
jpeg_rel = str(approved_jpeg.relative_to(root))
assert evidence_ref["authority_commit"]==sha and evidence_ref["original_source_path"]==jpeg_rel and evidence_ref["verified_original_sha256"]==approval["source_sha256"]
assert evidence_ref["upstream_original"]==approval and evidence_ref["measurements_file_sha256"]==digest(approval_path)
assert git("rev-parse",sha+":"+jpeg_rel)==git("rev-parse","870e1f64c4adc26209931bcc8e83562421b5c46f:"+jpeg_rel)
assert git("hash-object",jpeg_rel)==git("rev-parse",sha+":"+jpeg_rel)
direct = read("ui/original-comparison.json")
assert direct["original_sha256"]==digest(approved_jpeg)
assert direct["material_fidelity_from_unmatched_RGB"].startswith("NOT_APPLICABLE")
assert direct["source_revision"]==sha and direct["package_tree"]==tree and direct["binary_sha256"]==binary
assert direct["original_commit"]=="870e1f64c4adc26209931bcc8e83562421b5c46f" and direct["original_path"]==jpeg_rel
assert direct["reference_rect_px"]==approval["main_card_source_xywh"] and direct["capture_rect_px"]==[64,64,688,468]
native_capture=out/"ui/approved-reference/reference-recognizing.png"
assert root/direct["native_capture"]==native_capture and direct["native_capture_sha256"]==digest(native_capture)
assert direct["package_identity_sha256"]==digest(out/"package-identity.json")
assert direct["capture_manifest_sha256"]==digest(out/"ui/manifest.json") and direct["capture_run_log_sha256"]==digest(out/"ui/run.log")
assert root/direct["contact_sheet"]["file"]==out/"ui/original-comparison-pair.png" and direct["contact_sheet"]["sha256"]==digest(out/"ui/original-comparison-pair.png")
# The comparison compares current capture bytes after transforming both images
# to the same color space. Its measured errors are retained, without assigning
# a perceptual acceptance threshold.
assert direct["patches"] and direct["geometry"] and direct["controlled_backdrop_evidence"]=="../../compositor/README.md"
references.update(["ui/compare-original.py","ui/original-comparison-pair.png"])
# The neutral .9 source changes the material goal. A previous tinted surface's
# calibration summary is not a current output. Use this exact build's direct
# licensed JPEG comparison and separate same-source compositor receipts.

assessment = read("ui/reference-measurements.json")
assert assessment["source_revision"]==sha and assessment["source_tree"]==tree and assessment["binary_sha256"]==binary
assert assessment["project_measurements"]==approval
controls = assessment["controls"]["ax_sizes"]
assert len(controls)==11
for sample in controls:
    for control,design_size in (("panel.copy",approval["copy_points"]),("panel.capture",approval["voice_points"])):
        measured_size = sample[control]["size"]
        assert measured_size==design_size and sample[control]["bottom_gap"]==approval["footer_bottom_points"], (control,measured_size,design_size)
states_ref=("paused","standby","recognizing")
reference_hashes={}
for folder,mode_name in [("ui","controls"),("ui-render-only","render_only")]:
    reference_dir=out/folder/"approved-reference"
    measured_images=assessment[mode_name]["images"]
    image_names={"reference-"+state+".png" for state in states_ref}
    assert set(measured_images)==image_names and {p.name for p in reference_dir.glob("*.png")} == image_names
    reference_hashes[folder]={}
    log=(out/folder/"run.log").read_text().splitlines()
    reference_lines=[line for line in log if line.startswith("REFERENCE_GEOMETRY ")]
    assert len(reference_lines)==3
    for state in states_ref:
        name="reference-"+state+".png"
        actual_hash = digest(reference_dir/name)
        assert actual_hash == measured_images[name]["sha256"]
        assert sum(line.startswith("REFERENCE_GEOMETRY state="+state+" window=408x298 card=344x234 font=19.5 viewport=") for line in reference_lines)==1
        cap=measured_images[name]["capture"]
        assert [cap["width_points"],cap["height_points"]]==approval["native_window_points"]
        assert [cap["width_pixels"],cap["height_pixels"]]==[816,596]
        assert measured_images[name]["alpha200_center_scan_bounds"]==[64,64,752,532]
        reference_hashes[folder][name]=actual_hash
        references.add(folder+"/approved-reference/"+name)
    references.add(folder+"/run.log")
references.update(["ui/REVIEW.md","ui/measure-reference.py","input/NATIVE-INPUT.md","INDEPENDENT-REVIEW.md"])
references.update(["ui/caret-reading/CaretReadingProbe.swift","ui/caret-reading/result.log","ui/caret-reading/receipt.json"])
caret=read("ui/caret-reading/receipt.json")
assert (caret["source_revision"],caret["source_tree"],caret["tracked_inputs_unchanged"])==(sha,tree,True)
assert (caret["passed_checks"],caret["activated"],caret["window_created"],caret["cloud_calls"])==(7,False,False,0)
assert caret["fixture_sha256"]==digest(out/"ui/caret-reading/CaretReadingProbe.swift") and caret["result_sha256"]==digest(out/"ui/caret-reading/result.log")
verified_hashes(root,caret["production_source_sha256"])
model = read("input/app-model-identity.json")
dom = read("input/browser-identity.json")
inp = read("input/native-receipt.json")
owned = read("owned-range/summary.json")
assert (model["head"],model["tree"],model["checks"],model["exit"],model["unchanged"]) == (sha,tree,104,0,True)
assert (dom["head"],dom["tree"],dom["checks"],dom["unchanged"]) == (sha,tree,20,True)
assert model["log_sha256"] == digest(out / "input/app-model.log") and dom["log_sha256"] == digest(out / "input/input-browser-dom.log")
assert inp["source_revision"] == owned["head"] == sha and inp["source_tree"] == tree and inp["tracked_inputs_unchanged"]
assert (inp["ordinary_native_checks"],inp["owned_range_scenarios"],inp["send_events"],inp["uncertain_replay"],inp["foreground_resolver"],inp["wk_dispatch"]) == (9,9,0,False,"NOT_RUN","unverified")
assert owned["status"] == "PASS" and len(owned["scenarios_passed"]) == 9 and not owned["source_changed_during_run"]

apple = read("apple/apple-summary.json")
rows = read("apple/apple-corpus.json")
fixture = read("apple/fixture-identity.json")
asset = read("apple/asset-preparation.json")
signed = read("apple/signed-app.json")
assert (apple["runtime"],apple["tree"],apple["cases"],apple["completed"],len(rows)) == (sha,tree,8,8,8)
assert all(row["recognitionState"]=="completed" and row["localProviders"]==["apple-speech-analyzer"] and row["dispatchableUTF16Length"]>0 for row in rows)
verified_hashes(out / "apple", apple["results_sha256"])
assert (signed["passed"],signed["runtime"],signed["binary_sha256"]) == (True,sha,binary)
assert fixture["runtime"] == sha and fixture["tree"] == tree and signed["fixture_sha256"] == fixture["generated_synthetic_audio"][signed["synthesized_fixture"]]
attempt = signed["attempts"][-1]
assert attempt["exit"]==0 and attempt["rows"] == [["completed","available",0]] and attempt["latest_text"] and attempt["saved_wavs"]
assert all(n > 44 and re.fullmatch("[0-9a-f]{64}", h) for n,h in attempt["saved_wavs"])
assert asset["after"]["installed"] and asset["preparationCalls"] <= 1

upgrade = read("install-upgrade.json")
reinstall = read("uninstall-reinstall.json")
assert all(r["status"]=="PASS" and r["source_revision"]==sha and r["binary_sha256"]==binary for r in (upgrade,reinstall))
assert (upgrade["dmg_sha256"],upgrade["release_version"],upgrade["count"],len(reinstall["checks"])) == (dmg,version,8,2)
before_preserve = read("preservation-before.json")
assert upgrade["baseline_app_source_revision"] == before_preserve["installed_source"] == "8906a9dc4b2ec186f634bb2c829d8eb0c1700679"
assert upgrade["baseline_binary_sha256"]==before_preserve["installed_binary_sha256"] and upgrade["previous_dmg_sha256"]==before_preserve["rc1_dmg_sha256"]
cloud_cli = read("cloud-probe-cli.json")
setup = read("connection-setup-cli.json")
assert len(cloud_cli["cases"])==17 and all(c["result"].startswith("PASS") for c in cloud_cli["cases"])
assert not (cloud_cli["cloud_calls"] or cloud_cli["microphone_started"] or cloud_cli["private_database_accessed"])
assert (setup["passed"],setup["source_revision"],setup["binary_sha256"]) == (7,sha,binary)
assert not (setup["provider_requests"] or setup["window_opened"] or setup["credential_values_read"])
idle = read("app-idle.json")
assert (idle["source_revision"],idle["binary_sha256"],idle["release_version"],idle["isolated_preferences_confirmed"]) == (sha,binary,version,True)
assert idle["wall_seconds"] >= 300

quality = read("cloud-quality-boundary.json")
assert quality["scope"]=="NOT_MEASURED_WITH_LIVE_PROVIDERS" and quality["source_revision"]==sha
assert quality["real_provider_calls"]==quality["same_human_audio_samples_uploaded"]==0
assert all(quality[k] is None for k in ("best_single_model","absolute_accuracy_gain","relative_error_reduction","extra_confirmation_latency_seconds","winning_conditions"))
assert set(quality["stages"])=={"first_text","corrected_during_speech","dispatchable_stable","final_text"} and all(v is None for stage in quality["stages"].values() for v in stage.values())
short = read("../local/short-source-after.json")
storage = read("../local/storage-processes.json")
scale = read("../local/storage-scale/storage-scale.json")
assert (short["status"],short["source_revision"],short["tree"],short["source_changed"]) == ("PASS",sha,tree,[])
assert len(short["checks"])==8 and all(v is True for v in short["checks"].values())
assert (storage["status"],storage["passed"],storage["source_revision"],storage["source_dirty"]) == ("PASS",12,sha,False)
assert (scale["recordings"],scale["revisions"],scale["partial_writes"],scale["search_matches"]) == (100000,300000,200,100)
apple_live=read("local-vad-apple/summary.json")
apple_live_id=read("local-vad-apple/identity.json")
assert apple_live["source_revision"]==apple_live_id["source_revision"]==sha and apple_live["tree"]==apple_live_id["tree"]==tree
assert apple_live_id["source_unchanged"] and apple_live_id["library_hash_unchanged"] and apple_live_id["probe_hash_unchanged"] and apple_live_id["exit"]==0
assert apple_live["raw_report_sha256"]==digest(out/"local-vad-apple/raw-report.json") and apple_live_id["probe_source_sha256"]==digest(out/"local-vad-apple/LocalVADAppleProbe.swift")
assert all(v is True for v in apple_live["checks"].values()) and len(apple_live["checks"])==18 and len(apple_live["records"])==2
assert len(set(r["recording_id"] for r in apple_live["records"]))==2 and all(r["final_text"] and r["observed_while_open_texts"]>0 and r["last_error"] is None and all(c["frames"]>0 for c in r["chunks"]) for r in apple_live["records"])
references.update(["local-vad-apple/raw-report.json","local-vad-apple/README.md","local-vad-apple/run.py","local-vad-apple/run.log","local-vad-apple/LocalVADAppleProbe.swift","connection-contract.md"])
compositor=compositor_evidence()
pending = ["../local/realtime-assessment.json","../local/post-run-identities.json","source-after.json","preservation-after.json","public-download.json"]
missing = [f for f in pending if not (out / f).is_file()]
if args.check_current:
    print("Verified existing short receipts. No manifest written. Remaining receipt paths:", missing)
    raise SystemExit(0)
if missing:
    raise SystemExit("Open evidence. No manifest written. Missing " + ", ".join(missing))

after = read("source-after.json")
after_preserve = read("preservation-after.json")
assert (after["head"],after["tree"],after["runtime_diff"],after["changed_files"],after["source_sha256"]) == (sha,tree,[],[],before["source_sha256"])
assert all(before_preserve[k] == after_preserve[k] for k in ("installed_source","installed_binary_sha256","rc1_dmg_sha256"))
assert before_preserve["canonical_tracked_diff"] == after_preserve["canonical_tracked_diff"]
canonical = "/Users/hhf/Documents/GitHub/saytile"
canonical_changes = git("-C",canonical,"diff","--name-status",before_preserve["canonical_head"],after_preserve["canonical_head"]).splitlines()
assert all(row.split("\t")[-1].startswith(("docs/","design/")) for row in canonical_changes), "Inspect unexpected external canonical change before closing."
long = read("../local/realtime-assessment.json")
post = read("../local/post-run-identities.json")
assert long["source_revision"]==long["head_after"]==sha and long["status"] == "PASS" and len(long["checks"])==23 and all(v is True for v in long["checks"].values())
assert long["actual_wallclock_seconds"]>=1800 and long["different_sample_frames"]==0 and long["upload_grants"]==0
assert long["reference_frames"]==long["saved_frames"]==28800000 and long["reference_sha256"]==long["concatenated_saved_pcm_sha256"]
assert (post["status"],post["source_revision"],post["tree"],post["owned_probe_exited"],post["assessor_true_checks"]) == ("PASS",sha,tree,True,23)
assert post["probes"] and all(r["unchanged"] for r in post["probes"].values())
pub = read("public-download.json")
assert (pub["source_revision"],pub["bytes"],pub["downloaded_sha256"],pub["matches_mounted_tested_dmg"]) == (sha,pack["dmg_bytes"],dmg,True)
assert re.fullmatch("[0-9a-f]{40}",pub["publication_commit"]) and pub["retrieved_utc"]
assert pub["url"] == "https://raw.githubusercontent.com/haohongfei2001-png/saytile/" + pub["publication_commit"] + "/" + paths["github_path"]

publication_ci = None
if (out/"protocol/publication-ci.json").is_file():
    publication_ci = read("protocol/publication-ci.json")
    assert publication_ci["publication_commit"] == pub["publication_commit"] and publication_ci["source_revision"] == sha
    assert all(r["sha"] == pub["publication_commit"] for r in publication_ci["runs"])
if subprocess.run(["git","cat-file","-e",pub["publication_commit"]+"^{commit}"],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL).returncode == 0:
    published_blob = subprocess.check_output(["git","show",pub["publication_commit"]+":"+paths["github_path"]])
    assert hashlib.sha256(published_blob).hexdigest()==dmg and len(published_blob)==pack["dmg_bytes"]

states = {"NO_API_ENGINEERING_READY":True,"LIVE_CONNECTION_PENDING":True,"LIVE_PROTOCOL_VERIFIED":False,
          "LIVE_TRANSCRIPTION_VERIFIED":False,"QUALITY_VERIFIED":False,"PRODUCTION_READY":False}
manifest = {
    "states":states,"role":"Personal no-api.9 macOS engineering candidate with the approved reference geometry and neutral behind-window material. Live cloud acceptance pending.",
    "tested_source":sha,"runtime_tree":tree,"release_version":version,"binary_sha256":binary,
    "dmg_sha256":dmg,"dmg_bytes":pack["dmg_bytes"],"public_download":pub,"delivery_paths":paths,
    "source_inputs_before_and_after":len(before["source_sha256"]),"production_main_or_rc1_replaced":False,
    "canonical_commit_changes_during_verification":canonical_changes,"real_provider_calls":0,"private_audio_uploaded":False,
    "cloud_quality":quality,"assembler_sha256":digest(Path(__file__)),"owned_compositor":compositor,
    "native":{"functions":393,"suites":48,"expanded_scenarios":513,"protocol_functions":12,"protocol_scenarios":52,"wire_cases":50,"skipped":0,"appmodel_checks":104},
    "ci":{"exact_source":{"head":sha,"checkout":ci["checkout_merge_sha"],"checkout_tree":ci["checkout_tree"],"native":conclusions["Saytile native"],"design":conclusions["Saytile design contracts"],"swift_functions":ci["native_functions"],"wire_cases":50,"ui_captures":ci["ui_captures"],"ci_ax_controls":ci["ci_ui_controls"],"step_outcomes":steps},"publication_checkpoint_if_recorded":publication_ci},
    "ui":{"real_ax_press":45,"actual_menu_selections":10,"control_images":37,"render_only_images":27,"control_groups":15,"glyph_frames_per_mode":71,"outside_foreground_transitions":0,"scope":"Routine content-host images and control interactions retain their own coverage. Each additional three-image reference set uses the production InputPanelWindowView outer geometry. Synthetic captures do not certify every display, wallpaper, focus context or appearance."},
    "original_reference":{"reported_uploaded_jpeg_sha256":approval["source_sha256"],"measurements_path":"design/approved/original-reference-20261107.measurements.json","measurements_sha256":digest(approval_path),"repository_original_jpeg":jpeg_rel,"exact_original_jpeg_verified":True,"original_jpeg_bytes":approved_jpeg.stat().st_size,"native_card_points":approval["main_card_points"],"outer_window_points":approval["native_window_points"],"shadow_perimeter_points":32,"copy_points":approval["copy_points"],"voice_points":approval["voice_points"],"reference_images_per_mode":3,"reference_images_sha256":reference_hashes,"native_text_font_and_viewport_checks_per_mode":3,"measured_font_pt":19.5,"normal_font_fallback":"The view requests PingFangSC-Regular and falls back to system font at 19.5 pt if unavailable. The diagnostic verifies the size and viewport on this Mac; a forced missing-font scenario was not run.","actual_ax_footer_inspections":len(controls),"measurement_receipt":"ui/reference-measurements.json","original_srgb_comparison":"ui/original-comparison.json","visual_user_acceptance_verified":False},
    "input":inp,"headless_dom_checks":20,"local_vad_apple":apple_live,"apple":apple,"signed_packaged_apple":signed,
    "local_fallback_scope":"The current production Apple file route transcribed isolated synthetic fixtures, including one launched from the extracted signed application. The separate default capture worker also recognized and archived two paced synthetic utterances on one real ring through VAD, PCMJournal and on-device Apple with in-recording revisions. Ordinary live microphone speech and real external account failure mid-speech remain unmeasured.",
    "install":{"upgrade_checks":upgrade["count"],"reinstall_checks":len(reinstall["checks"]),"candidate_version":version,"rc1_source":upgrade["baseline_app_source_revision"],"rc1_rollback":"Use the explicit pre-upgrade copy, preserving candidate data."},
    "public_mac_distribution":{"code_integrity":"verified","gatekeeper_assessment":"rejected","notarized":False,"policy_modified":False},"signed_app_idle_seconds":idle["wall_seconds"],
    "long_capture":{k:long[k] for k in ("actual_wallclock_seconds","recordings","closed_wav_chunks_verified","saved_frames","reference_sha256","different_sample_frames","upload_grants","resource_samples","sampled_rss_kib_min","sampled_rss_kib_max","cpu_seconds_per_wallclock_percent")},
    "limitations":[
        "Real-provider authentication, authorized human speech processing, accuracy, strongest-single comparison, fusion gain and extra confirmation latency remain unmeasured.",
        "Apple speech evidence covers eight synthetic Mandarin fixtures and one separate signed-app fixture. Four expected phrases were missing in the corpus.",
        "Physical microphone, arbitrary foreground apps, physical sleep/hot-plug, multiple displays and 24–72-hour energy remain unverified.",
        "Foreground input resolution was not exercised. A background WK setter acknowledged the request without changing the DOM. That dispatch remained unverified and was not replayed.",
        "The exact approved JPEG is present in the frozen tree and its SHA-256 is verified. The original blue/purple setting and the offscreen neutral render have different backgrounds. Their raw RGB differences cannot grade material fidelity. Controlled two-window color transmission is measured separately. Physical wallpaper blur, pixel-perfect parity and user visual acceptance remain unverified.",
        "The personal arm64 build carries an ad-hoc signature. Strict code verification passed, but enabled Gatekeeper rejected the exact candidate (spctl exit 3). Ordinary distribution requires authorized Developer ID signing and notarization; no policy was bypassed."
    ],
    "evidence_sha256":{f:digest(out/f) for f in sorted(references)}
}
encoded = json.dumps(manifest,ensure_ascii=False,indent=2) + "\n"
if args.write:
    dest = out / "delivery-manifest.json"
    if dest.exists() and dest.read_text() != encoded:
        raise SystemExit("Different manifest already exists. Inspect it before replacing evidence.")
    if not dest.exists():
        with tempfile.NamedTemporaryFile(mode="w",encoding="utf-8",dir=out,delete=False) as temp:
            temp.write(encoded)
            temp.flush()
            os.fsync(temp.fileno())
            temp_path = Path(temp.name)
        os.replace(temp_path,dest)
    print("Closed local engineering evidence",sha,len(references),len(long["checks"]),long["actual_wallclock_seconds"])
else:
    print("All closure receipts verified. No manifest written. Use --write to save.")
