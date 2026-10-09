// Runs in the page's own JavaScript world (manifest "world": "MAIN") so it can stand in for
// navigator.credentials.get()/create() when a site asks for a passkey. It only relays the request to
// the extension's content script and turns the answer into the objects the site expects; the user
// picks or confirms in the extension's own UI, and OpenBubbles does the signing. Whenever the
// extension can't or shouldn't handle a request, the browser's normal passkey prompt runs instead.

(() => {
  const credentials = navigator.credentials;
  if (!credentials || typeof PublicKeyCredential === "undefined" || window.top !== window) return;
  if (window.__openBubblesPasskeys) return;
  window.__openBubblesPasskeys = true;

  const CHANNEL = "__openbubbles_passkeys";
  const nativeGet = credentials.get.bind(credentials);
  const nativeCreate = credentials.create.bind(credentials);
  const waiting = new Map();
  let nextId = 0;

  const b64 = (buffer) => {
    const bytes = buffer instanceof ArrayBuffer ? new Uint8Array(buffer) : new Uint8Array(buffer.buffer, buffer.byteOffset, buffer.byteLength);
    let s = "";
    for (const b of bytes) s += String.fromCharCode(b);
    return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
  };
  const unb64 = (value) => {
    const s = atob(value.replace(/-/g, "+").replace(/_/g, "/") + "===".slice((value.length + 3) % 4));
    const bytes = new Uint8Array(s.length);
    for (let i = 0; i < s.length; i++) bytes[i] = s.charCodeAt(i);
    return bytes.buffer;
  };

  window.addEventListener("message", (e) => {
    const d = e.data;
    if (e.source !== window || !d || d[CHANNEL] !== "response") return;
    const resolve = waiting.get(d.id);
    if (resolve) {
      waiting.delete(d.id);
      resolve(d);
    }
  });

  function ask(kind, payload, signal) {
    const id = `${Date.now()}:${++nextId}:${Math.random()}`;
    const promise = new Promise((resolve) => waiting.set(id, resolve));
    window.postMessage({ [CHANNEL]: "request", id, kind, payload }, location.origin);
    if (signal) {
      signal.addEventListener("abort", () => {
        window.postMessage({ [CHANNEL]: "request", id, kind: "cancel", payload: {} }, location.origin);
        const resolve = waiting.get(id);
        if (resolve) {
          waiting.delete(id);
          resolve({ aborted: true });
        }
      }, { once: true });
    }
    return { id, promise };
  }

  // own properties shadow the prototype's getters, so the objects pass instanceof checks
  function define(target, values) {
    for (const [key, value] of Object.entries(values)) {
      Object.defineProperty(target, key, { value, enumerable: true, configurable: true });
    }
    return target;
  }

  function assertionCredential(r) {
    const response = define(Object.create(AuthenticatorAssertionResponse.prototype), {
      clientDataJSON: unb64(r.clientDataJSON),
      authenticatorData: unb64(r.authenticatorData),
      signature: unb64(r.signature),
      userHandle: r.userHandle ? unb64(r.userHandle) : null,
    });
    return credential(r, response, () => ({
      clientDataJSON: r.clientDataJSON,
      authenticatorData: r.authenticatorData,
      signature: r.signature,
      ...(r.userHandle ? { userHandle: r.userHandle } : {}),
    }));
  }

  function registrationCredential(r) {
    const response = define(Object.create(AuthenticatorAttestationResponse.prototype), {
      clientDataJSON: unb64(r.clientDataJSON),
      attestationObject: unb64(r.attestationObject),
      getAuthenticatorData: () => unb64(r.authenticatorData),
      getPublicKey: () => unb64(r.publicKey),
      getPublicKeyAlgorithm: () => -7,
      getTransports: () => ["hybrid", "internal"],
    });
    return credential(r, response, () => ({
      clientDataJSON: r.clientDataJSON,
      attestationObject: r.attestationObject,
      authenticatorData: r.authenticatorData,
      publicKey: r.publicKey,
      publicKeyAlgorithm: -7,
      transports: ["hybrid", "internal"],
    }));
  }

  function credential(r, response, responseJSON) {
    return define(Object.create(PublicKeyCredential.prototype), {
      id: r.credentialId,
      rawId: unb64(r.credentialId),
      type: "public-key",
      authenticatorAttachment: "platform",
      response,
      getClientExtensionResults: () => ({}),
      toJSON: () => ({
        id: r.credentialId,
        rawId: r.credentialId,
        type: "public-key",
        authenticatorAttachment: "platform",
        response: responseJSON(),
        clientExtensionResults: {},
      }),
    });
  }

  function fail(error) {
    return new DOMException(error.message || "The operation either timed out or was not allowed.", error.name || "NotAllowedError");
  }

  credentials.get = function (options) {
    const pk = options && options.publicKey;
    if (!pk) return nativeGet(options);
    let payload;
    try {
      payload = {
        rpId: pk.rpId || location.hostname,
        challenge: b64(pk.challenge),
        allow: (pk.allowCredentials || []).map((c) => b64(c.id)),
        userVerification: pk.userVerification || "preferred",
        extensions: Object.keys(pk.extensions || {}),
      };
    } catch (e) {
      return nativeGet(options);
    }

    if (options.mediation === "conditional") return conditionalGet(options, payload);

    const { promise } = ask("get", payload, options.signal);
    return promise.then((res) => {
      if (res.aborted) throw new DOMException("The operation was aborted.", "AbortError");
      if (res.fallback) return nativeGet(options);
      if (res.error) throw fail(res.error);
      return assertionCredential(res.result);
    });
  };

  // Sign-in suggestions in the username box (mediation: "conditional"): offer OpenBubbles passkeys in
  // the extension's menu while the browser's own suggestions keep working; whichever is used first wins.
  function conditionalGet(options, payload) {
    const browser = new AbortController();
    const pageSignal = options.signal;
    return new Promise((resolve, reject) => {
      let done = false;
      const finish = (fn, value) => {
        if (done) return;
        done = true;
        fn(value);
      };
      const ours = ask("conditional", payload, pageSignal);
      ours.promise.then((res) => {
        if (res.result) {
          browser.abort();
          finish(resolve, assertionCredential(res.result));
        }
      });
      const nativeOptions = { ...options, signal: browser.signal };
      nativeGet(nativeOptions).then(
        (c) => {
          window.postMessage({ [CHANNEL]: "request", id: ours.id, kind: "cancel", payload: {} }, location.origin);
          finish(resolve, c);
        },
        (err) => {
          if (!browser.signal.aborted) finish(reject, err);
        }
      );
      if (pageSignal) {
        pageSignal.addEventListener("abort", () => {
          browser.abort();
          finish(reject, new DOMException("The operation was aborted.", "AbortError"));
        }, { once: true });
      }
    });
  }

  credentials.create = function (options) {
    const pk = options && options.publicKey;
    if (!pk) return nativeCreate(options);
    let payload;
    try {
      payload = {
        rpId: (pk.rp && pk.rp.id) || location.hostname,
        rpName: (pk.rp && pk.rp.name) || "",
        user: { id: b64(pk.user.id), name: pk.user.name || "", displayName: pk.user.displayName || "" },
        challenge: b64(pk.challenge),
        algorithms: (pk.pubKeyCredParams || []).map((p) => p.alg),
        exclude: (pk.excludeCredentials || []).map((c) => b64(c.id)),
        userVerification: (pk.authenticatorSelection && pk.authenticatorSelection.userVerification) || "preferred",
        attachment: pk.authenticatorSelection && pk.authenticatorSelection.authenticatorAttachment,
      };
    } catch (e) {
      return nativeCreate(options);
    }
    // only ES256 keys, and only when the site doesn't insist on a security key
    if (!payload.algorithms.includes(-7) || payload.attachment === "cross-platform") return nativeCreate(options);

    const { promise } = ask("create", payload, options.signal);
    return promise.then((res) => {
      if (res.aborted) throw new DOMException("The operation was aborted.", "AbortError");
      if (res.fallback) return nativeCreate(options);
      if (res.error) throw fail(res.error);
      return registrationCredential(res.result);
    });
  };
})();
