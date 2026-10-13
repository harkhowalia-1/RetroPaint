// Desktop shell: windows, taskbar, start menu, menus and the clock.
(() => {
  'use strict';

  const $ = (s, el = document) => el.querySelector(s);
  const $$ = (s, el = document) => [...el.querySelectorAll(s)];
  const desktop = $('#desktop');
  const tasks = $('#tasks');
  const wide = () => window.matchMedia('(min-width: 900px)').matches;
  let topZ = 10;

  // ---------- Boot screen ----------
  const boot = $('#boot');
  const finishBoot = () => { boot.classList.add('done'); setTimeout(() => boot.remove(), 500); };
  boot.addEventListener('click', finishBoot);
  setTimeout(finishBoot, 1600);

  // ---------- Windows ----------
  const win = id => document.getElementById('win-' + id);
  const isOpen = w => !w.hidden;

  function focusWindow(w) {
    $$('.window').forEach(o => o.classList.toggle('active', o === w));
    w.style.zIndex = ++topZ;
    w.classList.remove('minimized');
    renderTasks();
  }

  function placeNew(w) {
    if (!wide() || w.dataset.placed) return;
    const dw = desktop.clientWidth, dh = desktop.clientHeight;
    const width = Math.min(w.classList.contains('dialog') ? 400 : 620, dw - 140);
    w.style.width = width + 'px';
    const n = $$('.window').filter(isOpen).length;
    w.style.left = Math.max(110, (dw - width) / 2 + n * 18) + 'px';
    w.style.top = Math.max(16, Math.min(dh * 0.12 + n * 18, dh - 200)) + 'px';
    w.dataset.placed = '1';
  }

  function openWindow(id) {
    const w = win(id);
    if (!w) return;
    w.hidden = false;
    placeNew(w);
    focusWindow(w);
    if (!wide()) w.scrollIntoView({ behavior: 'smooth', block: 'start' });
  }
  function closeWindow(w) { w.hidden = true; w.classList.remove('active', 'maximized'); renderTasks(); }

  $$('.window').forEach(w => {
    w.addEventListener('pointerdown', () => focusWindow(w));
    $('.close', w)?.addEventListener('click', e => { e.stopPropagation(); closeWindow(w); });
    $('.min', w)?.addEventListener('click', e => { e.stopPropagation(); w.classList.add('minimized'); w.classList.remove('active'); renderTasks(); });
    $('.max', w)?.addEventListener('click', e => { e.stopPropagation(); w.classList.toggle('maximized'); });
    $('.close-dialog', w)?.addEventListener('click', () => closeWindow(w));
    const bar = $('.title-bar', w);
    bar.addEventListener('dblclick', () => { if (wide() && $('.max', w)) w.classList.toggle('maximized'); });
    bar.addEventListener('pointerdown', e => {
      if (!wide() || e.target.closest('button') || w.classList.contains('maximized')) return;
      const startX = e.clientX, startY = e.clientY, left = w.offsetLeft, top = w.offsetTop;
      bar.setPointerCapture(e.pointerId);
      const move = ev => {
        const maxL = desktop.clientWidth - 80, maxT = desktop.clientHeight - 30;
        w.style.left = Math.min(maxL, Math.max(-w.offsetWidth + 80, left + ev.clientX - startX)) + 'px';
        w.style.top = Math.min(maxT, Math.max(0, top + ev.clientY - startY)) + 'px';
      };
      const up = () => { bar.removeEventListener('pointermove', move); bar.removeEventListener('pointerup', up); };
      bar.addEventListener('pointermove', move);
      bar.addEventListener('pointerup', up);
    });
  });

  // Opening windows from icons, buttons and menu items.
  document.addEventListener('click', e => {
    const opener = e.target.closest('[data-open]');
    if (!opener) return;
    // Desktop icons open on double-click with a mouse, single tap on touch/narrow screens.
    if (opener.classList.contains('icon') && wide() && e.pointerType === 'mouse' && e.detail < 2) {
      $$('.icon').forEach(i => i.classList.toggle('selected', i === opener));
      return;
    }
    closeMenus();
    hideStart();
    openWindow(opener.dataset.open);
  });
  $$('.icon').forEach(i => i.addEventListener('keydown', e => { if (e.key === 'Enter' && i.dataset.open) openWindow(i.dataset.open); }));
  desktop.addEventListener('pointerdown', e => { if (e.target === desktop) $$('.icon').forEach(i => i.classList.remove('selected')); });

  // ---------- Taskbar ----------
  function renderTasks() {
    tasks.innerHTML = '';
    $$('.window').filter(isOpen).forEach(w => {
      const b = document.createElement('button');
      b.className = 'task' + (w.classList.contains('active') ? ' active' : '');
      b.innerHTML = `<img src="${w.dataset.icon}" alt="" class="pixelated"><span>${w.dataset.title}</span>`;
      b.addEventListener('click', () => {
        if (w.classList.contains('active') && !w.classList.contains('minimized')) {
          w.classList.add('minimized'); w.classList.remove('active'); renderTasks();
        } else {
          focusWindow(w);
          if (!wide()) w.scrollIntoView({ behavior: 'smooth', block: 'start' });
        }
      });
      tasks.appendChild(b);
    });
  }

  const clock = $('#clock');
  const tick = () => { clock.textContent = new Date().toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' }); };
  tick(); setInterval(tick, 15000);

  // ---------- Start menu ----------
  const startBtn = $('#start-btn'), startMenu = $('#start-menu');
  function hideStart() { startMenu.hidden = true; startBtn.setAttribute('aria-expanded', 'false'); }
  startBtn.addEventListener('click', e => {
    e.stopPropagation();
    startMenu.hidden = !startMenu.hidden;
    startBtn.setAttribute('aria-expanded', String(!startMenu.hidden));
  });
  document.addEventListener('pointerdown', e => {
    if (!startMenu.hidden && !e.target.closest('#start-menu, #start-btn')) hideStart();
  });
  const safeOff = $('#safe-off');
  $('#turn-off').addEventListener('click', () => { hideStart(); safeOff.hidden = false; });
  safeOff.addEventListener('click', () => { safeOff.hidden = true; });

  // ---------- Menus in the paint window ----------
  function closeMenus() { $$('.menu.open').forEach(m => m.classList.remove('open')); }
  $$('.menu').forEach(m => {
    const btn = m.firstElementChild;
    btn.addEventListener('click', e => {
      e.stopPropagation();
      const wasOpen = m.classList.contains('open');
      closeMenus();
      if (!wasOpen) m.classList.add('open');
    });
    btn.addEventListener('mouseenter', () => { if ($('.menu.open') && !m.classList.contains('open')) { closeMenus(); m.classList.add('open'); } });
  });
  document.addEventListener('click', e => {
    const cmd = e.target.closest('[data-cmd]');
    if (cmd) { closeMenus(); window.RetroPaint?.run(cmd.dataset.cmd); return; }
    if (!e.target.closest('.menu')) closeMenus();
  });
  document.addEventListener('keydown', e => { if (e.key === 'Escape') { closeMenus(); hideStart(); } });

  // ---------- Screenshot tabs ----------
  $$('.tabs [role=tab]').forEach(tab => tab.addEventListener('click', () => {
    $$('.tabs [role=tab]').forEach(t => t.setAttribute('aria-selected', String(t === tab)));
    $$('.tab-panel figure').forEach(f => { f.hidden = f.dataset.panel !== tab.dataset.tab; });
  }));

  // ---------- Initial layout ----------
  function layout() {
    if (!wide()) return;
    const dw = desktop.clientWidth, dh = desktop.clientHeight;
    const welcome = win('welcome'), paint = win('paint');
    const paintW = Math.min(760, dw - 600);
    if (paintW >= 520) {
      welcome.style.cssText += `left:110px;top:24px;width:${Math.min(460, dw - paintW - 150)}px;`;
      paint.style.cssText += `left:${dw - paintW - 24}px;top:16px;width:${paintW}px;height:${Math.min(dh - 32, 640)}px;`;
    } else {
      welcome.style.cssText += `left:110px;top:20px;width:${Math.min(480, dw - 130)}px;`;
      paint.style.cssText += `left:${Math.max(110, dw - 720)}px;top:${Math.min(240, dh - 420)}px;width:${Math.min(700, dw - 130)}px;height:${Math.min(dh - 40, 600)}px;`;
    }
    welcome.dataset.placed = paint.dataset.placed = '1';
  }
  layout();
  focusWindow(win('paint'));
  focusWindow(win('welcome'));
})();
