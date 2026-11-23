// Disposable CI Safari witness. Loopback only; no Apple Events, remote
// automation preference, keyboard injection or existing browser profile.
import http from 'node:http';
import {readFileSync} from 'node:fs';
import {randomUUID} from 'node:crypto';

const [mode, ...args] = process.argv.slice(2);
function check({documentURL, action, expected}) {
  if (location.href !== documentURL) throw Error('Document changed');
  const field = document.querySelector('#entry'), other = document.querySelector('#other');
  if (!(field instanceof HTMLTextAreaElement) || !(other instanceof HTMLTextAreaElement)) throw Error('Unknown draft');
  if (action !== 'state') {
    if (field !== document.activeElement || field.value !== expected || other.value !== 'OTHER') throw Error('Setup target changed');
    if (action === 'collapse') field.setSelectionRange(15, 15);
    else if (action === 'manualEdit') {
      field.setRangeText('EDITED', 0, 6, 'preserve');
      field.dispatchEvent(new InputEvent('input', {bubbles:true,inputType:'insertText'}));
    } else if (action === 'switchTarget') other.focus();
    else throw Error('Unknown fixture action');
  }
  return {exact:field.value===expected, otherIntact:other.value==='OTHER', focused:field===document.activeElement,
    otherFocused:other===document.activeElement,start:field.selectionStart,end:field.selectionEnd,
    sawFirst:window.sawFirst,sawAppendAfterFirst:window.sawAppendAfterFirst,enter:window.returnCount,submits:window.submitCount};
}
if (mode === 'serve') {
  if (process.env.GITHUB_ACTIONS !== 'true' || process.env.SAYTILE_HOSTED_TARGETS !== '1') throw Error('Disposable CI only');
  const [file] = args;
  if (!/\/saytile-textedit-[\da-f-]{36}\/Saytile-owned-[\da-f-]{36}\.html$/i.test(file)) throw Error('Not owned fixture');
  const name = file.split('/').at(-1), token = randomUUID(), html = readFileSync(file,'utf8');
  let queued, pending, serial = 0;
  const server = http.createServer(async (req,res) => {
    res.setHeader('Cache-Control','no-store');
    if (req.socket.remoteAddress !== '127.0.0.1') { res.writeHead(403).end(); return; }
    if (req.url === '/'+name && req.method==='GET') {
      res.setHeader('Content-Type','text/html; charset=utf-8');
      const js = `const check=${check.toString()}; async function poll(){try{const r=await fetch('/poll/${token}');if(r.status===200){const cmd=await r.json();let value;try{value=check(cmd)}catch(e){value={error:String(e)}}await fetch('/reply/${token}',{method:'POST',body:JSON.stringify({id:cmd.id,value})})}}finally{setTimeout(poll,40)}}poll();`;
      res.end(html+'<script>'+js+'</script>'); return;
    }
    if (req.url === '/poll/'+token && req.method==='GET') {
      if (!queued) { res.writeHead(204).end(); return; }
      res.end(JSON.stringify(queued)); queued=undefined;return;
    }
    if (req.url !== '/command/'+token && req.url !== '/reply/'+token) {res.writeHead(404).end();return;}
    let body='';for await(const part of req){body+=part;if(body.length>4096){res.writeHead(413).end();return;}}
    const value=JSON.parse(body);
    if (req.url === '/reply/'+token) {
      if (!pending || value.id!==pending.id) {res.writeHead(409).end();return;}
      clearTimeout(pending.timer);pending.res.end(JSON.stringify(value.value));pending=undefined;res.end();return;
    }
    if(pending){res.writeHead(409).end();return;}
    const id=++serial;queued={...value,id};
    pending={id,res,timer:setTimeout(()=>{res.writeHead(504).end();pending=undefined;queued=undefined},4000)};
  });
  server.listen(0,'127.0.0.1',()=>console.log(JSON.stringify({port:server.address().port,token})));
} else if(mode === 'request') {
  const [port,token,documentURL,action,expected]=args;
  if(!/^\d+$/.test(port)|| !/^[\da-f-]{36}$/i.test(token) || new URL(documentURL).host!==`127.0.0.1:${port}`) throw Error('Invalid owned endpoint');
  const response=await fetch(`http://127.0.0.1:${port}/command/${token}`,{method:'POST',body:JSON.stringify({documentURL,action,expected}),signal:AbortSignal.timeout(5000)});
  if(!response.ok)throw Error('Owned DOM request failed');const value=await response.json();if(value.error)throw Error(value.error);console.log(JSON.stringify(value));
} else throw Error('Unknown mode');
