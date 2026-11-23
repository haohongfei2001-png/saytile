// Public admission and operator-only heartbeat check. No account login, audio or model request.
import https from 'node:https';import fs from 'node:fs';import {createRequire} from 'node:module';import {once} from 'node:events';import assert from 'node:assert/strict';
const WebSocket=createRequire(new URL('../cloud/package.json',import.meta.url))('ws');
const expected=process.argv[2];assert.match(expected,/^[0-9a-f]{40}$/);
const base='https://saytile-cloud.vercel.app',agent=new https.Agent({proxyEnv:process.env}),start=Date.now();
const get=(p,method='GET')=>new Promise((resolve,reject)=>{const req=https.request(base+p,{agent,method,timeout:10000},r=>{const chunks=[];r.on('data',d=>{if(p==='/v1/health')chunks.push(d)});r.on('end',()=>resolve({status:r.statusCode,...(p==='/v1/health'?JSON.parse(Buffer.concat(chunks)): {})}))});req.on('error',reject);req.on('timeout',()=>req.destroy(Error('timeout')));req.end()});
const health=await get('/v1/health');assert.equal(health.revision,expected);assert.equal(health.environment,'production');
const checks={};for(const [p,expectedStatus] of [['/v1/config',503],['/v1/account',401],['/.env.local',404],['/.vercel/probe-token',404]]){checks[p]=(await get(p,p.startsWith('/.')?'HEAD':'GET')).status;assert.equal(checks[p],expectedStatus)}
const unauthorized=new WebSocket(base.replace('https','wss')+'/v1/stream',{agent,handshakeTimeout:10000});
const [err]=await once(unauthorized,'error');assert.match(err.message,/401/);
const unconfigured=new WebSocket(base.replace('https','wss')+'/v1/stream',{agent,handshakeTimeout:10000,headers:{authorization:'Bearer no-account-public-synthetic-check'}});
const [unavailable]=await once(unconfigured,'error');assert.match(unavailable.message,/503/);
const probe=new WebSocket(base.replace('https','wss')+'/v1/probe',{agent,headers:{authorization:'Bearer '+fs.readFileSync(process.env.SAYTILE_PROBE_SECRET_FILE,'utf8').trim()},handshakeTimeout:10000});const timer=setTimeout(()=>probe.terminate(),18000);let pings=0;
probe.on('ping',()=>{if(++pings===2)probe.close(1000)});const [msg]=await once(probe,'message');assert.equal(JSON.parse(msg).service,'saytile-cloud');const [code]=await once(probe,'close');clearTimeout(timer);assert.equal(pings,2);assert.equal(code,1000);
console.log(JSON.stringify({status:'PASS',timestamp:new Date().toISOString(),health,checks,unauthenticatedStream:401,unconfiguredStream:503,noAudioProbe:{pings,closeCode:code},proxiesConfigured:Boolean(process.env.HTTPS_PROXY||process.env.https_proxy),durationMS:Date.now()-start}));
