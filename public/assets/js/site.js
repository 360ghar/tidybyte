// TidyByte marketing site — UI enhancements layered on top of nav.js.
// Pure vanilla JS, no dependencies. Safe to defer-load.

(function () {
  'use strict';

  document.addEventListener('DOMContentLoaded', function () {
    initThemeToggle();
    initReveal();
  });

  // 1) Light / Dark / System popover in the header.
  function initThemeToggle() {
    var btn = document.querySelector('[data-theme-toggle]');
    var menu = document.querySelector('[data-theme-menu]');
    if (!btn || !menu || !window.__tidybyteTheme) return;

    function sync() {
      var current = window.__tidybyteTheme.get();
      var options = menu.querySelectorAll('[data-theme-option]');
      for (var i = 0; i < options.length; i++) {
        var opt = options[i];
        var active = opt.getAttribute('data-theme-option') === current;
        opt.setAttribute('aria-checked', String(active));
        var dot = opt.querySelector('[data-theme-dot]');
        if (dot) dot.classList.toggle('opacity-0', !active);
      }
    }

    function setOpen(open) {
      btn.setAttribute('aria-expanded', String(open));
      menu.classList.toggle('hidden', !open);
      if (open) sync();
    }

    btn.addEventListener('click', function () {
      setOpen(btn.getAttribute('aria-expanded') !== 'true');
    });

    menu.addEventListener('click', function (event) {
      var opt = event.target.closest('[data-theme-option]');
      if (!opt) return;
      window.__tidybyteTheme.set(opt.getAttribute('data-theme-option'));
      sync();
      setOpen(false);
      btn.focus();
    });

    // Close on outside click.
    document.addEventListener('click', function (event) {
      if (btn.getAttribute('aria-expanded') !== 'true') return;
      if (menu.contains(event.target) || btn.contains(event.target)) return;
      setOpen(false);
    });

    // Close on Escape.
    document.addEventListener('keydown', function (event) {
      if (event.key === 'Escape' && btn.getAttribute('aria-expanded') === 'true') {
        setOpen(false);
        btn.focus();
      }
    });

    sync();
  }

  // 2) Scroll-in reveals. Opt-in per element via [data-reveal]; skipped
  // entirely for visitors who prefer reduced motion.
  function initReveal() {
    var els = document.querySelectorAll('[data-reveal]');
    if (!els.length) return;

    var reduced = window.matchMedia &&
      window.matchMedia('(prefers-reduced-motion: reduce)').matches;

    if (reduced || !('IntersectionObserver' in window)) {
      for (var i = 0; i < els.length; i++) els[i].classList.add('is-revealed');
      return;
    }

    var observer = new IntersectionObserver(function (entries) {
      entries.forEach(function (entry) {
        if (!entry.isIntersecting) return;
        entry.target.classList.add('is-revealed');
        observer.unobserve(entry.target);
      });
    }, { threshold: 0.12, rootMargin: '0px 0px -8% 0px' });

    for (var j = 0; j < els.length; j++) observer.observe(els[j]);
  }
})();
