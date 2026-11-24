import test from "node:test";
import assert from "node:assert/strict";
import { MediaService, MEDIA_CONFIG } from "../../src/services/MediaService.js";
import { errors } from "../../src/domain/errors/domainErrors.js";

test("media upload validation accepts approved MIME types and sizes", () => {
  const service = new MediaService({ clientFactory: () => ({}) });
  assert.doesNotThrow(() => service.validateUpload({
    mediaType: "portfolio_image",
    mimeType: "image/webp",
    byteSize: 1024,
    tenantId: "10000000-0000-4000-8000-000000000001"
  }));
});

test("media upload validation rejects cross-policy MIME types and oversized files", () => {
  const service = new MediaService({ clientFactory: () => ({}) });
  assert.throws(
    () => service.validateUpload({ mediaType: "business_logo", mimeType: "application/pdf", byteSize: 1024 }),
    (error) => error.code === "VALIDATION_ERROR"
  );
  assert.throws(
    () => service.validateUpload({ mediaType: "business_logo", mimeType: "image/png", byteSize: MEDIA_CONFIG.business_logo.maxBytes + 1 }),
    (error) => error.code === "PAYLOAD_TOO_LARGE"
  );
});

test("business media writes require an owner or manager membership", () => {
  const service = new MediaService({ clientFactory: () => ({}) });
  const tenantId = "10000000-0000-4000-8000-000000000001";
  assert.throws(
    () => service.assertBusinessWrite({
      provider: "supabase",
      memberships: [{ tenantId, role: "stylist", status: "active" }]
    }, tenantId),
    (error) => error.code === "FORBIDDEN"
  );
  assert.doesNotThrow(() => service.assertBusinessWrite({
    provider: "supabase",
    memberships: [{ tenantId, role: "manager", status: "active" }]
  }, tenantId));
});

test("storage paths are tenant and user UUID scoped", () => {
  const service = new MediaService({ clientFactory: () => ({}) });
  const tenantId = "10000000-0000-4000-8000-000000000001";
  const userId = "20000000-0000-4000-8000-000000000002";
  const assetId = "30000000-0000-4000-8000-000000000003";
  assert.equal(
    service.buildPath({ mediaType: "staff_photo", tenantId, entityId: "40000000-0000-4000-8000-000000000004", assetId, mimeType: "image/webp" }),
    `business/${tenantId}/staff/40000000-0000-4000-8000-000000000004/${assetId}.webp`
  );
  assert.equal(
    service.buildPath({ mediaType: "customer_profile", profileId: userId, assetId, mimeType: "image/jpeg" }),
    `customer/${userId}/${assetId}.jpg`
  );
});
