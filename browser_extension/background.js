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
  return false;
});
