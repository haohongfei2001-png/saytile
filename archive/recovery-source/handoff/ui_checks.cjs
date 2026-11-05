// Optional browser regression for the supplied HTML mockup; requires Playwright. Run from the package root.
const {chromium}=require('playwright');
const fs=require('fs'),path=require('path');
(async()=>{
 const browser=await chromium.launch({executablePath:process.env.AOV_BROWSER_PATH||undefined,headless:true,args:['--no-sandbox']});
 const page=await browser.newPage({viewport:{width:1440,height:1020}});
 const errors=[],checks=[];
 page.on('pageerror',e=>errors.push(String(e)));
 const check=(name,ok,detail='')=>{checks.push({name,result:ok?'PASS':'FAIL',detail});if(!ok)throw new Error(name+': '+detail)};
 const scene=async s=>{await page.locator('[data-scene="'+s+'"]').click();await page.waitForTimeout(50)};
 await page.goto('file://'+path.resolve('always_on_voice_prototype.html'));
 for(const s of ['standby','live','continuous','recovery','archive','settings','onboarding']){
  await scene(s);check('scene_'+s,await page.locator('.panel,.desktop-app').first().isVisible());
 }
 await scene('continuous');
 const draft=page.locator('#target-draft');
 await draft.fill('已有草稿：请保留附件与正文。');
 await draft.evaluate(e=>e.setSelectionRange(e.value.length,e.value.length));
 const before=await draft.inputValue();
 await page.locator('#voice-panel [data-action="insert"]').click();
 const after=await draft.inputValue();
 check('insertion_keeps_existing_draft',after.startsWith(before)&&after.length>before.length);
 await draft.evaluate(e=>e.setSelectionRange(0,4));
 await page.locator('#voice-panel [data-action="insert"]').click();
 check('selection_is_not_replaced',await draft.inputValue()===after);
 await draft.evaluate(e=>e.setSelectionRange(e.value.length,e.value.length));
 await page.locator('[data-mode="direct"]').click();
 await page.locator('[data-action="change-target"]').click();
 await page.locator('#voice-panel [data-action="insert"]').click();
 check('changed_target_blocks_insertion',await draft.inputValue()==='');
 await scene('recovery');
 const oldText=await page.locator('.transcript-text').first().innerText();
 await page.locator('[data-action="retry"]').click();
 await page.waitForFunction(()=>document.querySelectorAll('.transcript').length===2);
 check('recovery_keeps_prior_text',await page.locator('.transcript-text').first().innerText()===oldText);
 await scene('archive');
 await page.locator('#archive-search').fill('边界');
 await page.waitForTimeout(150);
 check('chinese_history_search',(await page.locator('#archive-records').innerText()).includes('论文里的两个问题')&&!(await page.locator('#archive-records').innerText()).includes('让表达先被留下'));
 await page.locator('#archive-search').fill('');
 await page.waitForTimeout(100);
 const count=await page.locator('[data-record]').count();
 await page.locator('[data-action="delete-record"]').click();
 check('archive_delete',await page.locator('[data-record]').count()===count-1);
 await page.locator('[data-action="undo-delete"]').click();
 check('archive_undo',await page.locator('[data-record]').count()===count);
 await page.locator('[data-action="edit-record"]').click();
 await page.locator('#record-editor').fill('我修改的文本保持独立。');
 await page.locator('[data-action="save-edit"]').click();
 check('archive_edit',(await page.locator('#archive-detail').innerText()).includes('我修改的文本保持独立。'));
 await scene('settings');
 for(const tab of ['general','capture','storage','privacy']){
  await page.locator('[data-setting-tab="'+tab+'"]').click();
  check('settings_'+tab,await page.locator('.settings-body').isVisible());
 }
 await scene('onboarding');
 check('onboarding_requires_microphone_choice',await page.locator('[data-action="start-onboarding"]').isDisabled());
 await page.locator('[data-action="grant-mic"]').click();
 await page.locator('[data-confirm-permission="mic"]').click();
 await page.locator('[data-action="start-onboarding"]').click();
 check('onboarding_starts_free_record',await page.locator('#voice-panel').isVisible());
 const widths=[];
 for(const width of [390,900,1440]){
  await page.setViewportSize({width,height:1020});
  for(const s of ['continuous','archive','settings','onboarding']){
   await scene(s);const d=await page.evaluate(()=>({width:document.documentElement.clientWidth,scroll:document.documentElement.scrollWidth}));widths.push({viewport:width,scene:s,...d});
  }
 }
 check('no_page_script_errors',errors.length===0,errors.join('; '));
 const result={scope:'Browser UI simulation only; no microphone, ASR, disk durability or native external app insertion.',checks,errors,widths};
 fs.writeFileSync('handoff/prototype_checks.json',JSON.stringify(result,null,2));
 console.log(JSON.stringify({passed:checks.filter(c=>c.result==='PASS').length,total:checks.length,errors,widths}));
 await browser.close();
})().catch(e=>{console.error(e);process.exit(1)});
