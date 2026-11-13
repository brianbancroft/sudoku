import { env, SELF } from "cloudflare:test";
import { beforeAll, describe, expect, it } from "vitest";
import { createSession, seal } from "../src/session";

const productId = "com.brianbancroft.sudoku.pack.starter";

describe("catalog and delivery", () => {
  beforeAll(async () => {
    const existing = await env.DB.prepare("SELECT id FROM packs WHERE id = ?").bind("quiet-start").first();
    if (existing) return;
    const now = new Date().toISOString();
    await env.DB.prepare(
      "INSERT INTO packs (id, name, summary, difficulty_mix, product_id, available, created_at, updated_at) VALUES (?, ?, ?, ?, ?, 1, ?, ?)",
    )
      .bind("quiet-start", "Quiet Start", "Six calm puzzles.", "4 easy · 2 medium", productId, now, now)
      .run();
    await env.DB.prepare(
      "INSERT INTO puzzles (id, pack_id, title, givens, solution, difficulty, sort_order) VALUES (?, ?, ?, ?, ?, ?, ?)",
    )
      .bind("quiet-start-1", "quiet-start", "Puzzle 1", "[1,2,3]", "[1,2,3]", "easy", 1)
      .run();
  });

  it("lists available packs", async () => {
    const response = await SELF.fetch("https://sudoku-packs.example.workers.dev/catalog");
    expect(response.status).toBe(200);
    const body = (await response.json()) as { packs: Array<{ id: string; productID: string }> };
    const quiet = body.packs.find((pack) => pack.id === "quiet-start");
    expect(quiet?.productID).toBe(productId);
  });

  it("records an Xcode purchase and returns the pack", async () => {
    const response = await SELF.fetch("https://sudoku-packs.example.workers.dev/packs/download", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        deviceID: "phone-a",
        packID: "quiet-start",
        signedTransaction: xcodeJws(),
      }),
    });
    expect(response.status).toBe(200);
    const body = (await response.json()) as { packID: string; puzzles: unknown[] };
    expect(body.packID).toBe("quiet-start");
    expect(body.puzzles.length).toBeGreaterThan(0);
    const again = await SELF.fetch("https://sudoku-packs.example.workers.dev/entitlements", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ deviceID: "phone-b", signedTransactions: [xcodeJws()] }),
    });
    const owned = (await again.json()) as { productIDs: string[]; packIDs: string[] };
    expect(owned.productIDs).toEqual([productId]);
    expect(owned.packIDs).toEqual(["quiet-start"]);
  });

  it("rejects a download for a different product", async () => {
    const response = await SELF.fetch("https://sudoku-packs.example.workers.dev/packs/download", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        deviceID: "phone-a",
        packID: "quiet-start",
        signedTransaction: xcodeJws("com.brianbancroft.sudoku.pack.hard"),
      }),
    });
    expect(response.status).toBe(403);
  });
});

describe("admin auth", () => {
  it("rejects an unsigned admin page", async () => {
    const response = await SELF.fetch("https://sudoku-packs.example.workers.dev/admin");
    expect(response.status).toBe(401);
  });

  it("rejects an unsigned pack change", async () => {
    const response = await SELF.fetch("https://sudoku-packs.example.workers.dev/admin/packs", {
      method: "POST",
      headers: { "content-type": "application/x-www-form-urlencoded" },
      body: "name=Nope",
    });
    expect(response.status).toBe(401);
  });

  it("opens the admin list for an allowlisted session and rejects a bad form token", async () => {
    const session = await createSession(env.DB, "admin@example.com");
    const cookie = await seal(env.SESSION_SECRET, session.id);
    const page = await SELF.fetch("https://sudoku-packs.example.workers.dev/admin", {
      headers: { cookie: `sudoku_admin=${cookie}` },
    });
    expect(page.status).toBe(200);
    expect(await page.text()).toContain("Packs");
    const rejected = await SELF.fetch("https://sudoku-packs.example.workers.dev/admin/packs", {
      method: "POST",
      headers: { cookie: `sudoku_admin=${cookie}`, origin: "https://sudoku-packs.example.workers.dev" },
      body: new URLSearchParams({ csrf: "nope", id: "x", name: "X", summary: "S", difficulty_mix: "easy", product_id: "p" }),
    });
    expect(rejected.status).toBe(403);
  });
});

function xcodeJws(product = productId): string {
  const header = base64url(JSON.stringify({ alg: "ES256" }));
  const payload = base64url(
    JSON.stringify({
      transactionId: "xcode-1",
      originalTransactionId: "xcode-1",
      bundleId: "com.brianbancroft.sudoku",
      productId: product,
      environment: "Xcode",
      type: "Non-Consumable",
      inAppOwnershipType: "PURCHASED",
    }),
  );
  return `${header}.${payload}.${base64url("xcode")}`;
}

function base64url(value: string): string {
  return btoa(value).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "");
}
