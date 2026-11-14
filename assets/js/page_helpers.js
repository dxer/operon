/**
 * Operon page helpers.
 *
 * Only what has to run inside the document: the fingerprint masking a browser
 * needs, and the reading-mode helpers, which remove nodes and re-expand article
 * bodies — things unavailable from outside the page.
 *
 * Nothing here observes a page for an agent or acts on its behalf, and nothing
 * here draws: the agent works over the DevTools protocol, and the gesture
 * overlay is a Flutter widget above the WebView.
 */
(function () {
  if (window.OPERON && window.OPERON.version === '0.4.0') {
    return;
  }

  // ==========================================
  // 1. Stealth Mode: Anti-Bot Masking Patches
  // ==========================================
  try {
    // 1.1 Mask navigator.webdriver
    Object.defineProperty(navigator, 'webdriver', {
      get: () => undefined,
      configurable: true,
    });

    // 1.2 Mock window.chrome runtime
    if (!window.chrome) {
      window.chrome = {
        runtime: {},
        app: {},
        loadTimes: function () {},
        csi: function () {},
      };
    }

    // 1.3 Mock navigator.languages
    if (!navigator.languages || navigator.languages.length === 0) {
      Object.defineProperty(navigator, 'languages', {
        get: () => ['zh-CN', 'zh', 'en-US', 'en'],
        configurable: true,
      });
    }
  } catch (_) {}

  const engine = {
    version: '0.4.0',

    /// Mobile clean reader: removes app-jump banners and modal masks, and
    /// re-expands article bodies the page collapsed behind "read more".
    cleanPageMode: function () {
      let removedCount = 0;
      let expandedCount = 0;

      // 8.1 Remove common mobile download app banners & modal masks
      const adSelectors = [
        '.openApp', '.open-app', '[class*="openApp"]', '[class*="download-app"]',
        '[class*="open-in-app"]', '[class*="app-banner"]', '[id*="app-banner"]',
        '.modal-mask', '.pop-window', '.download-bar', '.bottom-bar-download',
        '[class*="callup"]', '[class*="scheme-box"]', '.guide-app',
        '.wx-open-launch-app', '[class*="jump-app"]'
      ];

      adSelectors.forEach(sel => {
        try {
          const els = document.querySelectorAll(sel);
          els.forEach(el => {
            el.style.display = 'none';
            el.remove();
            removedCount++;
          });
        } catch (_) {}
      });

      // 8.2 Auto-expand collapsed article bodies
      const expandSelectors = [
        'button', 'a', 'div', 'span'
      ];
      const expandKeywords = ['展开全文', '阅读全文', '查看全文', '展开阅读', '查看更多', 'read more', 'show more'];

      document.querySelectorAll(expandSelectors.join(',')).forEach(el => {
        const text = (el.innerText || el.textContent || '').trim().toLowerCase();
        if (expandKeywords.some(kw => text === kw || (text.length <= 10 && text.includes(kw)))) {
          try {
            el.click();
            expandedCount++;
          } catch (_) {}
        }
      });

      // 8.3 Unlock scroll & selection restriction
      try {
        if (document.documentElement) {
          document.documentElement.style.overflow = 'auto';
          document.documentElement.style.height = 'auto';
          document.documentElement.style.position = 'static';
        }
        if (document.body) {
          document.body.style.overflow = 'auto';
          document.body.style.height = 'auto';
          document.body.style.position = 'static';
          document.body.style.userSelect = 'auto';
          document.body.style.webkitUserSelect = 'auto';
        }
      } catch (_) {}

      // 8.4 Expand restricted max-heights on content containers
      document.querySelectorAll('[class*="content"], [class*="article"], main, article').forEach(el => {
        if (el.style.maxHeight || el.style.height) {
          el.style.maxHeight = 'none';
          el.style.height = 'auto';
          el.style.overflow = 'visible';
        }
      });

      return JSON.stringify({
        success: true,
        removedCount,
        expandedCount
      });
    },

    extractReadableContent: function () {
      const title = document.title || '';
      let metaDesc = '';
      const metaTag = document.querySelector('meta[name="description"]') ||
                      document.querySelector('meta[property="og:description"]');
      if (metaTag) {
        metaDesc = metaTag.getAttribute('content') || '';
      }

      // Candidate containers
      const candidates = ['article', 'main', '[role="main"]', '.post-content', '.article-content', '.entry-content', '#content', 'body'];
      let bestElement = null;
      let maxLen = 0;

      for (const sel of candidates) {
        const el = document.querySelector(sel);
        if (el) {
          const txt = (el.innerText || '').trim();
          if (txt.length > maxLen) {
            maxLen = txt.length;
            bestElement = el;
          }
        }
      }

      if (!bestElement) {
        bestElement = document.body;
      }

      // Clone and sanitize
      let text = '';
      if (bestElement) {
        const clone = bestElement.cloneNode(true);
        // Remove junk elements
        const junks = clone.querySelectorAll('script, style, noscript, iframe, svg, nav, footer, header, [role="navigation"]');
        junks.forEach(j => j.remove());
        text = (clone.innerText || clone.textContent || '')
          .replace(/\n\s*\n\s*\n/g, '\n\n')
          .trim();
      }

      // Truncate to reasonable token limit (~6000 chars)
      if (text.length > 6000) {
        text = text.substring(0, 6000) + '\n\n...(篇幅过长，已截取前文)...';
      }

      return JSON.stringify({
        title,
        url: window.location.href || '',
        description: metaDesc,
        content: text,
        length: text.length
      });
    },

    /// The current selection, with the rect the action menu anchors to.
    getSelectedTextInfo: function () {
      const sel = window.getSelection();
      if (!sel || sel.isCollapsed) return JSON.stringify({ hasSelection: false });
      const text = sel.toString().trim();
      if (!text) return JSON.stringify({ hasSelection: false });

      let rect = { x: 0, y: 0, width: 0, height: 0 };
      if (sel.rangeCount > 0) {
        const range = sel.getRangeAt(0);
        const clientRect = range.getBoundingClientRect();
        rect = {
          x: clientRect.left,
          y: clientRect.top,
          width: clientRect.width,
          height: clientRect.height
        };
      }

      return JSON.stringify({
        hasSelection: true,
        text: text,
        rect: rect
      });
    }
  };

  window.OPERON = window.BBX_AGENT = engine;
})();
