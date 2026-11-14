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
  function sourceSync(){ /* This independent section retains its own edited transcript. */ }
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

  if(!reduce){root.classList.add('r8-motion-ready');const enter=new IntersectionObserver(es=>es.forEach(e=>{if(e.isIntersecting){e.target.classList.add('is-seen');enter.unobserve(e.target);}}),{threshold:.1});$$('.r8-editorial,.r8-stage,.r8-fidelity').forEach(e=>{e.classList.add('r8-enter');enter.observe(e);});}
  document.addEventListener('visibilitychange',()=>{if(document.hidden){stop();settleProof();cancelAnimationFrame(pframe);pframe=0;}else if(!reduce&&!pframe)pframe=requestAnimationFrame(loop);});
  media.addEventListener('change',e=>{reduce=e.matches;if(reduce){stop(false);settleProof();cancelAnimationFrame(pframe);pframe=0;root.classList.remove('r8-motion-ready');draw(0);}else if(!pframe)pframe=requestAnimationFrame(loop);});
})();
