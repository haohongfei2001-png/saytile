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
  document.addEventListener('visibilitychange',()=>{if(document.hidden){window.SaytileDemo?.pause();timers.forEach(clearTimeout);timers.clear();}});
})();
