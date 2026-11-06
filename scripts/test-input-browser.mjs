#!/usr/bin/env node
// Independent headless DOM layer. No real browser profiles, accounts, or native AX claim.
import { createRequire } from 'node:module';
import { readFileSync, mkdirSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';
import { spawnSync, spawn } from 'node:child_process';
import { createServer } from 'node:http';
import { createInterface } from 'node:readline';
const root=resolve(dirname(fileURLToPath(import.meta.url)),'..');
const scratch=process.env.SAYTILE_INPUT_SCRATCH??'/tmp/saytile-rc-input';
const require=createRequire(resolve(process.env.SAYTILE_PLAYWRIGHT_DIR??`${scratch}/browser-tools`,'package.json'));
const {chromium}=require('playwright');
const html=readFileSync(`${root}/tests/fixtures/input-browser.html`);
const server=createServer((_req,res)=>{res.setHeader('Content-Type','text/html; charset=utf-8');res.end(html);});
await new Promise(r=>server.listen(0,'127.0.0.1',r));
let browser,child;const lines=[];
const log=s=>{lines.push(s);console.log(s);};
try {
 const build=spawnSync('/bin/zsh',['-c',`swiftc -swift-version 6 -parse-as-library -I Sources/CSQLite Sources/SaytileKit/Models.swift Sources/SaytileKit/Store*.swift Sources/SaytileKit/Input*.swift tests/fixtures/InputDOMCoordinatorProbe.swift -o '${scratch}/dom-coordinator-probe'`],{cwd:root,encoding:'utf8'});
 if(build.status!==0)throw Error(build.stderr);
 browser=await chromium.launch({headless:true, ...(process.env.SAYTILE_CHROMIUM_EXECUTABLE?{executablePath:process.env.SAYTILE_CHROMIUM_EXECUTABLE}:{})});
 log('HEADLESS_BROWSER '+browser.version());
 const context=await browser.newContext();const page=await context.newPage();
 await page.goto(`http://127.0.0.1:${server.address().port}/chat/one`);
 child=spawn(`${scratch}/dom-coordinator-probe`,[],{stdio:['pipe','pipe','pipe']});
 let stderr='';child.stderr.on('data',b=>stderr+=b);
 const timeout=setTimeout(()=>child.kill('SIGKILL'),30000);
 let complete=false;
 for await(const line of createInterface({input:child.stdout})){
  const request=JSON.parse(line);let response={};
  try {
   if(request.method==='pass')log('PASS '+request.message);
   else if(request.method==='complete'){complete=true;log(`DOM_COORDINATOR_PASS ${request.checks} checks; ${request.scope}`);}
   else response=await page.evaluate(async request=>{
    switch(request.method){
     case 'reset':reset(request.kind);return {};
     case 'snapshot':return snapshot();
     case 'dispatch':return dispatch(request.text);
     case 'matches':return {ok:value().slice(request.start,request.start+request.text.length)===request.text};
     case 'mutation':return await mutation(request.name);
     case 'state':return {text:value(),sends,dispatches};
     default:throw Error('Unknown method');
    }
   },request);
  }catch(error){response={error:String(error)};}
  child.stdin.write(JSON.stringify(response)+'\n');
 }
 clearTimeout(timeout);
 if(!complete)throw Error(stderr||'Probe incomplete');
 await context.close();
}finally{
 child?.kill();await browser?.close();server.close();
 mkdirSync(`${root}/evidence/rc`,{recursive:true});
 writeFileSync(`${root}/evidence/rc/input-browser-dom.log`,lines.join('\n')+'\n');
}
