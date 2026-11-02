/**
 * BBX Universal Agent DOM Engine (v2.0)
 * Advanced Injected Engine for Universal Web Browsing, Deep Shadow DOM inspection,
 * Keyboard Emulation, Content/Data Extraction, and Synthetic Actions.
 */
(function () {
  if (window.BBX_AGENT && window.BBX_AGENT.version === '2.0') {
    return;
  }

  const BADGE_CONTAINER_ID = '__bbx_agent_badge_container__';
  let elementsMap = new Map();
  let nextElementId = 1;

  // 1. Recursive Shadow DOM & Light DOM Selector
  function querySelectorAllDeep(root, selector) {
    let results = [];
    if (!root) return results;

    try {
      if (typeof root.querySelectorAll === 'function') {
        const matches = root.querySelectorAll(selector);
        for (let i = 0; i < matches.length; i++) {
          results.push(matches[i]);
        }
      }
    } catch (_) {}

    // Deep traverse open Shadow Roots
    try {
      const allDescendants = root.querySelectorAll ? root.querySelectorAll('*') : [];
      for (let i = 0; i < allDescendants.length; i++) {
        const child = allDescendants[i];
        if (child.shadowRoot) {
          results = results.concat(querySelectorAllDeep(child.shadowRoot, selector));
        }
      }
    } catch (_) {}

    return results;
  }

  // 2. Visibility & Geometry Check
  function isVisible(el) {
    if (!el || el.nodeType !== (typeof Node !== 'undefined' ? Node.ELEMENT_NODE : 1)) return false;
    if (typeof window.getComputedStyle !== 'function') return true;

    const style = window.getComputedStyle(el);
    if (
      style.display === 'none' ||
      style.visibility === 'hidden' ||
      parseFloat(style.opacity) === 0
    ) {
      return false;
    }

    if (typeof el.getBoundingClientRect !== 'function') return false;
    const rect = el.getBoundingClientRect();
    if (rect.width <= 0 || rect.height <= 0) return false;

    // Viewport check (allow slight buffer)
    const viewportHeight = window.innerHeight || (document.documentElement ? document.documentElement.clientHeight : 800);
    const viewportWidth = window.innerWidth || (document.documentElement ? document.documentElement.clientWidth : 400);

    const inViewport =
      rect.bottom >= -50 &&
      rect.top <= viewportHeight + 50 &&
      rect.right >= 0 &&
      rect.left <= viewportWidth;

    return inViewport;
  }

  function cleanText(text, maxLen = 70) {
    if (!text) return '';
    const cleaned = text.replace(/\s+/g, ' ').trim();
    if (cleaned.length > maxLen) {
      return cleaned.slice(0, maxLen) + '...';
    }
    return cleaned;
  }

  function getElementLabel(el) {
    const ariaLabel = el.getAttribute ? el.getAttribute('aria-label') : null;
    if (ariaLabel) return cleanText(ariaLabel);

    const placeholder = el.getAttribute ? el.getAttribute('placeholder') : null;
    if (placeholder) return cleanText(placeholder);

    const title = el.getAttribute ? el.getAttribute('title') : null;
    if (title) return cleanText(title);

    const alt = el.getAttribute ? el.getAttribute('alt') : null;
    if (alt) return cleanText(alt);

    if (el.tagName === 'INPUT') {
      if (el.value) return `value="${cleanText(el.value)}"`;
      return '';
    }

    if (el.tagName === 'SELECT') {
      const selected = el.options && el.selectedIndex >= 0 ? el.options[el.selectedIndex] : null;
      return selected ? `selected="${cleanText(selected.text || selected.value)}"` : '';
    }

    const text = el.innerText || el.textContent;
    return cleanText(text);
  }

  function determineElementType(el) {
    const tag = (el.tagName || '').toLowerCase();
    const role = el.getAttribute ? el.getAttribute('role') : null;
    const isContentEditable = (el.getAttribute && el.getAttribute('contenteditable') === 'true') || el.isContentEditable;

    if (isContentEditable) return 'EDITABLE';
    if (tag === 'button' || role === 'button') return 'BUTTON';
    if (tag === 'a' && el.hasAttribute && el.hasAttribute('href')) return 'LINK';
    if (tag === 'input') {
      const type = (el.getAttribute ? el.getAttribute('type') || 'text' : 'text').toLowerCase();
      if (type === 'checkbox' || role === 'checkbox') return 'CHECKBOX';
      if (type === 'radio' || role === 'radio') return 'RADIO';
      if (type === 'submit' || type === 'button') return 'BUTTON';
      return `INPUT[${type}]`;
    }
    if (tag === 'textarea') return 'TEXTAREA';
    if (tag === 'select') return 'SELECT';
    if (role === 'tab') return 'TAB';
    if (role === 'menuitem') return 'MENUITEM';

    return 'CLICKABLE';
  }

  function removeBadges() {
    const container = document.getElementById(BADGE_CONTAINER_ID);
    if (container) {
      container.remove();
    }
    const elements = document.querySelectorAll ? document.querySelectorAll('[data-bbx-id]') : [];
    for (let i = 0; i < elements.length; i++) {
      elements[i].removeAttribute('data-bbx-id');
    }
  }

  function createBadge(id, rect) {
    const badge = document.createElement('div');
    badge.className = '__bbx_badge__';
    badge.textContent = id;
    badge.style.position = 'absolute';
    badge.style.left = `${Math.max(0, rect.left + (window.scrollX || 0))}px`;
    badge.style.top = `${Math.max(0, rect.top + (window.scrollY || 0))}px`;
    badge.style.backgroundColor = '#1d9bf0';
    badge.style.color = '#ffffff';
    badge.style.fontSize = '10px';
    badge.style.fontWeight = 'bold';
    badge.style.padding = '1px 4px';
    badge.style.borderRadius = '3px';
    badge.style.zIndex = '2147483647';
    badge.style.pointerEvents = 'none';
    badge.style.boxShadow = '0 1px 3px rgba(0,0,0,0.5)';
    badge.style.fontFamily = 'monospace';
    return badge;
  }

  // 3. Content Block Extractor (for general Scraping / Reading)
  function extractContentBlocks(maxBlocks = 15) {
    const contentSelectors = 'h1, h2, h3, h4, article, blockquote, [data-testid="tweetText"], .article-content, .post-content';
    const contentNodes = querySelectorAllDeep(document, contentSelectors);
    const lines = [];

    for (let i = 0; i < contentNodes.length && lines.length < maxBlocks; i++) {
      const node = contentNodes[i];
      if (!isVisible(node)) continue;
      const text = cleanText(node.innerText || node.textContent, 100);
      if (text.length > 8) {
        lines.push(`• [${node.tagName}]: "${text}"`);
      }
    }
    return lines;
  }

  const engine = {
    version: '2.0',

    /**
     * Extracts observable interactive elements & key content blocks
     */
    extractPrunedDOM: function (showVisualBadges = true, includeContent = true) {
      removeBadges();
      elementsMap.clear();
      nextElementId = 1;

      let badgeContainer = null;
      if (showVisualBadges && document.body) {
        badgeContainer = document.createElement('div');
        badgeContainer.id = BADGE_CONTAINER_ID;
        badgeContainer.style.position = 'absolute';
        badgeContainer.style.top = '0';
        badgeContainer.style.left = '0';
        badgeContainer.style.width = '100%';
        badgeContainer.style.height = '100%';
        badgeContainer.style.pointerEvents = 'none';
        badgeContainer.style.zIndex = '2147483646';
        document.body.appendChild(badgeContainer);
      }

      // Universal interactive selector covering Shadow DOM, SPAs, and standard HTML
      const selector = [
        'button',
        'a[href]',
        'input',
        'textarea',
        'select',
        '[role="button"]',
        '[role="link"]',
        '[role="textbox"]',
        '[role="menuitem"]',
        '[role="tab"]',
        '[role="checkbox"]',
        '[role="radio"]',
        '[contenteditable="true"]',
        '[tabindex="0"]',
        '[data-testid]',
      ].join(',');

      const candidates = querySelectorAllDeep(document, selector);
      const interactiveLines = [];

      candidates.forEach((el) => {
        if (!isVisible(el)) return;

        // Skip nested redundant child
        const parent = el.parentElement;
        if (
          parent &&
          elementsMap.has(parent.getAttribute('data-bbx-id')) &&
          el.innerText === parent.innerText
        ) {
          return;
        }

        const id = nextElementId++;
        el.setAttribute('data-bbx-id', id.toString());
        elementsMap.set(id.toString(), el);

        const type = determineElementType(el);
        const label = getElementLabel(el);

        if (badgeContainer) {
          const rect = el.getBoundingClientRect();
          badgeContainer.appendChild(createBadge(id, rect));
        }

        if (label || type === 'BUTTON' || type === 'EDITABLE' || type.startsWith('INPUT') || type === 'SELECT') {
          interactiveLines.push(`[${id}] ${type}: ${label || '(empty)'}`);
        }
      });

      // Extract key textual headings/content for scraping tasks
      const contentLines = includeContent ? extractContentBlocks(10) : [];

      let combinedTree = '';
      if (contentLines.length > 0) {
        combinedTree += '【页面主要内容摘要】:\n' + contentLines.join('\n') + '\n\n';
      }
      combinedTree += '【可交互操作元素】:\n' + (interactiveLines.join('\n') || '(无明显交互元素，可尝试滚动)');

      return JSON.stringify({
        url: (window.location && window.location.href) ? window.location.href : '',
        title: document.title || '',
        elementCount: elementsMap.size,
        text_tree: combinedTree,
      });
    },

    /**
     * Executes atomic actions
     */
    executeAction: function (actionJson) {
      const parsed = typeof actionJson === 'string' ? JSON.parse(actionJson) : actionJson;
      const act = parsed.action;
      const params = parsed.params || {};

      switch (act) {
        case 'click': {
          const id = (params.element_id || '').toString();
          const el = elementsMap.get(id) || document.querySelector(`[data-bbx-id="${id}"]`);
          if (!el) {
            return JSON.stringify({ success: false, error: `Element [${id}] not found in DOM` });
          }

          if (typeof el.scrollIntoView === 'function') {
            el.scrollIntoView({ behavior: 'smooth', block: 'center' });
          }

          const rect = el.getBoundingClientRect ? el.getBoundingClientRect() : { left: 0, top: 0, width: 0, height: 0 };
          const clientX = rect.left + rect.width / 2;
          const clientY = rect.top + rect.height / 2;

          const eventInit = {
            bubbles: true,
            cancelable: true,
            view: window,
            clientX: clientX,
            clientY: clientY,
          };

          if (typeof PointerEvent !== 'undefined') {
            try { el.dispatchEvent(new PointerEvent('pointerdown', eventInit)); } catch (_) {}
          }
          if (typeof MouseEvent !== 'undefined') {
            try { el.dispatchEvent(new MouseEvent('mousedown', eventInit)); } catch (_) {}
          }
          if (typeof PointerEvent !== 'undefined') {
            try { el.dispatchEvent(new PointerEvent('pointerup', eventInit)); } catch (_) {}
          }
          if (typeof MouseEvent !== 'undefined') {
            try { el.dispatchEvent(new MouseEvent('mouseup', eventInit)); } catch (_) {}
            try { el.dispatchEvent(new MouseEvent('click', eventInit)); } catch (_) {}
          }
          if (typeof el.click === 'function') {
            try { el.click(); } catch (_) {}
          }
          if (typeof el.focus === 'function') {
            try { el.focus(); } catch (_) {}
          }

          if (el.tagName === 'A' && el.href && !el.href.startsWith('javascript:')) {
            setTimeout(() => {
              if (window.location && window.location.href !== el.href) {
                window.location.href = el.href;
              }
            }, 300);
          }

          return JSON.stringify({ success: true, message: `Clicked element [${id}]` });
        }

        case 'type': {
          const id = (params.element_id || '').toString();
          const text = params.text || '';
          const clearFirst = params.clear_first !== false;

          const el = elementsMap.get(id) || document.querySelector(`[data-bbx-id="${id}"]`);
          if (!el) {
            return JSON.stringify({ success: false, error: `Element [${id}] not found in DOM` });
          }

          if (typeof el.scrollIntoView === 'function') {
            el.scrollIntoView({ behavior: 'smooth', block: 'center' });
          }
          if (typeof el.focus === 'function') {
            el.focus();
          }

          const isEditable = (el.getAttribute && el.getAttribute('contenteditable') === 'true') || el.isContentEditable;

          if (isEditable) {
            let handled = false;
            if (typeof document.execCommand === 'function') {
              try {
                if (clearFirst) {
                  document.execCommand('selectAll', false, null);
                }
                handled = document.execCommand('insertText', false, text);
              } catch (_) {}
            }
            if (!handled) {
              el.innerText = text;
            }

            if (typeof InputEvent !== 'undefined') {
              try {
                el.dispatchEvent(
                  new InputEvent('input', {
                    bubbles: true,
                    cancelable: true,
                    inputType: 'insertText',
                    data: text,
                  })
                );
              } catch (_) {}
            } else if (typeof Event !== 'undefined') {
              try { el.dispatchEvent(new Event('input', { bubbles: true })); } catch (_) {}
            }
          } else if (el.tagName === 'INPUT' || el.tagName === 'TEXTAREA') {
            if (clearFirst) {
              el.value = '';
            }
            el.value = text;
            if (typeof Event !== 'undefined') {
              try {
                el.dispatchEvent(new Event('input', { bubbles: true }));
                el.dispatchEvent(new Event('change', { bubbles: true }));
              } catch (_) {}
            }
          } else {
            el.innerText = text;
          }

          return JSON.stringify({ success: true, message: `Typed into element [${id}]` });
        }

        case 'press_key': {
          // Universal keyboard emulation: Enter, Escape, Backspace, Tab
          const keyName = params.key || 'Enter';
          const id = params.element_id ? params.element_id.toString() : null;
          const target = (id ? (elementsMap.get(id) || document.querySelector(`[data-bbx-id="${id}"]`)) : null) || document.activeElement || document.body;

          let keyCode = 13;
          if (keyName.toLowerCase() === 'escape') keyCode = 27;
          else if (keyName.toLowerCase() === 'backspace') keyCode = 8;
          else if (keyName.toLowerCase() === 'tab') keyCode = 9;

          const keyEventInit = {
            key: keyName,
            code: keyName,
            keyCode: keyCode,
            which: keyCode,
            bubbles: true,
            cancelable: true,
            view: window,
          };

          if (typeof KeyboardEvent !== 'undefined') {
            try {
              target.dispatchEvent(new KeyboardEvent('keydown', keyEventInit));
              target.dispatchEvent(new KeyboardEvent('keypress', keyEventInit));
              target.dispatchEvent(new KeyboardEvent('keyup', keyEventInit));
            } catch (_) {}
          }

          // If Enter is pressed inside an input within a form, trigger form submit if not submitted
          if (keyName.toLowerCase() === 'enter' && target && target.form && typeof target.form.requestSubmit === 'function') {
            try { target.form.requestSubmit(); } catch (_) {}
          }

          return JSON.stringify({ success: true, message: `Pressed key [${keyName}]` });
        }

        case 'select_option': {
          // Handle native <select> dropdowns
          const id = (params.element_id || '').toString();
          const val = params.value || '';
          const el = elementsMap.get(id) || document.querySelector(`[data-bbx-id="${id}"]`);
          if (!el || el.tagName !== 'SELECT') {
            return JSON.stringify({ success: false, error: `Element [${id}] is not a <select> element` });
          }

          let matched = false;
          for (let i = 0; i < el.options.length; i++) {
            const opt = el.options[i];
            if (opt.value === val || opt.text.trim() === val.trim() || opt.text.includes(val)) {
              el.selectedIndex = i;
              matched = true;
              break;
            }
          }
          if (matched && typeof Event !== 'undefined') {
            try {
              el.dispatchEvent(new Event('change', { bubbles: true }));
              el.dispatchEvent(new Event('input', { bubbles: true }));
            } catch (_) {}
          }
          return JSON.stringify({ success: matched, message: matched ? `Selected option [${val}]` : `Option [${val}] not found` });
        }

        case 'hover': {
          const id = (params.element_id || '').toString();
          const el = elementsMap.get(id) || document.querySelector(`[data-bbx-id="${id}"]`);
          if (!el) {
            return JSON.stringify({ success: false, error: `Element [${id}] not found in DOM` });
          }
          if (typeof MouseEvent !== 'undefined') {
            try {
              el.dispatchEvent(new MouseEvent('mouseover', { bubbles: true, cancelable: true, view: window }));
              el.dispatchEvent(new MouseEvent('mouseenter', { bubbles: true, cancelable: true, view: window }));
            } catch (_) {}
          }
          return JSON.stringify({ success: true, message: `Hovered over element [${id}]` });
        }

        case 'scroll': {
          const direction = params.direction || 'down';
          const distance = params.amount || Math.round((window.innerHeight || 800) * 0.7);
          const deltaY = direction === 'down' ? distance : -distance;

          if (typeof window.scrollBy === 'function') {
            window.scrollBy({ top: deltaY, left: 0, behavior: 'smooth' });
          }
          return JSON.stringify({ success: true, message: `Scrolled ${direction} by ${distance}px` });
        }

        case 'navigate': {
          const url = params.url;
          if (!url) {
            return JSON.stringify({ success: false, error: 'URL parameter missing' });
          }
          if (window.location) {
            window.location.href = url;
          }
          return JSON.stringify({ success: true, message: `Navigating to ${url}` });
        }

        case 'clear': {
          removeBadges();
          return JSON.stringify({ success: true, message: 'Cleared highlights' });
        }

        default:
          return JSON.stringify({ success: false, error: `Unknown action: ${act}` });
      }
    },

    /**
     * Dynamic DOM stabilization detector
     * Returns true when DOM mutations cease for 350ms or on timeout
     */
    waitForDomStable: function (timeoutMs = 2500) {
      return new Promise((resolve) => {
        if (typeof MutationObserver === 'undefined' || !document.body) {
          setTimeout(() => resolve(true), 600);
          return;
        }

        let debounceTimer = null;
        let totalTimer = null;

        const observer = new MutationObserver(() => {
          if (debounceTimer) clearTimeout(debounceTimer);
          debounceTimer = setTimeout(() => {
            cleanup();
            resolve(true);
          }, 350);
        });

        function cleanup() {
          if (debounceTimer) clearTimeout(debounceTimer);
          if (totalTimer) clearTimeout(totalTimer);
          try { observer.disconnect(); } catch (_) {}
        }

        totalTimer = setTimeout(() => {
          cleanup();
          resolve(false);
        }, timeoutMs);

        try {
          observer.observe(document.body, { childList: true, subtree: true, attributes: true });
        } catch (_) {
          cleanup();
          resolve(true);
        }
      });
    },

    clearHighlights: removeBadges,
  };

  // Export globally as Operon and alias for backward compatibility
  window.OPERON = window.BBX_AGENT = engine;

  console.log('[Operon] Universal Agent Engine v2.0 Injected.');
})();
