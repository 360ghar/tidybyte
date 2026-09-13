// Blog hub: category filter + client-side pagination, synced to the URL
// (?cat=privacy&page=2). Loaded with <script defer>; the CSP allows only
// external scripts, so there are no inline handlers. Class strings below are
// Tailwind token utilities — tailwind.config.js scans this file, so they
// compile into styles.css on `npm run build`.
(function () {
  'use strict';

  var PER_PAGE = 12;

  var CATS = ['features', 'privacy', 'reviews', 'storage', 'tutorials', 'comparisons'];
  var CAT_LABELS = {
    features: 'Features',
    privacy: 'Privacy',
    reviews: 'Reviews',
    storage: 'Storage',
    tutorials: 'Tutorials',
    comparisons: 'Comparisons'
  };

  var FOCUS_RING = 'focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary/40';
  var CHIP_ACTIVE = 'inline-flex cursor-pointer items-center rounded-full bg-primary px-4 py-1.5 text-sm font-semibold text-on-primary transition ' + FOCUS_RING;
  var CHIP_INACTIVE = 'badge cursor-pointer px-4 py-1.5 text-sm font-medium transition hover:text-ink ' + FOCUS_RING;
  var PAGE_ACTIVE = 'inline-flex cursor-pointer items-center justify-center rounded-full bg-primary px-3.5 py-1.5 text-sm font-semibold text-on-primary transition ' + FOCUS_RING;
  var PAGE_INACTIVE = 'badge cursor-pointer px-3.5 py-1.5 text-sm font-medium transition hover:text-ink ' + FOCUS_RING;

  var grid = document.getElementById('blog-list');
  var cards = grid ? Array.prototype.slice.call(grid.querySelectorAll('article[data-cats]')) : [];
  var chips = Array.prototype.slice.call(document.querySelectorAll('[data-filter]'));
  var gridHeading = document.getElementById('grid-heading');
  var resultCount = document.getElementById('result-count');
  var pagination = document.getElementById('pagination');
  var pageButtons = document.getElementById('page-buttons');
  var prevBtn = document.getElementById('prev-btn');
  var nextBtn = document.getElementById('next-btn');
  var emptyState = document.getElementById('blog-empty');
  var emptyAllLink = document.getElementById('blog-empty-all');

  var state = { cat: 'all', page: 1 };

  function parseStateFromUrl() {
    var params = new URLSearchParams(window.location.search);
    var cat = params.get('cat');
    if (CATS.indexOf(cat) === -1) cat = 'all';
    var page = parseInt(params.get('page'), 10);
    if (isNaN(page) || page < 1) page = 1;
    return { cat: cat, page: page };
  }

  function syncUrl(method) {
    if (!window.history || !window.history.replaceState) return;
    var params = new URLSearchParams();
    if (state.cat !== 'all') params.set('cat', state.cat);
    if (state.page > 1) params.set('page', String(state.page));
    var qs = params.toString();
    var url = window.location.pathname + (qs ? '?' + qs : '');
    if (method === 'push') window.history.pushState(state, '', url);
    else window.history.replaceState(state, '', url);
  }

  function filteredPosts() {
    var list = cards.filter(function (card) {
      if (state.cat === 'all') return true;
      return (card.getAttribute('data-cats') || '').split(' ').indexOf(state.cat) !== -1;
    });
    // Newest first (stable for equal dates, which preserves DOM order).
    list.sort(function (a, b) {
      return (b.getAttribute('data-date') || '').localeCompare(a.getAttribute('data-date') || '');
    });
    return list;
  }

  function applyChips() {
    chips.forEach(function (chip) {
      var isActive = chip.getAttribute('data-filter') === state.cat;
      chip.className = isActive ? CHIP_ACTIVE : CHIP_INACTIVE;
      chip.setAttribute('aria-pressed', isActive ? 'true' : 'false');
    });
  }

  function scrollToTop() {
    var reduce = window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches;
    window.scrollTo({ top: 0, behavior: reduce ? 'auto' : 'smooth' });
  }

  function render(focusHeading) {
    var posts = filteredPosts();
    var total = posts.length;
    var totalPages = Math.max(1, Math.ceil(total / PER_PAGE));
    if (state.page > totalPages) state.page = totalPages;

    var start = (state.page - 1) * PER_PAGE;
    var end = Math.min(start + PER_PAGE, total);

    // Only cards that were not already on screen get a stagger index. Cards
    // that persist across a filter keep the delay they had, because changing
    // animation-delay on a finished animation would push it back into its
    // delay phase and flash the card out again.
    var wasVisible = [];
    cards.forEach(function (card) {
      if (!card.classList.contains('hidden')) wasVisible.push(card);
    });
    cards.forEach(function (card) { card.classList.add('hidden'); });
    posts.slice(start, end).forEach(function (card, index) {
      if (wasVisible.indexOf(card) === -1) {
        card.style.setProperty('--i', String(Math.min(index, 7)));
      }
      card.classList.remove('hidden');
    });

    if (gridHeading) {
      gridHeading.textContent = state.cat === 'all' ? 'All posts' : CAT_LABELS[state.cat];
    }

    // Status line. Grammar: "45 posts" unfiltered, "5 in Privacy" filtered;
    // from page 2 on, "Showing 13–24 of 45 posts" / "Showing 13–24 of 8 in Storage".
    if (resultCount) {
      var ranged = '\u2013';
      if (total === 0) {
        resultCount.textContent = '';
      } else if (state.cat === 'all') {
        resultCount.textContent = state.page > 1
          ? 'Showing ' + (start + 1) + ranged + end + ' of ' + total + ' posts'
          : total + ' posts';
      } else {
        resultCount.textContent = state.page > 1
          ? 'Showing ' + (start + 1) + ranged + end + ' of ' + total + ' in ' + CAT_LABELS[state.cat]
          : total + ' in ' + CAT_LABELS[state.cat];
      }
    }

    if (emptyState) emptyState.classList.toggle('hidden', total !== 0);

    if (pagination && pageButtons && prevBtn && nextBtn) {
      // Container ships with `hidden` (no-JS users never see dead controls).
      pagination.classList.remove('hidden');
      pageButtons.textContent = '';
      if (totalPages > 1) {
        for (var i = 1; i <= totalPages; i++) {
          var btn = document.createElement('button');
          btn.type = 'button';
          btn.textContent = String(i);
          btn.className = i === state.page ? PAGE_ACTIVE : PAGE_INACTIVE;
          btn.setAttribute('aria-label', 'Page ' + i);
          if (i === state.page) btn.setAttribute('aria-current', 'page');
          (function (target) {
            btn.addEventListener('click', function () {
              if (state.page === target) return;
              state.page = target;
              syncUrl('push');
              render(false);
              scrollToTop();
            });
          })(i);
          pageButtons.appendChild(btn);
        }
        prevBtn.disabled = state.page === 1;
        nextBtn.disabled = state.page === totalPages;
      } else {
        prevBtn.disabled = true;
        nextBtn.disabled = true;
        pagination.classList.add('hidden');
      }
    }

    if (focusHeading && gridHeading && gridHeading.focus) gridHeading.focus();
  }

  function setFilter(cat, focusHeading) {
    if (CATS.indexOf(cat) === -1) cat = 'all';
    state.cat = cat;
    state.page = 1;
    syncUrl('push');
    applyChips();
    render(focusHeading);
  }

  chips.forEach(function (chip) {
    chip.addEventListener('click', function () {
      setFilter(chip.getAttribute('data-filter'), true);
    });
  });

  if (prevBtn) {
    prevBtn.addEventListener('click', function () {
      if (state.page > 1) {
        state.page -= 1;
        syncUrl('push');
        render(false);
        scrollToTop();
      }
    });
  }

  if (nextBtn) {
    nextBtn.addEventListener('click', function () {
      var totalPages = Math.max(1, Math.ceil(filteredPosts().length / PER_PAGE));
      if (state.page < totalPages) {
        state.page += 1;
        syncUrl('push');
        render(false);
        scrollToTop();
      }
    });
  }

  if (emptyAllLink) {
    emptyAllLink.addEventListener('click', function (event) {
      event.preventDefault();
      setFilter('all', true);
    });
  }

  window.addEventListener('popstate', function () {
    state = parseStateFromUrl();
    applyChips();
    render(true);
    syncUrl('replace'); // normalize junk params (e.g. ?cat=bogus&page=99)
  });

  // Init: restore ?cat=&page= from the URL, then normalize the address bar.
  state = parseStateFromUrl();
  applyChips();
  render(false);
  syncUrl('replace');
})();
