// Base path to reports (relative to reportviewer/)
const REPORTS_BASE = '../reports';

// ── State ──
let reportIndex = {};
let allReports = [];   // flat list: { period, file, label }
let activeIdx = -1;

// ── Boot ──
async function init() {
  try {
    const res = await fetch(`${REPORTS_BASE}/index.json`);
    reportIndex = await res.json();
  } catch {
    console.warn('Could not load reports/index.json — run Update-ReportsIndex.ps1.');
    return;
  }
  buildNav();
  handleDeepLink();
}

// ── Navigation ──
function buildNav() {
  const nav = document.getElementById('sidebarNav');
  nav.innerHTML = '';
  allReports = [];

  // Sort periods descending (newest first)
  const periods = Object.keys(reportIndex).sort().reverse();

  periods.forEach((period, pi) => {
    const files = reportIndex[period];
    const group = document.createElement('div');
    group.className = 'period-group';

    const header = document.createElement('div');
    header.className = 'period-header';
    header.innerHTML = `
      <svg class="chevron" viewBox="0 0 16 16" fill="currentColor">
        <path d="M6 3.5l4.5 4.5L6 12.5" stroke="currentColor" stroke-width="1.5" fill="none" stroke-linecap="round" stroke-linejoin="round"/>
      </svg>
      <span class="period-label">${formatPeriod(period)}</span>
      <span class="period-count">${files.length}</span>
    `;

    const list = document.createElement('div');
    list.className = 'period-reports';

    files.sort((a, b) => {
      const aSum = /summary/i.test(a) ? 0 : 1;
      const bSum = /summary/i.test(b) ? 0 : 1;
      return aSum - bSum || a.localeCompare(b);
    }).forEach(file => {
      const label = file.replace(/\.md$/i, '');
      const idx = allReports.length;
      allReports.push({ period, file, label });

      const link = document.createElement('div');
      link.className = 'report-link';
      link.dataset.idx = idx;
      link.innerHTML = `<span class="dot"></span>${label}`;
      link.onclick = () => selectReport(idx);
      list.appendChild(link);
    });

    header.onclick = () => {
      header.classList.toggle('collapsed');
      list.classList.toggle('collapsed');
    };

    // Set initial max-height for animation
    group.appendChild(header);
    group.appendChild(list);
    nav.appendChild(group);

    requestAnimationFrame(() => {
      list.style.maxHeight = list.scrollHeight + 'px';
    });
  });
}

function formatPeriod(p) {
  // "20260223-20260301" → "Feb 23 – Mar 01, 2026"
  const m = p.match(/^(\d{4})(\d{2})(\d{2})-(\d{4})(\d{2})(\d{2})$/);
  if (!m) return p;
  const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
  const [, y1, mo1, d1, y2, mo2, d2] = m;
  const from = `${months[+mo1 - 1]} ${+d1}`;
  const to = `${months[+mo2 - 1]} ${+d2}`;
  return `${from} – ${to}, ${y2}`;
}

async function selectReport(idx) {
  if (idx < 0 || idx >= allReports.length) return;
  activeIdx = idx;
  const { period, file, label } = allReports[idx];

  // Update URL hash
  location.hash = `${period}/${file}`;

  // Highlight active link
  document.querySelectorAll('.report-link').forEach(el => {
    el.classList.toggle('active', +el.dataset.idx === idx);
  });

  // Update breadcrumb
  document.getElementById('breadcrumb').innerHTML = `
    <span>${formatPeriod(period)}</span>
    <span class="sep">/</span>
    <span class="current">${label}</span>
  `;

  // Close mobile sidebar
  closeSidebar();

  // Show loading
  const article = document.getElementById('article');
  const empty = document.getElementById('emptyState');
  const body = document.getElementById('markdownBody');
  empty.style.display = 'none';
  article.style.display = 'none';
  body.innerHTML = '<div class="loading"><div class="loading-spinner"></div>Loading…</div>';
  article.style.display = 'block';

  // Fetch markdown
  try {
    const res = await fetch(`${REPORTS_BASE}/${period}/${encodeURIComponent(file)}`);
    if (!res.ok) throw new Error(res.statusText);
    const md = await res.text();
    const html = marked.parse(md);
    body.innerHTML = html;

    // Re-trigger animation
    article.style.animation = 'none';
    article.offsetHeight;
    article.style.animation = '';

    // Show word count
    const words = md.replace(/[#*_\-\[\]()>|]/g, '').split(/\s+/).filter(Boolean).length;
    document.getElementById('topbarMeta').textContent = `${words.toLocaleString()} words`;
  } catch (err) {
    body.innerHTML = `<p style="color:var(--red)">Failed to load report: ${err.message}</p>`;
    document.getElementById('topbarMeta').textContent = '';
  }

  // Scroll to top
  document.getElementById('contentScroll').scrollTop = 0;
}

function handleDeepLink() {
  const hash = decodeURIComponent(location.hash.slice(1));
  if (!hash) return;
  const idx = allReports.findIndex(r => `${r.period}/${r.file}` === hash);
  if (idx >= 0) selectReport(idx);
}

// ── Keyboard Navigation ──
document.addEventListener('keydown', e => {
  if (e.key === 'ArrowDown' || e.key === 'j') {
    e.preventDefault();
    selectReport(Math.min(activeIdx + 1, allReports.length - 1));
  } else if (e.key === 'ArrowUp' || e.key === 'k') {
    e.preventDefault();
    selectReport(Math.max(activeIdx - 1, 0));
  } else if (e.key === 'Enter') {
    e.preventDefault();
    if (activeIdx < 0 && allReports.length > 0) selectReport(0);
    else if (activeIdx >= 0) selectReport(activeIdx);
  }
});

// ── Mobile Sidebar ──
function toggleSidebar() {
  document.getElementById('sidebar').classList.toggle('open');
  document.getElementById('overlay').classList.toggle('active');
}

function closeSidebar() {
  document.getElementById('sidebar').classList.remove('open');
  document.getElementById('overlay').classList.remove('active');
}

// ── Theme Toggle ──
function toggleTheme() {
  const current = document.documentElement.getAttribute('data-theme');
  const next = current === 'light' ? 'dark' : 'light';
  document.documentElement.setAttribute('data-theme', next);
  localStorage.setItem('theme', next);
}

// Restore saved theme
(function() {
  const saved = localStorage.getItem('theme');
  if (saved) document.documentElement.setAttribute('data-theme', saved);
})();

// ── Init ──
init();
