/* =============================================================
   Daily Cadence — Theme toggle
   -------------------------------------------------------------
   - Reads saved pref from localStorage('dc-theme')
   - Falls back to prefers-color-scheme
   - Exposes window.DCTheme.set('light' | 'dark' | 'system')
   - Renders a floating sun/moon pill in the corner
   ============================================================= */
(function () {
  const KEY = 'dc-theme';

  function getSaved() {
    try { return localStorage.getItem(KEY); } catch (e) { return null; }
  }
  function setSaved(v) {
    try { v ? localStorage.setItem(KEY, v) : localStorage.removeItem(KEY); } catch (e) {}
  }
  function systemPrefersDark() {
    return window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches;
  }
  function resolve(pref) {
    if (pref === 'dark' || pref === 'light') return pref;
    return systemPrefersDark() ? 'dark' : 'light';
  }
  function apply(pref) {
    const mode = resolve(pref);
    document.documentElement.setAttribute('data-theme', mode);
    document.documentElement.style.colorScheme = mode;
    // Let other scripts react
    window.dispatchEvent(new CustomEvent('dc-theme-change', { detail: { mode, pref } }));
  }

  // Apply ASAP to avoid flash (script is loaded in <head>)
  const initialPref = getSaved() || 'system';
  apply(initialPref);

  // Update when system changes (only if user is on 'system')
  if (window.matchMedia) {
    const mql = window.matchMedia('(prefers-color-scheme: dark)');
    const onChange = () => {
      if ((getSaved() || 'system') === 'system') apply('system');
    };
    mql.addEventListener ? mql.addEventListener('change', onChange) : mql.addListener(onChange);
  }

  // Public API
  const DCTheme = {
    get: () => getSaved() || 'system',
    resolved: () => document.documentElement.getAttribute('data-theme') || 'light',
    set: (pref) => { setSaved(pref === 'system' ? null : pref); apply(pref); renderToggle(); },
  };
  window.DCTheme = DCTheme;

  // ---------------------------------------------------------
  // Floating toggle pill (3-state: Light / Dark / Auto)
  // ---------------------------------------------------------
  let host = null;

  function ensureStyles() {
    if (document.getElementById('dc-theme-toggle-styles')) return;
    const s = document.createElement('style');
    s.id = 'dc-theme-toggle-styles';
    s.textContent = `
      .dc-theme-toggle {
        position: fixed; bottom: 16px; right: 16px; z-index: 9999;
        display: inline-flex; align-items: center; gap: 2px;
        padding: 3px; border-radius: 999px;
        background: var(--bg-2); border: 1px solid var(--border-1);
        box-shadow: var(--shadow-2);
        font-family: var(--font-sans); font-size: 11px;
      }
      .dc-theme-toggle button {
        display: inline-flex; align-items: center; justify-content: center;
        gap: 5px; padding: 6px 10px; border-radius: 999px;
        border: 0; background: transparent; cursor: pointer;
        color: var(--fg-2); font-weight: 500; font-family: inherit; font-size: inherit;
        transition: background 140ms, color 140ms;
      }
      .dc-theme-toggle button:hover { color: var(--fg-1); }
      .dc-theme-toggle button.on {
        background: var(--dc-ink); color: var(--dc-cream);
      }
      :root[data-theme="dark"] .dc-theme-toggle button.on {
        background: var(--dc-sage-soft); color: var(--dc-sage-deep);
      }
      .dc-theme-toggle svg {
        width: 13px; height: 13px; stroke-width: 2;
        stroke: currentColor; fill: none; stroke-linecap: round; stroke-linejoin: round;
      }
      @media print { .dc-theme-toggle { display: none !important; } }
    `;
    document.head.appendChild(s);
  }

  const ICONS = {
    light: '<svg viewBox="0 0 24 24"><circle cx="12" cy="12" r="4"/><path d="M12 2v2M12 20v2M4.93 4.93l1.41 1.41M17.66 17.66l1.41 1.41M2 12h2M20 12h2M4.93 19.07l1.41-1.41M17.66 6.34l1.41-1.41"/></svg>',
    dark: '<svg viewBox="0 0 24 24"><path d="M21 12.79A9 9 0 1 1 11.21 3 7 7 0 0 0 21 12.79z"/></svg>',
    auto: '<svg viewBox="0 0 24 24"><circle cx="12" cy="12" r="9"/><path d="M12 3a9 9 0 0 0 0 18z" fill="currentColor" stroke="none"/></svg>',
  };

  function renderToggle() {
    if (!host) return;
    const pref = DCTheme.get();
    host.innerHTML = `
      <button data-mode="light" class="${pref==='light'?'on':''}" aria-label="Light mode" title="Light">${ICONS.light}</button>
      <button data-mode="dark"   class="${pref==='dark' ?'on':''}" aria-label="Dark mode"  title="Dark">${ICONS.dark}</button>
      <button data-mode="system" class="${pref==='system'?'on':''}" aria-label="Match system"  title="Auto">${ICONS.auto}</button>
    `;
  }

  function mount(options) {
    options = options || {};
    if (host) return; // already mounted
    ensureStyles();
    host = document.createElement('div');
    host.className = 'dc-theme-toggle';
    if (options.position === 'top-right') {
      host.style.top = '16px'; host.style.bottom = 'auto';
    }
    host.addEventListener('click', (e) => {
      const b = e.target.closest('button[data-mode]');
      if (!b) return;
      DCTheme.set(b.dataset.mode);
    });
    document.body.appendChild(host);
    renderToggle();
  }

  DCTheme.mount = mount;

  // Auto-mount unless the host page opts out with <script ... data-no-toggle>
  function autoMount() {
    const tag = document.currentScript || document.querySelector('script[src*="theme-toggle.js"]');
    if (tag && tag.hasAttribute('data-no-toggle')) return;
    if (document.readyState === 'loading') {
      document.addEventListener('DOMContentLoaded', () => mount());
    } else {
      mount();
    }
  }
  autoMount();
})();
