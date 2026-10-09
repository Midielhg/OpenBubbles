// Talks to the OpenBubbles desktop app through Chrome/Edge native messaging. The browser starts
// openbubbles_password_host.exe (registered by the app, and only for this extension's ID), which
// relays to the running app. Every request carries the page address as reported by the browser
// (sender.url), never one supplied by the page, so a site can only get its own passwords.

const HOST = "com.openbubbles.passwords";

let port = null;
let nextId = 1;
let lastError = null;
const pending = new Map();

function failAll(error) {
  for (const p of pending.values()) {
    clearTimeout(p.timer);
    p.reject(new Error(error));
  }
  pending.clear();
}

function connect() {
  if (port) return port;
  lastError = null;
  try {
    port = chrome.runtime.connectNative(HOST);
  } catch (e) {
    lastError = "not_installed";
    return null;
  }
  port.onMessage.addListener((msg) => {
    if (!msg || typeof msg !== "object") return;
    if (msg.id == null) {
      // the host reports a problem that isn't tied to one request (e.g. the app isn't running)
      if (msg.error) {
        lastError = msg.error;
        failAll(msg.error);
      }
      return;
    }
    const p = pending.get(msg.id);
    if (!p) return;
    pending.delete(msg.id);
    clearTimeout(p.timer);
    if (msg.error) p.reject(new Error(msg.error));
    else p.resolve(msg.result);
  });
  port.onDisconnect.addListener(() => {
    const reason = chrome.runtime.lastError?.message || "";
    if (!lastError) {
      lastError = /not found|forbidden|not exist/i.test(reason) ? "not_installed" : "not_running";
    }
    port = null;
    failAll(lastError);
  });
  return port;
}

function request(type, params, timeoutMs) {
  return new Promise((resolve, reject) => {
    const p = connect();
    if (!p) {
      reject(new Error(lastError || "not_installed"));
      return;
    }
    const id = nextId++;
    const timer = setTimeout(() => {
      pending.delete(id);
      reject(new Error("timeout"));
    }, timeoutMs);
    pending.set(id, { resolve, reject, timer });
    try {
      p.postMessage({ id, type, ...params });
    } catch (e) {
      pending.delete(id);
      clearTimeout(timer);
      port = null;
      reject(new Error(lastError || "not_running"));
    }
  });
}

function reply(promise, sendResponse) {
  promise.then(
    (result) => sendResponse({ ok: true, result }),
    (error) => sendResponse({ ok: false, error: error.message })
  );
  return true; // respond asynchronously
}

chrome.runtime.onMessage.addListener((msg, sender, sendResponse) => {
  if (sender.id !== chrome.runtime.id || !msg) return false;

  // toolbar popup (an extension page, not a website)
  if (msg.type === "status" && sender.url?.startsWith(chrome.runtime.getURL(""))) {
    return reply(request("status", {}, 15000), sendResponse);
  }

  // content scripts: use the frame address the browser reports
  const url = sender.url;
  if (!sender.tab || !url || !/^https?:/i.test(url)) return false;

  if (msg.type === "lookup") {
    return reply(request("lookup", { url }, 15000), sendResponse);
  }
  if (msg.type === "fill" && typeof msg.credentialId === "string") {
    // long timeout: OpenBubbles may be waiting on Windows Hello
    return reply(request("fill", { url, credentialId: msg.credentialId }, 120000), sendResponse);
  }

  const tabId = sender.tab.id;

  // a login field inside a frame: its menu is drawn by the top frame of the same tab
  if (msg.type === "remoteMenu" && typeof msg.nonce === "string" && sender.frameId !== 0) {
    remoteMenus.set(msg.nonce, { tabId, frameId: sender.frameId, url, at: Date.now() });
    pruneRemoteMenus();
    toTop(tabId, { type: "menu", nonce: msg.nonce, accounts: msg.accounts || [], note: msg.note || null });
    return false;
  }
  if (msg.type === "remoteHide" && typeof msg.nonce === "string") {
    toTop(tabId, { type: "menuHide", nonce: msg.nonce });
    return false;
  }
  if (msg.type === "remoteActive" && typeof msg.nonce === "string") {
    toTop(tabId, { type: "menuActive", nonce: msg.nonce, active: msg.active });
    return false;
  }
  if (msg.type === "remoteChoose" && sender.frameId === 0 && typeof msg.nonce === "string" && typeof msg.credentialId === "string") {
    return reply(remoteChoose(tabId, msg.nonce, msg.credentialId), sendResponse);
  }
  // passkeys: top frames only, for the page's own site
  if (msg.type === "passkeyList" && sender.frameId === 0 && typeof msg.rpId === "string") {
    return reply(passkeyList(url, msg), sendResponse);
  }
  if (msg.type === "passkeySkipped" && typeof msg.reason === "string") {
    notePasskey(msg.rpId, msg.reason);
    return false;
  }
  if (msg.type === "passkeyGet" && sender.frameId === 0) {
    return reply(passkeyGet(url, msg), sendResponse);
  }
  if (msg.type === "passkeyCreate" && sender.frameId === 0) {
    return reply(passkeyCreate(url, msg), sendResponse);
  }
  if (msg.type === "rememberUsername" && typeof msg.username === "string") {
    return reply(rememberUsername(tabId, url, msg.username), sendResponse);
  }
  if (msg.type === "capture" && typeof msg.password === "string" && typeof msg.username === "string") {
    return reply(capture(tabId, sender.frameId, url, msg.username, msg.password), sendResponse);
  }
  if (msg.type === "knownUsername") {
    return reply(knownUsername(tabId, url), sendResponse);
  }
  if (msg.type === "pendingSave") {
    return reply(pendingFor(tabId), sendResponse);
  }
  if (msg.type === "saveDecision" && sender.frameId === 0 && typeof msg.id === "string") {
    return reply(decide(tabId, msg.id, msg.decision), sendResponse);
  }
  return false;
});

// ---------- passkeys ----------
//
// The client data the site checks is built here, from the page address the browser reports for the
// requesting tab, so a page can't claim to be another site. OpenBubbles signs its hash.

function b64url(bytes) {
  let s = "";
  for (const b of new Uint8Array(bytes)) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

async function clientData(type, url, challenge) {
  if (typeof challenge !== "string" || !/^[A-Za-z0-9_-]+$/.test(challenge)) throw new Error("denied");
  const json = JSON.stringify({ type, challenge, origin: new URL(url).origin, crossOrigin: false });
  const bytes = new TextEncoder().encode(json);
  return { clientDataJSON: b64url(bytes), clientDataHash: b64url(await crypto.subtle.digest("SHA-256", bytes)) };
}

// what happened with the last passkey request, shown in the toolbar popup
function notePasskey(site, outcome) {
  chrome.storage.session.set({ lastPasskey: { site, outcome, at: Date.now() } });
}

async function passkeyList(url, msg) {
  try {
    const result = await request("passkeys", { url, rpId: msg.rpId, allow: msg.allow || [] }, 15000);
    const n = (result.passkeys || []).length;
    if (n) notePasskey(msg.rpId, `offered ${n} passkey${n === 1 ? "" : "s"}`);
    else if (result.forSite) notePasskey(msg.rpId, "the site asked for a different passkey than the one saved");
    else notePasskey(msg.rpId, `no passkey saved for this site in OpenBubbles (${result.total ?? "?"} passkeys in total)`);
    return result;
  } catch (e) {
    const reasons = {
      not_running: "OpenBubbles wasn't running",
      not_ready: "OpenBubbles passwords weren't ready",
      unknown: "OpenBubbles needs updating to 1.15.10 or newer",
      denied: "the site's passkey name doesn't match its address",
    };
    notePasskey(msg.rpId, reasons[e.message] || `error: ${e.message}`);
    throw e;
  }
}

async function passkeyGet(url, msg) {
  const data = await clientData("webauthn.get", url, msg.challenge);
  const result = await request("passkeyAssert", {
    url,
    rpId: msg.rpId,
    passkeyId: msg.id, // not "id": that's the request's own ID
    clientDataHash: data.clientDataHash,
    userVerification: msg.userVerification,
  }, 120000);
  return { ...result, clientDataJSON: data.clientDataJSON };
}

async function passkeyCreate(url, msg) {
  const data = await clientData("webauthn.create", url, msg.challenge);
  const result = await request("passkeyRegister", {
    url,
    rpId: msg.rpId,
    user: msg.user,
    exclude: msg.exclude || [],
    clientDataHash: data.clientDataHash,
    userVerification: msg.userVerification,
  }, 120000);
  return { ...result, clientDataJSON: data.clientDataJSON };
}

// ---------- menus for fields inside frames ----------

const remoteMenus = new Map(); // nonce -> { tabId, frameId, url, at }

function toTop(tabId, message) {
  chrome.tabs.sendMessage(tabId, message, { frameId: 0 }).catch(() => {});
}

function pruneRemoteMenus() {
  const cutoff = Date.now() - 10 * 60 * 1000;
  for (const [nonce, m] of remoteMenus) if (m.at < cutoff) remoteMenus.delete(nonce);
}

// The account was clicked in the top frame's menu. Fill it in the frame that has the field, for
// the address that frame reported, so the top page never sees the password.
async function remoteChoose(tabId, nonce, credentialId) {
  const m = remoteMenus.get(nonce);
  if (!m || m.tabId !== tabId) throw new Error("expired");
  const result = await request("fill", { url: m.url, credentialId }, 120000);
  await chrome.tabs.sendMessage(tabId, { type: "doFill", nonce, ...result }, { frameId: m.frameId });
  return null;
}

// ---------- offering to save ----------
//
// Captured logins are kept in chrome.storage.session, which lives in memory only and which
// websites and content scripts can't read. They expire after a couple of minutes.

const PENDING_TTL_MS = 2 * 60 * 1000;

function siteOf(url) {
  try {
    const host = new URL(url).hostname.toLowerCase();
    return host.startsWith("www.") ? host.slice(4) : host;
  } catch (e) {
    return "";
  }
}

async function sessionGet(key) {
  return (await chrome.storage.session.get(key))[key];
}

async function neverSites() {
  return (await chrome.storage.local.get("neverSave")).neverSave || [];
}

async function rememberUsername(tabId, url, username) {
  if (!username) return null;
  await chrome.storage.session.set({ [`user:${tabId}`]: { site: siteOf(url), username, at: Date.now() } });
  return null;
}

// the user name typed on the previous step of this site's sign-in, if recent
async function knownUsername(tabId, url) {
  const remembered = await sessionGet(`user:${tabId}`);
  if (!remembered || remembered.site !== siteOf(url) || Date.now() - remembered.at > 10 * 60 * 1000) return null;
  return remembered.username;
}

async function capture(tabId, frameId, url, username, password) {
  const site = siteOf(url);
  if (!site || !password || (await neverSites()).includes(site)) return null;
  if (!username) {
    // password step of a two-step sign-in
    const remembered = await sessionGet(`user:${tabId}`);
    if (remembered && remembered.site === site && Date.now() - remembered.at < PENDING_TTL_MS) {
      username = remembered.username;
    }
  }
  const check = await request("checkSave", { url, username, password }, 15000);
  if (!check || (check.state !== "new" && check.state !== "update")) return null;
  const pending = {
    id: crypto.randomUUID(),
    url,
    site: check.site || site,
    username,
    password,
    state: check.state,
    at: Date.now(),
  };
  await chrome.storage.session.set({ [`save:${tabId}`]: pending });
  // give the page a moment: most sign-ins navigate away, and the new page asks for the offer itself
  setTimeout(async () => {
    const latest = await sessionGet(`save:${tabId}`);
    if (!latest || latest.id !== pending.id) return;
    chrome.tabs.sendMessage(tabId, { type: "showSave", pending: publicView(latest) }, { frameId: 0 }).catch(() => {});
  }, 1200);
  return null;
}

// what the page script needs to draw the banner (no password)
function publicView(pending) {
  return { id: pending.id, site: pending.site, username: pending.username, state: pending.state };
}

async function pendingFor(tabId) {
  const pending = await sessionGet(`save:${tabId}`);
  if (!pending || Date.now() - pending.at > PENDING_TTL_MS) return null;
  return publicView(pending);
}

async function decide(tabId, id, decision) {
  const key = `save:${tabId}`;
  const pending = await sessionGet(key);
  if (!pending || pending.id !== id) throw new Error("expired");
  if (decision === "save") {
    // the address the login was typed on, as reported by the browser when it was captured
    await request("save", { url: pending.url, username: pending.username, password: pending.password }, 30000);
  } else if (decision === "never") {
    const sites = await neverSites();
    if (!sites.includes(pending.site)) await chrome.storage.local.set({ neverSave: [...sites, pending.site] });
  }
  await chrome.storage.session.remove(key);
  return null;
}

chrome.tabs.onRemoved.addListener((tabId) => {
  chrome.storage.session.remove([`save:${tabId}`, `user:${tabId}`]);
});
