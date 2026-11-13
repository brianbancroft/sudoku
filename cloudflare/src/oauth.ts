import { pemToDer } from "./x509";

type IdClaims = { email: string; emailVerified: boolean; nonce?: string; aud?: string; iss?: string };

export async function verifyIdToken(
  token: string,
  options: { issuer: string | string[]; audience: string; nonce: string; jwksUrl: string },
): Promise<IdClaims> {
  const parts = token.split(".");
  if (parts.length !== 3) throw new Error("malformed id token");
  const header = JSON.parse(new TextDecoder().decode(b64url(parts[0]))) as { kid?: string; alg?: string };
  const payload = JSON.parse(new TextDecoder().decode(b64url(parts[1]))) as Record<string, unknown>;
  if (!header.kid) throw new Error("missing kid");
  const jwks = (await (await fetch(options.jwksUrl)).json()) as { keys: Array<JsonWebKey & { kid?: string }> };
  const jwk = jwks.keys.find((key) => key.kid === header.kid);
  if (!jwk) throw new Error("unknown signing key");
  const algorithm =
    header.alg === "RS256"
      ? { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }
      : { name: "ECDSA", namedCurve: "P-256" };
  const key = await crypto.subtle.importKey("jwk", jwk, algorithm, false, ["verify"]);
  const ok = await crypto.subtle.verify(
    header.alg === "RS256" ? { name: "RSASSA-PKCS1-v1_5" } : { name: "ECDSA", hash: "SHA-256" },
    key,
    b64url(parts[2]),
    new TextEncoder().encode(`${parts[0]}.${parts[1]}`),
  );
  if (!ok) throw new Error("bad id token signature");
  const aud = payload.aud;
  const audience = Array.isArray(aud) ? aud : [aud];
  if (!audience.includes(options.audience)) throw new Error("bad audience");
  const issuers = Array.isArray(options.issuer) ? options.issuer : [options.issuer];
  if (!issuers.includes(String(payload.iss))) throw new Error("bad issuer");
  if (payload.nonce !== options.nonce) throw new Error("bad nonce");
  const exp = typeof payload.exp === "number" ? payload.exp : 0;
  if (exp < Math.floor(Date.now() / 1000)) throw new Error("expired id token");
  const email = typeof payload.email === "string" ? payload.email.toLowerCase() : "";
  const verified = payload.email_verified === true || payload.email_verified === "true";
  if (!email || !verified) throw new Error("unverified email");
  return { email, emailVerified: verified };
}

export async function appleClientSecret(env: Env): Promise<string> {
  const header = { alg: "ES256", kid: env.APPLE_KEY_ID };
  const now = Math.floor(Date.now() / 1000);
  const payload = {
    iss: env.APPLE_TEAM_ID,
    iat: now,
    exp: now + 60 * 10,
    aud: "https://appleid.apple.com",
    sub: env.APPLE_SERVICES_ID,
  };
  const encodedHeader = b64urlEncode(JSON.stringify(header));
  const encodedPayload = b64urlEncode(JSON.stringify(payload));
  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToDer(env.APPLE_PRIVATE_KEY.replace(/\\n/g, "\n")),
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    key,
    new TextEncoder().encode(`${encodedHeader}.${encodedPayload}`),
  );
  return `${encodedHeader}.${encodedPayload}.${b64urlEncode(signature)}`;
}

function b64url(value: string): Uint8Array {
  const normalized = value.replace(/-/g, "+").replace(/_/g, "/");
  const padded = normalized + "=".repeat((4 - (normalized.length % 4)) % 4);
  const binary = atob(padded);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i += 1) bytes[i] = binary.charCodeAt(i);
  return bytes;
}

function b64urlEncode(value: string | ArrayBuffer): string {
  const bytes = typeof value === "string" ? new TextEncoder().encode(value) : new Uint8Array(value);
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "");
}
