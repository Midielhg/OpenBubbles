// Shows an OpenBubbles account picker under login fields and fills the chosen account.
// Nothing is filled until the user clicks an account; the page never sees the list of accounts
// (it lives in a closed shadow root).

(() => {
  if (window.__openBubblesPasswords) return;
  window.__openBubblesPasswords = true;

  const USERNAME_HINT = /user|e-?mail|login|log-in|sign-?in|account|phone|identifier|correo|usuario/i;
  const LOOKUP_TTL_MS = 30000;
  // inlined so the icon needn't be exposed to every website (web_accessible_resources)
  const ICON = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAYAAABzenr0AAAFnklEQVR42rWX24vd1RXHP2vv/TtnZs45uWlrq+k4vgQZiEhE6EP7UEgLhYYGyegQoQ+2Ng0WxUDFv6BCHyz60EIL9qmimXlSoQ9NkD5ohVKxMZ3EYFuvMZPbzJw5Z2Z+v9/ea/lwLnPmkjSacW1+nAt7/9Z3fdfa37W3AEzYhJ+SqTRx9fHR4VrtCUMPmOqdZmSAcHNmIpTi3IcCry63l5+b2vX8Rz2f0vtyePHYQ2Go8pwL4bYUIxoTGFtjAi54fAhojLNxpXjixcazL0/YhBeAh9tPHaqMVKdiLNE8JgSHiLCVZmYY6qrBh5BRLOUTf679Zloebj+1W5ydEu93aJkUwV8/mN5Y937AuuP6QEgu885SmjeVe4JaPFYZGtpZtPIkTvy11jschlFSUlgkkVjNkeDxVCQQCAiCoteC4GNepkq9urNcyp8MSfVgnuemmtxm9eZxKErTWjiEr7ld7Hbf4OvuFhqMALDIEhf1Cp/oBS7pVRSjJsM4HGkzIGqu41MPhqTpW5qrmMH6uR5H0xapkPHd7D6+V/k2d/u7aEht09AWrc3Z9D9eL97irfIdCkpqMrIRhCGaK2Y2KgevPmabFC0ijqa2uC8b55HhQ+wJYwPr12ZbBmqjZ+fiB7ywPM0/yxm2uTpmuml25cDlX9hm+V60Fg8O/5Cf1x5ak9PNS3AtsMGa+UP7ZY4v/4WG1Deti5A0baB9Thc4XPsRR2qTKIahONwNbPdVcB1nwpHaJBi82H6N7a6+IR0uaaL3mBoLscW+bJwj9UkSinSj+aLmcAiQUI7UJ9mXjbMQW5gagz5dSr0fStSIGBxtHF6T2y8vgKurjzYOIwZRI0mVnt8OAylhqjS70e/JxtAbpP1GmFCUPdkY+7JxmrGFqdLz63rRa1LylHN/dW9f1bZMhbtvu7+6lzzlaNI+690iFAwFFUbD7V3atrIVdFIxGm4HhUiktylDUu1pA6ZKRbKvwH3HKpJ1ipA0ACCl7gxHngrmYrPfvLYKRe9d86lJngqGqfa3Y78IkyplKjm9fI6vyk4vn6NM5eouWC3CRJlKMgInm29SWkREtqQMDRARokVONv9ORuiCGNyGmogaqVLh9NJ7vDJ/otPJLN40gGQRh+OV+ZO82z5LlUpXC7oAYh9Ah4UqFX59/nd8WlwgSCBa+tLOoyWCBD4rL/LM+d9TpdKPPm5QwtRhwZvnYn6FR/77NJfjHEH8FwZhGNEiQTxzcYGf/udpLuSX8OZXo1+vhJ1PpUgFIzLEqdYZHjh7lHfaMwTxfWHS7rB1Q1GSJZIlBCFI4NTSWR547yhvt/7NiAxRpIKUlMGg5c5/fMcEwbC+chtGEE87LZNJ4Jff/AnH7vgZYAQJ/5eBz4qLvDA7xR9nX2JFc+p+hNgFNsiSIB0hkoE/epaTqMkwH+afcqWcJ0jnrHpm6X0E4Y7qbQy7YcBY0hVmi8ucXjrHyfk3ODH3BueLWbaHBkNSJU/FhqY2ACBGQYIZDB7EBeFqmufgrh/wzF2/4l+tM/zpwhQvXXoNEeHWsJO6H8GAVmozFxdophZmRt2PsMNv69Dcbelrhanjy7AYYkofu8yNWWn93ivdSRmBW8NOfvzuo7zZfJt2WmZ7aIAZ51dm+2rmxRHwNKSOCCRT8lRct0olE7TUj+WWv937rDTCk7YYE+uO5SLCYmwhItT9CB7fPY6zKaVmN9gY1JI0grfF+FvZ9fre3erklATZYYUqImsuJl5c9yStW9OgzZJUnLNo807tHgGonxg/5LaFKVtRKDWBuJs6Cl1LHDAlc16GHNqME639M9OO4xO+tX9mOi2UkyY2S815C4iZsaVPQKg5b6KzaaGcbO2fmeZ493LK8QnPg1Np6K/jo6Eqj2McQHUMlS25nuOsxLkPEF6NuT2/8v2Zj3o+PwdObdevlzFJ0wAAAABJRU5ErkJggg==";

  let lookup = null; // { at, promise }
  let host = null;
  let shadow = null;
  let list = null;
  let suppressUntil = 0;
  const dismissed = new WeakSet();

  // ---------- field detection ----------

  function visible(el) {
    if (!el.isConnected) return false;
    const r = el.getBoundingClientRect();
    if (r.width < 2 || r.height < 2) return false;
    const s = getComputedStyle(el);
    return s.visibility !== "hidden" && s.display !== "none" && s.opacity !== "0";
  }

  function usable(el) {
    return el instanceof HTMLInputElement && !el.disabled && !el.readOnly && visible(el);
  }

  function isPassword(el) {
    return el instanceof HTMLInputElement && el.type === "password";
  }

  function isTextLike(el) {
    return el instanceof HTMLInputElement && ["text", "email", "tel"].includes(el.type);
  }

  function isNewPassword(el) {
    return /new-password/i.test(el.autocomplete || "");
  }

  function scopeOf(el) {
    return el.form || el.closest("form") || el.getRootNode();
  }

  function follows(a, b) {
    // true when b comes after a in the document
    return !!(a.compareDocumentPosition(b) & Node.DOCUMENT_POSITION_FOLLOWING);
  }

  function usernameFor(password) {
    const inputs = [...scopeOf(password).querySelectorAll("input")].filter((e) => isTextLike(e) && usable(e));
    let best = null;
    for (const e of inputs) {
      if (follows(e, password)) best = e;
    }
    return best;
  }

  function looksLikeUsername(el) {
    if (/username|email/i.test(el.autocomplete || "")) return true;
    if (el.type === "email") return true;
    return USERNAME_HINT.test([el.name, el.id, el.placeholder, el.getAttribute("aria-label")].join(" "));
  }

  function loginFieldsFor(el) {
    if (!usable(el)) return null;
    if (isPassword(el)) {
      if (isNewPassword(el)) return null;
      return { password: el, username: usernameFor(el) };
    }
    if (!isTextLike(el)) return null;
    const passwords = [...scopeOf(el).querySelectorAll('input[type="password"]')].filter(
      (p) => usable(p) && !isNewPassword(p)
    );
    const next = passwords.find((p) => follows(el, p));
    if (next && usernameFor(next) === el) return { username: el, password: next };
    // username-only step (e.g. "enter your email" first, password on the next page)
    if (passwords.length === 0 && looksLikeUsername(el)) return { username: el, password: null };
    return null;
  }

  // ---------- talking to the extension ----------

  function send(msg) {
    return new Promise((resolve) => {
      try {
        chrome.runtime.sendMessage(msg, (res) => {
          if (chrome.runtime.lastError || !res) resolve({ ok: false, error: "extension" });
          else resolve(res);
        });
      } catch (e) {
        resolve({ ok: false, error: "extension" }); // extension reloaded; page needs a refresh
      }
    });
  }

  function getAccounts() {
    if (!lookup || Date.now() - lookup.at > LOOKUP_TTL_MS) {
      lookup = { at: Date.now(), promise: send({ type: "lookup" }) };
    }
    return lookup.promise;
  }

  // ---------- dropdown ----------
  //
  // The menu is always drawn in the top frame, so a small embedded sign-in frame (like Apple's)
  // can't clip it. A field inside a frame reports where it is up the chain of frames (position
  // only); the account list travels through the extension's background worker, and the chosen
  // password goes straight back to the frame that has the field.

  const IS_TOP = window.top === window;
  const FILL_FAILED = "Couldn't fill this password. Check that OpenBubbles is open.";

  let field = null; // this frame's focused login field: { username, password, anchor, accounts, active, nonce }
  let menu = null; // top frame: the menu on screen { nonce, accounts, note, active, local, rect }
  let showGen = 0;
  const offsets = new Map(); // top frame: nonce -> field position in top-frame coordinates
  const pendingMenus = new Map(); // top frame: nonce -> { accounts, note }, waiting for its position
  const fieldsByNonce = new Map(); // frames: nonce -> fields to fill when the top frame's menu is used

  const STYLE = `
    :host { all: initial; }
    .menu {
      position: fixed; z-index: 2147483647; min-width: 240px; max-width: 360px;
      max-height: min(360px, calc(100vh - 16px)); overflow-y: auto;
      background: #fff; color: #1d1d1f; border: 1px solid rgba(0,0,0,.12); border-radius: 12px;
      box-shadow: 0 10px 30px rgba(0,0,0,.18); padding: 6px; box-sizing: border-box;
      font: 13px/1.3 -apple-system, "Segoe UI", system-ui, sans-serif;
    }
    .head { display: flex; align-items: center; gap: 6px; padding: 4px 8px 6px; color: #6e6e73; font-size: 11px; }
    .head img { width: 14px; height: 14px; border-radius: 3px; }
    .item {
      display: flex; align-items: center; gap: 10px; padding: 8px; border-radius: 8px; cursor: pointer;
    }
    .item.active, .item:hover { background: #0a84ff; color: #fff; }
    .item.active .site, .item:hover .site { color: rgba(255,255,255,.85); }
    .key {
      flex: none; width: 28px; height: 28px; border-radius: 50%; background: #34c759; color: #fff;
      display: flex; align-items: center; justify-content: center; font-size: 13px; font-weight: 600;
    }
    .text { min-width: 0; }
    .user { font-weight: 600; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
    .site { color: #6e6e73; font-size: 12px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
    .note { padding: 8px; color: #6e6e73; }
    @media (prefers-color-scheme: dark) {
      .menu { background: #2c2c2e; color: #f5f5f7; border-color: rgba(255,255,255,.12); }
      .head, .site, .note { color: #a1a1a6; }
    }
  `;

  function rectOf(el) {
    const r = el.getBoundingClientRect();
    return { left: r.left, top: r.top, bottom: r.bottom, width: r.width };
  }

  // ----- drawing (top frame) -----

  function ensureHost() {
    if (host && host.isConnected) return;
    host = document.createElement("openbubbles-passwords");
    shadow = host.attachShadow({ mode: "closed" });
    const style = document.createElement("style");
    style.textContent = STYLE;
    list = document.createElement("div");
    list.className = "menu";
    // keep focus in the page's field (even in another frame) while the menu is clicked
    list.addEventListener("mousedown", (e) => e.preventDefault());
    shadow.append(style, list);
    document.documentElement.appendChild(host);
  }

  function removeMenu() {
    menu = null;
    if (host) host.remove();
    host = null;
  }

  function position() {
    if (!menu || !list) return;
    let r = menu.rect;
    if (menu.local) {
      const anchor = field && field.anchor;
      if (!anchor || !anchor.isConnected || !visible(anchor)) return closeMenu();
      r = rectOf(anchor);
    }
    const menuHeight = list.offsetHeight || 0;
    let top = r.bottom + 4;
    if (top + menuHeight > window.innerHeight && r.top - menuHeight - 4 > 0) top = r.top - menuHeight - 4;
    const left = Math.max(4, Math.min(r.left, window.innerWidth - list.offsetWidth - 4));
    list.style.top = `${Math.max(4, top)}px`;
    list.style.left = `${left}px`;
    list.style.minWidth = `${Math.max(240, Math.min(r.width, 360))}px`;
  }

  function header() {
    const head = document.createElement("div");
    head.className = "head";
    const img = document.createElement("img");
    img.src = ICON;
    head.append(img, document.createTextNode("OpenBubbles Passwords"));
    return head;
  }

  function renderMenu() {
    ensureHost();
    list.replaceChildren(header());
    if (menu.note) {
      const note = document.createElement("div");
      note.className = "note";
      note.textContent = menu.note;
      list.append(note);
    }
    menu.accounts.forEach((account, i) => {
      const item = document.createElement("div");
      item.className = "item" + (i === menu.active ? " active" : "");
      const key = document.createElement("div");
      key.className = "key";
      key.textContent = (account.username || "?").trim().charAt(0).toUpperCase() || "?";
      const text = document.createElement("div");
      text.className = "text";
      const user = document.createElement("div");
      user.className = "user";
      user.textContent = account.username || "(no username)";
      const site = document.createElement("div");
      site.className = "site";
      site.textContent = account.site;
      text.append(user, site);
      item.append(key, text);
      item.addEventListener("click", (e) => e.isTrusted && pick(account));
      list.append(item);
    });
    position();
  }

  function openMenu(m) {
    menu = { active: -1, accounts: [], note: null, ...m };
    renderMenu();
  }

  function tryOpenRemote(nonce) {
    const rect = offsets.get(nonce);
    const data = pendingMenus.get(nonce);
    if (!rect || !data) return;
    offsets.delete(nonce);
    pendingMenus.delete(nonce);
    openMenu({ nonce, rect, accounts: data.accounts || [], note: data.note || null, local: false });
  }

  // a click on an account in the menu
  async function pick(account) {
    const m = menu;
    if (!m) return;
    removeMenu();
    if (m.local) return fillFromApp(field, account.id);
    // the field is in another frame: OpenBubbles sends the password straight to that frame
    const res = await send({ type: "remoteChoose", nonce: m.nonce, credentialId: account.id });
    if (!res.ok && res.error !== "denied") openMenu({ ...m, accounts: [], note: FILL_FAILED });
  }

  // ----- the focused field (any frame) -----

  function closeMenu() {
    showGen++;
    if (IS_TOP) removeMenu();
    else if (field) send({ type: "remoteHide", nonce: field.nonce });
    field = null;
  }

  function setActive(active) {
    field.active = active;
    if (IS_TOP) {
      if (menu) {
        menu.active = active;
        renderMenu();
      }
    } else {
      send({ type: "remoteActive", nonce: field.nonce, active });
    }
  }

  async function show(fields) {
    const gen = ++showGen;
    const res = await getAccounts();
    // the user may have typed, or moved on, while we waited
    if (gen !== showGen) return;
    const anchor = document.activeElement;
    if (anchor !== fields.username && anchor !== fields.password) return;
    if (dismissed.has(anchor)) return;
    let accounts = [];
    let note = null;
    if (!res.ok) {
      if (!fields.password) return;
      if (res.error === "not_running") note = "Open OpenBubbles on this PC to fill passwords.";
      else if (res.error === "not_ready") note = "Passwords aren't ready yet. Open Passwords in OpenBubbles.";
      else return;
    } else {
      accounts = res.result?.accounts || [];
      if (!accounts.length) return closeMenu();
    }
    field = { ...fields, anchor, accounts, active: -1, nonce: crypto.randomUUID() };
    if (IS_TOP) {
      openMenu({ nonce: field.nonce, accounts, note, local: true });
      return;
    }
    fieldsByNonce.set(field.nonce, field);
    window.parent.postMessage({ __openbubbles: "offset", nonce: field.nonce, rect: rectOf(anchor) }, "*");
    send({ type: "remoteMenu", nonce: field.nonce, accounts, note });
  }

  // ---------- filling ----------

  function setValue(input, value) {
    input.focus();
    const setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, "value").set;
    setter.call(input, value);
    input.dispatchEvent(new InputEvent("input", { bubbles: true, inputType: "insertReplacementText", data: value }));
    input.dispatchEvent(new Event("change", { bubbles: true }));
  }

  function applyFill(fields, result) {
    const { username, password } = result || {};
    suppressUntil = Date.now() + 1500;
    if (fields.username && fields.username.isConnected && username) setValue(fields.username, username);
    if (fields.password && fields.password.isConnected && password) setValue(fields.password, password);
  }

  async function fillFromApp(fields, credentialId) {
    if (!fields) return;
    closeMenu();
    const res = await send({ type: "fill", credentialId });
    if (res.ok) return applyFill(fields, res.result);
    if (res.error !== "denied" && IS_TOP) {
      field = fields;
      openMenu({ nonce: fields.nonce, note: FILL_FAILED, local: true });
    }
  }

  // ---------- messages ----------

  chrome.runtime.onMessage.addListener((msg) => {
    if (!msg) return;
    if (msg.type === "doFill") {
      const fields = fieldsByNonce.get(msg.nonce);
      if (fields) applyFill(fields, msg);
      return;
    }
    if (!IS_TOP) return;
    if (msg.type === "menu" && typeof msg.nonce === "string") {
      pendingMenus.set(msg.nonce, msg);
      tryOpenRemote(msg.nonce);
    } else if (msg.type === "menuHide") {
      if (menu && menu.nonce === msg.nonce) removeMenu();
      pendingMenus.delete(msg.nonce);
      offsets.delete(msg.nonce);
    } else if (msg.type === "menuActive") {
      if (menu && menu.nonce === msg.nonce) {
        menu.active = msg.active;
        renderMenu();
      }
    }
  });

  // positions of fields in frames, passed up one frame at a time
  window.addEventListener("message", (e) => {
    const d = e.data;
    if (!d || d.__openbubbles !== "offset" || typeof d.nonce !== "string" || !d.rect) return;
    const frame = [...document.querySelectorAll("iframe, frame")].find((f) => f.contentWindow === e.source);
    if (!frame) return;
    const fr = frame.getBoundingClientRect();
    const cs = getComputedStyle(frame);
    const dx = fr.left + frame.clientLeft + (parseFloat(cs.paddingLeft) || 0);
    const dy = fr.top + frame.clientTop + (parseFloat(cs.paddingTop) || 0);
    const rect = { left: d.rect.left + dx, top: d.rect.top + dy, bottom: d.rect.bottom + dy, width: d.rect.width };
    if (IS_TOP) {
      offsets.set(d.nonce, rect);
      tryOpenRemote(d.nonce);
    } else {
      window.parent.postMessage({ __openbubbles: "offset", nonce: d.nonce, rect }, "*");
    }
  });

  // ---------- events ----------

  function onFocus(e) {
    const el = e.composedPath ? e.composedPath()[0] : e.target;
    if (Date.now() < suppressUntil) return;
    const fields = loginFieldsFor(el);
    if (!fields) return closeMenu();
    show(fields);
  }

  document.addEventListener("focusin", onFocus, true);
  document.addEventListener("click", (e) => {
    const el = e.composedPath ? e.composedPath()[0] : e.target;
    if (host && el === host) return;
    if (field && el === field.anchor) return;
    if (el instanceof HTMLInputElement && el === document.activeElement) return onFocus(e);
    closeMenu();
  }, true);
  document.addEventListener("focusout", () => {
    setTimeout(() => {
      if (field && document.activeElement !== field.anchor) closeMenu();
    }, 150);
  }, true);
  document.addEventListener("keydown", (e) => {
    if (!field || e.target !== field.anchor) {
      if (e.key.length === 1) showGen++; // typing elsewhere: don't pop a menu up late
      return;
    }
    const n = field.accounts.length;
    if (e.key === "Escape") {
      dismissed.add(field.anchor);
      closeMenu();
    } else if (n && e.key === "ArrowDown") {
      setActive((field.active + 1) % n);
      e.preventDefault();
    } else if (n && e.key === "ArrowUp") {
      setActive((field.active - 1 + n) % n);
      e.preventDefault();
    } else if (n && e.key === "Enter" && field.active >= 0) {
      e.preventDefault();
      e.stopPropagation();
      fillFromApp(field, field.accounts[field.active].id);
    } else if (e.key.length === 1) {
      // the user is typing their own value
      closeMenu();
    }
  }, true);
  window.addEventListener("scroll", () => {
    if (IS_TOP && menu && !menu.local) removeMenu(); // the frame moved under the menu
    else if (IS_TOP) position();
    else if (field) closeMenu();
  }, true);
  window.addEventListener("resize", () => (IS_TOP ? position() : field && closeMenu()));

  // ---------- offering to save ----------
  //
  // When a form with a password is submitted, the typed values go to the extension's background
  // worker, which asks OpenBubbles whether they're new or changed. The "Save password?" banner then
  // shows in the top frame (after the page navigates, if it does). Nothing is saved unless the user
  // clicks Save.

  let lastCapture = { key: "", at: 0 };

  function filledPasswords(root) {
    return [...root.querySelectorAll('input[type="password"]')].filter((p) => p.value && p.isConnected);
  }

  // the password being set: the new one on sign-up / change-password forms, else the only one
  function chosenPassword(passwords) {
    const fresh = passwords.filter(isNewPassword);
    if (fresh.length) return fresh[0];
    if (passwords.length >= 2) {
      const [a, b] = passwords.slice(-2);
      return a.value === b.value ? a : passwords[passwords.length - 1];
    }
    return passwords[0];
  }

  function capture(root) {
    const passwords = filledPasswords(root);
    if (!passwords.length) {
      // first step of a two-step sign-in: remember the user name for the password step
      const user = [...root.querySelectorAll("input")].find((e) => isTextLike(e) && e.value && looksLikeUsername(e));
      if (user) send({ type: "rememberUsername", username: user.value.trim() });
      return;
    }
    const password = chosenPassword(passwords);
    const user = usernameFor(password);
    const username = user && user.value ? user.value.trim() : "";
    const key = `${username}\n${password.value}`;
    if (key === lastCapture.key && Date.now() - lastCapture.at < 3000) return;
    lastCapture = { key, at: Date.now() };
    send({ type: "capture", username, password: password.value });
  }

  document.addEventListener("submit", (e) => {
    if (e.target instanceof HTMLFormElement) capture(e.target);
  }, true);

  // sites that sign in with script instead of submitting a form
  document.addEventListener("click", (e) => {
    const el = e.composedPath ? e.composedPath()[0] : e.target;
    const button = el instanceof Element ? el.closest('button, input[type="submit"], [role="button"]') : null;
    if (!button || button === host) return;
    const root = button.closest("form") || (filledPasswords(document).length ? document : null);
    if (root) capture(root);
  }, true);

  document.addEventListener("keydown", (e) => {
    if (e.key !== "Enter" || (field && field.active >= 0)) return;
    const el = e.target;
    if (el instanceof HTMLInputElement && (isPassword(el) || isTextLike(el))) capture(scopeOf(el));
  }, true);

  let banner = null;

  const BANNER_STYLE = `
    :host { all: initial; }
    .card {
      position: fixed; top: 16px; right: 16px; z-index: 2147483647; width: 340px; box-sizing: border-box;
      background: #fff; color: #1d1d1f; border: 1px solid rgba(0,0,0,.12); border-radius: 14px;
      box-shadow: 0 12px 36px rgba(0,0,0,.22); padding: 14px 16px 12px;
      font: 13px/1.35 -apple-system, "Segoe UI", system-ui, sans-serif;
      animation: in .18s ease-out;
    }
    @keyframes in { from { opacity: 0; transform: translateY(-6px); } to { opacity: 1; transform: none; } }
    .top { display: flex; gap: 12px; align-items: center; }
    .top img { width: 36px; height: 36px; border-radius: 8px; flex: none; }
    .title { font-weight: 600; font-size: 14px; }
    .sub { color: #6e6e73; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
    .text { min-width: 0; }
    .buttons { display: flex; align-items: center; gap: 8px; margin-top: 12px; }
    .never { margin-right: auto; background: none; border: 0; padding: 4px 0; color: #6e6e73; cursor: pointer; font: inherit; }
    .never:hover { text-decoration: underline; }
    button.b { border: 0; border-radius: 8px; padding: 6px 14px; font: inherit; font-weight: 600; cursor: pointer; }
    .later { background: rgba(0,0,0,.06); color: inherit; }
    .save { background: #0a84ff; color: #fff; }
    @media (prefers-color-scheme: dark) {
      .card { background: #2c2c2e; color: #f5f5f7; border-color: rgba(255,255,255,.12); }
      .sub, .never { color: #a1a1a6; }
      .later { background: rgba(255,255,255,.1); }
    }
  `;

  function closeBanner() {
    if (banner) banner.remove();
    banner = null;
  }

  function showBanner(pending) {
    if (window.top !== window) return;
    closeBanner();
    banner = document.createElement("openbubbles-save");
    const root = banner.attachShadow({ mode: "closed" });
    const style = document.createElement("style");
    style.textContent = BANNER_STYLE;
    const card = document.createElement("div");
    card.className = "card";

    const top = document.createElement("div");
    top.className = "top";
    const img = document.createElement("img");
    img.src = ICON;
    const text = document.createElement("div");
    text.className = "text";
    const title = document.createElement("div");
    title.className = "title";
    title.textContent = pending.failed
      ? "Couldn't save. Is OpenBubbles open?"
      : pending.state === "update" ? "Update saved password?" : "Save password?";
    const sub = document.createElement("div");
    sub.className = "sub";
    sub.textContent = `${pending.username || "No user name"} · ${pending.site}`;
    text.append(title, sub);
    top.append(img, text);

    const buttons = document.createElement("div");
    buttons.className = "buttons";
    const never = document.createElement("button");
    never.className = "never";
    never.textContent = "Never for this site";
    const later = document.createElement("button");
    later.className = "b later";
    later.textContent = "Not now";
    const save = document.createElement("button");
    save.className = "b save";
    save.textContent = pending.failed ? "Try again" : pending.state === "update" ? "Update" : "Save";
    buttons.append(never, later, save);

    const decide = async (decision) => {
      closeBanner();
      const res = await send({ type: "saveDecision", id: pending.id, decision });
      if (decision === "save" && !res.ok) {
        showBanner({ ...pending, failed: true });
      }
    };
    // only real clicks count; scripts on the page can't reach into the closed shadow root
    never.addEventListener("click", (e) => e.isTrusted && decide("never"));
    later.addEventListener("click", (e) => e.isTrusted && decide("dismiss"));
    save.addEventListener("click", (e) => e.isTrusted && decide("save"));

    card.append(top, buttons);
    root.append(style, card);
    document.documentElement.appendChild(banner);
  }

  chrome.runtime.onMessage.addListener((msg) => {
    if (msg && msg.type === "showSave" && msg.pending) showBanner(msg.pending);
  });

  // a save offered just before this page loaded (the sign-in form navigated here)
  if (window.top === window) {
    send({ type: "pendingSave" }).then((res) => {
      if (res.ok && res.result) showBanner(res.result);
    });
  }
})();
