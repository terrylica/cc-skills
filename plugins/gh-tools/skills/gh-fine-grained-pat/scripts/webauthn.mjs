// webauthn.mjs — CDP virtual-authenticator helpers (Chromium-only) so the engine
// can satisfy GitHub passkey challenges with NO biometric at run time.
//
// The virtual authenticator signs WebAuthn challenges itself; we persist the
// resident credential it produces (via getCredentials) into the gated vault blob
// and re-inject it (addCredential) on later runs. CDP does the crypto — we only
// move the credential object around. Enable presence simulation BEFORE the page
// triggers the prompt (race condition, per Chrome DevTools docs).

const VIRTUAL_AUTHENTICATOR_OPTIONS = {
  protocol: "ctap2",
  transport: "internal", // platform authenticator (like Touch ID / a synced passkey)
  hasResidentKey: true,
  hasUserVerification: true,
  isUserVerified: true,
  automaticPresenceSimulation: true,
};

/** Open a CDP session bound to the page and enable the WebAuthn domain. */
export async function openWebAuthn(page) {
  const client = await page.context().newCDPSession(page);
  await client.send("WebAuthn.enable");
  return client;
}

/** Mount a virtual authenticator; returns its authenticatorId. */
export async function mountAuthenticator(client) {
  const { authenticatorId } = await client.send("WebAuthn.addVirtualAuthenticator", {
    options: VIRTUAL_AUTHENTICATOR_OPTIONS,
  });
  return authenticatorId;
}

/** Inject a previously-captured resident credential into the authenticator. */
export async function injectCredential(client, authenticatorId, cred) {
  await client.send("WebAuthn.addCredential", {
    authenticatorId,
    credential: {
      credentialId: cred.credentialId,
      isResidentCredential: true,
      rpId: cred.rpId,
      privateKey: cred.privateKey,
      userHandle: cred.userHandle ?? "",
      signCount: cred.signCount ?? 0,
    },
  });
}

/** Read resident credentials out of the authenticator (post-registration). */
export async function getCredentials(client, authenticatorId) {
  const { credentials } = await client.send("WebAuthn.getCredentials", { authenticatorId });
  return credentials ?? [];
}

/** Normalize a CDP credential into the JSON we persist in the gated blob. */
export function serializeCredential(c) {
  return {
    credentialId: c.credentialId,
    rpId: c.rpId,
    privateKey: c.privateKey,
    userHandle: c.userHandle ?? "",
    signCount: c.signCount ?? 0,
  };
}

export async function removeAuthenticator(client, authenticatorId) {
  try {
    await client.send("WebAuthn.removeVirtualAuthenticator", { authenticatorId });
    await client.send("WebAuthn.disable");
  } catch {
    /* best-effort cleanup */
  }
}

/**
 * Mount + inject a stored passkey so the next assertion on the page succeeds
 * autonomously. Returns the authenticatorId (remove it when done).
 */
export async function armStoredPasskey(page, cred) {
  const client = await openWebAuthn(page);
  const authenticatorId = await mountAuthenticator(client);
  await injectCredential(client, authenticatorId, cred);
  return { client, authenticatorId };
}
