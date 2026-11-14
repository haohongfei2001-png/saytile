'use strict';
(() => {
  const $ = s => document.querySelector(s), all = s => [...document.querySelectorAll(s)];
  const scene = $('#journey'); if (!scene) return;
  const media = matchMedia('(prefers-reduced-motion: reduce)'); let reduced = media.matches;
  const sample = '这个周末，想去看海。\n嗯，不赶时间。\n等天气放晴，再出发。';
  let toastTimer;
  const notice = message => { const n=$('#toast'); if(!n)return; clearTimeout(toastTimer);n.textContent=message;n.classList.add('visible');toastTimer=setTimeout(()=>n.classList.remove('visible'),2300); };
  const plain = el => el.innerText.replace(/\u00a0/g,' ').trim();
  async function writeClipboard(value) {
    if(!value.trim()){notice('这里还没有文字。');return false;}
    try { await navigator.clipboard.writeText(value); notice('文字已复制。'); return true; }
    catch (_) {
      const active=document.activeElement, selection=getSelection(),range=selection?.rangeCount?selection.getRangeAt(0).cloneRange():null;
      const temp=document.createElement('textarea');temp.value=value;temp.readOnly=true;temp.style.cssText='position:fixed;left:-9999px;top:0;opacity:0';document.body.append(temp);temp.select();
      let ok=false;try{ok=document.execCommand('copy');}catch(_){}temp.remove();active?.focus({preventScroll:true});if(range&&selection){selection.removeAllRanges();selection.addRange(range);}
      notice(ok?'文字已复制。':'浏览器没有允许复制，请选中文字后复制。');return ok;
    }
  }
  const transcript=$('#journey-transcript'),draft=$('#journey-draft'),copy=$('#journey-copy'),paste=$('#journey-paste'),play=$('#journey-play'),pointer=$('#journey-pointer');
  const steps=all('[data-journey-step]');
  let running=false,started=false,elapsed=0,origin=0,timer=0,dirty=false,focusProtected=false,buffer=null,autoCopied=false,autoPasted=false,lastStep=-1,lastClick=-1,copyEpoch=0;
  const DURATION=12600;
  function playback() {
    play.querySelector('use').setAttribute('href',running?'#i-pause':'#i-play');play.querySelector('span').textContent=running?'暂停演示':elapsed>=DURATION?'再看一次':'播放这段流程';
    play.setAttribute('aria-label',running?'暂停说话、复制与粘贴流程':'播放说话、复制与粘贴流程');$('#journey-voice').setAttribute('aria-label',running?'暂停演示':'播放演示');
  }
  function step(n,caption) {if(lastStep!==n){lastStep=n;steps.forEach(b=>b.setAttribute('aria-pressed',String(Number(b.dataset.journeyStep)===n)));}if(caption&&$('#journey-caption').textContent!==caption)$('#journey-caption').textContent=caption;}
  function stop(protectedInput=false) {
    if(running)elapsed=Math.min(DURATION,performance.now()-origin);running=false;clearTimeout(timer);scene.dataset.speaking='false';scene.dataset.paused=String(elapsed<DURATION);pointer.style.opacity='0';pointer.classList.remove('is-clicking');
    if(protectedInput){started=true;focusProtected=true;copyEpoch++;$('#journey-state').textContent='编辑你的文字';$('#journey-caption').textContent='你的修改会保留。只有重播会重新开始。';}
    playback();
  }
  function pointFor(el,dx=.5,dy=.5) {const b=el.getBoundingClientRect(),r=scene.getBoundingClientRect();return {x:b.left-r.left+b.width*dx,y:b.top-r.top+b.height*dy};}
  function routePath(){
    const r=scene.getBoundingClientRect(),c=pointFor(copy),speech=$('#journey-panel').getBoundingClientRect(),target=$('#journey-composer').getBoundingClientRect();
    const path=$('.s9-transfer-path'),start={x:c.x,y:speech.bottom-r.top-4},end={x:target.left-r.left+target.width*.32,y:target.top-r.top+8};
    path.setAttribute('viewBox',`0 0 ${r.width} ${r.height}`);
    path.querySelector('path').setAttribute('d',`M${start.x} ${start.y} C${start.x} ${start.y+34} ${end.x} ${end.y-35} ${end.x} ${end.y}`);
    path.querySelector('.s9-path-tip').setAttribute('d',`m${end.x-5} ${end.y-8} 5 9 5-9`);
  }
  new ResizeObserver(routePath).observe(scene);
  function drawPointer(a,b,t) {t=Math.max(0,Math.min(1,t));const e=t*t*(3-2*t);pointer.style.left=(a.x+(b.x-a.x)*e)+'px';pointer.style.top=(a.y+(b.y-a.y)*e)+'px';pointer.style.opacity='1';}
  function clickMark(index) {if(lastClick===index)return;lastClick=index;pointer.classList.remove('is-clicking');void pointer.offsetWidth;pointer.classList.add('is-clicking');}
  function copiedFeedback(real=false) {copy.dataset.copied='true';$('#journey-copy-feedback').textContent=real?'已复制':'已复制 · 示例';paste.disabled=!buffer;}
  function finalState() {
    transcript.textContent=sample;draft.value=sample;buffer=sample;autoCopied=autoPasted=true;elapsed=DURATION;
    scene.dataset.phase='ready';scene.dataset.speaking='false';scene.dataset.paused='false';copy.dataset.copied='true';$('#journey-copy-feedback').textContent='已复制 · 示例';
    $('#journey-state').textContent='刚刚完成';$('#journey-draft-status').textContent='已粘贴，发送由你决定。';step(2,'说完 · 复制 · 粘贴到对话框');paste.disabled=false;paste.classList.remove('is-available');pointer.style.opacity='0';playback();
  }
  function tick() {
    if(!running||document.hidden||dirty)return;
    elapsed=performance.now()-origin;const t=elapsed;
    const cp=pointFor(copy,.55,.62),ct=pointFor(draft,.67,.43),pt=pointFor(paste,.45,.55),home={x:cp.x+75,y:cp.y+30};
    scene.dataset.paused='false';
    if(t<5200) {
      scene.dataset.phase='speaking';scene.dataset.speaking='true';step(0,'自然说，文字在语音板中接续出现。');$('#journey-state').textContent='正在听你说';
      const chars=Math.min(sample.length,Math.max(1,Math.floor(t/125)));const value=sample.slice(0,chars);
      if(transcript.textContent!==value)transcript.textContent=value;pointer.style.opacity='0';
    } else if(t<6200) {
      transcript.textContent=sample;scene.dataset.speaking='false';scene.dataset.phase='copy';$('#journey-state').textContent='说完了，点一下复制';step(1,'说完，点一下语音板上的复制。');drawPointer(home,cp,(t-5200)/800);
    } else if(t<7300) {
      scene.dataset.phase='copy';drawPointer(cp,cp,1);clickMark(0);if(!autoCopied){buffer=plain(transcript);autoCopied=true;copiedFeedback();}
    } else if(t<8400) {
      scene.dataset.phase='copied';step(2,'来到 AI 的输入框，准备粘贴。');drawPointer(cp,ct,(t-7300)/950);
    } else if(t<9100) {
      scene.dataset.phase='paste';drawPointer(ct,ct,1);clickMark(1);$('#journey-state').textContent='刚才的话，完整带过来';
    } else if(t<10000) {
      scene.dataset.phase='paste';drawPointer(ct,pt,(t-9100)/700);
    } else if(t<10900) {
      scene.dataset.phase='paste';drawPointer(pt,pt,1);clickMark(2);
      if(!autoPasted){draft.value=buffer||'';autoPasted=true;$('#journey-draft-status').textContent='已粘贴，发送由你决定。';step(2,'文字已在输入框。发送，仍由你决定。');}
    } else {
      scene.dataset.phase='ready';scene.dataset.speaking='false';pointer.style.opacity='0';paste.classList.remove('is-available');$('#journey-state').textContent='刚刚完成';
    }
    if(t>=DURATION){elapsed=DURATION;running=false;clearTimeout(timer);playback();return;}timer=setTimeout(tick,40);
  }
  function start(reset=false) {
    stop();started=true;
    if(reset){copyEpoch++;dirty=focusProtected=false;elapsed=0;transcript.textContent='';draft.value='';buffer=null;autoCopied=autoPasted=false;lastStep=lastClick=-1;copy.dataset.copied='false';$('#journey-copy-feedback').textContent='';paste.disabled=true;paste.classList.remove('is-available');$('#journey-draft-status').textContent='发送前，还可以再想一想。';}
    if(dirty||focusProtected){notice('已保留你的编辑；点击“重播”可重新观看流程。');return;}
    if(reduced){finalState();return;}
    running=true;origin=performance.now()-elapsed;playback();tick();
  }
  play.addEventListener('click',()=>running?stop():start(elapsed>=DURATION&&!dirty&&!focusProtected));
  $('#journey-replay').addEventListener('click',()=>start(true));$('#journey-voice').addEventListener('click',()=>running?stop():start(elapsed>=DURATION&&!dirty&&!focusProtected));
  [transcript,draft].forEach(e=>{e.addEventListener('focus',()=>stop(true));e.addEventListener('input',()=>{dirty=true;stop(true);});});
  copy.addEventListener('click',async()=>{
    stop();started=true;focusProtected=true;const ticket=++copyEpoch,value=plain(transcript);if(!value){notice('这里还没有文字。');return;}
    const ok=await writeClipboard(value);if(ticket!==copyEpoch)return;
    if(ok){buffer=value;copiedFeedback(true);scene.dataset.phase='copied';paste.classList.add('is-available');$('#journey-caption').textContent='已复制。点击输入框上的“粘贴”，试试下一步。';}
  });
  paste.addEventListener('click',()=>{
    stop();started=true;focusProtected=true;if(buffer===null){notice('先点击语音板上的复制。');return;}
    const a=draft.selectionStart??draft.value.length,b=draft.selectionEnd??a;draft.setRangeText(buffer,a,b,'end');dirty=true;scene.dataset.phase='ready';paste.classList.remove('is-available');$('#journey-draft-status').textContent='已粘贴，发送由你决定。';step(2,'文字已进入示例输入框，可以继续编辑。');
  });
  $('#journey-send').addEventListener('click',()=>{stop();notice('这是示例输入框，内容没有发送给任何服务。');});
  steps.forEach(b=>b.addEventListener('click',()=>{
    stop();started=true;if(dirty||focusProtected){notice('你的编辑已保留。点击“重播”可重新演示。');return;}
    const n=Number(b.dataset.journeyStep);if(n===0){start(true);return;}transcript.textContent=sample;draft.value='';autoPasted=false;
    if(n===1){buffer=null;autoCopied=false;elapsed=5200;copy.dataset.copied='false';$('#journey-copy-feedback').textContent='';}
    else{buffer=sample;autoCopied=true;copiedFeedback();elapsed=7300;}start();
  }));
  if(reduced)finalState();else{draft.value='';transcript.textContent='这个周末，想去看海。';paste.disabled=true;}
  new IntersectionObserver(es=>es.forEach(e=>{if(e.isIntersecting&&!started&&!document.hidden)start(true);else if(!e.isIntersecting&&running)stop();}),{threshold:.3}).observe(scene);
  playback();

  // Archive samples are isolated, editable in this page session, and never uploaded.
  const records=[
    {title:'等天气放晴。',date:'今天 14:06',group:'today',text:sample,first:'这个周末，想去看海。\n嗯，不赶时间。\n等天气放晴，在出发。',audio:'assets/archive-sea.m4a'},
    {title:'读到这里，想到一点。',date:'今天 10:18',group:'today',text:'读到这里，我想到一点。\n不是内容越多越好。\n是让重要的事，先被看见。',first:'读到这里，我想到一点。\n不是内容越多越好。',audio:'assets/archive-reading.m4a'},
    {title:'关于下一版。',date:'昨天 09:32',group:'older',text:'第一版，先把最直接的入口做好。\n打开以后，就应该能开始说。\n设置可以晚一点再出现。',first:'第一版，先把最直接的入口做好。\n打开以后，就应该能开始说。',audio:'assets/archive-next.m4a'},
    {title:'先把想法留下。',date:'更早 08:47',group:'older',text:'这个方案，先别急着定。\n下次评审，再一起看看。\n也许，还有更简单的做法。',first:'这个方案，先别急着定。\n下次评审，再一起看看。',audio:'assets/archive-thought.m4a'}
  ];
  let selected=0,tab='text',period='all',lastQuery='',rate=1;
  const editor=$('#archive-transcript'),audio=$('#archive-audio'),audioPlay=$('#archive-audio-play'),tabs=all('[data-content]'),recordButtons=all('.s9-record');
  const wave=$('#archive-wave');
  for(let i=0;i<52;i++){const bar=document.createElement('i');bar.style.height=(3+Math.abs(Math.sin(i*1.29)*Math.cos(i*.36))*19)+'px';wave.append(bar);}
  const bars=[...wave.children];
  function save(){if(tab==='text')records[selected].text=plain(editor);}
  function updateVersions(){ $('#archive-current-version').textContent=records[selected].text;$('#archive-first-version').textContent=records[selected].first;}
  function favoriteUI(){const y=!!records[selected].favorite;$('#archive-favorite').setAttribute('aria-pressed',String(y));$('#archive-favorite').setAttribute('aria-label',y?'取消收藏这段示例':'收藏这段示例');}
  function setTab(next){if(!['text','audio','history'].includes(next))return;save();tab=next;tabs.forEach(b=>{const active=b.dataset.content===next;b.setAttribute('aria-selected',String(active));b.tabIndex=active?0:-1;$('#archive-'+b.dataset.content+'-panel').hidden=!active;});updateVersions();}
  function selectRecord(index){if(index===selected)return;save();audio.pause();selected=index;editor.textContent=records[index].text;$('#archive-title').textContent=records[index].title;$('#archive-date').textContent=records[index].date;audio.src=records[index].audio;audio.playbackRate=rate;recordButtons.forEach(b=>{const a=Number(b.dataset.record)===index;b.classList.toggle('is-selected',a);b.setAttribute('aria-pressed',String(a));});favoriteUI();setTab('text');audioUI();}
  recordButtons.forEach(b=>b.addEventListener('click',()=>selectRecord(Number(b.dataset.record))));
  tabs.forEach((b,i)=>{b.addEventListener('click',()=>setTab(b.dataset.content));b.addEventListener('keydown',e=>{let n;if(e.key==='ArrowRight')n=(i+1)%tabs.length;else if(e.key==='ArrowLeft')n=(i+tabs.length-1)%tabs.length;else if(e.key==='Home')n=0;else if(e.key==='End')n=tabs.length-1;else return;e.preventDefault();tabs[n].focus();setTab(tabs[n].dataset.content);});});
  editor.addEventListener('input',()=>{save();$('#archive-save-state').innerHTML='<i></i> 本页修改已保留';});
  $('#archive-favorite').addEventListener('click',()=>{records[selected].favorite=!records[selected].favorite;favoriteUI();});
  $('#archive-edit').addEventListener('click',()=>{setTab('text');editor.focus();const r=document.createRange();r.selectNodeContents(editor);r.collapse(false);const s=getSelection();s.removeAllRanges();s.addRange(r);});
  $('#archive-versions').addEventListener('click',()=>setTab(tab==='history'?'text':'history'));
  $('#archive-copy').addEventListener('click',()=>{save();writeClipboard(records[selected].text);});
  function filterRecords(){save();const q=$('#archive-search').value.trim().toLocaleLowerCase();lastQuery=q;const found=[];recordButtons.forEach(b=>{const i=Number(b.dataset.record),r=records[i],ok=(period==='all'||period===r.group)&&(r.title+' '+r.text+' '+r.first).toLocaleLowerCase().includes(q);b.hidden=!ok;if(ok)found.push(i);});$('#archive-empty').hidden=found.length>0;$('#archive-reader').hidden=found.length===0;$('#archive-reader-empty').hidden=found.length>0;$('#archive-result').textContent=q?`找到 ${found.length} 段示例表达`:found.length+' 段示例表达';if(found.length&&!found.includes(selected))selectRecord(found[0]);if(!found.length)audio.pause();}
  $('#archive-search').addEventListener('input',filterRecords);$('#archive-search').addEventListener('keydown',e=>{if(e.key==='Escape'){$('#archive-search').value='';filterRecords();}});
  all('[data-period]').forEach(b=>b.addEventListener('click',()=>{period=b.dataset.period;all('[data-period]').forEach(x=>x.setAttribute('aria-pressed',String(x===b)));filterRecords();}));
  $('#archive-clear').addEventListener('click',()=>{$('#archive-search').value='';period='all';all('[data-period]').forEach(b=>b.setAttribute('aria-pressed',String(b.dataset.period==='all')));filterRecords();$('#archive-search').focus();});
  $('#archive-search-invite').addEventListener('click',()=>{period='all';all('[data-period]').forEach(b=>b.setAttribute('aria-pressed',String(b.dataset.period==='all')));$('#archive-search').value='看海';filterRecords();$('#archive-search').focus();});
  function clock(value){if(!Number.isFinite(value))value=0;return Math.floor(value/60)+':'+String(Math.floor(value%60)).padStart(2,'0');}
  function audioUI(){const playing=!audio.paused;audioPlay.querySelector('use').setAttribute('href',playing?'#i-pause':'#i-play');audioPlay.setAttribute('aria-label',playing?'暂停合成示例音频':'播放合成示例音频');$('#archive-audio-time').textContent=clock(audio.currentTime);const f=Number.isFinite(audio.duration)&&audio.duration>0?audio.currentTime/audio.duration:0;$('#archive-seek').value=String(f*100);bars.forEach((b,i)=>b.classList.toggle('is-played',i<f*bars.length));}
  audioPlay.addEventListener('click',async()=>{if(!audio.paused){audio.pause();return;}if(audio.ended)audio.currentTime=0;try{await audio.play();}catch(_){notice('暂时无法播放示例音频，文字仍然可用。');}});
  ['play','pause','timeupdate','ended','loadedmetadata'].forEach(e=>audio.addEventListener(e,audioUI));audio.addEventListener('error',()=>notice('示例音频未能加载，请稍后重试。'));
  $('#archive-seek').addEventListener('input',e=>{if(Number.isFinite(audio.duration)&&audio.duration>0)audio.currentTime=Number(e.target.value)/100*audio.duration;});
  $('#archive-speed').addEventListener('click',()=>{rate=rate===1?1.5:rate===1.5?2:1;audio.playbackRate=rate;$('#archive-speed').textContent=rate+'×';$('#archive-speed').setAttribute('aria-label','播放速度，当前 '+rate+' 倍速');});
  new IntersectionObserver(es=>es.forEach(e=>{if(!e.isIntersecting)audio.pause();}),{threshold:0}).observe($('#archive-demo'));
  const dialog=$('#native-dialog');$('#native-open').addEventListener('click',()=>dialog.showModal());$('#native-close').addEventListener('click',()=>dialog.close());dialog.addEventListener('close',()=>$('#native-open').focus({preventScroll:true}));dialog.addEventListener('click',e=>{if(e.target!==dialog)return;const r=dialog.getBoundingClientRect();if(e.clientX<r.left||e.clientX>r.right||e.clientY<r.top||e.clientY>r.bottom)dialog.close();});
  document.addEventListener('visibilitychange',()=>{if(document.hidden){stop();audio.pause();}});
  media.addEventListener('change',e=>{reduced=e.matches;if(reduced){stop();if(!dirty&&!focusProtected)finalState();}});
  updateVersions();
})();
