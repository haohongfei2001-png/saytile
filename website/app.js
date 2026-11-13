'use strict';
(() => {
  const $ = selector => document.querySelector(selector);
  const reduced = matchMedia('(prefers-reduced-motion: reduce)').matches;
  const timers = new Set();
  const later = (fn, delay) => { const id = setTimeout(() => { timers.delete(id); fn(); }, delay); timers.add(id); return id; };
  let toastTimer;
  function toast(message) { clearTimeout(toastTimer); $('#toast').textContent = message; $('#toast').classList.add('visible'); toastTimer = setTimeout(() => $('#toast').classList.remove('visible'), 2500); }
  if (!reduced) {
    document.documentElement.classList.add('js-motion');
    const reveal = new IntersectionObserver(entries => entries.forEach(entry => { if (entry.isIntersecting) { entry.target.classList.add('is-visible'); reveal.unobserve(entry.target); } }), {threshold: .12});
    document.querySelectorAll('.reveal').forEach(el => reveal.observe(el));
  }
  let heroUsed = false;
  window.addEventListener('saytile-state', event => { $('#product-phase').textContent = event.detail.phase; $('#caption-dot').dataset.state = event.detail.state; });
  window.addEventListener('saytile-copy', event => toast(event.detail.ok ? '这段原话，已复制。' : '可以选中文字，直接复制。'));
  $('#hero-replay').addEventListener('click', () => { heroUsed = true; window.SaytileDemo?.play({restart:true}); });
  $('#saytile-panel').addEventListener('pointerdown', () => { heroUsed = true; });
  $('#saytile-panel').addEventListener('focusin', () => { heroUsed = true; });
  const heroObserver = new IntersectionObserver(entries => { if (entries.some(e => e.isIntersecting)) { heroObserver.disconnect(); later(() => { if (!heroUsed) window.SaytileDemo?.play(); }, 900); } }, {threshold:.65});
  heroObserver.observe($('#saytile-panel'));
  if (!reduced && matchMedia('(pointer:fine)').matches) {
    let x = 0, y = 0, tx = 0, ty = 0, frame = 0;
    const float = $('#product-float');
    function settle() { x += (tx-x)*.09; y += (ty-y)*.09; float.style.transform = 'rotateX(' + (-y*2.4).toFixed(3) + 'deg) rotateY(' + (x*3.2).toFixed(3) + 'deg) translate3d(' + (x*3).toFixed(2) + 'px,' + (y*2).toFixed(2) + 'px,0)'; $('#experience').style.setProperty('--light-x', (x*9).toFixed(2)+'px'); $('#experience').style.setProperty('--light-y', (y*6).toFixed(2)+'px'); if (Math.abs(tx-x)+Math.abs(ty-y)>.001) frame=requestAnimationFrame(settle); else frame=0; }
    $('#experience').addEventListener('pointermove', e => { const r=$('#experience').getBoundingClientRect(); tx=(e.clientX-r.left)/r.width*2-1; ty=(e.clientY-r.top)/r.height*2-1; if(!frame) frame=requestAnimationFrame(settle); });
    $('#experience').addEventListener('pointerleave', () => {tx=0;ty=0;if(!frame)frame=requestAnimationFrame(settle);});
  }
  const phrases = ['#phrase-a','#phrase-b','#phrase-c','#phrase-d'].map($);
  let precisionStarted=false, precisionRunning=false, precisionIndex=0, precisionTimer=null;
  const steps = [
    {delay:700,run:()=>{phrases[0].classList.remove('phrase-wait');$('#precision-caption').textContent='你的语气，自然留下。';}},
    {delay:1050,run:()=>{phrases[1].classList.remove('phrase-wait');$('#corrected-word').textContent='在';}},
    {delay:1100,run:()=>{phrases[2].classList.remove('phrase-wait');$('#precision-caption').textContent='你继续说，文字继续核对。';}},
    {delay:850,run:()=>{$('#corrected-word').textContent='再';$('#corrected-word').classList.add('correcting');}},
    {delay:1300,run:()=>{phrases[3].classList.remove('phrase-wait');$('#corrected-word').classList.remove('correcting');$('#precision-caption').textContent='修订发生在原处，表达继续。';}}
  ];
  function precisionLabel(playing) { const b=$('#precision-toggle'); b.setAttribute('aria-label',playing?'暂停持续核对演示':'继续持续核对演示');b.title=playing?'暂停演示':'继续演示';b.querySelector('use').setAttribute('href',playing?'#i-pause':'#i-play');$('.spoken-passage').classList.toggle('is-playing',playing); }
  function precisionStop() {clearTimeout(precisionTimer);precisionTimer=null;precisionRunning=false;precisionLabel(false);}
  function precisionStep() {if(!precisionRunning)return;if(precisionIndex>=steps.length){precisionStop();$('#precision-caption').textContent='语气与补充，都留在原话里。';return;}const item=steps[precisionIndex++];item.run();precisionTimer=setTimeout(precisionStep,item.delay);}
  function precisionPlay(restart=false) {precisionStarted=true;clearTimeout(precisionTimer);if(restart){precisionIndex=0;phrases.forEach(el=>el.classList.add('phrase-wait'));$('#corrected-word').textContent='在';$('#corrected-word').classList.remove('correcting');}if(reduced){phrases.forEach(el=>el.classList.remove('phrase-wait'));$('#corrected-word').textContent='再';precisionIndex=steps.length;precisionStop();return;}if(precisionIndex>=steps.length){precisionPlay(true);return;}precisionRunning=true;precisionLabel(true);precisionTimer=setTimeout(precisionStep,250);}
  $('#precision-replay').addEventListener('click',()=>precisionPlay(true));
  $('#precision-toggle').addEventListener('click',()=>precisionRunning?precisionStop():precisionPlay());
  const precisionObserver=new IntersectionObserver(entries=>{if(entries.some(e=>e.isIntersecting)){precisionObserver.disconnect();if(!precisionStarted)precisionPlay(true);}}, {threshold:.55});precisionObserver.observe($('#precision-demo'));
  const additions=['还有，刚才那个入口，可以直接给一个能用的示例。','嗯，先这样。我把这一版做出来，再看看实际感觉。','下一次再接着想，也能回到这里。'];let thoughtCount=0;
  $('#continue-thought').addEventListener('click',()=>{
    document.querySelectorAll('.journal-entry').forEach(el=>el.classList.remove('is-latest'));
    const entry=document.createElement('article');entry.className='journal-entry is-latest added';
    const time=document.createElement('time');time.textContent='接着';const body=document.createElement('div');const p=document.createElement('p');p.textContent=additions[thoughtCount%additions.length];thoughtCount++;body.appendChild(p);entry.append(time,body);$('#journal-entries').appendChild(entry);
    $('#journal-viewport').scrollTo({top:$('#journal-viewport').scrollHeight,behavior:reduced?'instant':'smooth'});
    $('#journal-state').textContent='刚才的思路，接着留下。';toast('已在示例时间轴中接上这一句。');
  });
  $('#history-top').addEventListener('click',()=>{$('#journal-viewport').scrollTo({top:0,behavior:reduced?'instant':'smooth'});$('#journal-state').textContent='之前的表达，一直都在。';});
  document.addEventListener('visibilitychange',()=>{if(document.hidden){window.SaytileDemo?.pause();precisionStop();timers.forEach(clearTimeout);timers.clear();}});
})();
