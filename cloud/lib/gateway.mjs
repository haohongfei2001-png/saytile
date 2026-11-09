import http from 'node:http';
import {WebSocketServer,WebSocket} from 'ws';
import {Fault,uuid,digest,platform} from './platform.mjs';
import {providerConfig,qwen,review} from './providers.mjs';
import {payments} from './payments.mjs';

async function rawBody(req,max) {
  const chunks=[]; let size=0;
  for await (const chunk of req) { size+=chunk.length;if(size>max)throw new Fault('too_large',413);chunks.push(chunk); }
  return Buffer.concat(chunks);
}
const deny=(socket,code)=>{if(!socket.destroyed)socket.end('HTTP/1.1 '+code+' Rejected\r\nConnection: close\r\nContent-Length: 0\r\n\r\n');};
export function gateway({env=process.env,db=platform(env),openASR=qwen,ask=review,billing=payments(env,db)}={}) {
  const wsServer=new WebSocketServer({noServer:true,maxPayload:65540,perMessageDeflate:false});
  const server=http.createServer(async(req,res)=>{
    const send=(status,data)=>{res.writeHead(status,{'content-type':'application/json','cache-control':'no-store'});res.end(JSON.stringify(data));};
    try {
      const path=new URL(req.url,'http://localhost').pathname;
      if(req.method==='GET'&&path==='/v1/health')return send(200,{service:'saytile-cloud',protocol:1,revision:env.SAYTILE_REVISION||env.VERCEL_GIT_COMMIT_SHA||'local',environment:env.VERCEL_ENV||'local'});
      if(req.method==='GET'&&path==='/v1/billing-return') {res.writeHead(200,{'content-type':'text/plain; charset=utf-8'});return res.end('请返回 Saytile 设置刷新权益。');}
      if(req.method==='GET'&&path==='/v1/config')return send(200,db.config());
      if(req.method==='POST'&&path==='/v1/stripe') {await billing.webhook(await rawBody(req,131072),req.headers['stripe-signature']);return send(200,{ok:true})}
      const uid=await db.user(req.headers);
      if(req.method==='GET'&&path==='/v1/account')return send(200,await db.rpc('account',{p_uid:uid}));
      if(req.method==='POST'&&['/v1/checkout','/v1/portal'].includes(path))return send(200,{url:await billing.link(uid,path.endsWith('portal'))});
      if(req.method==='POST'&&path==='/v1/review') {
        const config=providerConfig(env), b=JSON.parse(await rawBody(req,40000)), p=db.verify(b.proof);
        if(p.uid!==uid||!uuid(p.lease)||p.until<Date.now()||typeof b.text!=='string'||Buffer.byteLength(b.text)>16384||
           digest(b.text)!==p.sha||!uuid(b.candidateID))throw new Fault('invalid_evidence',403);
        await db.rpc('review',{p_uid:uid,p_lease:p.lease,p_seq:p.seq});
        const finish=units=>db.rpc('settle',{p_lease:p.lease,p_op:String(p.seq),p_ms:null,p_actual:null,p_units:units});
        let answer;
        try {answer=await ask(config,b.text,p.stable)}catch {await finish(null);throw new Fault('review_unavailable',502)}
        await finish(answer.usage);
        return send(200,{decision:{selections:answer.end?[{candidateID:b.candidateID,utf16Start:0,utf16End:answer.end}]:[],
          unresolved:answer.uncertain,needsAudioReview:false,reasonCode:'hosted-verbatim'},usage:answer.usage});
      }
      throw new Fault('not_found',404);
    }catch(e){send(e instanceof Fault?e.status:400,{error:e instanceof Fault?e.message:'invalid_request'})}
  });
  server.on('upgrade',async(req,socket,head)=>{
    let lease, handed=false;
    socket.on('error',()=>{});
    try {
      const path=new URL(req.url,'http://localhost');
      if(path.pathname==='/v1/probe' && env.PROBE_TOKEN && req.headers.authorization==='Bearer '+env.PROBE_TOKEN) {
        return wsServer.handleUpgrade(req,socket,head,ws=>{
          ws.send(JSON.stringify({service:'saytile-cloud',probe:true}));
          const timer=setInterval(()=>{if(ws.readyState===WebSocket.OPEN)ws.ping()},5000);
          ws.on('error',()=>{});ws.once('close',()=>clearInterval(timer));ws.on('message',()=>ws.close(1008));
        });
      }
      if(path.pathname!=='/v1/stream'||path.search)throw new Fault('not_found',404);
      const user=await db.user(req.headers), config=providerConfig(env);
      const id=req.headers['x-saytile-recording'], epoch=Number(req.headers['x-saytile-epoch']);
      if(!uuid(id)||!Number.isSafeInteger(epoch)||epoch<0||req.headers['x-saytile-consent']!=='zh-v1')throw new Fault('invalid_session');
      lease=await db.rpc('reserve',{p_uid:user,p_recording:id,p_epoch:epoch});
      if(socket.destroyed)throw new Fault('disconnected');
      wsServer.handleUpgrade(req,socket,head,ws=>{
        handed=true; stream(ws,{db,config,id,epoch,lease,user,openASR});
      });
    }catch(e){deny(socket,e instanceof Fault?e.status:503)}
    finally {if(lease&&!handed)await db.rpc('settle',{p_lease:lease,p_op:'audio',p_ms:0,p_actual:0,p_units:null}).catch(()=>{})}
  });
  return server;
}

function stream(ws,{db,config,id,epoch,lease,user,openASR}) {
  let upstream,ready=false,eos=false,closed=false,seq=0,frame=0,bytes=0;
  const segments=new Map(), until=Date.now()+145000;
  const send=data=>{if(ws.readyState===WebSocket.OPEN&&ws.bufferedAmount<262144)ws.send(JSON.stringify(data));else throw new Fault('client_slow')};
  const finish=(code=1011)=>{
    if(closed)return;closed=true;clearTimeout(deadline);clearInterval(check);
    upstream?.close(); if(ws.readyState===WebSocket.OPEN)ws.close(code);
    // A dropped connection can still be billed. The durable hold survives failure to settle.
    void db.rpc('settle',{p_lease:lease,p_op:'audio',p_ms:Math.ceil(bytes/32),p_actual:null,p_units:{pcm_bytes:bytes,request_id:id}}).catch(()=>{});
  };
  const deadline=setTimeout(()=>finish(1001),95000);
  let checking=false;
  const check=setInterval(async()=>{if(checking)return;checking=true;try{
    const a=await db.rpc('account',{p_uid:user});if(!a.active||!a.available)finish(1008);
  } catch{finish(1011)}finally{checking=false}},5000);
  ws.on('close',()=>finish());ws.on('error',()=>finish());
  ws.on('message',(data,binary)=>{try{
    if(!ready||closed||eos)throw new Fault('invalid_state');
    if(!binary) {if(data.toString()!=='eos')throw new Fault('invalid_eos');eos=true;upstream.end();return}
    if(data.length<6||(data.length-4)%2!==0||data.readUInt32BE(0)!==frame++||bytes+data.length-4>1120000)throw new Fault('invalid_frame');
    bytes+=data.length-4;upstream.audio(data.subarray(4));
  }catch{finish(1008)}});
  try {upstream=openASR(config,id,e=>{
    if(closed)return;
    const kind=e.header?.event;
    if(kind==='task-started'&&!ready){ready=true;send({event:e});return}
    if(!ready||!['result-generated','task-finished'].includes(kind))throw new Fault('provider_failed');
    const sentence=e.payload?.output?.sentence;
    if(kind==='result-generated'&&sentence&&!sentence.heartbeat&&typeof sentence.text==='string' && Number.isInteger(sentence.sentence_id)){
      segments.set(sentence.sentence_id,{text:sentence.text,done:sentence.sentence_end===true});
      const stash=sentence.stash;
      if(stash&&Number.isInteger(stash.sentence_id)&&stash.sentence_id>sentence.sentence_id&&typeof stash.text==='string'&&!segments.get(stash.sentence_id)?.done)segments.set(stash.sentence_id,{text:stash.text,done:false});
    }
    let text='', stable=0, continuous=true, expected=1;
    for(const [n,s] of [...segments].sort(([a],[b])=>a-b)){text+=s.text;continuous=continuous&&n===expected++&&s.done;if(continuous)stable=text.length;}
    if(Buffer.byteLength(text)>16384)throw new Fault('output_too_large');
    const proof=db.sign({uid:user,lease,seq:++seq,sha:digest(text),stable,until});
    send({event:e,proof,sequence:seq,recording:id,epoch});
    if(kind==='task-finished'){if(!eos)throw new Fault('early_eos');finish(1000)}
  },()=>finish());}catch{finish()}
}
