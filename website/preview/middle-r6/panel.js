(() => {
  'use strict';
  const root = document.getElementById('saytile-panel');
  if (!root) return;
  const text = root.querySelector('.sp-text');
  const scroll = root.querySelector('.sp-scroll');
  const voiceButton = root.querySelector('.sp-voice');
  const copyButton = root.querySelector('.sp-copy');
  const reduced = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  const chunks = ['先别急着下结论。', '\n嗯，我想把两个方案都试一下，', '尤其是第一次打开的时候。', '\n还有，记得保留最开始的想法。'];
  let next = 1;
  let timer = null;
  let copiedTimer = null;
  let running = false;
  let edited = false;
  let state = 'standby';

  function emit(phase) {
    root.dispatchEvent(new CustomEvent('saytile-state', {
      bubbles: true,
      detail: { state, phase }
    }));
  }
  function setState(value, phase) {
    state = value;
    root.dataset.state = value;
    const action = value === 'paused' ? '继续演示' : '暂停演示';
    voiceButton.setAttribute('aria-label', action);
    voiceButton.title = action;
    emit(phase);
  }
  function stopTimer() {
    clearTimeout(timer);
    timer = null;
    running = false;
  }
  function finish() {
    stopTimer();
    setState('standby', '等你下一句。');
  }
  function append() {
    if (!running || edited) return;
    if (next >= chunks.length) { finish(); return; }
    const nearBottom = scroll.scrollHeight - scroll.clientHeight - scroll.scrollTop < 24;
    const incoming = document.createElement('span');
    incoming.className = 'sp-incoming';
    incoming.textContent = chunks[next];
    text.appendChild(incoming);
    next += 1;
    setState('speaking', '正在听你说。');
    if (nearBottom && document.activeElement !== text) scroll.scrollTop = scroll.scrollHeight;
    const spokenFor = next === 1 ? 1100 : 850;
    timer = setTimeout(() => {
      if (!running) return;
      if (next === chunks.length) { finish(); return; }
      setState('standby', '等你下一句。');
      timer = setTimeout(append, next === 2 ? 1000 : 480);
    }, spokenFor);
  }
  function play(options = {}) {
    stopTimer();
    if (options.restart === true) {
      next = 0;
      edited = false;
      text.textContent = '';
    }
    if (edited) {
      setState('standby', '你的修改已保留，随时复制。');
      return false;
    }
    if (next >= chunks.length) { finish(); return true; }
    if (reduced) {
      text.textContent = chunks.join('');
      next = chunks.length;
      finish();
      return true;
    }
    running = true;
    setState('standby', '等你下一句。');
    timer = setTimeout(append, 320);
    return true;
  }
  function pause() {
    stopTimer();
    setState('paused', '已暂停。');
  }
  async function copy() {
    const selection = window.getSelection();
    const inText = selection && !selection.isCollapsed &&
      text.contains(selection.anchorNode) && text.contains(selection.focusNode);
    const value = inText ? selection.toString() : text.textContent;
    if (!value.trim()) {
      emit('这里还没有文字。');
      return false;
    }
    let ok = false;
    try {
      await navigator.clipboard.writeText(value);
      ok = true;
    } catch (_) {
      const active = document.activeElement;
      const field = document.createElement('textarea');
      field.value = value;
      field.setAttribute('readonly', '');
      field.style.cssText = 'position:fixed;left:-10000px;top:0;opacity:0';
      document.body.appendChild(field);
      field.select();
      try { ok = document.execCommand('copy'); } catch (_) { /* The caller receives failure. */ }
      field.remove();
      if (active && typeof active.focus === 'function') active.focus({ preventScroll: true });
    }
    if (ok) {
      clearTimeout(copiedTimer);
      copyButton.dataset.copied = 'true';
      copiedTimer = setTimeout(() => { delete copyButton.dataset.copied; }, 1400);
    }
    root.dispatchEvent(new CustomEvent('saytile-copy', {
      bubbles: true,
      detail: { ok, text: value }
    }));
    emit(ok ? '这段原话，已复制。' : '可以选中文字，直接复制。');
    return ok;
  }
  text.addEventListener('focus', () => { if (running) pause(); });
  text.addEventListener('input', () => {
    stopTimer();
    edited = true;
    setState('paused', '你的修改已保留。');
  });
  voiceButton.addEventListener('click', () => state === 'paused' ? play() : pause());
  copyButton.addEventListener('click', copy);
  window.SaytileDemo = Object.freeze({ play, pause, copy });
})();
