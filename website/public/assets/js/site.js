// TidyByte marketing site — UI enhancements layered on top of nav.js.
// Pure vanilla JS, no dependencies. Safe to defer-load.

(function () {
  'use strict';

  // Keep these in sync with src/input.css: the pop-out keyframe duration and
  // the theme-switching crossfade window.
  var POPOVER_EXIT = 130;
  var THEME_FADE = 300;

  function prefersReduced() {
    return Boolean(window.matchMedia &&
      window.matchMedia('(prefers-reduced-motion: reduce)').matches);
  }

  document.addEventListener('DOMContentLoaded', function () {
    initThemeToggle();
    initReveal();
    initImageFade();
  });

  // 1) Light / Dark / System popover in the header.
  function initThemeToggle() {
    var btn = document.querySelector('[data-theme-toggle]');
    var menu = document.querySelector('[data-theme-menu]');
    if (!btn || !menu || !window.__tidybyteTheme) return;

    var reduced = prefersReduced();
    var closing = false;
    var closeTimer = null;

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

    // The close animation needs the node to stay rendered, so `hidden` lands a
    // beat after `.is-closing`. aria-expanded still flips immediately — the
    // popover is already dismissed as far as the accessibility tree cares.
    function finishClose() {
      window.clearTimeout(closeTimer);
      closeTimer = null;
      closing = false;
      menu.classList.remove('is-closing');
      menu.classList.add('hidden');
    }

    function setOpen(open) {
      btn.setAttribute('aria-expanded', String(open));

      if (open) {
        window.clearTimeout(closeTimer);
        closeTimer = null;
        closing = false;
        menu.classList.remove('is-closing');
        menu.classList.remove('hidden');
        sync();
        return;
      }

      if (closing) return;
      if (menu.classList.contains('hidden')) return;
      if (reduced) { finishClose(); return; }

      closing = true;
      menu.classList.add('is-closing');
      closeTimer = window.setTimeout(finishClose, POPOVER_EXIT + 80);
    }

    btn.addEventListener('click', function () {
      setOpen(btn.getAttribute('aria-expanded') !== 'true');
    });

    menu.addEventListener('click', function (event) {
      var opt = event.target.closest('[data-theme-option]');
      if (!opt) return;
      // Crossfade the palette instead of hard-cutting every surface.
      if (!reduced) {
        var root = document.documentElement;
        root.classList.add('theme-switching');
        window.setTimeout(function () {
          root.classList.remove('theme-switching');
        }, THEME_FADE);
      }
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

    var reduced = prefersReduced();

    if (reduced || !('IntersectionObserver' in window)) {
      for (var i = 0; i < els.length; i++) els[i].classList.add('is-revealed');
      return;
    }

    // Elements sharing a group cascade in reading order so the eye can follow
    // the order they are meant to be read in. The cap keeps a twelve-card grid
    // from trickling in, and the small jitter stops the rhythm reading as a
    // metronome.
    var groups = document.querySelectorAll('[data-reveal-group]');
    for (var g = 0; g < groups.length; g++) {
      var children = groups[g].children;
      for (var c = 0, order = 0; c < children.length; c++) {
        if (!children[c].hasAttribute('data-reveal')) continue;
        var delay = Math.min(order, 7) * 40 + (order % 3) * 8;
        children[c].style.setProperty('--reveal-delay', delay + 'ms');
        order++;
      }
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

  // 3) Lazy images fade in as they decode instead of popping in mid-scroll.
  // Nothing is hidden unless this function decided to hide it and has a load
  // handler attached, and a failed image is revealed rather than stranded.
  // `motion-fade` is swapped for `is-loaded` in the same frame; the animation
  // then settles on the image's own opacity, so `opacity-90` survives.
  function initImageFade() {
    var imgs = document.querySelectorAll('img[loading="lazy"]');
    for (var i = 0; i < imgs.length; i++) {
      (function (img) {
        if (img.complete && img.naturalWidth > 0) return;
        var reveal = function () {
          img.classList.remove('motion-fade');
          img.classList.add('is-loaded');
        };
        img.classList.add('motion-fade');
        img.addEventListener('load', reveal, { once: true });
        img.addEventListener('error', reveal, { once: true });
        if (img.complete) reveal();
      })(imgs[i]);
    }
  }
})();
