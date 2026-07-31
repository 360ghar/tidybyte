// Blog hub filtering + pagination (loaded via <script defer> so the CSP
// `script-src 'self'` policy in netlify.toml can allow it).
(function() {
  const PER_PAGE = 12;
  const allPosts = document.querySelectorAll('#blog-list article');
  const filterBtns = document.querySelectorAll('.filter-btn');
  const pageButtons = document.getElementById('page-buttons');
  const prevBtn = document.getElementById('prev-btn');
  const nextBtn = document.getElementById('next-btn');
  const resultCount = document.getElementById('result-count');
  const pagination = document.getElementById('pagination');

  let currentFilter = 'all';
  let currentPage = 1;

  function getFilteredPosts() {
    if (currentFilter === 'all') return Array.from(allPosts);
    return Array.from(allPosts).filter(p => p.dataset.cats.includes(currentFilter));
  }

  function updateView() {
    const filtered = getFilteredPosts();
    const totalPages = Math.max(1, Math.ceil(filtered.length / PER_PAGE));
    if (currentPage > totalPages) currentPage = totalPages;

    // Hide all, then show current page
    allPosts.forEach(p => p.classList.add('hidden'));
    const start = (currentPage - 1) * PER_PAGE;
    const end = start + PER_PAGE;
    filtered.slice(start, end).forEach(p => p.classList.remove('hidden'));

    // Update result count
    const catName = currentFilter === 'all' ? 'all' : currentFilter;
    const showing = filtered.length === 0 ? 'No' : `${Math.min(end, filtered.length)} of ${filtered.length}`;
    resultCount.textContent = currentFilter === 'all'
      ? `Showing all ${filtered.length} guides`
      : `Showing ${showing} ${catName} guides`;

    // Update pagination
    pageButtons.innerHTML = '';
    if (totalPages > 1) {
      pagination.style.display = '';
      for (let i = 1; i <= totalPages; i++) {
        const btn = document.createElement('button');
        btn.className = 'pagination-btn rounded-lg border border-white/10 px-3 py-2 text-sm text-zinc-300 transition hover:border-white/20 hover:text-white' + (i === currentPage ? ' active' : '');
        btn.textContent = i;
        btn.setAttribute('aria-label', `Page ${i}`);
        if (i === currentPage) btn.setAttribute('aria-current', 'page');
        btn.addEventListener('click', () => { currentPage = i; updateView(); window.scrollTo({top: 0, behavior: 'smooth'}); });
        pageButtons.appendChild(btn);
      }
      prevBtn.disabled = currentPage === 1;
      nextBtn.disabled = currentPage === totalPages;
    } else {
      pagination.style.display = 'none';
    }
  }

  filterBtns.forEach(btn => {
    btn.addEventListener('click', () => {
      filterBtns.forEach(b => b.classList.remove('active'));
      btn.classList.add('active');
      currentFilter = btn.dataset.filter;
      currentPage = 1;
      updateView();
    });
  });

  prevBtn.addEventListener('click', () => { if (currentPage > 1) { currentPage--; updateView(); } });
  nextBtn.addEventListener('click', () => {
    const filtered = getFilteredPosts();
    const totalPages = Math.ceil(filtered.length / PER_PAGE);
    if (currentPage < totalPages) { currentPage++; updateView(); }
  });

  updateView();
})();
