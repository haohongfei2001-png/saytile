'use strict';
(() => {
  const $ = (s) => document.querySelector(s);
  const reduced = matchMedia('(prefers-reduced-motion: reduce)').matches;
  const sceneTabs = [...document.querySelectorAll('.r4-scene-tabs button')];
  let toastTimer;
  function toast(message) { const el = $('#toast'); clearTimeout(toastTimer); el.textContent = message; el.classList.add('visible'); toastTimer = setTimeout(() => el.classList.remove('visible'), 2500); }
  function textOf(el) { return el.innerText.replace(/\u00a0/g, ' ').trim(); }
  function selectedOrAll(el) { const selection = getSelection(); return selection && selection.rangeCount && !selection.isCollapsed && el.contains(selection.anchorNode) && el.contains(selection.focusNode) ? selection.toString() : textOf(el); }
  async function copy(el) {
    const value = selectedOrAll(el); if (!value) { toast('这里还没有文字。'); return false; }
    try { await navigator.clipboard.writeText(value); toast('文字已复制，粘贴到你需要的地方。'); return true; }
    catch { toast('浏览器未允许复制。请选中文字后复制。'); return false; }
  }
  const scenes = {
    write: { menu:'文稿', title:'下一版，先从这里开始', body:'<p class="r4-document-eyebrow">工作札记 / 07</p><h3>把开始，<br>留给表达。</h3><p class="r4-document-intro">一个好用的入口，不应该让人先学会使用。</p><div class="r4-document-rule"></div><h4>先做好最简单的那一步</h4><p>第一次打开，眼前就应该是可以开始的地方。<br>减少准备，少一点打断，让注意力留在想法上。</p><p>至于更复杂的选项，可以等真正需要时再出现。</p><div class="r4-context-caret" aria-hidden="true"></div>', chunks:['第一版，先把最直接的入口做好。','\n\n打开以后，就应该能开始说。','设置可以晚一点再出现。','\n\n嗯，先把这个想法留下来。'] },
    read: { menu:'阅读', title:'读到这里，想到一点', body:'<p class="r4-document-eyebrow">阅读摘记 / 12</p><h3>留一点空白，<br>才听得见想法。</h3><p class="r4-document-intro">关于注意力、选择，以及那些暂时不做的事。</p><div class="r4-document-rule"></div><p>我们常常把更多，误认为更好。</p><p class="r4-article-quote">真正重要的，<br>往往需要更少的打扰。</p><p>停下来想一想，也是一种继续。</p>', chunks:['读到这里，我想到一点。','\n\n不是内容越多越好。','是让重要的事，先被看见。','\n\n这一点，可以放进明天的方案里。'] },
    ai: { menu:'对话', title:'准备一个更清楚的问题', body:'<p class="r4-document-eyebrow">一段新的对话</p><h3>先把问题，<br>讲清楚。</h3><p class="r4-document-intro">背景、限制，还有你真正想解决的事。</p><div class="r4-document-rule"></div><p>让回答从理解你的处境开始。</p><p class="r4-ai-prompt">这里是另一个应用的草稿。<br><br>文字准备好以后，再由你复制过去。</p>', chunks:['帮我看看这个方案。','\n\n先别急着给结论。','我想知道，第一次使用的人会在哪一步卡住。','\n\n也看看，有没有更简单的做法。'] }
  };
  const workText = $('#r4-work-text'), workPanel = $('#r4-work-panel');
  let scene = 'write', workIndex = 1, workTimer = null, workStarted = false, workRunning = false, workEdited = false, sceneCache = new Map();
  function workState(state, caption) { workPanel.dataset.state = state; $('#r4-side-status').textContent = caption; const b = $('#r4-work-toggle'); b.setAttribute('aria-pressed', String(state === 'paused')); b.setAttribute('aria-label', state === 'paused' ? '继续场景演示' : '暂停场景演示'); }
  function stopWork(state='paused') { clearTimeout(workTimer); workTimer = null; workRunning = false; workState(state, state === 'paused' ? '已暂停，文字仍在' : '在一旁，等你开口'); }
  function stepWork() {
    if (!workRunning || document.hidden) return;
    if (workEdited) { stopWork(); return; }
    if (workIndex >= scenes[scene].chunks.length) { stopWork('standby'); return; }
    workState('speaking','你继续，文字也继续');
    const span = document.createElement('span'); span.className='r4-chunk'; span.textContent = scenes[scene].chunks[workIndex++]; workText.append(span); workText.parentElement.scrollTop = workText.parentElement.scrollHeight;
    workTimer = setTimeout(() => { if (!workRunning) return; workState('standby','停一下，也不用结束'); workTimer = setTimeout(stepWork, 950); }, 1450);
  }
  function playWork() {
    workStarted = true;
    if (workEdited) { workState('standby','保留你编辑后的文字'); return; }
    if (reduced) { workText.textContent = scenes[scene].chunks.join(''); workIndex = scenes[scene].chunks.length; stopWork('standby'); return; }
    if (workIndex >= scenes[scene].chunks.length) { stopWork('standby'); return; }
    clearTimeout(workTimer); workRunning = true; workState('speaking','你继续，文字也继续'); workTimer = setTimeout(stepWork, 1100);
  }
  function resetWork() { stopWork(); workEdited = false; workIndex = 1; workText.textContent = scenes[scene].chunks[0]; sceneCache.delete(scene); playWork(); }
  function selectScene(next) {
    if (!scenes[next] || next === scene) return;
    sceneCache.set(scene,{text:textOf(workText),edited:workEdited,index:workIndex}); stopWork(); scene=next;
    $('#r4-desktop').dataset.scene = scene; $('#r4-desktop').setAttribute('aria-labelledby','r4-tab-'+scene); $('#r4-menu-app').textContent = scenes[scene].menu; $('#r4-window-title').textContent = scenes[scene].title; $('#r4-context').innerHTML = scenes[scene].body;
    sceneTabs.forEach(b => { const current=b.dataset.scene===scene; b.setAttribute('aria-selected',String(current)); b.tabIndex=current?0:-1; });
    const cached=sceneCache.get(scene); workEdited=!!cached?.edited; workIndex=cached?.edited?cached.index:1; workText.textContent=cached?.edited?cached.text:scenes[scene].chunks[0]; playWork();
  }
  sceneTabs.forEach((b,index) => { b.addEventListener('click',()=>selectScene(b.dataset.scene)); b.addEventListener('keydown',e=>{ let i; if(e.key==='ArrowRight')i=(index+1)%sceneTabs.length;else if(e.key==='ArrowLeft')i=(index+sceneTabs.length-1)%sceneTabs.length;else if(e.key==='Home')i=0;else if(e.key==='End')i=sceneTabs.length-1;else return;e.preventDefault();sceneTabs[i].focus();selectScene(sceneTabs[i].dataset.scene); }); });
  $('#r4-work-replay').addEventListener('click',resetWork);
  $('#r4-work-toggle').addEventListener('click',()=>{if(workPanel.dataset.state==='paused')playWork();else stopWork();});
  $('#r4-work-copy').addEventListener('click',()=>copy(workText));
  workText.addEventListener('focusin',()=>stopWork()); workText.addEventListener('input',()=>{workEdited=true;stopWork();});
  const workObserver=new IntersectionObserver(entries=>{entries.forEach(e=>{if(e.isIntersecting&&!workStarted)playWork();else if(!e.isIntersecting&&workRunning)stopWork();});},{threshold:.3});workObserver.observe($('#r4-desktop'));

  const clauses=[...document.querySelectorAll('.r4-clause')], correction=$('#r4-correction');
  let correctionTimer=null,correctionIndex=0,correctionRunning=false,correctionStarted=false;
  const correctionSteps=[
    ()=>{clauses[0].classList.remove('is-pending');$('#r4-correction-status').textContent='自然说，语气也留下。';},
    ()=>clauses[1].classList.remove('is-pending'),
    ()=>{clauses[2].classList.remove('is-pending');correction.textContent='平审';},
    ()=>{clauses[3].classList.remove('is-pending');$('#r4-correction-status').textContent='继续表达，同一份文字持续核对。';},
    ()=>{correction.textContent='评审';correction.classList.add('is-correcting');$('#r4-correction-status').textContent='「平审」→「评审」，只在原处修正。';},
    ()=>{correction.classList.remove('is-correcting');$('#r4-correction-status').textContent='你的停顿与语气，也留在原话里。';}
  ];
  function correctionLabel(playing){const b=$('#r4-correct-toggle');b.setAttribute('aria-label',playing?'暂停原位修正演示':'继续原位修正演示');b.querySelector('use').setAttribute('href',playing?'#i-pause':'#i-play');}
  function stopCorrection(){clearTimeout(correctionTimer);correctionTimer=null;correctionRunning=false;correctionLabel(false);}
  function showFinal(){clauses.forEach(c=>c.classList.remove('is-pending'));correction.textContent='评审';correction.classList.remove('is-correcting');correctionIndex=correctionSteps.length;stopCorrection();$('#r4-correction-status').textContent='你的停顿与语气，也留在原话里。';}
  function correctionTick(){if(!correctionRunning||document.hidden)return;if(correctionIndex>=correctionSteps.length){stopCorrection();return;}correctionSteps[correctionIndex++]();correctionTimer=setTimeout(correctionTick,correctionIndex===5?1700:1100);}
  function playCorrection(restart=false){stopCorrection();correctionStarted=true;if(reduced){showFinal();return;}if(restart||correctionIndex>=correctionSteps.length){correctionIndex=0;clauses.forEach(c=>c.classList.add('is-pending'));correction.textContent='评审';correction.classList.remove('is-correcting');}correctionRunning=true;correctionLabel(true);correctionTimer=setTimeout(correctionTick,250);}
  $('#r4-correct-replay').addEventListener('click',()=>playCorrection(true));$('#r4-correct-toggle').addEventListener('click',()=>correctionRunning?stopCorrection():playCorrection());
  new IntersectionObserver(entries=>entries.forEach(e=>{if(e.isIntersecting&&!correctionStarted)playCorrection(true);else if(!e.isIntersecting&&correctionRunning)stopCorrection();}),{threshold:.4}).observe($('#r4-manuscript'));

  const audio=$('#r4-original-audio'), archiveAudio=$('#r4-record-audio'), wave=$('#r4-original-wave');
  const amplitudes=window.SAYTILE_WAVE||Array.from({length:72},(_,i)=>.15+Math.abs(Math.sin(i*1.7)*Math.cos(i*.36))*.8);
  amplitudes.forEach(v=>{const i=document.createElement('i');i.style.height=(4+v*27).toFixed(1)+'px';wave.append(i);});
  const bars=[...wave.children];
  function clock(t){if(!Number.isFinite(t))t=0;return Math.floor(t/60)+':'+String(Math.floor(t%60)).padStart(2,'0');}
  function originalUI(){const playing=!audio.paused;$('#r4-original-play use').setAttribute('href',playing?'#i-pause':'#i-play');$('#r4-original-play').setAttribute('aria-label',playing?'暂停合成示例原音':'播放合成示例原音');$('#r4-original-time').textContent=clock(audio.currentTime);const p=Number.isFinite(audio.duration)&&audio.duration>0?audio.currentTime/audio.duration:0;$('#r4-original-seek').value=String(p*100);bars.forEach((b,i)=>b.classList.toggle('is-played',i<Math.floor(p*bars.length)));}
  function archiveUI(){const playing=!archiveAudio.paused;$('#r4-record-play use').setAttribute('href',playing?'#i-pause':'#i-play');$('#r4-record-play').setAttribute('aria-label',playing?'暂停此档案的合成示例原音':'播放此档案的合成示例原音');$('#r4-record-time').textContent=clock(archiveAudio.currentTime);}
  async function toggleAudio(player){if(!player.paused){player.pause();return;}if(player.ended)player.currentTime=0;[audio,archiveAudio].filter(p=>p!==player).forEach(p=>p.pause());if(player===audio){stopCorrection();showFinal();}try{await player.play();}catch{toast('暂时无法播放示例音频。文字仍可使用。');}}
  $('#r4-original-play').addEventListener('click',()=>toggleAudio(audio));$('#r4-record-play').addEventListener('click',()=>toggleAudio(archiveAudio));
  ['timeupdate','play','pause','ended','loadedmetadata'].forEach(e=>{audio.addEventListener(e,originalUI);archiveAudio.addEventListener(e,archiveUI);});
  $('#r4-original-seek').addEventListener('input',e=>{if(Number.isFinite(audio.duration))audio.currentTime=Number(e.target.value)*audio.duration/100;});
  [audio,archiveAudio].forEach(p=>p.addEventListener('error',()=>toast('示例音频未能加载，请稍后重试。')));

  const records=[
    {title:'下一版的入口',date:'今天　14:06',text:'第一版，先把最直接的入口做好。\n\n打开以后，就应该能开始说。设置可以晚一点再出现。\n\n嗯，先把这个想法留下来。明天再接着想。',audio:'assets/archive-0.m4a'},
    {title:'读到这里，想到一点',date:'今天　10:18',text:'读到这里，我想到一点。\n\n不是内容越多越好。是让重要的事，先被看见。\n\n这一点，可以放进明天的方案里。',audio:'assets/archive-1.m4a'},
    {title:'还没想完的问题',date:'昨天　21:32',text:'这个方案，嗯，先别急着定。\n\n下次评审，我们再一起看看。',audio:'assets/original-demo.m4a'}
  ];
  let selected=0;const recordText=$('#r4-record-text');
  function chooseRecord(index){if(index===selected)return;records[selected].text=textOf(recordText);selected=index;archiveAudio.pause();archiveAudio.src=records[index].audio;archiveUI();$('#r4-record-date').textContent=records[index].date;$('#r4-record-title').textContent=records[index].title;recordText.textContent=records[index].text;document.querySelectorAll('.r4-record').forEach(b=>{const yes=Number(b.dataset.record)===index;b.classList.toggle('is-selected',yes);b.setAttribute('aria-pressed',String(yes));});}
  document.querySelectorAll('.r4-record').forEach(b=>b.addEventListener('click',()=>chooseRecord(Number(b.dataset.record))));
  function filterRecords(){records[selected].text=textOf(recordText);const q=$('#r4-search').value.trim().toLocaleLowerCase();let count=0,first=null;document.querySelectorAll('.r4-record').forEach(b=>{const i=Number(b.dataset.record),visible=(records[i].title+' '+records[i].text).toLocaleLowerCase().includes(q);b.hidden=!visible;if(visible){count++;if(first===null)first=i;}});$('#r4-result-count').textContent=String(count);$('#r4-no-results').hidden=count>0;if(q&&first!==null&&!((records[selected].title+' '+records[selected].text).toLocaleLowerCase().includes(q)))chooseRecord(first);}
  $('#r4-search').addEventListener('input',filterRecords);$('#r4-search').addEventListener('keydown',e=>{if(e.key==='Escape'){$('#r4-search').value='';filterRecords();}});$('#r4-clear-search').addEventListener('click',()=>{$('#r4-search').value='';filterRecords();$('#r4-search').focus();});
  recordText.addEventListener('input',()=>{records[selected].text=textOf(recordText);});
  $('#r4-record-copy').addEventListener('click',async()=>{if(await copy(recordText)){const label=$('#r4-record-copy span');label.textContent='已复制';setTimeout(()=>label.textContent='复制这段话',1800);}});

  if(!reduced&&'IntersectionObserver'in window){document.documentElement.classList.add('r4-motion');const observer=new IntersectionObserver(entries=>entries.forEach(e=>{if(e.isIntersecting){e.target.classList.add('is-visible');observer.unobserve(e.target);}}),{threshold:.1});document.querySelectorAll('.r4-enter').forEach(e=>observer.observe(e));}
  new IntersectionObserver(entries=>entries.forEach(e=>{if(!e.isIntersecting){if(e.target.id==='r4-manuscript')audio.pause();if(e.target.id==='r4-library')archiveAudio.pause();}}),{threshold:0}).observe($('#r4-manuscript'));
  const archiveObserver=new IntersectionObserver(entries=>entries.forEach(e=>{if(!e.isIntersecting)archiveAudio.pause();}),{threshold:0});archiveObserver.observe($('#r4-library'));
  document.addEventListener('visibilitychange',()=>{if(document.hidden){stopWork();stopCorrection();audio.pause();archiveAudio.pause();}});
})();
