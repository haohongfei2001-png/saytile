'use strict';
(() => {
  const root = document.querySelector('.s6');
  if (!root) return;
  const $ = selector => root.querySelector(selector);
  const all = selector => [...root.querySelectorAll(selector)];
  const reduceQuery = matchMedia('(prefers-reduced-motion: reduce)');
  let reduced = reduceQuery.matches;
  const first = '这个周末，想去看海。\n嗯，不赶时间。';
  const final = first + '\n等天气放晴，再出发。';
  let toastTimer;
  function notify(message) {
    const box = document.getElementById('toast');
    if (!box) return;
    clearTimeout(toastTimer); box.textContent = message; box.classList.add('visible');
    toastTimer = setTimeout(() => box.classList.remove('visible'), 2400);
  }
  function plain(element) { return element.innerText.replace(/\u00a0/g, ' ').trim(); }
  async function copyText(value) {
    if (!value.trim()) { notify('这里还没有文字。'); return false; }
    try {
      await navigator.clipboard.writeText(value);
      notify('文字已复制。'); return true;
    } catch (_) {
      // Use a temporary field only after an explicit copy action. Never read the clipboard.
      const active = document.activeElement, selection = getSelection();
      const range = selection && selection.rangeCount ? selection.getRangeAt(0).cloneRange() : null;
      const field = document.createElement('textarea');
      field.value = value; field.readOnly = true; field.style.cssText = 'position:fixed;left:-10000px;top:0;opacity:0';
      document.body.append(field); field.select();
      let ok = false;
      try { ok = document.execCommand('copy'); } catch (_) { /* Report failure truthfully below. */ }
      field.remove(); active?.focus({preventScroll: true});
      if (range && selection) { selection.removeAllRanges(); selection.addRange(range); }
      notify(ok ? '文字已复制。' : '浏览器没有允许复制，请选中文字后复制。');
      return ok;
    }
  }
  function playIcon(element, playing) { element.querySelector('use')?.setAttribute('href', playing ? '#i-pause' : '#i-play'); }
  const film = $('#flow-film'), panel = $('#flow-panel'), text = $('#flow-text'), flowPlay = $('#flow-play');
  const chapters = all('[data-step]');
  let flowTimer = null, stepIndex = 0, running = false, started = false, edited = false, activeStep = 0;
  function state(value, label) {
    panel.dataset.state = value; $('#flow-status span:last-child').textContent = label;
    const voice = $('#flow-voice');
    voice.setAttribute('aria-label', value === 'paused' ? '继续口述演示' : '暂停口述演示');
    voice.title = value === 'paused' ? '继续演示' : '暂停演示';
  }
  function chapter(value) {
    activeStep = value;
    film.dataset.chapter = ['speak', 'pause', 'continue'][value];
    chapters.forEach(b => b.setAttribute('aria-pressed', String(Number(b.dataset.step) === value)));
    $('#film-caption').textContent = ['先说一点。', '停一下。', '再接着说。'][value];
    $('#film-subcaption').textContent = ['不必组织成一篇文章。', 'Saytile 在原处，等你继续。', '新的内容，接在刚才之后。'][value];
  }
  function playbackUI() {
    film.dataset.playing = String(running); playIcon(flowPlay, running);
    flowPlay.setAttribute('aria-label', running ? '暂停完整演示' : (stepIndex >= events.length ? '重新播放完整演示' : '播放完整演示'));
  }
  function stopFlow(showPause = true) {
    clearTimeout(flowTimer); flowTimer = null; running = false; playbackUI();
    if (showPause) state('paused', edited ? '你的修改已保留。' : '演示已暂停。');
  }
  function syncSource() { $('#take-source').textContent = plain(text) || final; }
  function followIfAllowed(wasNear) {
    const scroller = $('.s6-voice-scroll');
    if (wasNear && document.activeElement !== text) scroller.scrollTop = scroller.scrollHeight;
  }
  function append(value) {
    if (edited) return;
    const scroller = $('.s6-voice-scroll');
    const near = scroller.scrollHeight - scroller.clientHeight - scroller.scrollTop < 24;
    const span = document.createElement('span'); span.className = 's6-incoming'; span.textContent = value;
    text.append(span); followIfAllowed(near);
  }
  const events = [
    {wait: 300, run: () => {chapter(0); text.textContent = '这个周末，想去看海。'; state('speaking', '正在听你说。');}},
    {wait: 1500, run: () => {append('\n嗯，不赶时间。'); state('speaking', '一句接着一句。');}},
    {wait: 1800, run: () => {chapter(1); state('standby', '等你下一句。');}},
    {wait: 2200, run: () => {chapter(2); state('speaking', '思路继续，文字也继续。'); append('\n等天气放晴，再出发。');}},
    {wait: 1800, run: () => {state('standby', '说完了，仍在这里等你。'); syncSource(); stopFlow(false);}}
  ];
  function scheduleNext() {
    if (!running || document.hidden || edited) return;
    if (stepIndex >= events.length) {stopFlow(false); state('standby', '等你下一句。'); return;}
    const item = events[stepIndex];
    flowTimer = setTimeout(() => {
      if (!running || document.hidden || edited) return;
      stepIndex++; item.run(); if (running) scheduleNext();
    }, item.wait);
  }
  function startFlow(restart = false) {
    stopFlow(false); started = true;
    if (restart) {edited = false; stepIndex = 0; text.textContent = '这个周末，想去看海。';}
    if (edited) {state('standby', '你的修改已保留，随时复制。'); return;}
    if (reduced) {text.textContent = final; stepIndex = events.length; chapter(2); state('standby', '完整示例已显示。'); syncSource(); playbackUI(); return;}
    if (stepIndex >= events.length) {state('standby', '说完了，仍在这里等你。'); return;}
    running = true; state('standby', '等你下一句。'); playbackUI(); scheduleNext();
  }
  flowPlay.addEventListener('click', () => running ? stopFlow() : startFlow(!edited && stepIndex >= events.length));
  $('#flow-replay').addEventListener('click', () => startFlow(true));
  $('#flow-voice').addEventListener('click', () => panel.dataset.state === 'paused' ? startFlow() : stopFlow());
  chapters.forEach(button => button.addEventListener('click', () => {
    started = true; stopFlow(false); const selected = Number(button.dataset.step); chapter(selected);
    if (edited) {state('paused', '你的修改已保留。'); return;}
    if (selected === 0) {state('speaking', '正在讲话 · 状态示意'); stepIndex = Math.max(stepIndex, 1);}
    if (selected === 1) {state('standby', '短暂停顿，文字不会清空。'); stepIndex = Math.max(stepIndex, 3);}
    if (selected === 2) {if (!plain(text).includes('等天气放晴')) append('\n等天气放晴，再出发。'); state('standby', '新的内容，接在刚才之后。'); stepIndex = events.length; syncSource();}
    playbackUI();
  }));
  text.addEventListener('focus', () => {started = true; stopFlow();});
  text.addEventListener('input', () => {edited = true; stopFlow(); syncSource();});
  $('#flow-copy').addEventListener('click', async () => {
    const s = getSelection(); const selected = s && !s.isCollapsed && text.contains(s.anchorNode) && text.contains(s.focusNode);
    if (await copyText(selected ? s.toString() : plain(text))) {
      $('#flow-copy').dataset.copied = 'true'; setTimeout(() => delete $('#flow-copy').dataset.copied, 1300);
    }
  });
  if ('IntersectionObserver' in window) {
    new IntersectionObserver(entries => entries.forEach(e => {
      if (e.isIntersecting && !started && !document.hidden) startFlow();
      if (!e.isIntersecting) {if(running)stopFlow();else if(panel.dataset.state==='speaking')state('standby','等你下一句。');}
    }), {threshold: .32}).observe(film);
  }
  if (!reduced && matchMedia('(pointer:fine)').matches) {
    let frame = 0, mx = 0, my = 0;
    const render = () => {film.style.setProperty('--mx', mx.toFixed(3)); film.style.setProperty('--my', my.toFixed(3)); frame = 0;};
    film.addEventListener('pointermove', e => {const r = film.getBoundingClientRect(); mx = (e.clientX-r.left)/r.width*2-1; my=(e.clientY-r.top)/r.height*2-1; if (!frame) frame=requestAnimationFrame(render);});
    film.addEventListener('pointerleave', () => {mx=0;my=0;if(!frame)frame=requestAnimationFrame(render);});
  }
  playbackUI();

  const proof = $('#correction-proof'), word = $('#correction-word');
  let correctionTimers = [], correctionStarted = false;
  function stopCorrection() {correctionTimers.forEach(clearTimeout); correctionTimers = []; word.textContent='再'; delete word.dataset.correcting; proof.dataset.active='false';}
  function correction() {
    stopCorrection(); correctionStarted=true;
    if (reduced) {$('#correction-status').textContent='「在」在原处修正为「再」。'; return;}
    proof.dataset.active='true'; word.textContent='在'; $('#correction-status').textContent='同一处文字，继续核对。';
    correctionTimers.push(setTimeout(() => {word.textContent='再';word.dataset.correcting='true';$('#correction-status').textContent='「在」→「再」，只在原处修正。';}, 1100));
    correctionTimers.push(setTimeout(() => {delete word.dataset.correcting;proof.dataset.active='false';$('#correction-status').textContent='修正一个字，不改写一句话。';}, 3100));
  }
  $('#correction-replay').addEventListener('click', correction);
  if ('IntersectionObserver' in window) new IntersectionObserver(es=>es.forEach(e=>{if(e.isIntersecting&&!correctionStarted)correction();else if(!e.isIntersecting)stopCorrection();}),{threshold:.5}).observe(proof);

  const take = $('#take-stage'), draft = $('#take-draft'), action = $('#take-action'), paste = $('#paste-example');
  const modeTabs = all('.s6-mode-tabs [data-mode]');
  let mode = 'copy', copiedValue = null, bound = false, bindingValue = '', bindingCaret = 0, utterance = 0;
  let takeUsed=false, demoShown=false, demoTicket=0;
  if(!reduced)draft.value='';
  function protectDraft(){takeUsed=true;demoTicket++;}
  draft.addEventListener('focus',protectDraft);
  draft.addEventListener('input',protectDraft);
  const continuation = ['\n对了，记得带相机。', '\n出发时间，明天再定。'];
  function actionLabel(label, icon='#i-copy') {action.querySelector('span').textContent=label;action.querySelector('use').setAttribute('href',icon);}
  function unbind(reason = '') {
    bound = false;
    if (mode === 'direct') {actionLabel('选择示例草稿','#i-plus'); $('#draft-caption').textContent=reason || '先明确目标，再开始追加。'; $('#draft-state').textContent='尚未选择输入目标';}
  }
  function setMode(value) {
    if (!['copy','direct'].includes(value)) return;
    protectDraft();mode = value; take.dataset.mode=value; bound=false;
    modeTabs.forEach(b=>{const yes=b.dataset.mode===value;b.setAttribute('aria-selected',String(yes));b.tabIndex=yes?0:-1;});
    $('#take-content').setAttribute('aria-labelledby','mode-'+value);
    if (value === 'copy') {
      actionLabel('复制这段话');paste.hidden=false;paste.disabled=!copiedValue;
      $('#take-description').textContent='编辑后再复制，也保留你的修改。';
      $('#draft-caption').textContent=copiedValue?'文字已复制，点一下粘贴示例。':'文字准备好，下一步由你。';
      $('#draft-state').textContent='由你决定什么时候发送。';
    } else {
      paste.hidden=true;actionLabel('选择示例草稿','#i-plus');
      $('#take-description').textContent='只在本网页示例中追加新话，不连接外部应用。';
      $('#draft-caption').textContent='先明确目标，再开始追加。';$('#draft-state').textContent='尚未选择输入目标';
    }
  }
  modeTabs.forEach((b,i)=>{
    b.addEventListener('click',()=>setMode(b.dataset.mode));
    b.addEventListener('keydown',e=>{let n=i;if(e.key==='ArrowRight')n=(i+1)%modeTabs.length;else if(e.key==='ArrowLeft')n=(i+modeTabs.length-1)%modeTabs.length;else if(e.key==='Home')n=0;else if(e.key==='End')n=modeTabs.length-1;else return;e.preventDefault();modeTabs[n].focus();setMode(modeTabs[n].dataset.mode);});
  });
  function transfer(value, callback) {
    if (reduced) {callback(); return;}
    const from=$('#take-source').getBoundingClientRect(), to=draft.getBoundingClientRect();
    const ghost=document.createElement('div');ghost.className='s6-transfer';ghost.textContent=value;
    Object.assign(ghost.style,{left:from.left+'px',top:from.top+'px',width:Math.min(from.width,340)+'px'});document.body.append(ghost);
    const a=ghost.animate([{transform:'translate(0,0) scale(.96)',opacity:0},{offset:.16,opacity:.85},{transform:`translate(${to.left-from.left+9}px,${to.top-from.top+14}px) scale(.88)`,opacity:0}],{duration:600,easing:'cubic-bezier(.22,.8,.25,1)'});
    a.finished.then(()=>{ghost.remove();callback();}).catch(()=>{ghost.remove();callback();});
  }
  action.addEventListener('click', async () => {
    protectDraft();
    if (mode==='copy') {
      const value=plain($('#take-source'));
      if (await copyText(value)) {copiedValue=value;paste.disabled=false;actionLabel('已复制','#i-copy');$('#draft-caption').textContent='文字已复制，点一下粘贴示例。';setTimeout(()=>{if(mode==='copy')actionLabel('复制这段话');},1500);}
      return;
    }
    if (!bound) {
      bound=true;bindingValue=draft.value;bindingCaret=draft.value.length;
      draft.setSelectionRange(bindingCaret,bindingCaret);
      actionLabel('继续一句新话','#i-voice');$('#draft-caption').textContent='已选择：本网页的示例草稿';$('#draft-state').textContent='示例目标已选定';return;
    }
    if(draft.value!==bindingValue || draft.selectionStart!==bindingCaret || draft.selectionEnd!==bindingCaret){unbind('草稿或光标已变化，请重新选择目标。');return;}
    const value=continuation[utterance%continuation.length];utterance++;
    // Append only the new stable sample at the verified caret; do not rewrite the draft.
    draft.setRangeText((bindingValue?'\n':'')+value.trim(),bindingCaret,bindingCaret,'end');
    bindingValue=draft.value;bindingCaret=draft.value.length;draft.setSelectionRange(bindingCaret,bindingCaret);
    take.dataset.result='ready';$('#draft-state').textContent='只追加了刚才的新话';
    if(!reduced)draft.animate([{opacity:.55},{opacity:1}],{duration:350});
  });
  let pasting=false;
  paste.addEventListener('click',()=>{
    if(!copiedValue||mode!=='copy'||pasting)return;protectDraft();
    pasting=true;paste.disabled=true;const value=copiedValue;const previous=draft.value, from=draft.selectionStart, to=draft.selectionEnd;
    transfer(value,()=>{
      // If the reader typed while the visual transfer was playing, append instead of overwriting it.
      const begin=draft.value===previous?from:draft.value.length, end=draft.value===previous?to:draft.value.length;
      draft.setRangeText(value,begin,end,'end');take.dataset.result='ready';$('#draft-state').textContent='文字已进入示例草稿';$('#draft-caption').textContent='可以继续编辑。发送仍由你决定。';pasting=false;paste.disabled=!copiedValue;
    });
  });
  draft.addEventListener('input',()=>{if(mode==='direct')unbind('草稿已修改，请重新选择目标。');});
  draft.addEventListener('pointerup',()=>{if(mode==='direct'&&bound&&(draft.selectionStart!==bindingCaret||draft.selectionEnd!==bindingCaret))unbind('光标已变化，请重新选择目标。');});
  $('#take-reset').addEventListener('click',()=>{draft.value='';copiedValue=null;bound=false;utterance=0;take.dataset.result='empty';setMode(mode);});

  if('IntersectionObserver' in window){const demoObserver=new IntersectionObserver(es=>es.forEach(e=>{if(!e.isIntersecting||demoShown)return;demoShown=true;demoObserver.disconnect();if(takeUsed||mode!=='copy')return;const ticket=++demoTicket;if(reduced){draft.value=final;take.dataset.result='ready';return;}transfer(plain($('#take-source')),()=>{if(ticket!==demoTicket||takeUsed)return;draft.value=plain($('#take-source'));take.dataset.result='ready';$('#draft-state').textContent='取用过程演示';$('#draft-caption').textContent='可以在这里继续编辑。';});}),{threshold:.45});demoObserver.observe(take);}

  const memory = $('#memory-stage'), memoryTabs = all('.s6-memory-tabs [data-view]');
  function alignNative() {
    if(innerWidth<=650){const width=$('.s6-native-window').clientWidth;memory.style.setProperty('--native-offset',(memory.dataset.view==='detail'?width-850:-142)+'px');}
  }
  memoryTabs.forEach(b=>b.addEventListener('click',()=>{memory.dataset.view=b.dataset.view;memoryTabs.forEach(x=>x.setAttribute('aria-pressed',String(x===b)));alignNative();}));
  addEventListener('resize',alignNative,{passive:true});alignNative();
  const dialog=$('#native-dialog'),open=$('#native-zoom');
  open.addEventListener('click',()=>{dialog.showModal();});
  $('.s6-native-window').addEventListener('click',()=>dialog.showModal());
  $('.s6-native-window').addEventListener('keydown',e=>{if(e.key==='Enter'||e.key===' '){e.preventDefault();dialog.showModal();}});
  $('#native-close').addEventListener('click',()=>dialog.close());
  dialog.addEventListener('click',e=>{if(e.target===dialog){const r=dialog.getBoundingClientRect();if(e.clientX<r.left||e.clientX>r.right||e.clientY<r.top||e.clientY>r.bottom)dialog.close();}});
  dialog.addEventListener('close',()=>open.focus({preventScroll:true}));
  if (!reduced && 'IntersectionObserver' in window) {
    root.classList.add('motion-ready');
    const observer=new IntersectionObserver(entries=>entries.forEach(e=>{if(e.isIntersecting){e.target.classList.add('is-visible');observer.unobserve(e.target);}}),{threshold:.1});
    all('.s6-reveal').forEach(el=>observer.observe(el));
  }
  document.addEventListener('visibilitychange',()=>{if(document.hidden){stopFlow();stopCorrection();unbind('页面离开后，请重新选择示例目标。');}});
  reduceQuery.addEventListener('change',e=>{reduced=e.matches;if(reduced){stopFlow(false);stopCorrection();root.classList.remove('motion-ready');}});
})();
