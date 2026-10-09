// Shows an OpenBubbles account picker under login fields and fills the chosen account.
// Nothing is filled until the user clicks an account; the page never sees the list of accounts
// (it lives in a closed shadow root).

(() => {
  if (window.__openBubblesPasswords) return;
  window.__openBubblesPasswords = true;

  const USERNAME_HINT = /user|e-?mail|login|log-in|sign-?in|account|phone|identifier|correo|usuario/i;
  const LOOKUP_TTL_MS = 30000;
  // inlined so the icon needn't be exposed to every website (web_accessible_resources)
  const ICON = "data:image/png;base64,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";

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

  // Password boxes with a "show password" eye turn into text boxes when revealed, so remember every
  // box that has been a password box, and recognize the usual password names and autocomplete hints.
  const seenPasswords = new WeakSet();

  function notePasswords(root = document) {
    for (const input of root.querySelectorAll('input[type="password"]')) seenPasswords.add(input);
  }

  function isPassword(el) {
    if (!(el instanceof HTMLInputElement)) return false;
    if (el.type === "password" || seenPasswords.has(el)) return true;
    if (el.type !== "text") return false;
    return /current-password|new-password/i.test(el.autocomplete || "") ||
      /^(pass(word)?|passwd|pwd|pw)$|password/i.test(`${el.name} ${el.id}`.trim());
  }

  function passwordInputs(root) {
    return [...root.querySelectorAll("input")].filter(isPassword);
  }

  function isTextLike(el) {
    return el instanceof HTMLInputElement && ["text", "email", "tel"].includes(el.type) && !isPassword(el);
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
    const passwords = passwordInputs(scopeOf(el)).filter(
      (p) => usable(p) && !isNewPassword(p)
    );
    const next = passwords.find((p) => follows(el, p));
    if (next && usernameFor(next) === el) return { username: el, password: next };
    // username-only step (e.g. "enter your email" first, password on the next page)
    if (passwords.length === 0 && looksLikeUsername(el)) return { username: el, password: null };
    return null;
  }

  // ---------- which account is this sign-in for? ----------
  //
  // On a password-only step (e.g. Ring: the email is shown as text, with a "Change" link) the
  // account was picked a step earlier. Work out which one from a hidden user name field, the user
  // name typed on the previous step, or the address shown near the password box.

  const sameUser = (a, b) => (a || "").trim().toLowerCase() === (b || "").trim().toLowerCase();

  function hiddenUsername(fields) {
    const scope = scopeOf(fields.password || fields.username);
    const input = [...scope.querySelectorAll("input")].find((e) =>
      e !== fields.password && e.value && e.type !== "password" &&
      (e.type === "hidden" || e.readOnly || !visible(e)) &&
      (/username|email/i.test(e.autocomplete || "") || /user|e-?mail|login|account|identifier/i.test(`${e.name} ${e.id}`)));
    return input ? input.value.trim() : "";
  }

  function nearbyText(el) {
    let text = "";
    for (let node = el.parentElement, i = 0; node && i < 6; node = node.parentElement, i++) {
      const t = node.innerText || "";
      if (t.length > 5000) break;
      text = t;
    }
    return text.toLowerCase();
  }

  async function chosenAccounts(fields, accounts) {
    const named = accounts.filter((a) => a.username);
    const pick = (name) => named.filter((a) => sameUser(a.username, name));
    const hidden = hiddenUsername(fields);
    if (hidden && pick(hidden).length) return pick(hidden);
    const remembered = await send({ type: "knownUsername" });
    if (remembered.ok && remembered.result && pick(remembered.result).length) return pick(remembered.result);
    // the address shown on the page; prefer the longest so "bob" doesn't also match "bob2@..."
    const text = nearbyText(fields.password || fields.username);
    const shown = named.filter((a) => text.includes(a.username.trim().toLowerCase()));
    return shown.filter((a) => !shown.some((b) => b !== a && b.username.length > a.username.length &&
      b.username.toLowerCase().includes(a.username.trim().toLowerCase())));
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
    .key.passkey { background: #5e5ce6; font-size: 14px; }
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
    head.append(img, document.createTextNode("Passwords"));
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
      key.textContent = account.passkey ? "\u{1F511}" : (account.username || "?").trim().charAt(0).toUpperCase() || "?";
      if (account.passkey) key.classList.add("passkey");
      const text = document.createElement("div");
      text.className = "text";
      const user = document.createElement("div");
      user.className = "user";
      user.textContent = account.username || "(no username)";
      const site = document.createElement("div");
      site.className = "site";
      site.textContent = account.passkey ? `Passkey · ${account.site}` : account.site;
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
    if (account.passkey) return useConditionalPasskey(account);
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
      if (fields.username && fields.username.value && anchor === fields.password) {
        // the user name is already typed: offer just that login
        const only = accounts.filter((a) => sameUser(a.username, fields.username.value));
        if (only.length) accounts = only;
      } else if (!fields.username) {
        // password step after the account was chosen on an earlier step: offer just that login
        const only = await chosenAccounts(fields, accounts);
        if (gen !== showGen || document.activeElement !== anchor) return;
        if (only.length) accounts = only;
      }
      if (IS_TOP && conditional && conditional.passkeys.length && fields.username && anchor === fields.username) {
        accounts = [...conditional.passkeys, ...accounts];
      }
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
    notePasswords();
    const el = e.composedPath ? e.composedPath()[0] : e.target;
    if (Date.now() < suppressUntil) return;
    const fields = loginFieldsFor(el);
    if (!fields) return closeMenu();
    show(fields);
  }

  document.addEventListener("focusin", onFocus, true);
  document.addEventListener("pointerdown", () => notePasswords(), true);
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
      const account = field.accounts[field.active];
      if (account.passkey) {
        closeMenu();
        useConditionalPasskey(account);
      } else {
        fillFromApp(field, account.id);
      }
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
    return passwordInputs(root).filter((p) => p.value && p.isConnected);
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
    // change-password forms: the current password tells OpenBubbles which saved login this is
    const others = passwords.filter((p) => p !== password && p.value !== password.value);
    const old = others.find((p) => /current-password/i.test(p.autocomplete || "")) || others[0];
    // no user name box (signed in already): pass along user names shown on the page
    const hints = [];
    if (!username) {
      const hidden = hiddenUsername({ password, username: null });
      if (hidden) hints.push(hidden);
      hints.push(...(nearbyText(password).match(/[^\s@]+@[^\s@]+\.[a-z]{2,}/gi) || []).slice(0, 5));
    }
    const key = `${username}\n${password.value}`;
    if (key === lastCapture.key && Date.now() - lastCapture.at < 3000) return;
    lastCapture = { key, at: Date.now() };
    send({ type: "capture", username, password: password.value, oldPassword: old ? old.value : "", hints });
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

  // ---------- passkeys ----------
  //
  // passkeys_page.js (in the page's own world) hands navigator.credentials requests over with
  // window.postMessage. The user chooses in the extension's own cards (closed shadow root, real
  // clicks only); the background worker builds the client data from the address the browser
  // reports, and OpenBubbles signs.

  const PASSKEY_CHANNEL = "__openbubbles_passkeys";
  let conditional = null; // { id, payload, passkeys } waiting in the username box's menu
  let passkeyCard = null; // { id, el }

  function answer(id, message) {
    window.postMessage({ [PASSKEY_CHANNEL]: "response", id, ...message }, location.origin);
  }

  const PASSKEY_ERRORS = {
    exists: { name: "InvalidStateError", message: "A passkey for this account is already saved." },
    denied: { name: "NotAllowedError", message: "The operation either timed out or was not allowed." },
    no_windows_hello: { name: "NotAllowedError", message: "This site requires Windows Hello, which isn't set up." },
  };

  async function passkeysFor(payload) {
    if (!IS_TOP) return null;
    // Apple's own sign-in needs extra Apple data that only Apple devices provide
    if (payload.extensions && payload.extensions.includes("largeBlob")) {
      send({ type: "passkeySkipped", rpId: payload.rpId, reason: "Apple sign-in, which needs an Apple device" });
      return null;
    }
    const res = await send({ type: "passkeyList", rpId: payload.rpId, allow: payload.allow || [] });
    if (!res.ok) return null;
    return (res.result?.passkeys || []).map((p) => ({ ...p, passkey: true }));
  }

  async function sign(payload, passkey) {
    return send({
      type: "passkeyGet",
      rpId: payload.rpId,
      id: passkey.id,
      challenge: payload.challenge,
      userVerification: payload.userVerification,
    });
  }

  async function useConditionalPasskey(account) {
    const c = conditional;
    if (!c) return;
    const res = await sign(c.payload, account);
    if (res.ok) {
      conditional = null;
      answer(c.id, { result: res.result });
    }
  }

  function closePasskeyCard() {
    if (passkeyCard) passkeyCard.el.remove();
    passkeyCard = null;
  }

  // a card like the save banner, with a list of passkeys and buttons
  function showPasskeyCard(id, { title, subtitle, items, buttons }) {
    closePasskeyCard();
    const el = document.createElement("openbubbles-passkey");
    const root = el.attachShadow({ mode: "closed" });
    const style = document.createElement("style");
    style.textContent = BANNER_STYLE + PASSKEY_CARD_STYLE;
    const card = document.createElement("div");
    card.className = "card";
    const top = document.createElement("div");
    top.className = "top";
    const img = document.createElement("img");
    img.src = ICON;
    const text = document.createElement("div");
    text.className = "text";
    const t = document.createElement("div");
    t.className = "title";
    t.textContent = title;
    const sub = document.createElement("div");
    sub.className = "sub";
    sub.textContent = subtitle;
    text.append(t, sub);
    top.append(img, text);
    card.append(top);
    if (items && items.length) {
      const list = document.createElement("div");
      list.className = "list";
      for (const item of items) {
        const row = document.createElement("div");
        row.className = "row";
        const key = document.createElement("div");
        key.className = "pk";
        key.textContent = "\u{1F511}";
        const name = document.createElement("div");
        name.className = "name";
        name.textContent = item.label;
        row.append(key, name);
        row.addEventListener("click", (e) => e.isTrusted && item.onClick());
        list.append(row);
      }
      card.append(list);
    }
    const row = document.createElement("div");
    row.className = "buttons";
    for (const b of buttons) {
      const button = document.createElement("button");
      button.className = b.kind === "link" ? "never" : `b ${b.kind === "primary" ? "save" : "later"}`;
      button.textContent = b.label;
      button.addEventListener("click", (e) => e.isTrusted && b.onClick());
      row.append(button);
    }
    card.append(row);
    root.append(style, card);
    document.documentElement.appendChild(el);
    passkeyCard = { id, el };
  }

  const PASSKEY_CARD_STYLE = `
    .list { margin-top: 10px; display: flex; flex-direction: column; gap: 2px; max-height: 220px; overflow-y: auto; }
    .row { display: flex; align-items: center; gap: 10px; padding: 8px; border-radius: 8px; cursor: pointer; }
    .row:hover { background: #0a84ff; color: #fff; }
    .pk { width: 28px; height: 28px; border-radius: 50%; background: #5e5ce6; display: flex; align-items: center; justify-content: center; flex: none; }
    .name { font-weight: 600; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  `;

  async function handleGet(id, payload) {
    const passkeys = await passkeysFor(payload);
    if (!passkeys || !passkeys.length) return answer(id, { fallback: true });
    const done = (message) => {
      closePasskeyCard();
      answer(id, message);
    };
    showPasskeyCard(id, {
      title: "Sign in with a passkey",
      subtitle: payload.rpId,
      items: passkeys.map((p) => ({
        label: p.username || "(no user name)",
        onClick: async () => {
          closePasskeyCard();
          const res = await sign(payload, p);
          answer(id, res.ok ? { result: res.result } : { error: PASSKEY_ERRORS[res.error] || PASSKEY_ERRORS.denied });
        },
      })),
      buttons: [
        { label: "Use another device", kind: "link", onClick: () => done({ fallback: true }) },
        { label: "Cancel", kind: "secondary", onClick: () => done({ error: PASSKEY_ERRORS.denied }) },
      ],
    });
  }

  async function handleCreate(id, payload) {
    if (!IS_TOP) return answer(id, { fallback: true });
    const status = await send({ type: "passkeyList", rpId: payload.rpId, allow: [] });
    if (!status.ok) return answer(id, { fallback: true }); // OpenBubbles isn't available
    const done = (message) => {
      closePasskeyCard();
      answer(id, message);
    };
    showPasskeyCard(id, {
      title: "Save a passkey?",
      subtitle: `${payload.user.name || payload.user.displayName || "Your account"} · ${payload.rpId}`,
      buttons: [
        { label: "Use another device", kind: "link", onClick: () => done({ fallback: true }) },
        { label: "Cancel", kind: "secondary", onClick: () => done({ error: PASSKEY_ERRORS.denied }) },
        {
          label: "Save",
          kind: "primary",
          onClick: async () => {
            closePasskeyCard();
            const res = await send({
              type: "passkeyCreate",
              rpId: payload.rpId,
              user: payload.user,
              challenge: payload.challenge,
              exclude: payload.exclude,
              userVerification: payload.userVerification,
            });
            answer(id, res.ok ? { result: res.result } : { error: PASSKEY_ERRORS[res.error] || PASSKEY_ERRORS.denied });
          },
        },
      ],
    });
  }

  window.addEventListener("message", async (e) => {
    const d = e.data;
    if (e.source !== window || !d || d[PASSKEY_CHANNEL] !== "request" || typeof d.id !== "string") return;
    const payload = d.payload || {};
    if (d.kind === "cancel") {
      if (passkeyCard && passkeyCard.id === d.id) closePasskeyCard();
      if (conditional && conditional.id === d.id) conditional = null;
    } else if (d.kind === "get") {
      handleGet(d.id, payload);
    } else if (d.kind === "create") {
      handleCreate(d.id, payload);
    } else if (d.kind === "conditional") {
      const passkeys = await passkeysFor(payload);
      if (passkeys && passkeys.length) conditional = { id: d.id, payload, passkeys };
    }
  });
})();
