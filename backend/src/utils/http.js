export async function readJson(req, maxBytes = 1048576) {
  const chunks = [];
  let bytes = 0;
  for await (const chunk of req) {
    const bytesChunk = typeof chunk === "string" ? new TextEncoder().encode(chunk) : chunk;
    bytes += bytesChunk.length;
    if (bytes > maxBytes) {
      const { errors } = await import("../domain/errors/domainErrors.js");
      throw errors.payloadTooLarge("Request body exceeds the maximum allowed size");
    }
    chunks.push(bytesChunk);
  }
  if (!chunks.length) return null;
  try {
    const combined = new Uint8Array(bytes);
    let offset = 0;
    for (const chunk of chunks) {
      combined.set(chunk instanceof Uint8Array ? chunk : new TextEncoder().encode(chunk), offset);
      offset += chunk.length;
    }
    return JSON.parse(new TextDecoder("utf-8").decode(combined));
  } catch {
    const { errors } = await import("../domain/errors/domainErrors.js");
    throw errors.validation("Request body must contain valid JSON");
  }
}
