'use strict';
(() => {
  const root=document.querySelector('.r8'); if(!root)return;
  const $=s=>root.querySelector(s), $$=s=>[...root.querySelectorAll(s)];
  const media=matchMedia('(prefers-reduced-motion: reduce)');let reduce=media.matches;
  const initial='这个周末，想去看海。\n嗯，不赶时间。',addition='\n等天气放晴，再出发。',complete=initial+addition;
  const stage=$('#voice-stage'),panel=$('#voice-panel'),editor=$('#voice-text'),play=$('#voice-play');
  let toastTimer;
  function notice(message){const n=document.getElementById('toast');if(!n)return;clearTimeout(toastTimer);n.textContent=message;n.classList.add('visible');toastTimer=setTimeout(()=>n.classList.remove('visible'),2300);}
  const read=e=>e.innerText.replace(/\u00a0/g,' ').trim();
  async function copy(value){if(!value.trim()){notice('这里还没有文字。');return false;}try{await navigator.clipboard.writeText(value);notice('文字已复制。');return true;}catch(_){const active=document.activeElement,sel=getSelection(),range=sel?.rangeCount?sel.getRangeAt(0).cloneRange():null;const f=document.createElement('textarea');f.value=value;f.readOnly=true;f.style.cssText='position:fixed;left:-10000px;top:0;opacity:0';document.body.append(f);f.select();let ok=false;try{ok=document.execCommand('copy');}catch(_){}f.remove();active?.focus({preventScroll:true});if(range&&sel){sel.removeAllRanges();sel.addRange(range);}notice(ok?'文字已复制。':'请选中文字后复制。');return ok;}}
  let running=false,started=false,edited=false,elapsed=0,origin=0,clock=0,phase=-1,finished=false,autoAllowed=true;
  const phases=$$('[data-phase]');
  function phaseUI(n){if(phase===n)return;phase=n;phases.forEach(b=>b.setAttribute('aria-pressed',String(Number(b.dataset.phase)===n)));}
  function state(value,label){if(stage.dataset.state!==value)stage.dataset.state=panel.dataset.state=value;const n=$('#voice-status');if(n.textContent!==label)n.textContent=label;$('#voice-toggle').setAttribute('aria-label',value==='paused'?'继续口述演示':'暂停口述演示');}
  function playerUI(){play.querySelector('use').setAttribute('href',running?'#i-pause':'#i-play');play.setAttribute('aria-label',running?'暂停演示':finished&&!edited?'重播演示':'播放演示');}
  function sourceSync(){ $('#source-text').textContent=edited?read(editor):(read(editor)||complete); }
  function stop(show=true){if(running)elapsed=Math.min(performance.now()-origin,12300);running=false;clearTimeout(clock);clock=0;playerUI();if(show)state('paused',edited?'你的修改已保留。':'演示已暂停。');}
  function displayValue(value){const old=read(editor);if(old===value.trim())return;const near=editor.parentElement.scrollHeight-editor.parentElement.scrollTop-editor.parentElement.clientHeight<28;if(value.startsWith(editor.textContent)){const s=document.createElement('span');s.className='r8-incoming';s.textContent=value.slice(editor.textContent.length);editor.append(s);}else editor.textContent=value;if(near&&document.activeElement!==editor)editor.parentElement.scrollTop=editor.parentElement.scrollHeight;}
  function tick(){if(!running||document.hidden||edited)return;elapsed=performance.now()-origin;const t=elapsed;$('#voice-progress').style.transform=`scaleX(${Math.min(t/12300,1)})`;
    if(t<3900){phaseUI(0);state('speaking','正在听你说。');displayValue(initial.slice(0,Math.max(1,Math.floor(t/125))));}
    else if(t<6600){phaseUI(1);displayValue(initial);state('standby','停一会儿，也不用结束。');}
    else if(t<10700){phaseUI(2);state('speaking','接着说，思路还在原处。');displayValue(initial+addition.slice(0,Math.max(0,Math.floor((t-6600)/155))));}
    else{displayValue(complete);state('standby','等你下一句。');}
    if(t>=12300){finished=true;elapsed=12300;stop(false);sourceSync();return;}clock=setTimeout(tick,70);
  }
  function start(reset=false){stop(false);started=true;if(reset){edited=false;finished=false;elapsed=0;phase=-1;editor.textContent='';}if(edited){state('paused','你的修改已保留。');return;}if(reduce){editor.textContent=complete;elapsed=12300;finished=true;phaseUI(2);state('standby','等你下一句。');$('#voice-progress').style.transform='scaleX(1)';sourceSync();return;}if(finished&&!reset){state('standby','等你下一句。');return;}running=true;origin=performance.now()-elapsed;playerUI();tick();}
  play.addEventListener('click',()=>running?stop():start(finished&&!edited));
  $('#voice-replay').addEventListener('click',()=>start(true));
  $('#voice-toggle').addEventListener('click',()=>panel.dataset.state==='paused'?start():stop());
  phases.forEach(b=>b.addEventListener('click',()=>{started=true;stop(false);const n=Number(b.dataset.phase);phaseUI(n);if(edited){state('paused','你的修改已保留。');return;}if(n===0){elapsed=0;finished=false;start(true);}else if(n===1){if(!read(editor))editor.textContent=initial;elapsed=Math.max(elapsed,3900);state('standby','停一会儿，也不用结束。');}else{if(read(editor).includes('等天气放晴，再出发。')){finished=true;elapsed=12300;state('standby','等你下一句。');sourceSync();playerUI();return;}elapsed=6600;finished=false;if(!read(editor))editor.textContent=initial;start();}}));
  editor.addEventListener('focus',()=>{started=true;stop();});editor.addEventListener('input',()=>{edited=true;stop();sourceSync();});
  $('#voice-copy').addEventListener('click',async()=>{const s=getSelection(),selected=s&&!s.isCollapsed&&editor.contains(s.anchorNode)&&editor.contains(s.focusNode);if(await copy(selected?s.toString():read(editor))){$('#voice-copy').dataset.copied='true';setTimeout(()=>delete $('#voice-copy').dataset.copied,1500);}});
  new IntersectionObserver(es=>es.forEach(e=>{autoAllowed=e.isIntersecting;if(e.isIntersecting&&!started&&!document.hidden)start(true);else if(!e.isIntersecting&&running)stop();}),{threshold:.38}).observe(stage);
  if(reduce){editor.textContent=complete;phaseUI(2);$('#voice-progress').style.transform='scaleX(1)';}
  playerUI();
  if(matchMedia('(pointer:fine)').matches){let f=0;stage.addEventListener('pointermove',e=>{if(reduce)return;const r=stage.getBoundingClientRect();cancelAnimationFrame(f);f=requestAnimationFrame(()=>{stage.style.setProperty('--mx',((e.clientX-r.left)/r.width*2-1).toFixed(3));stage.style.setProperty('--my',((e.clientY-r.top)/r.height*2-1).toFixed(3));});});stage.addEventListener('pointerleave',()=>{cancelAnimationFrame(f);stage.style.setProperty('--mx',0);stage.style.setProperty('--my',0);});}
  // The small point field is a graphic visualization, not an audio recording.
  const canvas=$('#voice-particles'),cx=canvas.getContext('2d');let W=0,H=0,pframe=0,last=0,amp=.18;
  function size(){const r=stage.getBoundingClientRect();W=r.width;H=r.height;const d=Math.min(devicePixelRatio||1,2);canvas.width=Math.round(W*d);canvas.height=Math.round(H*d);cx.setTransform(d,0,0,d,0,0);draw(0);}
  function draw(t){if(!cx||!W)return;cx.clearRect(0,0,W,H);const target=stage.dataset.state==='speaking'?.88:.16;amp+=(target-amp)*.1;const time=reduce?1:t/1200;
    for(let i=0;i<67;i++){const x=W*(.07+i/66*.87),u=i/66,env=Math.pow(Math.sin(u*Math.PI),1.6);for(let j=0;j<7;j++){const v=(j-3)/3,drift=Math.sin(u*7.8+time)*amp*env*24;const y=H*(.735+Math.sin(u*4.3)*.032)+drift+v*(6+amp*18)*env;const a=env*(.18+.1*(1-Math.abs(v)))*(stage.dataset.state==='speaking'?1.5:1);const hue=u<.4?282:220;cx.fillStyle=`hsla(${hue}, ${u<.4?36:40}%, 66%, ${a})`;cx.beginPath();cx.arc(x,y,.6+env*.45,0,Math.PI*2);cx.fill();}}
  }
  function loop(t){if(document.hidden||reduce){pframe=0;return;}if(autoAllowed&&t-last>32){draw(t);last=t;}pframe=requestAnimationFrame(loop);}
  new ResizeObserver(size).observe(stage);size();if(!reduce)pframe=requestAnimationFrame(loop);

  let corrections=[],proofUsed=false;const word=$('#corrected-sample');
  function settleProof(){corrections.forEach(clearTimeout);corrections=[];word.textContent='再';delete word.dataset.fixing;}
  function correct(){settleProof();proofUsed=true;if(reduce)return;word.textContent='在';corrections.push(setTimeout(()=>{word.textContent='再';word.dataset.fixing='true';},1000));corrections.push(setTimeout(()=>delete word.dataset.fixing,2700));}
  $('#correction-replay').addEventListener('click',correct);new IntersectionObserver(es=>es.forEach(e=>{if(e.isIntersecting&&!proofUsed)correct();if(!e.isIntersecting)settleProof();}),{threshold:.7}).observe($('#fidelity-demo'));

  const handoff=$('#handoff-scene'),draft=$('#draft-text'),take=$('#take-action'),paste=$('#paste-sample'),tabs=$$('.r8-mode-switch [data-mode]');
  let mode='copy',copied=null,bound=false,before='',caret=0,sequence=0,ticket=0,used=false,demonstrated=false,pasting=false;
  const newPhrases=['对了，记得带相机。','出发时间，明天再定。'];
  function protect(){ticket++;used=true;}
  function label(s,icon='#i-copy'){take.querySelector('span').textContent=s;take.querySelector('use').setAttribute('href',icon);}
  function release(msg='请先选择示例草稿。'){bound=false;handoff.dataset.bound='false';if(mode==='direct'){label('选择示例草稿','#i-plus');$('#target-status').textContent=msg;$('#draft-status').textContent='尚未选定目标';}}
  function changeMode(next){if(!['copy','direct'].includes(next))return;protect();mode=next;handoff.dataset.mode=next;tabs.forEach(b=>{const yes=b.dataset.mode===next;b.setAttribute('aria-selected',String(yes));b.tabIndex=yes?0:-1;});$('#mode-content').setAttribute('aria-labelledby',next+'-tab');bound=false;handoff.dataset.bound='false';paste.hidden=next==='direct';paste.disabled=!copied;
    if(next==='copy'){label('复制这段话');$('#take-note').textContent='你的修改，也一起带走。';$('#target-status').textContent='下一步，由你。';$('#draft-status').textContent='继续编辑，或直接取用。';}else{$('#take-note').textContent='只在本网页草稿中演示；新话追加，旧文不重发。';release();}}
  tabs.forEach((b,i)=>{b.addEventListener('click',()=>changeMode(b.dataset.mode));b.addEventListener('keydown',e=>{let n;if(e.key==='ArrowRight'||e.key==='ArrowLeft')n=1-i;else if(e.key==='Home')n=0;else if(e.key==='End')n=1;else return;e.preventDefault();tabs[n].focus();changeMode(tabs[n].dataset.mode);});});
  draft.addEventListener('focus',protect);draft.addEventListener('input',()=>{protect();if(bound)release('草稿已修改，请重新选择。');});draft.addEventListener('pointerup',()=>{if(bound&&(draft.selectionStart!==caret||draft.selectionEnd!==caret))release('光标已变化，请重新选择。');});
  function fly(value,done){if(reduce){done();return;}const from=$('#source-text').getBoundingClientRect(),to=draft.getBoundingClientRect(),ghost=document.createElement('div');ghost.className='r8-travel-text';ghost.textContent=value;Object.assign(ghost.style,{left:from.left+'px',top:from.top+'px',width:Math.min(from.width,350)+'px'});document.body.append(ghost);const dx=to.left-from.left+7,dy=to.top-from.top+18;const a=ghost.animate([{opacity:0,transform:'translate(0,0) scale(.96) rotate(-2deg)'},{offset:.2,opacity:.82},{offset:.68,opacity:.76,transform:`translate(${dx*.7}px,${dy*.45-25}px) scale(.93) rotate(-1deg)`},{opacity:0,transform:`translate(${dx}px,${dy}px) scale(.9) rotate(0deg)`}],{duration:1000,easing:'cubic-bezier(.22,.7,.25,1)'});a.finished.catch(()=>{}).then(()=>{ghost.remove();done();});}
  take.addEventListener('click',async()=>{protect();if(mode==='copy'){const value=read($('#source-text'));if(await copy(value)){copied=value;paste.disabled=false;label('已复制');$('#target-status').textContent='点「粘贴示例」，把文字放进草稿。';setTimeout(()=>{if(mode==='copy')label('复制这段话');},1600);}return;}
    if(!bound){draft.focus({preventScroll:true});bound=true;before=draft.value;caret=draft.value.length;draft.setSelectionRange(caret,caret);handoff.dataset.bound='true';label('继续一句新话','#i-voice');$('#target-status').textContent='已选择本页的示例草稿';$('#draft-status').textContent='只追加接下来的新话';return;}
    if(draft.value!==before||draft.selectionStart!==caret||draft.selectionEnd!==caret){release('草稿或光标已变化，请重新选择。');return;}
    draft.focus({preventScroll:true});const v=(before?'\n':'')+newPhrases[sequence++%newPhrases.length];draft.setRangeText(v,caret,caret,'end');before=draft.value;caret=before.length;draft.setSelectionRange(caret,caret);handoff.dataset.delivered='true';$('#draft-status').textContent='新话已追加，原文保留。';if(!reduce)draft.animate([{opacity:.45},{opacity:1}],{duration:450});
  });
  paste.addEventListener('click',()=>{if(!copied||mode!=='copy'||pasting)return;protect();const token=ticket,value=copied,old=draft.value,a=draft.selectionStart,b=draft.selectionEnd;pasting=true;paste.disabled=true;fly(value,()=>{pasting=false;paste.disabled=!copied;if(token!==ticket||mode!=='copy')return;if(draft.value!==old)return;draft.setRangeText(value,a,b,'end');handoff.dataset.delivered='true';$('#draft-status').textContent='文字已进入示例草稿';$('#target-status').textContent='继续编辑，发送由你。';});});
  $('#reset-draft').addEventListener('click',()=>{protect();draft.value='';copied=null;bound=false;pasting=false;sequence=0;handoff.dataset.delivered='false';changeMode(mode);});
  if(!reduce){draft.value='';handoff.dataset.delivered='false';}
  new IntersectionObserver(es=>es.forEach(e=>{if(!e.isIntersecting||demonstrated)return;demonstrated=true;if(used||reduce)return;const token=++ticket;setTimeout(()=>{if(token!==ticket||used)return;fly(read($('#source-text')),()=>{if(token!==ticket||used)return;draft.value=read($('#source-text'));handoff.dataset.delivered='true';$('#draft-status').textContent='取用过程演示';});},500);}),{threshold:.55}).observe(handoff);

  const records=[
    {title:'等天气放晴。',date:'今天 · 14:06',text:complete,prior:'这个周末，想去看海。\n嗯，不赶时间。\n等天气放晴，在出发。'},
    {title:'留一点空白。',date:'昨天 · 10:18',text:'读到这里，想到一点。\n不是内容越多越好。\n是让重要的事，先被看见。',prior:'读到这里，想到一点。\n不是内容越多越好。'},
    {title:'先别急着定。',date:'更早 · 21:32',text:'这个方案，嗯，先别急着定。\n下次评审，再一起看看。\n也许，还有更简单的做法。',prior:'这个方案，嗯，先别急着定。\n下次评审，再一起看看。'}
  ];
  let selected=0,history=false,cardAnimation=null,cardTimer=null;const record=$('#record-text'),version=$('#version-toggle'),visual=$('#memory-visual');
  function saveRecord(){if(!history)records[selected].text=read(record);}
  function showRecord(n){if(n===selected&&!history)return;saveRecord();selected=n;history=false;record.contentEditable='plaintext-only';record.textContent=records[n].text;$('#record-title').textContent=records[n].title;$('#record-date').textContent=records[n].date;version.setAttribute('aria-pressed','false');version.querySelector('span').textContent='文字版本';$$('[data-record]').forEach(b=>b.setAttribute('aria-pressed',String(Number(b.dataset.record)===n)));cardAnimation?.cancel();clearTimeout(cardTimer);if(!reduce){visual.dataset.switching='true';cardAnimation=$('#record-card').animate([{opacity:.25,transform:'translate(14px,12px) rotate(1.6deg)'},{opacity:1,transform:'translate(0,0) rotate(-1deg)'}],{duration:650,easing:'cubic-bezier(.18,.8,.24,1)'});cardTimer=setTimeout(()=>delete visual.dataset.switching,700);}}
  $$('[data-record]').forEach(b=>b.addEventListener('click',()=>showRecord(Number(b.dataset.record))));record.addEventListener('input',saveRecord);
  version.addEventListener('click',()=>{saveRecord();history=!history;version.setAttribute('aria-pressed',String(history));version.querySelector('span').textContent=history?'返回当前文字':'文字版本';record.contentEditable=history?'false':'plaintext-only';record.textContent=history?records[selected].prior:records[selected].text;if(!reduce)record.animate([{opacity:.2},{opacity:1}],{duration:400});});
  $('#record-copy').addEventListener('click',()=>copy(read(record)));
  $('#memory-search').addEventListener('input',()=>{saveRecord();const q=$('#memory-search').value.trim().toLocaleLowerCase();const matches=[];$$('[data-record]').forEach(b=>{const i=Number(b.dataset.record),yes=(records[i].title+' '+records[i].text+' '+records[i].prior).toLocaleLowerCase().includes(q);b.hidden=!yes;if(yes)matches.push(i);});$('#search-status').textContent=q?(matches.length?`找到 ${matches.length} 段示例表达。`:'没有匹配的示例，换一个词试试。'):'三个示例，随手翻一翻。';if(matches.length&&!matches.includes(selected))showRecord(matches[0]);$('#record-card').style.opacity=matches.length?'1':'.32';version.disabled=!matches.length;$('#record-copy').disabled=!matches.length;});
  const dialog=$('#native-dialog');$('#native-open').addEventListener('click',()=>dialog.showModal());$('#native-close').addEventListener('click',()=>dialog.close());dialog.addEventListener('close',()=>$('#native-open').focus({preventScroll:true}));dialog.addEventListener('click',e=>{if(e.target!==dialog)return;const r=dialog.getBoundingClientRect();if(e.clientX<r.left||e.clientX>r.right||e.clientY<r.top||e.clientY>r.bottom)dialog.close();});
  if(!reduce){root.classList.add('r8-motion-ready');const enter=new IntersectionObserver(es=>es.forEach(e=>{if(e.isIntersecting){e.target.classList.add('is-seen');enter.unobserve(e.target);}}),{threshold:.1});$$('.r8-editorial,.r8-stage,.r8-fidelity,.r8-section-head,.r8-handoff,.r8-memory-copy,.r8-memory-visual,.r8-coda').forEach(e=>{e.classList.add('r8-enter');enter.observe(e);});}
  document.addEventListener('visibilitychange',()=>{if(document.hidden){stop();settleProof();release('页面离开后，请重新选择示例草稿。');cancelAnimationFrame(pframe);pframe=0;protect();}else if(!reduce&&!pframe)pframe=requestAnimationFrame(loop);});
  media.addEventListener('change',e=>{reduce=e.matches;if(reduce){stop(false);settleProof();cancelAnimationFrame(pframe);pframe=0;root.classList.remove('r8-motion-ready');draw(0);}else if(!pframe)pframe=requestAnimationFrame(loop);});
})();
