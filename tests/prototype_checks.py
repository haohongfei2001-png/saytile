"""DOM interaction tests. Browser navigation is not required.

The exact HTML is injected using set_content. localStorage uses an explicit
in-memory test double because the runner's blank page has an opaque origin.
This validates serialization/restore behavior, not file:// persistence or Safari.
"""
from pathlib import Path
import json, os, sys, shutil
from playwright.sync_api import sync_playwright
ROOT=Path(__file__).resolve().parents[1]
HTML=(ROOT/'prototype/index.html').read_text()
checks=[];errors=[]
def check(name,condition,detail=''):
    checks.append({'name':name,'result':'PASS' if condition else 'FAIL','detail':detail})
    if not condition: raise AssertionError(name+' '+detail)
def content(storage=None):
    seed=json.dumps(storage or {},ensure_ascii=False).replace('</','<\\/')
    shim='''<script>window.__testStorage=SEED;Object.defineProperty(window,'localStorage',{value:{getItem(k){return window.__testStorage[k]??null},setItem(k,v){window.__testStorage[k]=String(v)},removeItem(k){delete window.__testStorage[k]}}});</script>'''.replace('SEED',seed)
    return HTML.replace('<script>',shim+'<script>',1)
def run():
 with sync_playwright() as w:
  browser=w.chromium.launch(executable_path=os.getenv('SAYTILE_BROWSER_PATH') or shutil.which('chromium') or None,headless=True,args=['--no-sandbox'])
  page=browser.new_page(viewport={'width':1440,'height':1020})
  page.on('pageerror',lambda e: errors.append(str(e)))
  page.set_default_timeout(4000)
  page.set_content(content(),wait_until='domcontentloaded')
  def scene(name): page.locator(f'[data-scene="{name}"]').click();page.wait_for_timeout(30)
  def action(name): page.locator(f'[data-action="{name}"]').first.click()
  check('brand_is_saytile','Saytile' in page.title() and page.locator('.brand h1').inner_text()=='Saytile')
  for name in ['standby','live','continuous','recovery','archive','settings','onboarding']:
   scene(name);check('scene_'+name,page.locator('.panel,.desktop-app').first.is_visible())
  scene('continuous');draft=page.locator('#target-draft')
  draft.fill('保留现有草稿。');draft.evaluate('(e)=>e.setSelectionRange(e.value.length,e.value.length)')
  page.locator('#voice-panel [data-action="insert"]').click()
  before=draft.input_value();check('manual_insert_preserves_existing_text',before.startswith('保留现有草稿。') and len(before)>8)
  draft.evaluate('(e)=>e.setSelectionRange(0,4)');page.locator('#voice-panel [data-action="insert"]').click()
  check('selected_text_is_not_overwritten',draft.input_value()==before)
  scene('continuous');action('incremental-demo')
  check('incremental_suffix_is_inserted_once',page.locator('#target-draft').input_value()=='你好，世界')
  action('incremental-demo');check('same_stable_revision_does_not_duplicate',page.locator('#target-draft').input_value()=='你好，世界')
  action('rewrite-demo');check('prefix_change_pauses_direct_input',page.evaluate('state.targetValid') is False and page.locator('#target-draft').input_value()=='你好，世界')
  action('rebind');check('rebind_does_not_replay_old_text',page.locator('#target-draft').input_value()=='你好，世界')
  action('change-target');page.locator('#voice-panel [data-action="insert"]').click()
  check('changed_target_keeps_draft_empty',page.locator('#target-draft').input_value()=='')
  scene('recovery');before=page.locator('.transcript-text').first.inner_text();action('retry')
  page.wait_for_function('document.querySelectorAll(".transcript").length===2')
  check('recovery_retains_previous_text',page.locator('.transcript-text').first.inner_text()==before)
  scene('archive');page.locator('#archive-search').fill('边界');page.wait_for_timeout(30)
  check('chinese_history_search','论文里的两个问题' in page.locator('#archive-records').inner_text())
  page.locator('#archive-search').fill('');count=page.locator('[data-record]').count()
  action('edit-record');page.locator('#record-editor').fill('第一次修改稿。');action('save-edit')
  action('edit-record');page.locator('#record-editor').fill('保留第二次修改稿。');action('save-edit')
  old=page.evaluate('JSON.parse(JSON.stringify(state.archive.find(r=>r.id===state.selectedRecord)))')
  action('delete-audio');check('audio_erasure_has_explicit_confirmation','保留识别文字' in page.locator('#dialog-host').inner_text())
  action('close-dialog');check('audio_erasure_cancel_does_nothing',page.locator('[data-action="play-record"]').count()==1)
  action('delete-audio');action('confirm-delete-audio')
  new=page.evaluate('state.archive.find(r=>r.id===state.selectedRecord)')
  check('audio_erasure_keeps_record_count',page.locator('[data-record]').count()==count)
  check('audio_erasure_keeps_all_demo_revisions',new['text']==old['text'] and new['originalText']==old['originalText'] and new['revisions']==old['revisions'])
  check('audio_erasure_removes_play_and_retry',page.locator('[data-action="play-record"]').count()==0 and page.locator('[data-action="retry-record"]').count()==0)
  check('audio_erasure_keeps_copy_and_reuse',page.locator('[data-action="copy-record"]').is_visible() and page.locator('[data-action="reuse-record"]').is_visible())
  page.locator('#archive-search').fill('第二次');check('erased_audio_text_still_searchable',page.locator('[data-record]').count()==1)
  page.locator('#archive-search').fill('')
  page.screenshot(path=str(ROOT/'evidence/prototype-audio-deleted.png'),full_page=True)
  storage=page.evaluate('window.__testStorage')
  page.close();page=browser.new_page(viewport={'width':1440,'height':1020});page.on('pageerror',lambda e:errors.append(str(e)))
  page.set_content(content(storage),wait_until='domcontentloaded');page.set_default_timeout(4000)
  # Helpers close over the current page variable.
  scene('archive');check('demo_storage_roundtrip_keeps_audio_deleted',page.evaluate('state.archive[0].audioDeleted') is True)
  check('demo_storage_roundtrip_keeps_text','第二次' in page.locator('#archive-detail').inner_text())
  scene('continuous');check('restart_never_rebinds_or_replays',page.evaluate('state.mode')=='record' and page.locator('#target-draft').input_value()=='')
  scene('archive');action('delete-record')
  check('whole_record_deletion_has_different_confirmation','文字、修改稿与原音' in page.locator('#dialog-host').inner_text())
  action('confirm-delete-record');check('whole_record_removed',page.locator('[data-record]').count()==count-1)
  action('undo-delete');check('undo_restores_record_not_deleted_audio',page.locator('[data-record]').count()==count and page.evaluate('state.archive[0].audioDeleted') is True)
  scene('settings')
  for tab in ['general','capture','storage','privacy']:
   page.locator(f'[data-setting-tab="{tab}"]').click();check('settings_'+tab,page.locator('.settings-body').is_visible())
  page.locator('[data-setting-tab="storage"]').click()
  check('default_audio_retention_no_silent_expiry',page.locator('[data-setting="retention"]').input_value()=='保留至手动删除')
  page.locator('[data-setting="retention"]').select_option('30 天后整理')
  check('retention_change_requires_confirmation',page.locator('[data-setting="retention"]').input_value()=='保留至手动删除' and page.locator('[data-action="confirm-retention"]').is_visible())
  action('close-dialog');check('retention_cancel_keeps_previous_policy',page.locator('[data-setting="retention"]').input_value()=='保留至手动删除')
  page.locator('[data-setting="retention"]').select_option('30 天后整理');action('confirm-retention')
  check('retention_confirm_changes_policy_only',page.locator('[data-setting="retention"]').input_value()=='30 天后整理' and len(page.evaluate('state.archive'))==count)
  page.locator('[data-setting-tab="capture"]').click()
  check('engine_policy_not_local_only',page.locator('[data-setting="engine"]').input_value()=='自动推荐')
  scene('onboarding');check('mic_permission_required_to_start',page.locator('[data-action="start-onboarding"]').is_disabled())
  action('grant-mic');page.locator('[data-confirm-permission="mic"]').click();action('start-onboarding')
  check('onboarding_starts_free_recording_demo',page.locator('#voice-panel').is_visible() and page.evaluate('state.mode')=='record')
  action('pause');check('pause_is_visible','已暂停' in page.locator('#voice-panel').inner_text())
  action('pause');check('resume_is_visible',page.evaluate('state.paused') is False)
  widths=[]
  for width in [390,900,1440]:
   page.set_viewport_size({'width':width,'height':1020})
   for name in ['continuous','archive','settings','onboarding']:
    scene(name);dims=page.evaluate('({width:document.documentElement.clientWidth,scroll:document.documentElement.scrollWidth})')
    widths.append({'viewport':width,'scene':name,**dims})
   check('no_horizontal_document_overflow_'+str(width),all(d['scroll']<=d['width']+1 for d in widths if d['viewport']==width))
  page.set_viewport_size({'width':1440,'height':1020})
  for name in ['standby','continuous','archive','settings']:
   scene(name);page.screenshot(path=str(ROOT/f'evidence/prototype-{name}.png'),full_page=True)
  action('reset-demo');scene('archive');check('reset_demo_restores_playback',page.locator('[data-action="play-record"]').count()==1)
  check('no_page_script_errors',len(errors)==0,';'.join(errors))
  browser.close()
  return widths

if __name__=='__main__':
 widths=[];fatal=None
 try:widths=run()
 except Exception as e:fatal=str(e);print(type(e).__name__,str(e))
 result={'scope':'Chromium DOM simulation; localStorage is a memory test double; no native audio/ASR/input.',
  'html_loading':'set_content; file/http navigation blocked by environment browser policy',
  'checks':checks,'passed':sum(c['result']=='PASS' for c in checks),'total':len(checks),'errors':errors,'fatal':fatal,'widths':widths}
 (ROOT/'evidence/prototype-checks.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
 print(json.dumps({k:result[k] for k in ['passed','total','fatal','errors']},ensure_ascii=False))
 sys.exit(bool(fatal) or bool(errors))
