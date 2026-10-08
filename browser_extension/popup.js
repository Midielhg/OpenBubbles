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

chrome.runtime.sendMessage({ type: "status" }, (res) => {
  if (chrome.runtime.lastError || !res) res = { ok: false, error: "not_running" };
  if (res.ok) {
    box.className = "status ok";
    const n = res.result?.count ?? 0;
    text.textContent = "Connected to OpenBubbles.";
    hint.textContent = `${n} saved password${n === 1 ? "" : "s"}. Click a login box on a website to fill one.`;
  } else {
    box.className = "status bad";
    const [t, h] = MESSAGES[res.error] || ["Couldn't reach OpenBubbles.", `(${res.error})`];
    text.textContent = t;
    hint.textContent = h;
  }
});
