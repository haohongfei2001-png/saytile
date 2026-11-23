// Run after publication. Fresh headless browser; no profile, user tabs or clipboard.
import {createRequire} from 'node:module';
import {createHash} from 'node:crypto';
import {createReadStream, writeFileSync, mkdirSync, statSync} from 'node:fs';
import {resolve} from 'node:path';
const require=createRequire(process.env.SAYTILE_PLAYWRIGHT_PACKAGE || '/Users/hhf/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/package.json');
const {chromium}=require('playwright');
const out=resolve(process.argv[2] || '/tmp/saytile-release100-public-download');mkdirSync(out,{recursive:true});
const expected='60e4abf60618d510c7f99d8e92a6ec456f16840f22cc0fcd7eb74ac729c9dba2';
const downloadURL='https://github.com/haohongfei2001-png/saytile/releases/download/v1.0.0/Saytile-1.0.0-arm64.dmg';
const browser=await chromium.launch({headless:true,executablePath:'/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',args:['--mute-audio'],...(process.env.SAYTILE_TEST_PROXY?{proxy:{server:process.env.SAYTILE_TEST_PROXY}}:{})});
const receipt={source:'https://saytile.com/',expected_download_url:downloadURL,expected_sha256:expected,started:new Date().toISOString(),profile:'fresh headless context',installed_user_app_modified:false};
try{
 const context=await browser.newContext({acceptDownloads:true});
 const page=await context.newPage();
 const response=await page.goto(receipt.source,{waitUntil:'networkidle',timeout:60000});
 receipt.homepage_status=response.status();
 const link=page.locator('#start a.button');receipt.actual_href=await link.getAttribute('href');
 if(receipt.actual_href!==downloadURL)throw Error('Homepage download destination differs from released file');
 await link.scrollIntoViewIfNeeded();
 const event=page.waitForEvent('download',{timeout:120000});
 await link.click();
 const download=await event;receipt.suggested_filename=download.suggestedFilename();
 console.log('PUBLIC_DOWNLOAD_STARTED');
 if(receipt.suggested_filename!=='Saytile-1.0.0-arm64.dmg')throw Error('Unexpected download filename');
 const file=resolve(out,receipt.suggested_filename);await download.saveAs(file);
 receipt.download_failure=await download.failure();
 const hash=createHash('sha256');for await(const data of createReadStream(file))hash.update(data);
 receipt.actual_sha256=hash.digest('hex');receipt.bytes=statSync(file).size;receipt.download_path=file;
 if(receipt.download_failure || receipt.actual_sha256!==expected || receipt.bytes!==65662466)throw Error('Public download failed or differs from tested DMG');
 receipt.status='PASS';console.log('PUBLIC_DOWNLOAD_SHA256_PASS');
}catch(e){receipt.status='FAIL';receipt.error=String(e);throw e;}
finally{receipt.finished=new Date().toISOString();writeFileSync(resolve(out,'receipt.json'),JSON.stringify(receipt,null,2)+'\n');await browser.close();}
