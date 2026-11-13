import { defaultRootPem, VerificationError, verifyTransaction, type TransactionClaims } from "./jws";
import { csrfField, escapeHtml as escapeText, page } from "./html";
import { appleClientSecret, verifyIdToken } from "./oauth";
import { createSession, csrfMatches, destroySession, loadSession, seal, serializeCookie, type Session } from "./session";
import { gridsMatch, parseGrid } from "./sudoku";

function json(body: unknown, status = 200, headers: HeadersInit = {}): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json; charset=utf-8", ...headers },
  });
}

function html(body: string, status = 200, headers: HeadersInit = {}): Response {
  return new Response(body, {
    status,
    headers: { "content-type": "text/html; charset=utf-8", ...headers },
  });
}

function allowlist(raw: string): Set<string> {
  return new Set(
    raw
      .split(",")
      .map((email) => email.trim().toLowerCase())
      .filter(Boolean),
  );
}

function secureRequest(request: Request): boolean {
  return new URL(request.url).protocol === "https:";
}

export default {
  async fetch(request, env): Promise<Response> {
    const url = new URL(request.url);
    try {
      return await route(request, env, url);
    } catch (error) {
      console.log(JSON.stringify({ level: "error", message: error instanceof Error ? error.message : "error" }));
      return json({ error: "server_error" }, 500);
    }
  },
} satisfies ExportedHandler<Env>;

async function route(request: Request, env: Env, url: URL): Promise<Response> {
  const path = url.pathname;
  if (request.method === "GET" && path === "/health") {
    return json({
      ok: true,
      mode: String(env.ALLOW_XCODE_JWS) === "true" ? "dev" : "apple",
      bundleID: env.BUNDLE_ID,
    });
  }
  if (request.method === "GET" && path === "/catalog") return catalog(env);
  if (request.method === "POST" && path === "/entitlements") return entitlements(request, env);
  if (request.method === "POST" && path === "/packs/download") return download(request, env);
  if (path === "/admin/login" && request.method === "GET") return loginPage(env);
  if (path === "/admin/oauth/google" && request.method === "GET") return startOAuth(env, "google");
  if (path === "/admin/oauth/google/callback" && request.method === "GET") return googleCallback(env, request, url);
  if (path === "/admin/oauth/apple" && request.method === "GET") return startOAuth(env, "apple");
  if (path === "/admin/oauth/apple/callback" && request.method === "POST") return appleCallback(env, request);
  if (path.startsWith("/admin")) return admin(request, env, path);
  return json({ error: "not_found" }, 404);
}

async function catalog(env: Env): Promise<Response> {
  const rows = await env.DB.prepare(
    `SELECT p.id, p.name, p.summary, p.difficulty_mix, p.product_id,
            (SELECT COUNT(*) FROM puzzles z WHERE z.pack_id = p.id) AS puzzle_count
     FROM packs p WHERE p.available = 1 ORDER BY p.name`,
  ).all<{ id: string; name: string; summary: string; difficulty_mix: string; product_id: string; puzzle_count: number }>();
  return json({
    packs: rows.results.map((row) => ({
      id: row.id,
      name: row.name,
      summary: row.summary,
      difficultyMix: row.difficulty_mix,
      puzzleCount: row.puzzle_count,
      productID: row.product_id,
    })),
  });
}

async function entitlements(request: Request, env: Env): Promise<Response> {
  const body = (await request.json().catch(() => null)) as { deviceID?: string; signedTransactions?: string[] } | null;
  if (!body || !Array.isArray(body.signedTransactions)) return json({ error: "malformed_body" }, 400);
  const deviceID = body.deviceID ?? "";
  if (body.signedTransactions.length === 0) {
    return json({ productIDs: [], packIDs: [] });
  }
  const grantedProducts = new Set<string>();
  for (const token of body.signedTransactions) {
    try {
      const claims = await checkTransaction(env, token);
      await record(env, claims, deviceID);
      grantedProducts.add(claims.productId);
    } catch (error) {
      if (body.signedTransactions.length === 1) return verificationResponse(error);
    }
  }
  if (grantedProducts.size === 0) return json({ error: "not_entitled" }, 403);
  const productIDs = [...grantedProducts].sort();
  const packs = await env.DB.prepare(
    `SELECT id FROM packs WHERE product_id IN (${productIDs.map(() => "?").join(",")}) ORDER BY id`,
  )
    .bind(...productIDs)
    .all<{ id: string }>();
  return json({ productIDs, packIDs: packs.results.map((row) => row.id) });
}

async function download(request: Request, env: Env): Promise<Response> {
  const body = (await request.json().catch(() => null)) as
    | { deviceID?: string; packID?: string; signedTransaction?: string }
    | null;
  if (!body?.packID || !body.signedTransaction) return json({ error: "malformed_body" }, 400);
  const pack = await env.DB.prepare("SELECT id, product_id FROM packs WHERE id = ?")
    .bind(body.packID)
    .first<{ id: string; product_id: string }>();
  if (!pack) return json({ error: "unknown_pack" }, 404);
  let claims: TransactionClaims;
  try {
    claims = await checkTransaction(env, body.signedTransaction);
  } catch (error) {
    return verificationResponse(error);
  }
  if (claims.productId !== pack.product_id) return json({ error: "wrong_product" }, 403);
  await record(env, claims, body.deviceID ?? "");
  const puzzles = await env.DB.prepare(
    "SELECT id, title, givens, solution, difficulty FROM puzzles WHERE pack_id = ? ORDER BY sort_order",
  )
    .bind(pack.id)
    .all<{ id: string; title: string; givens: string; solution: string; difficulty: string }>();
  return json({
    packID: pack.id,
    puzzles: puzzles.results.map((row) => ({
      id: row.id,
      title: row.title,
      givens: JSON.parse(row.givens),
      solution: JSON.parse(row.solution),
      difficulty: row.difficulty,
    })),
  });
}

async function checkTransaction(env: Env, jws: string): Promise<TransactionClaims> {
  return verifyTransaction(jws, {
    rootPem: defaultRootPem(),
    bundleId: env.BUNDLE_ID,
    allowXcode: String(env.ALLOW_XCODE_JWS) === "true",
  });
}

async function record(env: Env, claims: TransactionClaims, deviceID: string): Promise<void> {
  const known = await env.DB.prepare("SELECT id FROM packs WHERE product_id = ?").bind(claims.productId).first();
  if (!known) throw new VerificationError("unknown_product");
  const existing = await env.DB.prepare("SELECT device_ids FROM entitlements WHERE original_transaction_id = ?")
    .bind(claims.originalTransactionId)
    .first<{ device_ids: string }>();
  const devices = new Set<string>(existing ? (JSON.parse(existing.device_ids) as string[]) : []);
  if (deviceID.trim()) devices.add(deviceID.trim());
  const now = new Date().toISOString();
  await env.DB.prepare(
    `INSERT INTO entitlements
      (original_transaction_id, transaction_id, product_id, bundle_id, environment, device_ids, created_at, updated_at)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?)
     ON CONFLICT(original_transaction_id) DO UPDATE SET
      transaction_id = excluded.transaction_id,
      device_ids = excluded.device_ids,
      updated_at = excluded.updated_at`,
  )
    .bind(
      claims.originalTransactionId,
      claims.transactionId,
      claims.productId,
      claims.bundleId,
      claims.environment,
      JSON.stringify([...devices]),
      now,
      now,
    )
    .run();
  console.log(JSON.stringify({ event: "entitlement.recorded", productId: claims.productId, environment: claims.environment }));
}

function verificationResponse(error: unknown): Response {
  const code = error instanceof VerificationError ? error.code : "malformed";
  const status = code === "malformed" ? 400 : 403;
  return json({ error: code }, status);
}

function loginPage(env: Env): Response {
  const google = env.GOOGLE_CLIENT_ID && env.GOOGLE_CLIENT_SECRET;
  const apple = env.APPLE_SERVICES_ID && env.APPLE_TEAM_ID && env.APPLE_KEY_ID && env.APPLE_PRIVATE_KEY;
  const buttons = [
    google ? `<p><a class="button" href="/admin/oauth/google">Sign in with Google</a></p>` : "",
    apple ? `<p><a class="button" href="/admin/oauth/apple">Sign in with Apple</a></p>` : "",
  ].join("");
  const notice = buttons
    ? ""
    : "<p>OAuth is not configured yet. Add the Google or Apple secrets, then reload.</p>";
  return html(page("Sign in", `<h1>Sudoku packs</h1>${notice}${buttons}`));
}

async function startOAuth(env: Env, provider: "google" | "apple"): Promise<Response> {
  const state = crypto.randomUUID();
  const nonce = crypto.randomUUID();
  const expires = Math.floor(Date.now() / 1000) + 600;
  await env.DB.prepare("INSERT INTO oauth_states (state, nonce, provider, expires_at) VALUES (?, ?, ?, ?)")
    .bind(state, nonce, provider, expires)
    .run();
  const redirectUri = `${env.PUBLIC_BASE_URL.replace(/\/$/, "")}/admin/oauth/${provider}/callback`;
  if (provider === "google") {
    const auth = new URL("https://accounts.google.com/o/oauth2/v2/auth");
    auth.searchParams.set("client_id", env.GOOGLE_CLIENT_ID);
    auth.searchParams.set("redirect_uri", redirectUri);
    auth.searchParams.set("response_type", "code");
    auth.searchParams.set("scope", "openid email");
    auth.searchParams.set("state", state);
    auth.searchParams.set("nonce", nonce);
    return Response.redirect(auth.toString(), 302);
  }
  const auth = new URL("https://appleid.apple.com/auth/authorize");
  auth.searchParams.set("client_id", env.APPLE_SERVICES_ID);
  auth.searchParams.set("redirect_uri", redirectUri);
  auth.searchParams.set("response_type", "code");
  auth.searchParams.set("response_mode", "form_post");
  auth.searchParams.set("scope", "email");
  auth.searchParams.set("state", state);
  auth.searchParams.set("nonce", nonce);
  return Response.redirect(auth.toString(), 302);
}

async function googleCallback(env: Env, request: Request, url: URL): Promise<Response> {
  const code = url.searchParams.get("code") ?? "";
  const state = url.searchParams.get("state") ?? "";
  const nonce = await takeNonce(env, state, "google");
  if (!nonce || !code) return html(page("Sign in", "<p>The sign-in attempt expired. Try again.</p>"), 400);
  const redirectUri = `${env.PUBLIC_BASE_URL.replace(/\/$/, "")}/admin/oauth/google/callback`;
  const tokenResponse = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      code,
      client_id: env.GOOGLE_CLIENT_ID,
      client_secret: env.GOOGLE_CLIENT_SECRET,
      redirect_uri: redirectUri,
      grant_type: "authorization_code",
    }),
  });
  const token = (await tokenResponse.json()) as { id_token?: string };
  if (!token.id_token) return html(page("Sign in", "<p>Google did not return an identity.</p>"), 400);
  const identity = await verifyIdToken(token.id_token, {
    issuer: ["https://accounts.google.com", "accounts.google.com"],
    audience: env.GOOGLE_CLIENT_ID,
    nonce,
    jwksUrl: "https://www.googleapis.com/oauth2/v3/certs",
  });
  return finishLogin(env, request, identity.email);
}

async function appleCallback(env: Env, request: Request): Promise<Response> {
  const form = await request.formData();
  const code = String(form.get("code") ?? "");
  const state = String(form.get("state") ?? "");
  const nonce = await takeNonce(env, state, "apple");
  if (!nonce || !code) return html(page("Sign in", "<p>The sign-in attempt expired. Try again.</p>"), 400);
  const redirectUri = `${env.PUBLIC_BASE_URL.replace(/\/$/, "")}/admin/oauth/apple/callback`;
  const tokenResponse = await fetch("https://appleid.apple.com/auth/token", {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      code,
      client_id: env.APPLE_SERVICES_ID,
      client_secret: await appleClientSecret(env),
      redirect_uri: redirectUri,
      grant_type: "authorization_code",
    }),
  });
  const token = (await tokenResponse.json()) as { id_token?: string };
  if (!token.id_token) return html(page("Sign in", "<p>Apple did not return an identity.</p>"), 400);
  const identity = await verifyIdToken(token.id_token, {
    issuer: "https://appleid.apple.com",
    audience: env.APPLE_SERVICES_ID,
    nonce,
    jwksUrl: "https://appleid.apple.com/auth/keys",
  });
  return finishLogin(env, request, identity.email);
}

async function takeNonce(env: Env, state: string, provider: string): Promise<string | null> {
  const row = await env.DB.prepare("SELECT nonce, provider, expires_at FROM oauth_states WHERE state = ?")
    .bind(state)
    .first<{ nonce: string; provider: string; expires_at: number }>();
  await env.DB.prepare("DELETE FROM oauth_states WHERE state = ?").bind(state).run();
  if (!row || row.provider !== provider || row.expires_at < Math.floor(Date.now() / 1000)) return null;
  return row.nonce;
}

async function finishLogin(env: Env, request: Request, email: string): Promise<Response> {
  if (!allowlist(env.ADMIN_EMAILS).has(email.toLowerCase())) {
    return html(page("Sign in", "<p>That account is not on the admin list.</p>"), 403);
  }
  const now = new Date().toISOString();
  await env.DB.prepare(
    "INSERT INTO admin_users (email, last_login_at) VALUES (?, ?) ON CONFLICT(email) DO UPDATE SET last_login_at = excluded.last_login_at",
  )
    .bind(email, now)
    .run();
  const session = await createSession(env.DB, email);
  return new Response(null, {
    status: 302,
    headers: {
      location: "/admin",
      "set-cookie": serializeCookie(await seal(env.SESSION_SECRET, session.id), 60 * 60 * 12, secureRequest(request)),
    },
  });
}

async function admin(request: Request, env: Env, path: string): Promise<Response> {
  const session = await loadSession(env.DB, request, env.SESSION_SECRET);
  if (!session || !allowlist(env.ADMIN_EMAILS).has(session.email)) {
    return html(page("Sign in", `<p>Sign in required.</p><p><a href="/admin/login">Sign in</a></p>`), 401);
  }
  if (request.method === "POST") {
    const origin = request.headers.get("origin");
    if (origin && origin !== new URL(request.url).origin) return json({ error: "bad_origin" }, 403);
    const form = await request.formData();
    if (!(await csrfMatches(session.csrf, String(form.get("csrf") ?? "")))) {
      return html(page("Rejected", "<p>The form token did not match. Reload and try again.</p>"), 403);
    }
    return adminPost(env, request, path, form, session);
  }
  return adminGet(env, path, session);
}

async function adminGet(env: Env, path: string, session: Session): Promise<Response> {
  if (path === "/admin") return html(page("Packs", await packsPage(env, session)));
  if (path === "/admin/entitlements") return html(page("Purchases", await entitlementsPage(env, session)));
  if (path === "/admin/packs/new") return html(page("New pack", packForm(session, null)));
  const packEdit = path.match(/^\/admin\/packs\/([^/]+)$/);
  if (packEdit) return html(page("Edit pack", await packPage(env, session, decodeURIComponent(packEdit[1]))));
  const puzzleNew = path.match(/^\/admin\/packs\/([^/]+)\/puzzles\/new$/);
  if (puzzleNew) return html(page("New puzzle", puzzleForm(session, decodeURIComponent(puzzleNew[1]), null)));
  const puzzleEdit = path.match(/^\/admin\/puzzles\/([^/]+)$/);
  if (puzzleEdit) {
    const puzzle = await env.DB.prepare("SELECT * FROM puzzles WHERE id = ?")
      .bind(decodeURIComponent(puzzleEdit[1]))
      .first<PuzzleRow>();
    if (!puzzle) return html(page("Missing", "<p>That puzzle is gone.</p>"), 404);
    return html(page("Edit puzzle", puzzleForm(session, puzzle.pack_id, puzzle)));
  }
  return html(page("Missing", "<p>Not found.</p>"), 404);
}

async function adminPost(
  env: Env,
  request: Request,
  path: string,
  form: FormData,
  session: Session,
): Promise<Response> {
  if (path === "/admin/logout") {
    await destroySession(env.DB, request, env.SESSION_SECRET);
    return new Response(null, {
      status: 302,
      headers: { location: "/admin/login", "set-cookie": serializeCookie("", 0, secureRequest(request)) },
    });
  }
  if (path === "/admin/packs") return savePack(env, form, null);
  const packSave = path.match(/^\/admin\/packs\/([^/]+)$/);
  if (packSave) return savePack(env, form, decodeURIComponent(packSave[1]));
  const availability = path.match(/^\/admin\/packs\/([^/]+)\/availability$/);
  if (availability) return togglePack(env, form, decodeURIComponent(availability[1]));
  const puzzleCreate = path.match(/^\/admin\/packs\/([^/]+)\/puzzles$/);
  if (puzzleCreate) return savePuzzle(env, form, decodeURIComponent(puzzleCreate[1]), null);
  const puzzleSave = path.match(/^\/admin\/puzzles\/([^/]+)$/);
  if (puzzleSave) {
    const puzzle = await env.DB.prepare("SELECT pack_id FROM puzzles WHERE id = ?")
      .bind(decodeURIComponent(puzzleSave[1]))
      .first<{ pack_id: string }>();
    if (!puzzle) return html(page("Missing", "<p>That puzzle is gone.</p>"), 404);
    return savePuzzle(env, form, puzzle.pack_id, decodeURIComponent(puzzleSave[1]));
  }
  return html(page("Missing", "<p>Not found.</p>"), 404);
}

type PackRow = {
  id: string;
  name: string;
  summary: string;
  difficulty_mix: string;
  product_id: string;
  available: number;
};

type PuzzleRow = {
  id: string;
  pack_id: string;
  title: string;
  givens: string;
  solution: string;
  difficulty: string;
  sort_order: number;
};

async function packsPage(env: Env, session: Session): Promise<string> {
  const packs = await env.DB.prepare("SELECT id, name, product_id, available FROM packs ORDER BY name").all<PackRow>();
  const rows = packs.results
    .map(
      (pack) =>
        `<tr><td><a href="/admin/packs/${escapeAttr(pack.id)}">${escapeHtml(pack.name)}</a></td><td>${escapeHtml(pack.product_id)}</td><td>${pack.available ? "Listed" : "Hidden"}</td></tr>`,
    )
    .join("");
  return `<div class="row"><h1>Packs</h1><form method="post" action="/admin/logout">${csrfField(session.csrf)}<button>Sign out</button></form></div>
  <p><a href="/admin/packs/new">New pack</a> · <a href="/admin/entitlements">Purchases</a></p>
  <table><tr><th>Name</th><th>Product</th><th>Catalog</th></tr>${rows}</table>`;
}

async function entitlementsPage(env: Env, session: Session): Promise<string> {
  const rows = await env.DB.prepare(
    "SELECT original_transaction_id, product_id, environment, device_ids, updated_at FROM entitlements ORDER BY updated_at DESC",
  ).all<{ original_transaction_id: string; product_id: string; environment: string; device_ids: string; updated_at: string }>();
  const body = rows.results
    .map(
      (row) =>
        `<tr><td>${escapeHtml(row.product_id)}</td><td>${escapeHtml(row.environment)}</td><td>${escapeHtml(row.device_ids)}</td><td>${escapeHtml(row.updated_at)}</td></tr>`,
    )
    .join("");
  return `<p><a href="/admin">Packs</a></p><h1>Purchases</h1><p>Signed in as ${escapeHtml(session.email)}.</p>
    <table><tr><th>Product</th><th>Environment</th><th>Devices</th><th>Updated</th></tr>${body}</table>`;
}

function packForm(session: Session, pack: PackRow | null): string {
  const action = pack ? `/admin/packs/${escapeAttr(pack.id)}` : "/admin/packs";
  return `<p><a href="/admin">Packs</a></p><h1>${pack ? "Edit pack" : "New pack"}</h1>
  <form method="post" action="${action}">
    ${csrfField(session.csrf)}
    ${pack ? "" : `<label>Id</label><input name="id" required pattern="[a-z0-9-]+" />`}
    <label>Name</label><input name="name" required value="${escapeAttr(pack?.name ?? "")}" />
    <label>Summary</label><textarea name="summary" required rows="3">${escapeHtml(pack?.summary ?? "")}</textarea>
    <label>Difficulty mix</label><input name="difficulty_mix" required value="${escapeAttr(pack?.difficulty_mix ?? "")}" />
    <label>StoreKit product id</label><input name="product_id" required value="${escapeAttr(pack?.product_id ?? "")}" />
    <p><button>${pack ? "Save" : "Create"}</button></p>
  </form>`;
}

async function packPage(env: Env, session: Session, id: string): Promise<string> {
  const pack = await env.DB.prepare("SELECT * FROM packs WHERE id = ?").bind(id).first<PackRow>();
  if (!pack) return "<p>That pack is gone.</p>";
  const puzzles = await env.DB.prepare("SELECT id, title, difficulty, sort_order FROM puzzles WHERE pack_id = ? ORDER BY sort_order")
    .bind(id)
    .all<{ id: string; title: string; difficulty: string; sort_order: number }>();
  const list = puzzles.results
    .map(
      (puzzle) =>
        `<li><a href="/admin/puzzles/${escapeAttr(puzzle.id)}">${escapeHtml(puzzle.title)}</a> · ${escapeHtml(puzzle.difficulty)}</li>`,
    )
    .join("");
  return `${packForm(session, pack)}
    <form method="post" action="/admin/packs/${escapeAttr(id)}/availability">
      ${csrfField(session.csrf)}
      <input type="hidden" name="available" value="${pack.available ? "0" : "1"}" />
      <button>${pack.available ? "Hide from the catalog" : "List in the catalog"}</button>
    </form>
    <h2>Puzzles</h2><p><a href="/admin/packs/${escapeAttr(id)}/puzzles/new">Add a puzzle</a></p><ul>${list}</ul>`;
}

function puzzleForm(session: Session, packId: string, puzzle: PuzzleRow | null): string {
  const action = puzzle ? `/admin/puzzles/${escapeAttr(puzzle.id)}` : `/admin/packs/${escapeAttr(packId)}/puzzles`;
  return `<p><a href="/admin/packs/${escapeAttr(packId)}">Back to pack</a></p><h1>${puzzle ? "Edit puzzle" : "New puzzle"}</h1>
  <form method="post" action="${action}">
    ${csrfField(session.csrf)}
    <label>Title</label><input name="title" required value="${escapeAttr(puzzle?.title ?? "")}" />
    <label>Difficulty</label>
    <select name="difficulty">
      ${["easy", "medium", "hard", "expert"].map((level) => `<option ${puzzle?.difficulty === level ? "selected" : ""}>${level}</option>`).join("")}
    </select>
    <label>Givens, 81 numbers, 0 for empty</label><textarea name="givens" required rows="4">${escapeHtml(puzzle?.givens ?? "")}</textarea>
    <label>Solution, 81 numbers</label><textarea name="solution" required rows="4">${escapeHtml(puzzle?.solution ?? "")}</textarea>
    <p><button>Save puzzle</button></p>
  </form>`;
}

async function savePack(env: Env, form: FormData, existingId: string | null): Promise<Response> {
  const id = existingId ?? String(form.get("id") ?? "");
  const name = String(form.get("name") ?? "").trim();
  const summary = String(form.get("summary") ?? "").trim();
  const mix = String(form.get("difficulty_mix") ?? "").trim();
  const productId = String(form.get("product_id") ?? "").trim();
  if (!/^[a-z0-9-]+$/.test(id) || !name || !summary || !mix || !productId) {
    return html(page("Pack", "<p>Check the id, name, summary, mix, and product id.</p>"), 400);
  }
  const now = new Date().toISOString();
  if (existingId) {
    await env.DB.prepare(
      "UPDATE packs SET name = ?, summary = ?, difficulty_mix = ?, product_id = ?, updated_at = ? WHERE id = ?",
    )
      .bind(name, summary, mix, productId, now, id)
      .run();
  } else {
    await env.DB.prepare(
      "INSERT INTO packs (id, name, summary, difficulty_mix, product_id, available, created_at, updated_at) VALUES (?, ?, ?, ?, ?, 1, ?, ?)",
    )
      .bind(id, name, summary, mix, productId, now, now)
      .run();
  }
  return redirectTo(env, `/admin/packs/${id}`);
}

async function togglePack(env: Env, form: FormData, id: string): Promise<Response> {
  const available = String(form.get("available") ?? "") === "1" ? 1 : 0;
  await env.DB.prepare("UPDATE packs SET available = ?, updated_at = ? WHERE id = ?")
    .bind(available, new Date().toISOString(), id)
    .run();
  return redirectTo(env, `/admin/packs/${id}`);
}

async function savePuzzle(env: Env, form: FormData, packId: string, existingId: string | null): Promise<Response> {
  const title = String(form.get("title") ?? "").trim();
  const difficulty = String(form.get("difficulty") ?? "");
  const givens = parseGrid(String(form.get("givens") ?? ""));
  const solution = parseGrid(String(form.get("solution") ?? ""));
  if (!title || !["easy", "medium", "hard", "expert"].includes(difficulty) || !givens || !solution || !gridsMatch(givens, solution)) {
    return html(page("Puzzle", "<p>The grids need 81 digits, and the givens must have exactly one solution, matching the solution you entered.</p>"), 400);
  }
  const givensJson = JSON.stringify(givens);
  const solutionJson = JSON.stringify(solution);
  if (existingId) {
    await env.DB.prepare("UPDATE puzzles SET title = ?, givens = ?, solution = ?, difficulty = ? WHERE id = ?")
      .bind(title, givensJson, solutionJson, difficulty, existingId)
      .run();
  } else {
    const id = crypto.randomUUID();
    const order = await env.DB.prepare("SELECT COALESCE(MAX(sort_order), 0) + 1 AS next FROM puzzles WHERE pack_id = ?")
      .bind(packId)
      .first<{ next: number }>();
    await env.DB.prepare(
      "INSERT INTO puzzles (id, pack_id, title, givens, solution, difficulty, sort_order) VALUES (?, ?, ?, ?, ?, ?, ?)",
    )
      .bind(id, packId, title, givensJson, solutionJson, difficulty, order?.next ?? 1)
      .run();
  }
  return redirectTo(env, `/admin/packs/${packId}`);
}

function redirectTo(env: Env, path: string): Response {
  return Response.redirect(`${env.PUBLIC_BASE_URL.replace(/\/$/, "")}${path}`, 302);
}

function escapeHtml(value: string): string {
  return escapeText(value);
}

function escapeAttr(value: string): string {
  return escapeText(value);
}
