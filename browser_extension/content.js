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
  let current = null; // { username, password, anchor, accounts, active }
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

  const STYLE = `
    :host { all: initial; }
    .menu {
      position: fixed; z-index: 2147483647; min-width: 240px; max-width: 360px;
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

  function ensureHost() {
    if (host && host.isConnected) return;
    host = document.createElement("openbubbles-passwords");
    shadow = host.attachShadow({ mode: "closed" });
    const style = document.createElement("style");
    style.textContent = STYLE;
    list = document.createElement("div");
    list.className = "menu";
    // keep focus in the page's field while the menu is clicked
    list.addEventListener("mousedown", (e) => e.preventDefault());
    shadow.append(style, list);
    document.documentElement.appendChild(host);
  }

  function hide() {
    current = null;
    if (host) host.remove();
    host = null;
  }

  function position() {
    if (!current || !list) return;
    const anchor = current.anchor;
    if (!anchor.isConnected || !visible(anchor)) return hide();
    const r = anchor.getBoundingClientRect();
    const menuHeight = list.offsetHeight || 0;
    let top = r.bottom + 4;
    if (top + menuHeight > window.innerHeight && r.top - menuHeight - 4 > 0) top = r.top - menuHeight - 4;
    const left = Math.max(4, Math.min(r.left, window.innerWidth - list.offsetWidth - 4));
    list.style.top = `${top}px`;
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

  function showNote(fields, text) {
    ensureHost();
    const anchor = document.activeElement === fields.username ? fields.username : fields.password || fields.username;
    current = { ...fields, anchor, accounts: [], active: -1 };
    list.replaceChildren(header());
    const note = document.createElement("div");
    note.className = "note";
    note.textContent = text;
    list.append(note);
    position();
  }

  function render() {
    list.replaceChildren(header());
    current.accounts.forEach((account, i) => {
      const item = document.createElement("div");
      item.className = "item" + (i === current.active ? " active" : "");
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
      item.addEventListener("click", () => choose(account));
      list.append(item);
    });
    position();
  }

  async function show(fields) {
    const res = await getAccounts();
    // focus may have moved while we waited
    const anchor = document.activeElement;
    if (anchor !== fields.username && anchor !== fields.password) return;
    if (dismissed.has(anchor)) return;
    if (!res.ok) {
      if (fields.password && res.error === "not_running") showNote(fields, "Open OpenBubbles on this PC to fill passwords.");
      else if (fields.password && res.error === "not_ready") showNote(fields, "Passwords aren't ready yet. Open Passwords in OpenBubbles.");
      return;
    }
    const accounts = res.result?.accounts || [];
    if (!accounts.length) return hide();
    ensureHost();
    current = { ...fields, anchor, accounts, active: -1 };
    render();
  }

  // ---------- filling ----------

  function setValue(input, value) {
    input.focus();
    const setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, "value").set;
    setter.call(input, value);
    input.dispatchEvent(new InputEvent("input", { bubbles: true, inputType: "insertReplacementText", data: value }));
    input.dispatchEvent(new Event("change", { bubbles: true }));
  }

  async function choose(account) {
    const fields = current;
    if (!fields) return;
    hide();
    const res = await send({ type: "fill", credentialId: account.id });
    if (!res.ok) {
      if (res.error !== "denied") showNote(fields, "Couldn't fill this password. Check that OpenBubbles is open.");
      return;
    }
    const { username, password } = res.result || {};
    suppressUntil = Date.now() + 1500;
    if (fields.username && fields.username.isConnected && username) setValue(fields.username, username);
    if (fields.password && fields.password.isConnected && password) setValue(fields.password, password);
  }

  // ---------- events ----------

  function onFocus(e) {
    const el = e.composedPath ? e.composedPath()[0] : e.target;
    if (Date.now() < suppressUntil) return;
    const fields = loginFieldsFor(el);
    if (!fields) return hide();
    show(fields);
  }

  document.addEventListener("focusin", onFocus, true);
  document.addEventListener("click", (e) => {
    const el = e.composedPath ? e.composedPath()[0] : e.target;
    if (el === host) return;
    if (current && el === current.anchor) return;
    if (el instanceof HTMLInputElement && el === document.activeElement) return onFocus(e);
    hide();
  }, true);
  document.addEventListener("focusout", () => {
    setTimeout(() => {
      if (current && document.activeElement !== current.anchor) hide();
    }, 150);
  }, true);
  document.addEventListener("keydown", (e) => {
    if (!current || e.target !== current.anchor) return;
    const n = current.accounts.length;
    if (e.key === "Escape") {
      dismissed.add(current.anchor);
      hide();
    } else if (n && e.key === "ArrowDown") {
      current.active = (current.active + 1) % n;
      render();
      e.preventDefault();
    } else if (n && e.key === "ArrowUp") {
      current.active = (current.active - 1 + n) % n;
      render();
      e.preventDefault();
    } else if (n && e.key === "Enter" && current.active >= 0) {
      e.preventDefault();
      e.stopPropagation();
      choose(current.accounts[current.active]);
    } else if (e.key.length === 1) {
      // the user is typing their own value
      hide();
    }
  }, true);
  window.addEventListener("scroll", position, true);
  window.addEventListener("resize", position);
})();
