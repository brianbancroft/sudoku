import { describe, expect, it } from "vitest";
import { appleRootPem } from "../src/apple-root";
import { VerificationError, verifyTransaction } from "../src/jws";
import intermediatePem from "./fixtures/inter.pem?raw";
import leafKeyPem from "./fixtures/leaf-key.pkcs8.pem?raw";
import leafPem from "./fixtures/leaf.pem?raw";
import rootPem from "./fixtures/root.pem?raw";

const bundleId = "com.brianbancroft.sudoku";
const productId = "com.brianbancroft.sudoku.pack.starter";

describe("StoreKit JWS", () => {
  it("accepts a chain that reaches the pinned root", async () => {
    const jws = await signedJws({ bundleId, productId, environment: "Sandbox" });
    const claims = await verifyTransaction(jws, { rootPem, bundleId, allowXcode: false });
    expect(claims.productId).toBe(productId);
    expect(claims.environment).toBe("Sandbox");
  });

  it("rejects the fixture chain when the pinned root is Apple's", async () => {
    const jws = await signedJws({ bundleId, productId, environment: "Production" });
    await expect(verifyTransaction(jws, { rootPem: appleRootPem, bundleId, allowXcode: false })).rejects.toMatchObject({
      code: "bad_chain",
    });
  });

  it("rejects a tampered payload", async () => {
    const jws = await signedJws({ bundleId, productId, environment: "Sandbox" });
    const [header, , signature] = jws.split(".");
    const tampered = `${header}.${base64url(JSON.stringify({ bundleId, productId, transactionId: "other", environment: "Sandbox" }))}.${signature}`;
    await expect(verifyTransaction(tampered, { rootPem, bundleId, allowXcode: false })).rejects.toBeInstanceOf(
      VerificationError,
    );
  });

  it("rejects the wrong bundle even when the chain is valid", async () => {
    const jws = await signedJws({ bundleId: "com.example.other", productId, environment: "Sandbox" });
    await expect(verifyTransaction(jws, { rootPem, bundleId, allowXcode: false })).rejects.toMatchObject({
      code: "wrong_bundle",
    });
  });

  it("rejects a revoked transaction", async () => {
    const jws = await signedJws({ bundleId, productId, environment: "Sandbox", revocationDate: 1_700_000_000_000 });
    await expect(verifyTransaction(jws, { rootPem, bundleId, allowXcode: false })).rejects.toMatchObject({
      code: "revoked",
    });
  });

  it("accepts an Xcode transaction only when that mode is on", async () => {
    const jws = xcodeJws();
    await expect(verifyTransaction(jws, { rootPem, bundleId, allowXcode: false })).rejects.toMatchObject({
      code: "xcode_not_allowed",
    });
    const claims = await verifyTransaction(jws, { rootPem, bundleId, allowXcode: true });
    expect(claims.environment).toBe("Xcode");
  });
});

async function signedJws(claims: Record<string, unknown>): Promise<string> {
  const header = {
    alg: "ES256",
    x5c: [pemBody(leafPem), pemBody(intermediatePem)],
  };
  const payload = {
    transactionId: "tx-1",
    originalTransactionId: "tx-1",
    type: "Non-Consumable",
    inAppOwnershipType: "PURCHASED",
    ...claims,
  };
  const encodedHeader = base64url(JSON.stringify(header));
  const encodedPayload = base64url(JSON.stringify(payload));
  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemDer(leafKeyPem),
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    key,
    new TextEncoder().encode(`${encodedHeader}.${encodedPayload}`),
  );
  return `${encodedHeader}.${encodedPayload}.${base64url(signature)}`;
}

function xcodeJws(): string {
  const header = base64url(JSON.stringify({ alg: "ES256" }));
  const payload = base64url(
    JSON.stringify({
      transactionId: "xcode-1",
      originalTransactionId: "xcode-1",
      bundleId,
      productId,
      environment: "Xcode",
      type: "Non-Consumable",
      inAppOwnershipType: "PURCHASED",
    }),
  );
  return `${header}.${payload}.${base64url("xcode")}`;
}

function pemBody(pem: string): string {
  return pem.replace(/-----BEGIN [^-]+-----/g, "").replace(/-----END [^-]+-----/g, "").replace(/\s+/g, "");
}

function pemDer(pem: string): Uint8Array {
  const binary = atob(pemBody(pem));
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i += 1) bytes[i] = binary.charCodeAt(i);
  return bytes;
}

function base64url(value: string | ArrayBuffer): string {
  const bytes = typeof value === "string" ? new TextEncoder().encode(value) : new Uint8Array(value);
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "");
}
