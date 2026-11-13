type Node = { tag: number; start: number; valueStart: number; end: number };

function readNode(buf: Uint8Array, offset: number): Node {
  const tag = buf[offset] ?? 0;
  let index = offset + 1;
  let length = buf[index] ?? 0;
  index += 1;
  if (length & 0x80) {
    const count = length & 0x7f;
    length = 0;
    for (let i = 0; i < count; i += 1) {
      length = (length << 8) | (buf[index] ?? 0);
      index += 1;
    }
  }
  return { tag, start: offset, valueStart: index, end: index + length };
}

function children(buf: Uint8Array, node: Node): Node[] {
  const nodes: Node[] = [];
  let index = node.valueStart;
  while (index < node.end) {
    const child = readNode(buf, index);
    nodes.push(child);
    index = child.end;
  }
  return nodes;
}

function bytes(buf: Uint8Array, node: Node): Uint8Array {
  return buf.subarray(node.start, node.end);
}

function value(buf: Uint8Array, node: Node): Uint8Array {
  return buf.subarray(node.valueStart, node.end);
}

function integerBytes(buf: Uint8Array, node: Node): Uint8Array {
  let raw = value(buf, node);
  if (raw[0] === 0x00) raw = raw.subarray(1);
  return raw;
}

function derSignatureToRaw(signature: Uint8Array): Uint8Array {
  const sequence = readNode(signature, 0);
  const parts = children(signature, sequence);
  if (parts.length < 2) throw new Error("bad ecdsa signature");
  const raw = new Uint8Array(64);
  const r = integerBytes(signature, parts[0]);
  const s = integerBytes(signature, parts[1]);
  raw.set(r.subarray(Math.max(0, r.length - 32)), 32 - Math.min(32, r.length));
  raw.set(s.subarray(Math.max(0, s.length - 32)), 64 - Math.min(32, s.length));
  return raw;
}

export type ParsedCertificate = {
  der: Uint8Array;
  tbs: Uint8Array;
  spki: Uint8Array;
  signature: Uint8Array;
};

export function parseCertificate(der: Uint8Array): ParsedCertificate {
  const root = readNode(der, 0);
  const parts = children(der, root);
  if (parts.length < 3) throw new Error("bad certificate");
  const tbsNode = parts[0];
  const tbsChildren = children(der, tbsNode);
  const spkiIndex = (tbsChildren[0]?.tag ?? 0) === 0xa0 ? 6 : 5;
  const spki = tbsChildren[spkiIndex];
  if (!spki) throw new Error("missing public key");
  const bitString = value(der, parts[2]);
  const signature = bitString[0] === 0 ? bitString.subarray(1) : bitString;
  return {
    der,
    tbs: bytes(der, tbsNode),
    spki: bytes(der, spki),
    signature: derSignatureToRaw(signature),
  };
}

export async function importPublicKey(spki: Uint8Array): Promise<CryptoKey> {
  return crypto.subtle.importKey(
    "spki",
    spki,
    { name: "ECDSA", namedCurve: "P-256" },
    true,
    ["verify"],
  );
}

async function verifyCertificate(child: ParsedCertificate, issuer: CryptoKey): Promise<boolean> {
  return crypto.subtle.verify(
    { name: "ECDSA", hash: "SHA-256" },
    issuer,
    child.signature,
    child.tbs,
  );
}

export function pemToDer(pem: string): Uint8Array {
  const body = pem
    .replace(/-----BEGIN [^-]+-----/g, "")
    .replace(/-----END [^-]+-----/g, "")
    .replace(/\s+/g, "");
  const binary = atob(body);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i += 1) bytes[i] = binary.charCodeAt(i);
  return bytes;
}

export function derFromX5c(value: string): Uint8Array {
  const normalized = value.replace(/-/g, "+").replace(/_/g, "/");
  const padded = normalized + "=".repeat((4 - (normalized.length % 4)) % 4);
  const binary = atob(padded);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i += 1) bytes[i] = binary.charCodeAt(i);
  return bytes;
}

async function sameKey(left: CryptoKey, right: CryptoKey): Promise<boolean> {
  const [a, b] = await Promise.all([
    crypto.subtle.exportKey("spki", left) as Promise<ArrayBuffer>,
    crypto.subtle.exportKey("spki", right) as Promise<ArrayBuffer>,
  ]);
  const ua = new Uint8Array(a);
  const ub = new Uint8Array(b);
  if (ua.length !== ub.length) return false;
  let diff = 0;
  for (let i = 0; i < ua.length; i += 1) diff |= ua[i] ^ ub[i];
  return diff === 0;
}

/** Leaf through intermediates, signed up to the pinned root. The root itself may be omitted from x5c. */
export async function verifyChain(certificates: Uint8Array[], rootDer: Uint8Array): Promise<CryptoKey> {
  if (certificates.length === 0) throw new Error("empty chain");
  const parsed = certificates.map(parseCertificate);
  const root = parseCertificate(rootDer);
  const rootKey = await importPublicKey(root.spki);
  for (let index = 0; index < parsed.length - 1; index += 1) {
    const issuer = await importPublicKey(parsed[index + 1].spki);
    if (!(await verifyCertificate(parsed[index], issuer))) throw new Error("broken chain");
  }
  const last = parsed[parsed.length - 1];
  const lastKey = await importPublicKey(last.spki);
  if (await sameKey(lastKey, rootKey)) return await importPublicKey(parsed[0].spki);
  if (!(await verifyCertificate(last, rootKey))) throw new Error("chain does not reach the pinned root");
  return await importPublicKey(parsed[0].spki);
}
