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

chrome.runtime.sendMessage({ type: "status" }, (res) => {
  if (chrome.runtime.lastError || !res) res = { ok: false, error: "not_running" };
  if (res.ok) {
    box.className = "status ok";
    const n = res.result?.count ?? 0;
    text.textContent = "Connected to OpenBubbles.";
    hint.textContent = `${n} saved password${n === 1 ? "" : "s"}. Click a login box on a website to fill one.`;
    if (res.result?.version) appVersion = res.result.version;
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
  const { lastPasskey } = await chrome.storage.session.get("lastPasskey");
  if (lastPasskey && Date.now() - lastPasskey.at < 30 * 60 * 1000) {
    const el = document.getElementById("passkey");
    const mins = Math.round((Date.now() - lastPasskey.at) / 60000);
    el.textContent = `Last passkey request (${mins ? `${mins} min ago` : "just now"}): ${lastPasskey.site}, ${lastPasskey.outcome}.`;
    el.hidden = false;
  }
}
