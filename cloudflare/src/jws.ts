import { appleRootPem } from "./apple-root";
import { derFromX5c, pemToDer, verifyChain } from "./x509";

export type TransactionClaims = {
  transactionId: string;
  originalTransactionId: string;
  bundleId: string;
  productId: string;
  environment: string;
  ownership?: string;
  productType?: string;
  revoked: boolean;
};

export class VerificationError extends Error {
  constructor(readonly code: string) {
    super(code);
  }
}

export type VerifyOptions = {
  rootPem: string;
  bundleId: string;
  allowXcode: boolean;
};

function decodeBase64Url(value: string): Uint8Array {
  const normalized = value.replace(/-/g, "+").replace(/_/g, "/");
  const padded = normalized + "=".repeat((4 - (normalized.length % 4)) % 4);
  const binary = atob(padded);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i += 1) bytes[i] = binary.charCodeAt(i);
  return bytes;
}

function json<T>(bytes: Uint8Array): T {
  return JSON.parse(new TextDecoder().decode(bytes)) as T;
}

export async function verifyTransaction(jws: string, options: VerifyOptions): Promise<TransactionClaims> {
  const parts = jws.split(".");
  if (parts.length !== 3 || parts.some((part) => part.length === 0)) {
    throw new VerificationError("malformed");
  }
  let header: { alg?: string; x5c?: string[] };
  let payload: Record<string, unknown>;
  try {
    header = json(decodeBase64Url(parts[0]));
    payload = json(decodeBase64Url(parts[1]));
  } catch {
    throw new VerificationError("malformed");
  }
  if (header.alg !== "ES256") throw new VerificationError("malformed");
  const claims = readClaims(payload);
  validateClaims(claims, options.bundleId);
  if (claims.environment === "Xcode") {
    if (!options.allowXcode) throw new VerificationError("xcode_not_allowed");
    return claims;
  }
  if (!header.x5c || header.x5c.length === 0) throw new VerificationError("missing_chain");
  const certificates = header.x5c.map(derFromX5c);
  let leaf: CryptoKey;
  try {
    leaf = await verifyChain(certificates, pemToDer(options.rootPem));
  } catch {
    throw new VerificationError("bad_chain");
  }
  const signingInput = new TextEncoder().encode(`${parts[0]}.${parts[1]}`);
  const signature = decodeBase64Url(parts[2]);
  const ok = await crypto.subtle.verify(
    { name: "ECDSA", hash: "SHA-256" },
    leaf,
    signature,
    signingInput,
  );
  if (!ok) throw new VerificationError("bad_signature");
  return claims;
}

export function defaultRootPem(): string {
  return appleRootPem;
}

function readClaims(payload: Record<string, unknown>): TransactionClaims {
  const transactionId = stringField(payload, "transactionId");
  const bundleId = stringField(payload, "bundleId");
  const productId = stringField(payload, "productId");
  const environment = stringField(payload, "environment");
  if (!transactionId || !bundleId || !productId || !environment) {
    throw new VerificationError("malformed");
  }
  const original = stringField(payload, "originalTransactionId") || transactionId;
  return {
    transactionId,
    originalTransactionId: original,
    bundleId,
    productId,
    environment,
    ownership: stringField(payload, "inAppOwnershipType"),
    productType: stringField(payload, "type"),
    revoked: payload.revocationDate != null,
  };
}

function validateClaims(claims: TransactionClaims, bundleId: string): void {
  if (claims.bundleId !== bundleId) throw new VerificationError("wrong_bundle");
  if (claims.revoked) throw new VerificationError("revoked");
  if (claims.ownership && claims.ownership !== "PURCHASED" && claims.ownership !== "FAMILY_SHARED") {
    throw new VerificationError("not_purchased");
  }
  if (claims.productType && claims.productType !== "Non-Consumable") {
    throw new VerificationError("wrong_type");
  }
  if (!["Production", "Sandbox", "Xcode"].includes(claims.environment)) {
    throw new VerificationError("wrong_environment");
  }
}

function stringField(payload: Record<string, unknown>, key: string): string {
  const value = payload[key];
  return typeof value === "string" ? value : "";
}
