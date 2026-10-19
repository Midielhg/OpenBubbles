const box = document.getElementById("status");
const text = document.getElementById("text");
const hint = document.getElementById("hint");

const MESSAGES = {
  not_installed: ["OpenBubbles isn't set up for this browser.",
    "Open OpenBubbles > Settings > Passwords > Browser Extension once, then restart the browser."],
  not_running: ["OpenBubbles isn't running.", "Open OpenBubbles on this PC to fill passwords."],
  not_ready: ["Passwords aren't ready yet.", "Open Passwords in OpenBubbles and join iCloud Keychain if asked."],
  disabled: ["Browser filling is turned off.", "Turn it on in OpenBubbles > Settings > Passwords > Browser Extension."],
};

let appVersion = "?";

function newer(a, b) {
  const pa = String(a).split(".").map(Number), pb = String(b).split(".").map(Number);
  for (let i = 0; i < Math.max(pa.length, pb.length); i++) {
    const x = pa[i] || 0, y = pb[i] || 0;
    if (x !== y) return x > y;
  }
  return false;
}

chrome.runtime.sendMessage({ type: "status" }, (res) => {
  if (chrome.runtime.lastError || !res) res = { ok: false, error: "not_running" };
  if (res.ok) {
    box.className = "status ok";
    const n = res.result?.count ?? 0;
    text.textContent = "Connected to OpenBubbles.";
    hint.textContent = `${n} saved password${n === 1 ? "" : "s"}. Click a login box on a website to fill one.`;
    if (res.result?.version) appVersion = res.result.version;
    // Loaded unpacked from OpenBubbles' folder, the extension only picks up new files there when it's
    // reloaded; offer that when the app came with a newer copy
    const bundled = res.result?.extensionVersion;
    if (bundled && newer(bundled, chrome.runtime.getManifest().version)) {
      hint.textContent = `Version ${bundled} came with OpenBubbles. If it's still not updated after this, ` +
        "load the extension again from the folder in OpenBubbles > Settings > Passwords > Browser Extension.";
      const update = document.getElementById("update");
      update.textContent = `Update to ${bundled}`;
      update.hidden = false;
      update.addEventListener("click", () => chrome.runtime.reload());
    }
  } else {
    box.className = "status bad";
    const [t, h] = MESSAGES[res.error] || ["Couldn't reach OpenBubbles.", `(${res.error})`];
    text.textContent = t;
    hint.textContent = h;
  }
  details();
});

// versions, and what happened with the last passkey request (helps when the browser's own prompt
// showed up instead)
async function details() {
  document.getElementById("versions").textContent =
    `Extension ${chrome.runtime.getManifest().version} · OpenBubbles ${appVersion}`;
  // what happened on this tab's last login box
  try {
    const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
    const fkey = `frames:${tab?.id}`;
    const frames = (await chrome.storage.session.get(fkey))[fkey];
    const fel = document.getElementById("frames");
    fel.textContent = frames
      ? `Running on: ${frames.hosts.join(", ")}.` +
        (frames.lastField ? ` Last box: ${frames.lastField.field} on ${frames.lastField.host} (${frames.lastField.kind}).` : " No box clicked yet.")
      : "Not running on this page. Reload the page.";
    fel.hidden = false;
    const key = `lookup:${tab?.id}`;
    const last = (await chrome.storage.session.get(key))[key];
    if (last) {
      const el = document.getElementById("lookup");
      el.textContent = last.error
        ? `This page (${last.host}): couldn't get logins (${last.error}).`
        : `This page (${last.host}): ${last.count} saved login${last.count === 1 ? "" : "s"} found.`;
      el.hidden = false;
    }
  } catch (_) {}
  const { lastPasskey } = await chrome.storage.session.get("lastPasskey");
  if (lastPasskey && Date.now() - lastPasskey.at < 30 * 60 * 1000) {
    const el = document.getElementById("passkey");
    const mins = Math.round((Date.now() - lastPasskey.at) / 60000);
    el.textContent = `Last passkey request (${mins ? `${mins} min ago` : "just now"}): ${lastPasskey.site}, ${lastPasskey.outcome}.`;
    el.hidden = false;
  }
}

// opens OpenBubbles straight to password search; if the app isn't running, start it through the
// openbubbles:// link (the browser asks once whether to open OpenBubbles)
document.getElementById("open").addEventListener("click", () => {
  chrome.runtime.sendMessage({ type: "openApp" }, (res) => {
    if (chrome.runtime.lastError || !res || !res.ok) chrome.tabs.create({ url: "openbubbles://passwords" });
    window.close();
  });
});
