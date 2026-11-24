import {createRequire} from 'node:module';
import {createServer} from 'node:http';
import {readFileSync,writeFileSync,mkdirSync} from 'node:fs';
import {resolve,extname} from 'node:path';
const require=createRequire('/Users/hhf/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/package.json');
const {chromium}=require('playwright');
const root='/private/tmp/saytile-release-101/website', out=process.argv[3]||'/private/tmp/saytile-release-101/evidence/release-101/website-local';mkdirSync(out,{recursive:true});
let server;let url=process.argv[2];
if(!url){server=createServer((req,res)=>{let p=resolve(root,'.'+decodeURIComponent(req.url.split('?')[0]));if(p===root)p+='/index.html';if(!p.startsWith(root+'/')){res.writeHead(403).end();return;}try{res.setHeader('Content-Type',({'.html':'text/html; charset=utf-8','.js':'application/javascript','.css':'text/css','.png':'image/png','.webp':'image/webp','.m4a':'audio/mp4'})[extname(p)]||'application/octet-stream');const data=readFileSync(p);const range=req.headers.range?.match(/^bytes=(\d+)-(\d*)$/);res.setHeader('Accept-Ranges','bytes');if(range){const start=Number(range[1]),end=range[2]?Math.min(Number(range[2]),data.length-1):data.length-1;res.writeHead(206,{'Content-Range':`bytes ${start}-${end}/${data.length}`,'Content-Length':end-start+1});res.end(data.subarray(start,end+1));}else{res.setHeader('Content-Length',data.length);res.end(data);}}catch{res.writeHead(404).end();}});await new Promise(r=>server.listen(0,'127.0.0.1',r));url=`http://127.0.0.1:${server.address().port}/`;}
const browser=await chromium.launch({headless:true,executablePath:'/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',args:['--mute-audio']});
const checks=[], errors=[], failed=[];const check=(name,ok)=>{checks.push({name,pass:!!ok});if(!ok)failed.push(name);};
try{
 const c=await browser.newContext({reducedMotion:'reduce'});const p=await c.newPage();p.on('pageerror',e=>errors.push(String(e)));p.on('response',r=>{if(r.status()>=400)errors.push(`${r.status()} ${r.url()}`);});
 await p.goto(url,{waitUntil:'networkidle'});
 const href=await p.locator('#start a.button').getAttribute('href');check('Official 1.0.0 DMG',href==='https://github.com/haohongfei2001-png/saytile/releases/download/v1.0.0/Saytile-1.0.0-arm64.dmg');
 check('Version build and honest signing disclosure',/1.0.0（572）/.test(await p.locator('#release-download-info').innerText())&&(await p.locator('#release-download-info').innerText()).includes('尚未公证'));
 check('No obsolete current 0.18 download',await p.locator('a[href*="v0.18"]').count()===0);
 for(const w of [320,390,540,768,1000,1440,1600]){await p.setViewportSize({width:w,height:1000});await p.waitForTimeout(100);check(`Layout ${w}`,await p.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1));if(w===390||w===1440){await p.locator('#start').scrollIntoViewIfNeeded();await p.screenshot({path:`${out}/download-${w}.png`});}}
 for(const sel of ['.nav-cta','.hero-actions .button-dark']){await p.locator(sel).click();check(`Download navigation ${sel}`,await p.evaluate(()=>location.hash==='#start'));}
 await p.locator('#archive').scrollIntoViewIfNeeded();await p.locator('#archive-search').fill('看海');check('Archive search',await p.locator('.s9-record:visible').count()===1);await p.locator('#archive-search').fill('');
 await p.locator('#archive-transcript').fill('本页隔离编辑\n保留换行');await p.locator('#archive-tab-history').click();check('Edited version preserved',(await p.locator('#archive-current-version').innerText()).includes('本页隔离编辑'));
 await p.locator('#archive-tab-text').click();await p.locator('#archive-favorite').click();check('Favorite interactive',await p.locator('#archive-favorite').getAttribute('aria-pressed')==='true');
 await p.locator('#archive-audio-play').click();await p.waitForFunction(()=>document.querySelector('#archive-audio').currentTime>0.1);check('Actual labelled TTS playback',await p.locator('#archive-audio').evaluate(a=>!a.paused&&Number.isFinite(a.duration)));await p.locator('#archive-audio-play').click();check('Audio pause',await p.locator('#archive-audio').evaluate(a=>a.paused));
 await p.locator('#archive-speed').click();check('Playback speed',await p.locator('#archive-audio').evaluate(a=>a.playbackRate===1.5));
 await p.locator('#archive-seek').fill('50');await p.waitForFunction(()=>Math.abs(document.querySelector('#archive-audio').currentTime/document.querySelector('#archive-audio').duration-.5)<.05,{},{timeout:3000}).catch(()=>{});check('Actual seek',await p.locator('#archive-audio').evaluate(a=>Math.abs(a.currentTime/a.duration-.5)<.05));
 await p.locator('#archive-audio-play').click();await p.locator('[data-record="1"]').click();check('New record stops old audio',await p.locator('#archive-audio').evaluate(a=>a.paused));
 await p.locator('[data-record="0"]').click();check('Editing survives tab and record switches',(await p.locator('#archive-transcript').innerText()).includes('本页隔离编辑'));
 await p.locator('#native-open').click();check('Native screenshot dialog',await p.locator('#native-dialog').evaluate(e=>e.open));await p.keyboard.press('Escape');check('Dialog closes with Escape',await p.locator('#native-dialog').evaluate(e=>!e.open));
 for (const details of await p.locator('.start-faq details').all()) { if (!(await details.evaluate(e=>e.open))) await details.locator('summary').click(); }
 check('Optional Accessibility explained',(await p.locator('.start-faq').innerText()).includes('不需要。自由记录'));
 check('Cloud restore not misrepresented',(await p.locator('.start-faq').innerText()).includes('不提供已验证的 iCloud'));
 check('Original scripts and resources',await p.locator('script[src]').evaluateAll(es=>es.map(e=>e.getAttribute('src')).join(','))==='panel.js,hero.js,middle.js,scenes.js');
 check('No JS or resource errors',errors.length===0);
 await c.close();
}finally{await browser.close();if(server)server.close();writeFileSync(`${out}/receipt.json`,JSON.stringify({url,source:'1.0.1 candidate branch; download intentionally remains released 1.0.0',headless:true,privateBrowserProfile:false,systemClipboardAccess:false,checks,errors,status:failed.length?'FAIL':'PASS'},null,2));}
console.log(JSON.stringify({url,checks:checks.length,failed,errors}));if(failed.length)process.exitCode=1;
