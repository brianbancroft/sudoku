export type Session = { id: string; email: string; csrf: string };

const cookieName = "sudoku_admin";

export function readCookie(request: Request, name: string): string | null {
  const header = request.headers.get("cookie") ?? "";
  for (const part of header.split(";")) {
    const [key, ...rest] = part.trim().split("=");
    if (key === name) return decodeURIComponent(rest.join("="));
  }
  return null;
}

export async function loadSession(db: D1Database, request: Request, secret: string): Promise<Session | null> {
  const token = readCookie(request, cookieName);
  if (!token) return null;
  const id = await unseal(secret, token);
  if (!id) return null;
  const row = await db
    .prepare("SELECT id, email, csrf, expires_at FROM sessions WHERE id = ?")
    .bind(id)
    .first<{ id: string; email: string; csrf: string; expires_at: number }>();
  if (!row || row.expires_at < Math.floor(Date.now() / 1000)) return null;
  return { id: row.id, email: row.email, csrf: row.csrf };
}

export async function createSession(db: D1Database, email: string): Promise<Session> {
  const session = {
    id: bytesToHex(crypto.getRandomValues(new Uint8Array(32))),
    email: email.toLowerCase(),
    csrf: bytesToHex(crypto.getRandomValues(new Uint8Array(32))),
  };
  const expires = Math.floor(Date.now() / 1000) + 60 * 60 * 12;
  await db
    .prepare("INSERT INTO sessions (id, email, csrf, expires_at) VALUES (?, ?, ?, ?)")
    .bind(session.id, session.email, session.csrf, expires)
    .run();
  return session;
}

export async function destroySession(db: D1Database, request: Request, secret: string): Promise<void> {
  const token = readCookie(request, cookieName);
  if (!token) return;
  const id = await unseal(secret, token);
  if (id) await db.prepare("DELETE FROM sessions WHERE id = ?").bind(id).run();
}

export async function seal(secret: string, id: string): Promise<string> {
  return `${id}.${await hmac(secret, id)}`;
}

async function unseal(secret: string, token: string): Promise<string | null> {
  const splitAt = token.lastIndexOf(".");
  if (splitAt <= 0) return null;
  const id = token.slice(0, splitAt);
  const sig = token.slice(splitAt + 1);
  if (!(await csrfMatches(await hmac(secret, id), sig))) return null;
  return id;
}

async function hmac(secret: string, value: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(value));
  const bytes = new Uint8Array(signature);
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "");
}

export function serializeCookie(value: string, maxAge: number, secure: boolean): string {
  const securePart = secure ? "; Secure" : "";
  return `${cookieName}=${encodeURIComponent(value)}; HttpOnly; SameSite=Lax; Path=/; Max-Age=${maxAge}${securePart}`;
}

export async function csrfMatches(expected: string, provided: string): Promise<boolean> {
  const encoder = new TextEncoder();
  const [left, right] = await Promise.all([
    crypto.subtle.digest("SHA-256", encoder.encode(expected)),
    crypto.subtle.digest("SHA-256", encoder.encode(provided)),
  ]);
  const a = new Uint8Array(left);
  const b = new Uint8Array(right);
  let diff = a.length ^ b.length;
  for (let i = 0; i < a.length; i += 1) diff |= a[i] ^ b[i];
  return diff === 0 && expected.length === provided.length;
}

function bytesToHex(bytes: Uint8Array): string {
  return [...bytes].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}
