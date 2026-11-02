/**
 * Operon Universal Agent DOM Engine (v0.1.4)
 * - Stealth Anti-Bot Fingerprint Masking
 * - Ghost Cursor & Human-like Touch Ripple Animation
 * - Deep Shadow DOM & IFrame Traversal
 * - CAPTCHA / Challenge Detection (Cloudflare, Arkose, Geetest)
 * - Deterministic Selector Generation for Zero-Token Macro Replay
 * - Dynamic MutationObserver DOM Settle Detection
 */
(function () {
  if (window.OPERON && window.OPERON.version === '0.1.4') {
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

  const BADGE_CONTAINER_ID = '__operon_badge_container__';
  const GHOST_CURSOR_ID = '__operon_ghost_cursor__';
  let elementsMap = new Map();
  let nextElementId = 1;
  let ghostCursor = null;
  let lastInteractedEl = null;

  // ==========================================
  // 1.5 Network Activity Tracker
  // The agent waits for both DOM stability and in-flight requests, otherwise
  // SPA pages look unchanged for a few hundred ms and the model repeats clicks.
  // ==========================================
  try {
    if (!window.__operonNetworkPatched) {
      window.__operonNetworkPatched = true;
      window.__operonPendingNetwork = 0;

      const netBegin = () => {
        window.__operonPendingNetwork =
          (window.__operonPendingNetwork || 0) + 1;
      };
      const netEnd = () => {
        window.__operonPendingNetwork = Math.max(
          0,
          (window.__operonPendingNetwork || 0) - 1
        );
      };

      const originalFetch = window.fetch;
      if (typeof originalFetch === 'function') {
        window.fetch = function () {
          netBegin();
          let request;
          try {
            request = originalFetch.apply(this, arguments);
          } catch (e) {
            netEnd();
            throw e;
          }
          if (request && typeof request.finally === 'function') {
            return request.finally(netEnd);
          }
          netEnd();
          return request;
        };
      }

      if (window.XMLHttpRequest && XMLHttpRequest.prototype) {
        const originalSend = XMLHttpRequest.prototype.send;
        XMLHttpRequest.prototype.send = function () {
          netBegin();
          let finished = false;
          const done = () => {
            if (!finished) {
              finished = true;
              netEnd();
            }
          };
          try {
            this.addEventListener('loadend', done, { once: true });
          } catch (e) {}
          try {
            return originalSend.apply(this, arguments);
          } catch (e) {
            done();
            throw e;
          }
        };
      }
    }
  } catch (e) {}

  // ==========================================
  // 2. Ghost Cursor & Touch Ripple System
  // ==========================================
  function ensureGhostCursor() {
    if (ghostCursor && document.body.contains(ghostCursor)) {
      return ghostCursor;
    }

    // Inject cursor styles
    if (!document.getElementById('__operon_cursor_styles__')) {
      const style = document.createElement('style');
      style.id = '__operon_cursor_styles__';
      style.textContent = `
        #__operon_ghost_cursor__ {
          position: fixed;
          width: 22px;
          height: 22px;
          border-radius: 50%;
          background: rgba(29, 155, 240, 0.45);
          border: 2px solid #ffffff;
          box-shadow: 0 0 14px rgba(29, 155, 240, 0.8), 0 2px 6px rgba(0,0,0,0.4);
          pointer-events: none;
          z-index: 2147483647;
          transition: transform 0.28s cubic-bezier(0.25, 1, 0.5, 1), opacity 0.2s ease;
          opacity: 0;
          display: flex;
          align-items: center;
          justify-content: center;
        }
        #__operon_ghost_cursor__::after {
          content: '';
          width: 6px;
          height: 6px;
          border-radius: 50%;
          background: #ffffff;
        }
        .__operon_ripple__ {
          position: fixed;
          border-radius: 50%;
          border: 2px solid rgba(29, 155, 240, 0.9);
          background: rgba(29, 155, 240, 0.25);
          pointer-events: none;
          z-index: 2147483646;
          animation: __operon_ripple_anim__ 0.45s ease-out forwards;
        }
        .__operon_spotlight__ {
          position: absolute;
          border-radius: 8px;
          border: 2px solid rgba(255, 255, 255, 0.95);
          box-shadow: 0 0 0 3px rgba(29, 155, 240, 0.5), 0 0 24px rgba(29, 155, 240, 0.7);
          background: rgba(29, 155, 240, 0.12);
          pointer-events: none;
          z-index: 2147483645;
          animation: __operon_spotlight_anim__ 0.85s cubic-bezier(0.16, 1, 0.3, 1) forwards;
        }
        @keyframes __operon_spotlight_anim__ {
          0% {
            opacity: 0;
            transform: scale(0.96);
          }
          25% {
            opacity: 1;
            transform: scale(1);
          }
          75% {
            opacity: 0.9;
          }
          100% {
            opacity: 0;
            transform: scale(1.03);
          }
        }
        @keyframes __operon_ripple_anim__ {
          0% {
            width: 8px;
            height: 8px;
            opacity: 1;
            transform: translate(-50%, -50%) scale(1);
          }
          100% {
            width: 50px;
            height: 50px;
            opacity: 0;
            transform: translate(-50%, -50%) scale(1.6);
          }
        }
      `;
      (document.head || document.documentElement).appendChild(style);
    }

    ghostCursor = document.createElement('div');
    ghostCursor.id = GHOST_CURSOR_ID;
    document.body.appendChild(ghostCursor);
    return ghostCursor;
  }

  function moveGhostCursor(clientX, clientY) {
    const cursor = ensureGhostCursor();
    cursor.style.opacity = '1';
    cursor.style.transform = `translate3d(${clientX - 11}px, ${clientY - 11}px, 0)`;
  }

  function triggerSpotlight(el) {
    if (!el || typeof el.getBoundingClientRect !== 'function') return;
    ensureGhostCursor();

    const rect = el.getBoundingClientRect();
    if (rect.width <= 0 || rect.height <= 0) return;

    const spotlight = document.createElement('div');
    spotlight.className = '__operon_spotlight__';
    const scrollX = window.scrollX || window.pageXOffset || 0;
    const scrollY = window.scrollY || window.pageYOffset || 0;
    const pad = 4;

    spotlight.style.left = `${Math.max(0, rect.left + scrollX - pad)}px`;
    spotlight.style.top = `${Math.max(0, rect.top + scrollY - pad)}px`;
    spotlight.style.width = `${Math.max(24, rect.width + pad * 2)}px`;
    spotlight.style.height = `${Math.max(24, rect.height + pad * 2)}px`;

    document.body.appendChild(spotlight);
    setTimeout(() => {
      spotlight.remove();
    }, 850);
  }

  function playTouchRipple(clientX, clientY) {
    const ripple = document.createElement('div');
    ripple.className = '__operon_ripple__';
    ripple.style.left = `${clientX}px`;
    ripple.style.top = `${clientY}px`;
    document.body.appendChild(ripple);
    setTimeout(() => ripple.remove(), 500);
  }

  // ==========================================
  // 3. CAPTCHA / Bot Challenge Detector
  // ==========================================
  function detectCaptchaChallenge() {
    // 3.1 Cloudflare Turnstile / Challenge
    const cfToken = document.querySelector('[name="cf-turnstile-response"]');
    const cfPassed = !!(cfToken && cfToken.value);
    const cf = document.querySelector(
      '[name="cf-turnstile-response"], iframe[src*="cloudflare"], #challenge-stage, .cf-turnstile, #cf-wrapper'
    );
    if (!cfPassed && cf && isRendered(cf)) {
      return { hasCaptcha: true, type: 'Cloudflare 5秒人机盾 / Turnstile' };
    }

    // 3.2 Google reCAPTCHA
    const recaptchaToken = document.querySelector(
      'textarea[name="g-recaptcha-response"], #g-recaptcha-response'
    );
    const recaptchaPassed = !!(recaptchaToken && recaptchaToken.value);
    const recaptcha = document.querySelector(
      '.g-recaptcha, iframe[src*="recaptcha"], #recaptcha-anchor'
    );
    if (!recaptchaPassed && recaptcha && isRendered(recaptcha)) {
      return { hasCaptcha: true, type: 'Google reCAPTCHA 验证码' };
    }

    // 3.3 Geetest 极验
    const geetest = document.querySelector('.geetest_holder, .geetest_radar_tip, .geetest_popup');
    if (geetest && isRendered(geetest)) {
      return { hasCaptcha: true, type: '极验 (Geetest) 滑动验证码' };
    }

    // 3.4 Arkose Labs (Twitter/X常用)
    const arkose = document.querySelector('iframe[src*="arkoselabs"], #arkose, div[data-e2e="arkose-frame"]');
    if (arkose && isRendered(arkose)) {
      return { hasCaptcha: true, type: 'Arkose Labs (X人机验证)' };
    }

    return { hasCaptcha: false };
  }

  // ==========================================
  // 4. Stable Deterministic Selector Generator (for Macro Replay)
  // ==========================================
  function generateMacroSelector(el) {
    if (!el || !el.tagName) return null;

    // 4.1 Test IDs (Best for modern SPAs like X/React)
    const testId = el.getAttribute('data-testid');
    if (testId) return `[data-testid="${testId}"]`;

    // 4.2 Standard ID
    if (el.id && !/^\d/.test(el.id) && !el.id.includes('__operon')) {
      return `#${el.id}`;
    }

    // 4.3 Name or unique aria-label
    const name = el.getAttribute('name');
    if (name) return `${el.tagName.toLowerCase()}[name="${name}"]`;

    const ariaLabel = el.getAttribute('aria-label');
    if (ariaLabel && ariaLabel.length < 30) {
      return `${el.tagName.toLowerCase()}[aria-label="${ariaLabel}"]`;
    }

    // 4.4 Distinct button text
    if (el.tagName === 'BUTTON' || el.getAttribute('role') === 'button') {
      const text = (el.innerText || '').trim();
      if (text && text.length < 20) {
        return `xpath://button[contains(text(), "${text}")]`;
      }
    }

    // 4.5 Fallback CSS Path
    let path = el.tagName.toLowerCase();
    if (el.className && typeof el.className === 'string') {
      const classes = el.className.split(/\s+/).filter((c) => c && !c.startsWith('__operon')).slice(0, 2);
      if (classes.length) path += '.' + classes.join('.');
    }
    return path;
  }

  // ==========================================
  // 5. Deep Shadow DOM & Geometry Traversal
  // ==========================================
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

  function isRendered(el) {
    if (!el || el.nodeType !== 1) return false;
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

    // Filter out off-screen hidden containers (e.g. left: -9999px)
    if (rect.right < -400 || rect.bottom < -400) return false;

    return true;
  }

  function isInViewport(el, margin = 45) {
    if (!isRendered(el)) return false;
    const rect = el.getBoundingClientRect();
    const viewportHeight = window.innerHeight || (document.documentElement ? document.documentElement.clientHeight : 800);
    const viewportWidth = window.innerWidth || (document.documentElement ? document.documentElement.clientWidth : 400);

    return (
      rect.bottom >= -margin &&
      rect.top <= viewportHeight + margin &&
      rect.right >= 0 &&
      rect.left <= viewportWidth
    );
  }

  function isVisible(el) {
    return isInViewport(el);
  }

  function getMacroPageState() {
    const scrollY = window.scrollY || window.pageYOffset || 0;
    const vh = window.innerHeight || (document.documentElement ? document.documentElement.clientHeight : 800);
    const docHeight = Math.max(
      document.body ? document.body.scrollHeight : 0,
      document.documentElement ? document.documentElement.scrollHeight : 0,
      vh
    );
    const maxScroll = Math.max(0, docHeight - vh);
    const scrollPercent = maxScroll > 0 ? Math.min(100, Math.round((scrollY / maxScroll) * 100)) : 100;
    const totalScreens = Math.max(1.0, parseFloat((docHeight / vh).toFixed(1)));
    const currentScreen = Math.max(1.0, parseFloat(((scrollY / vh) + 1.0).toFixed(1)));

    const canScrollDown = maxScroll > 60 && scrollPercent < 92;
    const canScrollUp = scrollY > 60;

    return {
      scrollY: Math.round(scrollY),
      docHeight: Math.round(docHeight),
      vh: Math.round(vh),
      scrollPercent: scrollPercent,
      totalScreens: totalScreens,
      currentScreen: currentScreen,
      canScrollDown: canScrollDown,
      canScrollUp: canScrollUp
    };
  }

  const KEY_ACTION_REGEX = /(提交|下一步|确定|确认|支付|付款|发布|发送|回复|发推|购买|下单|加入购物车|结算|立即购买|登录|注册|保存|搜索|同意|查收|结账|submit|next|confirm|ok|pay|buy|post|send|reply|checkout|login|signup|register|save|search|agree)/i;

  function isKeyActionElement(el, type, label) {
    if (type === 'BUTTON' || type === 'CHECKBOX' || type === 'RADIO' || type === 'EDITABLE' || type.startsWith('INPUT') || type === 'SELECT' || type === 'TEXTAREA') {
      return true;
    }
    const role = el.getAttribute ? el.getAttribute('role') : null;
    if (role === 'button' || role === 'checkbox') return true;

    const testId = el.getAttribute ? (el.getAttribute('data-testid') || '') : '';
    if (KEY_ACTION_REGEX.test(testId)) return true;

    if (label && KEY_ACTION_REGEX.test(label)) return true;

    return false;
  }

  function extractOutsideActions(candidates, maxRadar = 6) {
    const vh = window.innerHeight || (document.documentElement ? document.documentElement.clientHeight : 800);
    const outsideLines = [];
    const seenLabels = new Set();

    for (let i = 0; i < candidates.length; i++) {
      const el = candidates[i];
      if (!isRendered(el) || isInViewport(el)) continue;

      const type = determineElementType(el);
      const label = getElementLabel(el);
      if (!isKeyActionElement(el, type, label)) continue;
      if (!label && type !== 'BUTTON' && !type.startsWith('INPUT')) continue;

      const cleanLbl = label || '(按钮)';
      if (seenLabels.has(cleanLbl)) continue;
      seenLabels.add(cleanLbl);

      const rect = el.getBoundingClientRect();
      let locationHint = '';
      if (rect.top > vh) {
        const screensBelow = Math.max(0.1, ((rect.top - vh) / vh)).toFixed(1);
        locationHint = `视口下方约 ${screensBelow} 屏`;
      } else if (rect.bottom < 0) {
        locationHint = '视口上方';
      } else {
        continue;
      }

      outsideLines.push(`• [${locationHint}] ${type}: "${cleanLbl}"`);
      if (outsideLines.length >= maxRadar) break;
    }

    return outsideLines;
  }

  function cleanText(text, maxLen = 70) {
    if (!text) return '';
    const cleaned = text.replace(/\s+/g, ' ').trim();
    return cleaned.length > maxLen ? cleaned.slice(0, maxLen) + '...' : cleaned;
  }

  // Describe an element without ever leaking a password/card value. Macro
  // recording stores this label, so secrets must never reach it.
  function safeTargetText(el, maxLen = 60) {
    if (!el) return '';
    try {
      const type = (el.getAttribute && el.getAttribute('type') || '').toLowerCase();
      const autocomplete = (el.getAttribute && el.getAttribute('autocomplete') || '').toLowerCase();
      const secret = type === 'password' ||
        /cc-|current-password|new-password|one-time-code/.test(autocomplete);
      const raw = el.innerText ||
        (secret ? '' : el.value) ||
        (el.getAttribute && el.getAttribute('aria-label')) ||
        '';
      return cleanText(raw, maxLen);
    } catch (_) {
      return '';
    }
  }

  function getElementLabel(el) {
    if (el.tagName === 'INPUT' && (el.type === 'checkbox' || el.type === 'radio')) {
      const base = el.getAttribute('aria-label') ||
        el.getAttribute('title') ||
        el.getAttribute('name') ||
        (el.value && el.value !== 'on' ? el.value : '');
      return `${el.checked ? '[已选中]' : '[未选中]'} ${cleanText(base)}`.trim();
    }

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
    if (container) container.remove();

    const elements = document.querySelectorAll ? document.querySelectorAll('[data-operon-id]') : [];
    for (let i = 0; i < elements.length; i++) {
      elements[i].removeAttribute('data-operon-id');
      elements[i].removeAttribute('data-bbx-id');
    }
    if (ghostCursor) {
      ghostCursor.style.opacity = '0';
    }
  }

  function createBadge(id, rect) {
    const badge = document.createElement('div');
    badge.className = '__operon_badge__';
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
    badge.style.zIndex = '2147483645';
    badge.style.pointerEvents = 'none';
    badge.style.boxShadow = '0 1px 3px rgba(0,0,0,0.5)';
    badge.style.fontFamily = 'monospace';
    return badge;
  }

  function extractContentBlocks(maxBlocks = 12) {
    const contentSelectors = 'h1, h2, h3, h4, article, blockquote, [data-testid="tweetText"], .article-content, .post-content';
    const contentNodes = querySelectorAllDeep(document, contentSelectors);
    const lines = [];

    for (let i = 0; i < contentNodes.length && lines.length < maxBlocks; i++) {
      const node = contentNodes[i];
      if (!isVisible(node)) continue;
      const text = cleanText(node.innerText || node.textContent, 90);
      if (text.length > 8) {
        lines.push(`• [${node.tagName}]: "${text}"`);
      }
    }
    return lines;
  }

  // ==========================================
  // 6. Main Operon Engine Definition
  // ==========================================
  const engine = {
    version: '0.1.4',

    detectCaptcha: detectCaptchaChallenge,

    extractPrunedDOM: function (showVisualBadges = false, includeContent = true) {
      removeBadges();
      elementsMap.clear();
      nextElementId = 1;

      // Check for CAPTCHA first
      const captchaInfo = detectCaptchaChallenge();

      // Macro page state
      const macroState = getMacroPageState();

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
        badgeContainer.style.zIndex = '2147483644';
        document.body.appendChild(badgeContainer);
      }

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

      // Radar for key action elements located outside the active viewport (e.g. below the fold)
      const outsideRadarLines = extractOutsideActions(candidates, 6);

      // 1. Separate candidates into in-viewport vs outside
      const inViewportCandidates = [];
      candidates.forEach((el) => {
        if (!isInViewport(el)) return;

        // Skip duplicate child if parent has same text and already has id
        const parent = el.parentElement;
        if (
          parent &&
          elementsMap.has(parent.getAttribute('data-operon-id')) &&
          (el.innerText || '').trim() === (parent.innerText || '').trim()
        ) {
          return;
        }

        const type = determineElementType(el);
        const label = getElementLabel(el);
        const isDisabled = el.disabled === true || (el.getAttribute && el.getAttribute('aria-disabled') === 'true');
        const isKey = isKeyActionElement(el, type, label);

        // Priority classification:
        // Priority 1 (Crucial/Immune): Buttons, inputs, forms, key actions (NEVER DROPPED)
        // Priority 2 (High): Links with meaningful text, tabs, menu items
        // Priority 3 (Low): Minor links, single icon/symbol, empty labels
        let priority = 3;
        if (isKey || type === 'BUTTON' || type === 'EDITABLE' || type.startsWith('INPUT') || type === 'SELECT' || type === 'TEXTAREA' || type === 'CHECKBOX' || type === 'RADIO') {
          priority = 1;
        } else if ((type === 'LINK' || type === 'CLICKABLE') && label && label.length > 2 && !/^\d+$/.test(label)) {
          priority = 2;
        } else if (type === 'TAB' || type === 'MENUITEM') {
          priority = 2;
        }

        inViewportCandidates.push({
          el: el,
          type: type,
          label: label,
          isDisabled: isDisabled,
          priority: priority,
          parent: el.parentElement,
          className: (el.className && typeof el.className === 'string') ? el.className.split(' ')[0] : ''
        });
      });

      // 2. Repetition Folding (detect and fold repetitive lists/feed cards)
      const foldedCandidates = [];
      let streak = [];

      function flushStreak() {
        if (streak.length === 0) return;
        if (streak.length > 4) {
          // Keep first 2 items
          foldedCandidates.push(streak[0]);
          foldedCandidates.push(streak[1]);
          // Insert collapse marker
          foldedCandidates.push({
            isCollapseMarker: true,
            count: streak.length - 3,
            hint: `• [...折叠 ${streak.length - 3} 项相似列表项目，可向下滚动浏览...]`
          });
          // Keep the last item
          foldedCandidates.push(streak[streak.length - 1]);
        } else {
          for (let k = 0; k < streak.length; k++) {
            foldedCandidates.push(streak[k]);
          }
        }
        streak = [];
      }

      for (let i = 0; i < inViewportCandidates.length; i++) {
        const item = inViewportCandidates[i];
        // Priority 1 elements (Buttons, inputs, form controls) are NEVER folded!
        if (item.priority === 1) {
          flushStreak();
          foldedCandidates.push(item);
          continue;
        }

        if (streak.length === 0) {
          streak.push(item);
        } else {
          const prev = streak[streak.length - 1];
          const isSimilar = (prev.parent === item.parent) || (prev.className && prev.className === item.className && prev.type === item.type);
          if (isSimilar) {
            streak.push(item);
          } else {
            flushStreak();
            streak.push(item);
          }
        }
      }
      flushStreak();

      // 3. Token Budget Guard (Target budget: ~65 interactive items max)
      // Priority 1 is NEVER dropped! Only Priority 3 and lowest Priority 2 are trimmed.
      const TARGET_BUDGET = 65;
      let finalCandidates = [];
      if (foldedCandidates.length <= TARGET_BUDGET) {
        finalCandidates = foldedCandidates;
      } else {
        const p1Items = [];
        const otherItems = [];
        foldedCandidates.forEach((it) => {
          if (it.isCollapseMarker || it.priority === 1) {
            p1Items.push(it);
          } else {
            otherItems.push(it);
          }
        });

        const remainingSlots = Math.max(10, TARGET_BUDGET - p1Items.length);
        const keptOthers = otherItems.slice(0, remainingSlots);
        finalCandidates = foldedCandidates.filter((it) => p1Items.includes(it) || keptOthers.includes(it));
      }

      // 4. Register Elements, Allocate Operon IDs, and Render Visual Badges
      const interactiveLines = [];
      finalCandidates.forEach((item) => {
        if (item.isCollapseMarker) {
          interactiveLines.push(item.hint);
          return;
        }

        const el = item.el;
        const id = nextElementId++;
        el.setAttribute('data-operon-id', id.toString());
        el.setAttribute('data-bbx-id', id.toString());
        elementsMap.set(id.toString(), el);

        const typeWithState = item.isDisabled ? `${item.type} [DISABLED]` : item.type;
        const label = item.label;

        if (badgeContainer) {
          const rect = el.getBoundingClientRect();
          badgeContainer.appendChild(createBadge(id, rect));
        }

        if (label || item.type === 'BUTTON' || item.type === 'EDITABLE' || item.type.startsWith('INPUT') || item.type === 'SELECT') {
          interactiveLines.push(`[${id}] ${typeWithState}: ${label || '(empty)'}`);
        }
      });

      // 5. Page Main Content Summary (Articles, Headings)
      const contentLines = includeContent ? extractContentBlocks(8) : [];

      let combinedTree = '';

      // 5.1 Macro page state & navigation guidance
      combinedTree += '【页面宏观状态】:\n';
      combinedTree += `• 页面总长度: 约 ${macroState.totalScreens} 屏 (当前处于第 ${macroState.currentScreen} 屏, 滚动进度: ${macroState.scrollPercent}%)\n`;
      if (macroState.canScrollDown) {
        const remainingScreens = Math.max(0.1, (macroState.totalScreens - macroState.currentScreen)).toFixed(1);
        combinedTree += `• 滚动寻路指引: 页面下方还有约 ${remainingScreens} 屏内容。若当前可视区无目标，可下发 scroll(direction: "down") 向下滚动寻路。\n`;
      } else if (macroState.canScrollUp && macroState.scrollPercent > 85) {
        combinedTree += '• 滚动寻路指引: 当前已接近页面最底部。若目标不在底部，可下发 scroll(direction: "up") 向上返回。\n';
      }
      combinedTree += '\n';

      // 5.2 Below/Above the fold Critical Action Radar
      if (outsideRadarLines.length > 0) {
        combinedTree += '【视口外核心交互雷达 (在屏幕下方/上方，需滚动后方可交互)】:\n';
        combinedTree += outsideRadarLines.join('\n') + '\n\n';
      }

      // 5.3 Page content blocks
      if (contentLines.length > 0) {
        combinedTree += '【页面主要内容摘要】:\n' + contentLines.join('\n') + '\n\n';
      }

      // 5.4 Viewport interactive elements
      combinedTree += '【当前屏幕可直接交互元素 (带 Operon ID，可直接点击/输入)】:\n';
      combinedTree += (interactiveLines.join('\n') || '(当前视口内无直接交互元素，可尝试滚动浏览)');

      return JSON.stringify({
        url: (window.location && window.location.href) ? window.location.href : '',
        title: document.title || '',
        captcha: captchaInfo,
        elementCount: elementsMap.size,
        macro: macroState,
        text_tree: combinedTree,
      });
    },

    executeAction: function (actionJson) {
      const parsed = typeof actionJson === 'string' ? JSON.parse(actionJson) : actionJson;
      const act = parsed.action;
      const params = parsed.params || {};

      switch (act) {
        case 'click': {
          const id = (params.element_id || '').toString();
          // Support direct selector fallback for Macro Replay!
          let el = elementsMap.get(id) || document.querySelector(`[data-operon-id="${id}"]`) || document.querySelector(`[data-bbx-id="${id}"]`);
          if (!el && params.selector) {
            try { el = document.querySelector(params.selector); } catch (_) {}
          }

          if (!el || el.isConnected === false) {
            return JSON.stringify({ success: false, error: `Element [${id}] not found or was replaced by a page update; please re-identify` });
          }

          if (el.disabled === true || (el.getAttribute && el.getAttribute('aria-disabled') === 'true')) {
            return JSON.stringify({
              success: false,
              error: `Element [${id}] is disabled and cannot be clicked right now`
            });
          }

          lastInteractedEl = el;

          if (typeof el.scrollIntoView === 'function') {
            try { el.scrollIntoView({ block: 'center' }); } catch (_) {}
          }

          const rect = el.getBoundingClientRect ? el.getBoundingClientRect() : { left: 0, top: 0, width: 0, height: 0 };
          const clientX = rect.left + rect.width / 2;
          const clientY = rect.top + rect.height / 2;

          // Non-Intrusive Spotlight & Touch Ripple
          triggerSpotlight(el);
          moveGhostCursor(clientX, clientY);
          playTouchRipple(clientX, clientY);

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
          }
          // Fire exactly one click: calling el.click() AND dispatching a
          // synthetic click double-toggles checkboxes/follow buttons.
          if (typeof el.click === 'function') {
            try { el.click(); } catch (_) {}
          } else if (typeof MouseEvent !== 'undefined') {
            try { el.dispatchEvent(new MouseEvent('click', eventInit)); } catch (_) {}
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

          // Return macro-compatible selector for recording!
          const macroSelector = generateMacroSelector(el);
          return JSON.stringify({
            success: true,
            message: `Clicked element [${id}]`,
            macroSelector: macroSelector,
            targetText: safeTargetText(el),
            tag: el.tagName || ''
          });
        }

        case 'type': {
          const id = (params.element_id || '').toString();
          const text = params.text || '';
          const clearFirst = params.clear !== false && params.clear_first !== false;

          let el = elementsMap.get(id) || document.querySelector(`[data-operon-id="${id}"]`) || document.querySelector(`[data-bbx-id="${id}"]`);
          if (!el && params.selector) {
            try { el = document.querySelector(params.selector); } catch (_) {}
          }

          if (!el || el.isConnected === false) {
            return JSON.stringify({ success: false, error: `Element [${id}] not found or was replaced by a page update; please re-identify` });
          }

          // 1. Resolve actual editable element (auto-penetrate wrapper/placeholder for Twitter Draft.js/Lexical)
          let target = el;
          const isDirectEditable = (target.getAttribute && target.getAttribute('contenteditable') === 'true') || target.isContentEditable;
          const isInputOrTextarea = target.tagName === 'INPUT' || target.tagName === 'TEXTAREA';

          if (!isDirectEditable && !isInputOrTextarea) {
            const innerEditable = target.querySelector('[contenteditable="true"]') ||
                                  target.querySelector('[role="textbox"]') ||
                                  target.querySelector('textarea, input');
            const outerEditable = target.closest('[contenteditable="true"]') ||
                                  target.closest('[role="textbox"]') ||
                                  target.closest('div[data-testid*="tweetTextarea"]');
            if (innerEditable) {
              target = innerEditable;
            } else if (outerEditable) {
              target = outerEditable;
            }
          }

          if (typeof target.scrollIntoView === 'function') {
            try { target.scrollIntoView({ block: 'center' }); } catch (_) {}
          }
          lastInteractedEl = target;
          if (typeof target.focus === 'function') {
            try { target.focus(); } catch (_) {}
          }

          const rect = target.getBoundingClientRect ? target.getBoundingClientRect() : { left: 0, top: 0, width: 0, height: 0 };
          triggerSpotlight(target);
          moveGhostCursor(rect.left + rect.width / 2, rect.top + rect.height / 2);

          const isEditable = (target.getAttribute && target.getAttribute('contenteditable') === 'true') ||
                             target.isContentEditable ||
                             target.getAttribute('role') === 'textbox';

          if (isEditable) {
            // --- A. Focus & Set Caret Selection Range ---
            target.focus();
            const sel = window.getSelection ? window.getSelection() : null;
            if (sel) {
              try {
                sel.removeAllRanges();
                const range = document.createRange();
                range.selectNodeContents(target);
                if (!clearFirst) {
                  range.collapse(false); // Move caret to end
                }
                sel.addRange(range);
              } catch (_) {}
            }

            // --- B. Dispatch beforeinput (Critical for Draft.js / Lexical / React 18+) ---
            if (typeof InputEvent !== 'undefined') {
              try {
                target.dispatchEvent(
                  new InputEvent('beforeinput', {
                    bubbles: true,
                    cancelable: true,
                    inputType: clearFirst ? 'insertReplacementText' : 'insertText',
                    data: text,
                  })
                );
              } catch (_) {}
            }

            // --- C. Execute document.execCommand('insertText') ---
            let execSuccess = false;
            if (typeof document.execCommand === 'function') {
              try {
                if (clearFirst) {
                  document.execCommand('selectAll', false, null);
                }
                execSuccess = document.execCommand('insertText', false, text);
              } catch (_) {}
            }

            // --- D. High-Fidelity Fallback if execCommand returned false ---
            if (!execSuccess) {
              try {
                target.dispatchEvent(new CompositionEvent('compositionstart', { bubbles: true, data: '' }));
              } catch (_) {}

              try {
                if (sel && sel.rangeCount > 0) {
                  const range = sel.getRangeAt(0);
                  if (clearFirst) {
                    range.selectNodeContents(target);
                    range.deleteContents();
                  }
                  const textNode = document.createTextNode(text);
                  range.insertNode(textNode);
                  range.setStartAfter(textNode);
                  range.setEndAfter(textNode);
                  sel.removeAllRanges();
                  sel.addRange(range);
                } else {
                  target.textContent = text;
                }
              } catch (_) {
                target.textContent = text;
              }

              try {
                target.dispatchEvent(new CompositionEvent('compositionend', { bubbles: true, data: text }));
              } catch (_) {}
            }

            // --- E. Dispatch Comprehensive Input & Key Events for Framework Listeners ---
            if (typeof InputEvent !== 'undefined') {
              try {
                target.dispatchEvent(
                  new InputEvent('input', {
                    bubbles: true,
                    cancelable: true,
                    inputType: 'insertText',
                    data: text,
                  })
                );
              } catch (_) {}
            } else if (typeof Event !== 'undefined') {
              try { target.dispatchEvent(new Event('input', { bubbles: true })); } catch (_) {}
            }

            try { target.dispatchEvent(new Event('change', { bubbles: true })); } catch (_) {}

            // Send key events to wake up Draft.js character count and state evaluators
            if (typeof KeyboardEvent !== 'undefined') {
              try {
                target.dispatchEvent(new KeyboardEvent('keydown', { bubbles: true, cancelable: true, key: ' ', code: 'Space' }));
                target.dispatchEvent(new KeyboardEvent('keyup', { bubbles: true, cancelable: true, key: ' ', code: 'Space' }));
              } catch (_) {}
            }

            // --- F. Twitter / X Specific Wake-up Routine ---
            try {
              const tweetButtons = document.querySelectorAll('[data-testid*="tweetButton"], [data-testid="tweetButtonInline"]');
              if (tweetButtons.length > 0) {
                target.dispatchEvent(new Event('input', { bubbles: true }));
              }
            } catch (_) {}

          } else if (target.tagName === 'INPUT' || target.tagName === 'TEXTAREA') {
            // React 16+ Property Descriptor setter bypass
            const proto = target.tagName === 'INPUT' ? window.HTMLInputElement.prototype : window.HTMLTextAreaElement.prototype;
            const valueDescriptor = Object.getOwnPropertyDescriptor(proto, 'value');

            const finalVal = clearFirst ? text : ((target.value || '') + text);

            if (valueDescriptor && typeof valueDescriptor.set === 'function') {
              try {
                valueDescriptor.set.call(target, finalVal);
              } catch (_) {
                target.value = finalVal;
              }
            } else {
              target.value = finalVal;
            }

            if (typeof Event !== 'undefined') {
              try {
                target.dispatchEvent(new Event('input', { bubbles: true }));
                target.dispatchEvent(new Event('change', { bubbles: true }));
              } catch (_) {}
            }
          } else {
            target.innerText = text;
            try { target.dispatchEvent(new Event('input', { bubbles: true })); } catch (_) {}
          }

          const macroSelector = generateMacroSelector(target);
          return JSON.stringify({
            success: true,
            message: `Typed into element [${id}]`,
            macroSelector: macroSelector,
            targetText: safeTargetText(target),
            tag: target.tagName || ''
          });
        }

        case 'press_key': {
          const keyName = params.key || 'Enter';
          const id = params.element_id ? params.element_id.toString() : null;
          const target = (id ? (elementsMap.get(id) || document.querySelector(`[data-operon-id="${id}"]`)) : null) || document.activeElement || document.body;

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

          if (keyName.toLowerCase() === 'enter' && target && target.form && typeof target.form.requestSubmit === 'function') {
            try { target.form.requestSubmit(); } catch (_) {}
          }

          return JSON.stringify({ success: true, message: `Pressed key [${keyName}]` });
        }

        case 'select_option': {
          const id = (params.element_id || '').toString();
          const val = params.value || '';
          const el = elementsMap.get(id) || document.querySelector(`[data-operon-id="${id}"]`);
          if (!el || el.isConnected === false || el.tagName !== 'SELECT') {
            return JSON.stringify({ success: false, error: `Element [${id}] is not an available <select> element` });
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
          const el = elementsMap.get(id) || document.querySelector(`[data-operon-id="${id}"]`);
          if (!el || el.isConnected === false) {
            return JSON.stringify({ success: false, error: `Element [${id}] not found or was replaced by a page update; please re-identify` });
          }
          lastInteractedEl = el;
          const rect = el.getBoundingClientRect ? el.getBoundingClientRect() : { left: 0, top: 0, width: 0, height: 0 };
          moveGhostCursor(rect.left + rect.width / 2, rect.top + rect.height / 2);

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

          // Prefer the scrollable container around the last touched element
          // (modals, side panels, comment lists) before falling back to page.
          let scroller = null;
          let probe = lastInteractedEl;
          while (probe && probe !== document.body && probe !== document.documentElement) {
            if (probe.isConnected === false) break;
            try {
              const style = window.getComputedStyle ? window.getComputedStyle(probe) : null;
              const overflowY = style ? style.overflowY : '';
              if ((overflowY === 'auto' || overflowY === 'scroll' || overflowY === 'overlay') &&
                  probe.scrollHeight > probe.clientHeight + 24) {
                scroller = probe;
                break;
              }
            } catch (_) {}
            probe = probe.parentElement;
          }

          const isPageScroll = !scroller;
          const vh = window.innerHeight || 800;
          const docHeight = Math.max(
            document.body ? document.body.scrollHeight : 0,
            document.documentElement ? document.documentElement.scrollHeight : 0,
            vh
          );
          const before = isPageScroll
            ? (window.scrollY || window.pageYOffset || 0)
            : scroller.scrollTop;
          const maxScroll = isPageScroll
            ? Math.max(0, docHeight - vh)
            : Math.max(0, scroller.scrollHeight - scroller.clientHeight);

          if (direction === 'down' && before >= maxScroll - 6) {
            return JSON.stringify({
              success: false,
              atBoundary: true,
              error: isPageScroll
                ? 'Already at the bottom of the page; scrolling down has no effect'
                : 'Already at the bottom of this scrollable panel; try page scroll or another area'
            });
          }
          if (direction !== 'down' && before <= 6) {
            return JSON.stringify({
              success: false,
              atBoundary: true,
              error: 'Already at the top; scrolling up has no effect'
            });
          }

          if (isPageScroll) {
            if (typeof window.scrollBy === 'function') {
              window.scrollBy({
                top: direction === 'down' ? distance : -distance,
                left: 0,
                behavior: 'auto'
              });
            }
          } else {
            try {
              scroller.scrollBy({
                top: direction === 'down' ? distance : -distance,
                behavior: 'auto'
              });
            } catch (_) {
              scroller.scrollTop = before + (direction === 'down' ? distance : -distance);
            }
          }

          return JSON.stringify({
            success: true,
            message: `Scrolled ${direction} inside ${isPageScroll ? 'page' : 'panel'}`,
            remaining: Math.max(0, Math.round(maxScroll - before))
          });
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

    waitForDomStable: function (timeoutMs = 2500) {
      return new Promise((resolve) => {
        if (typeof MutationObserver === 'undefined' || !document.body) {
          setTimeout(() => resolve(true), 600);
          return;
        }

        const startedAt = Date.now();
        let lastMutationAt = Date.now();
        let pollTimer = null;
        let totalTimer = null;
        let settled = false;

        const observer = new MutationObserver(() => {
          lastMutationAt = Date.now();
        });

        function cleanup() {
          if (pollTimer) clearInterval(pollTimer);
          if (totalTimer) clearTimeout(totalTimer);
          try { observer.disconnect(); } catch (_) {}
        }

        function finish(value) {
          if (settled) return;
          settled = true;
          cleanup();
          resolve(value);
        }

        // Require a minimum settle window so a fetch/XHR triggered by the
        // action has time to start before we declare the page stable.
        pollTimer = setInterval(() => {
          const now = Date.now();
          const quiet = now - lastMutationAt >= 350;
          const networkIdle = (window.__operonPendingNetwork || 0) === 0;
          const networkGraceExpired = now - startedAt >= 1300;
          if (now - startedAt >= 450 && quiet &&
              (networkIdle || networkGraceExpired)) {
            finish(true);
          }
        }, 100);

        totalTimer = setTimeout(() => finish(false), timeoutMs);

        try {
          observer.observe(document.body, {
            childList: true,
            subtree: true,
            attributes: true
          });
        } catch (_) {
          finish(true);
        }
      });
    },

    clearHighlights: removeBadges,

    // ==========================================
    // 8. Mobile Clean Reader & Anti-App-Jump
    // ==========================================
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

    // ==========================================
    // 9. Article Core Content Extractor for AI
    // ==========================================
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

    // ==========================================
    // 10. Inline Selection Bridge
    // ==========================================
    // Classify the actual DOM element behind an Operon ID. This closes the gap
    // where the model's reasoning looked harmless while the target was a
    // password field, a card input, or a destructive submit button.
    getElementRisk: function (elementId) {
      let el = null;
      try {
        el = elementsMap.get(String(elementId)) ||
          document.querySelector(`[data-operon-id="${elementId}"]`);
      } catch (e) {
        el = null;
      }
      if (!el) {
        return JSON.stringify({ found: false, sensitive: false, reason: '' });
      }

      const tag = (el.tagName || '').toUpperCase();
      const type = (el.getAttribute('type') || '').toLowerCase();
      const autocomplete = (el.getAttribute('autocomplete') || '').toLowerCase();
      const name = [
        el.getAttribute('name') || '',
        el.id || '',
        el.getAttribute('placeholder') || '',
        el.getAttribute('aria-label') || '',
        el.getAttribute('title') || ''
      ].join(' ');
      const text = safeTargetText(el, 120);
      let formAction = '';
      try {
        const form = el.closest ? el.closest('form') : null;
        formAction = form ? (form.getAttribute('action') || '') : '';
      } catch (e) {}

      const fieldContext = `${name} ${formAction}`.toLowerCase();
      const actionContext = `${text} ${name} ${formAction}`.toLowerCase();

      let reason = '';
      if (type === 'password') {
        reason = '密码输入框';
      } else if (type === 'file') {
        reason = '文件上传';
      } else if (/cc-|current-password|new-password|one-time-code/.test(autocomplete)) {
        reason = '支付或凭证字段';
      } else if (/(password|passwd|密码|验证码|信用卡|card.?number|卡号|cvv|cvc|安全码|身份证|social.?security)/i.test(fieldContext)) {
        reason = '凭证或支付字段';
      } else if (/(pay|payment|checkout|billing|purchase|place.?order|transfer|withdraw|delete.?account|refund)/i.test(formAction)) {
        reason = '支付/账户流程表单';
      } else if (/(提交|发布|发送|支付|付款|购买|下单|结算|删除|注销|解绑|授权|绑定|转账|提现|退款|submit|publish|send|pay|buy|checkout|place.?order|delete|remove|unfollow|logout|confirm)/i.test(text)) {
        reason = '高危操作按钮';
      }

      return JSON.stringify({
        found: true,
        sensitive: !!reason,
        reason: reason,
        tag: tag,
        type: type,
        text: text.slice(0, 60)
      });
    },

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
  console.log('[Operon] Universal Agent Engine v0.1.4 Injected.');
})();
