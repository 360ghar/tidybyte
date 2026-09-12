// TidyByte marketing site — theme bootstrap.
// Loaded synchronously in <head> (NOT deferred) so the theme class is applied
// before first paint. CSP `script-src 'self'` forbids inline scripts, hence
// the external file.
//
// Resolution: stored "light" | "dark" wins; stored "system" follows the OS;
// nothing stored defaults to LIGHT (the OS preference is ignored until the
// visitor explicitly picks System).
(function () {
  'use strict';

  // Marks that JS is running. Scroll-reveal CSS only hides [data-reveal]
  // under html.js, so a script failure can never blank the page.
  document.documentElement.classList.add('js');

  var STORAGE_KEY = 'tidybyte-theme';
  var DARK_COLOR = '#121212';
  var LIGHT_COLOR = '#fffaf0';

  function stored() {
    try {
      return localStorage.getItem(STORAGE_KEY);
    } catch (err) {
      return null;
    }
  }

  function systemDark() {
    return Boolean(window.matchMedia &&
      window.matchMedia('(prefers-color-scheme: dark)').matches);
  }

  function resolve() {
    var saved = stored();
    if (saved === 'dark') return 'dark';
    if (saved === 'system') return systemDark() ? 'dark' : 'light';
    return 'light';
  }

  function apply(theme) {
    var root = document.documentElement;
    root.classList.toggle('dark', theme === 'dark');
    root.style.colorScheme = theme;
    var meta = document.querySelector('meta[name="theme-color"]');
    if (meta) meta.setAttribute('content', theme === 'dark' ? DARK_COLOR : LIGHT_COLOR);
  }

  // Apply immediately — this file runs before the stylesheet finishes.
  apply(resolve());

  window.__tidybyteTheme = {
    // The persisted choice: "light" | "dark" | "system". Fresh visitors read "light".
    get: function () {
      var saved = stored();
      return saved === 'dark' || saved === 'system' ? saved : 'light';
    },
    // What is actually on screen right now.
    resolved: function () {
      return resolve();
    },
    set: function (choice) {
      if (choice === 'light' || choice === 'dark' || choice === 'system') {
        try { localStorage.setItem(STORAGE_KEY, choice); } catch (err) { /* private mode */ }
      } else {
        try { localStorage.removeItem(STORAGE_KEY); } catch (err) { /* private mode */ }
      }
      apply(resolve());
    }
  };

  // Follow live OS switches — only while the visitor opted into "system".
  if (window.matchMedia) {
    var mq = window.matchMedia('(prefers-color-scheme: dark)');
    var onChange = function () {
      if (stored() === 'system') apply(resolve());
    };
    if (mq.addEventListener) mq.addEventListener('change', onChange);
    else if (mq.addListener) mq.addListener(onChange);
  }
})();
