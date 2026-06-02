// TidyByte marketing site — minimal progressive enhancements.
// Pure vanilla JS, no dependencies. Safe to defer-load.

(function () {
  'use strict';

  document.addEventListener('DOMContentLoaded', function () {
    initMobileMenu();
    initFaqAccordion();
    initSupportFormSuccess();
  });

  // 1) Mobile menu toggle
  function initMobileMenu() {
    var toggle = document.querySelector('[data-menu-toggle]');
    var menu = document.querySelector('[data-mobile-menu]');
    if (!toggle || !menu) return;

    // Ensure the menu starts hidden on mobile (the component classes set
    // visibility at md+, so we only need to keep the closed state consistent).
    if (!menu.hasAttribute('data-open')) menu.setAttribute('data-open', 'false');

    function setOpen(isOpen) {
      toggle.setAttribute('aria-expanded', String(isOpen));
      menu.setAttribute('data-open', String(isOpen));
      menu.classList.toggle('hidden', !isOpen);
      document.body.classList.toggle('overflow-hidden', isOpen);
    }

    toggle.addEventListener('click', function () {
      var isOpen = toggle.getAttribute('aria-expanded') === 'true';
      setOpen(!isOpen);
    });

    // Close after tapping a link so in-page anchors don't leave the menu open.
    menu.addEventListener('click', function (event) {
      var link = event.target.closest('a');
      if (!link) return;
      setOpen(false);
    });

    // Auto-close when the viewport grows past the md breakpoint.
    var mq = window.matchMedia('(min-width: 768px)');
    var onChange = function (e) { if (e.matches) setOpen(false); };
    if (mq.addEventListener) mq.addEventListener('change', onChange);
    else if (mq.addListener) mq.addListener(onChange);

    // Close on Escape.
    document.addEventListener('keydown', function (event) {
      if (event.key === 'Escape' && toggle.getAttribute('aria-expanded') === 'true') {
        setOpen(false);
        toggle.focus();
      }
    });
  }

  // 2) FAQ exclusive accordion. Native <details>/<summary> still drives
  // accessibility and keyboard support; this just closes siblings on open.
  function initFaqAccordion() {
    var groups = document.querySelectorAll('[data-faq-accordion]');
    if (!groups.length) return;

    groups.forEach(function (group) {
      var items = group.querySelectorAll('details');
      items.forEach(function (details) {
        details.addEventListener('toggle', function () {
          if (!details.open) return;
          items.forEach(function (other) {
            if (other !== details && other.open) other.open = false;
          });
        });
      });
    });
  }

  // 3) Support form success state.
  // Netlify forms post back to the same URL with ?submitted=true when the
  // submission lands. We detect that and swap the form for a thank-you.
  function initSupportFormSuccess() {
    var form = document.querySelector('form[name="support"]');
    if (!form) return;
    if (!/submitted=true/.test(window.location.search)) return;

    form.hidden = true;

    var thanks = document.createElement('div');
    thanks.className = 'glass-card p-6 sm:p-8';
    thanks.setAttribute('role', 'status');
    thanks.setAttribute('aria-live', 'polite');
    thanks.innerHTML =
      '<h2 class="h-section">Thanks! We&rsquo;ll be in touch.</h2>' +
      '<p class="lede mt-3">Your message is on its way. We typically respond within 2 business days.</p>' +
      '<p class="muted mt-6 text-sm"><a href="/support" class="text-accent hover:underline">Send another message &rarr;</a></p>';

    form.parentNode.insertBefore(thanks, form);

    // Defer scroll to next frame so the inserted node is laid out first.
    requestAnimationFrame(function () {
      thanks.scrollIntoView({ behavior: 'smooth', block: 'start' });
    });
  }
})();
