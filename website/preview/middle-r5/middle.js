'use strict';
(() => {
  const $ = s => document.querySelector(s);
  const reduced = matchMedia('(prefers-reduced-motion: reduce)').matches;
  const toast = message => { const el=$('#toast'); if(!el)return; el.textContent=message; el.classList.add('visible'); setTimeout(()=>el.classList.remove('visible'),2200); };
  let heroUsed=false;
  window.addEventListener('saytile-state',e=>{const phase=$('#product-phase'),dot=$('#caption-dot');if(phase)phase.textContent=e.detail.phase;if(dot)dot.dataset.state=e.detail.state;});
  window.addEventListener('saytile-copy',e=>toast(e.detail.ok?'这段文字已复制。':'可以选中文字，直接复制。'));
  $('#hero-replay')?.addEventListener('click',()=>{heroUsed=true;window.SaytileDemo?.play({restart:true});});
  $('#saytile-panel')?.addEventListener('pointerdown',()=>{heroUsed=true;});
  $('#saytile-panel')?.addEventListener('focusin',()=>{heroUsed=true;});
  const hero=$('#saytile-panel');
  if(hero&&'IntersectionObserver'in window){const observer=new IntersectionObserver(entries=>{if(entries.some(e=>e.isIntersecting)){observer.disconnect();setTimeout(()=>{if(!heroUsed)window.SaytileDemo?.play();},700);}}, {threshold:.65});observer.observe(hero);}
  if(!reduced&&matchMedia('(pointer:fine)').matches&&$('#experience')){
    let x=0,y=0,tx=0,ty=0,frame=0;const float=$('#product-float');
    const step=()=>{x+=(tx-x)*.08;y+=(ty-y)*.08;float.style.transform='rotateX('+(-y*1.5).toFixed(2)+'deg) rotateY('+(x*2).toFixed(2)+'deg) translate3d('+(x*2).toFixed(2)+'px,'+(y*1.5).toFixed(2)+'px,0)';if(Math.abs(tx-x)+Math.abs(ty-y)>.001)frame=requestAnimationFrame(step);else frame=0;};
    $('#experience').addEventListener('pointermove',e=>{const r=$('#experience').getBoundingClientRect();tx=(e.clientX-r.left)/r.width*2-1;ty=(e.clientY-r.top)/r.height*2-1;if(!frame)frame=requestAnimationFrame(step);});
    $('#experience').addEventListener('pointerleave',()=>{tx=0;ty=0;if(!frame)frame=requestAnimationFrame(step);});
  }
  const stateNote=$('#r5-state-note');
  const stateMessages={
    speaking:'讲话时，文字逐步进入同一份记录。',
    standby:'短暂停顿回到待命；记录不会因此结束。',
    continue:'再次开口，新内容接在原来的表达之后。'
  };
  document.querySelectorAll('[data-capture-state]').forEach(button=>button.addEventListener('click',()=>{
    const state=button.dataset.captureState;
    document.querySelectorAll('[data-capture-state]').forEach(b=>b.setAttribute('aria-pressed',String(b===button)));
    if(stateNote)stateNote.textContent=stateMessages[state];
  }));
  const scene=$('#r5-mode-scene');
  const destination={
    free:{label:'自由记录',title:'留在输入板',copy:'你可以继续编辑、搜索和回听；需要时再复制，或单次插入到草稿。',actions:['编辑','复制','单次插入'],guard:'先完整留下，再由你决定何时取用。'},
    direct:{label:'已明确绑定目标',title:'追加到当前草稿',copy:'只把之后讲话形成的稳定新文字追加到你选定的草稿。目标或焦点变化时暂停，不发送消息。',actions:['明确选择目标','只追加新文字','变化时暂停'],guard:'目标由你选择；发送始终由你决定。'}
  };
  document.querySelectorAll('[data-mode]').forEach(button=>button.addEventListener('click',()=>{
    const mode=button.dataset.mode;if(!destination[mode]||!scene)return;
    document.querySelectorAll('[data-mode]').forEach(b=>b.setAttribute('aria-selected',String(b===button)));
    scene.dataset.mode=mode;$('#r5-destination-label').textContent=destination[mode].label;$('#r5-destination-title').textContent=destination[mode].title;$('#r5-destination-copy').textContent=destination[mode].copy;$('#r5-mode-guard span:last-child').textContent=destination[mode].guard;
    const actions=$('#r5-destination-actions');actions.replaceChildren(...destination[mode].actions.map(label=>{const el=document.createElement('span');el.textContent=label;return el;}));
  }));
  if(!reduced&&'IntersectionObserver'in window){document.documentElement.classList.add('r5-motion');const io=new IntersectionObserver(entries=>entries.forEach(e=>{if(e.isIntersecting){e.target.classList.add('is-visible');io.unobserve(e.target);}}),{threshold:.12});document.querySelectorAll('.r5-reveal').forEach(el=>io.observe(el));}
  document.addEventListener('visibilitychange',()=>{if(document.hidden)window.SaytileDemo?.pause();});
})();
