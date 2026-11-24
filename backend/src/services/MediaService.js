import { createClient } from "@supabase/supabase-js";
import { errors } from "../domain/errors/domainErrors.js";

const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export const MEDIA_CONFIG = {
  business_logo: { bucket: "business-logos", mimeTypes: ["image/jpeg", "image/png", "image/webp"], maxBytes: 5 * 1024 * 1024 },
  staff_photo: { bucket: "staff-photos", mimeTypes: ["image/jpeg", "image/png", "image/webp"], maxBytes: 5 * 1024 * 1024 },
  service_image: { bucket: "service-images", mimeTypes: ["image/jpeg", "image/png", "image/webp"], maxBytes: 5 * 1024 * 1024 },
  customer_profile: { bucket: "customer-profile-images", mimeTypes: ["image/jpeg", "image/png", "image/webp"], maxBytes: 5 * 1024 * 1024 },
  portfolio_image: { bucket: "business-portfolios", mimeTypes: ["image/jpeg", "image/png", "image/webp"], maxBytes: 10 * 1024 * 1024 },
  business_document: { bucket: "business-documents", mimeTypes: ["application/pdf", "image/jpeg", "image/png", "image/webp"], maxBytes: 20 * 1024 * 1024 },
  thumbnail: { bucket: null, mimeTypes: ["image/webp"], maxBytes: 5 * 1024 * 1024 }
};

export class MediaService {
  constructor({ supabaseUrl, supabaseAnonKey, clientFactory = null, repository = null } = {}) {
    if (!clientFactory && (!supabaseUrl || !supabaseAnonKey)) {
      throw new Error("SUPABASE_URL and SUPABASE_ANON_KEY are required");
    }
    this.supabaseUrl = supabaseUrl;
    this.supabaseAnonKey = supabaseAnonKey;
    this.clientFactory = clientFactory;
    this.repository = repository;
  }

  client(accessToken) {
    if (this.clientFactory) return this.clientFactory(accessToken);
    return createClient(this.supabaseUrl, this.supabaseAnonKey, {
      auth: { persistSession: false, autoRefreshToken: false },
      global: { headers: { Authorization: `Bearer ${accessToken}` } }
    });
  }

  validateUpload({ mediaType, mimeType, byteSize, tenantId, profileId, entityId }) {
    const config = MEDIA_CONFIG[mediaType];
    if (!config) throw errors.validation("Unsupported media type");
    if (!config.mimeTypes.includes(mimeType)) throw errors.validation("File MIME type is not allowed");
    if (!Number.isInteger(byteSize) || byteSize <= 0) throw errors.validation("File size is invalid");
    if (byteSize > config.maxBytes) throw errors.payloadTooLarge(`File exceeds the ${config.maxBytes} byte limit`);
    if (tenantId && !UUID_PATTERN.test(tenantId)) throw errors.validation("Invalid tenant UUID");
    if (profileId && !UUID_PATTERN.test(profileId)) throw errors.validation("Invalid profile UUID");
    if (entityId && !UUID_PATTERN.test(entityId)) throw errors.validation("Invalid media entity UUID");
  }

  assertBusinessWrite(identity, tenantId) {
    if (identity.provider !== "supabase") return;
    const membership = (identity.memberships || []).find((item) =>
      item.tenantId === tenantId && item.status === "active"
    );
    if (!membership || !["owner", "manager"].includes(membership.role)) {
      throw errors.forbidden("Only business owners or managers may manage this media");
    }
  }

  buildPath({ mediaType, tenantId, profileId, entityId, assetId, mimeType }) {
    const extension = mimeType === "image/webp" ? "webp"
      : mimeType === "image/png" ? "png"
      : mimeType === "image/jpeg" ? "jpg"
      : "pdf";
    if (mediaType === "customer_profile") {
      return `customer/${profileId}/${assetId}.${extension}`;
    }
    if (mediaType === "thumbnail") {
      return `business/${tenantId}/thumbnails/${assetId}.${extension}`;
    }
    const kind = {
      business_logo: "logo",
      staff_photo: `staff/${entityId}`,
      service_image: `service/${entityId}`,
      portfolio_image: "portfolio",
      business_document: `documents/${entityId}`
    }[mediaType];
    return `business/${tenantId}/${kind}/${assetId}.${extension}`;
  }

  async createUpload(identity, input) {
    const tenantId = input.tenantId || identity.tenantId;
    const profileId = identity.id;
    if (!tenantId && input.mediaType !== "customer_profile") {
      throw errors.validation("tenantId is required");
    }
    if (input.mediaType === "customer_profile") {
      if (input.profileId && input.profileId !== identity.id) {
        throw errors.forbidden("A customer may only manage their own profile image");
      }
    } else {
      this.assertBusinessWrite(identity, tenantId);
    }

    this.validateUpload({
      mediaType: input.mediaType,
      mimeType: input.mimeType,
      byteSize: input.byteSize,
      tenantId: input.mediaType === "customer_profile" ? null : tenantId,
      profileId: input.mediaType === "customer_profile" ? profileId : null,
      entityId: input.entityId
    });

    const config = MEDIA_CONFIG[input.mediaType];
    const bucket = input.mediaType === "thumbnail"
      ? MEDIA_CONFIG[input.parentMediaType]?.bucket
      : config.bucket;
    if (!bucket) throw errors.validation("A valid parent media type is required for thumbnails");
    const client = this.client(identity.accessToken);
    const assetId = globalThis.crypto.randomUUID();
    const objectPath = this.buildPath({
      mediaType: input.mediaType,
      tenantId,
      profileId,
      entityId: input.entityId || "default",
      assetId,
      mimeType: input.mimeType
    });
    const { data, error } = await client.storage
      .from(bucket)
      .createSignedUploadUrl(objectPath);
    if (error) throw errors.conflict("Could not create a secure upload URL");

    const { error: insertError } = await client.from("media_assets").insert({
      id: assetId,
      tenant_id: input.mediaType === "customer_profile" ? null : tenantId,
      owner_profile_id: input.mediaType === "customer_profile" ? profileId : null,
      bucket,
      object_path: objectPath,
      media_type: input.mediaType,
      mime_type: input.mimeType,
      byte_size: input.byteSize,
      width: input.width || null,
      height: input.height || null,
      thumbnail_path: input.thumbnailPath || null,
      metadata: input.metadata || {}
    });
    if (insertError) throw errors.conflict("Could not register media metadata");

    return {
      assetId,
      bucket,
      objectPath,
      signedUploadUrl: data.signedUrl,
      token: data.token,
      maxBytes: config.maxBytes
    };
  }

  async createSignedReadUrl(identity, assetId, expiresIn = 300) {
    if (!UUID_PATTERN.test(assetId)) throw errors.validation("Invalid media asset UUID");
    if (!Number.isInteger(expiresIn) || expiresIn < 1 || expiresIn > 3600) {
      throw errors.validation("Signed URL expiry must be between 1 and 3600 seconds");
    }
    const client = this.client(identity.accessToken);
    const { data: asset, error: assetError } = await client.from("media_assets")
      .select("tenant_id,owner_profile_id,bucket,object_path")
      .eq("id", assetId).maybeSingle();
    if (assetError || !asset) throw errors.notFound("Media asset not found");
    if (asset.owner_profile_id && asset.owner_profile_id !== identity.id) {
      throw errors.forbidden("Cross-user media access denied");
    }
    if (asset.tenant_id) this.assertBusinessReadOrPublic(identity, asset);
    if (asset.bucket === "customer-profile-images" && asset.owner_profile_id !== identity.id) {
      throw errors.forbidden("Private media access denied");
    }
    const { data, error } = await client.storage.from(asset.bucket).createSignedUrl(asset.object_path, expiresIn);
    if (error) throw errors.conflict("Could not create a signed media URL");
    return { url: data.signedUrl, expiresIn };
  }

  assertBusinessReadOrPublic(identity, asset) {
    const membership = (identity.memberships || []).find((item) =>
      item.tenantId === asset.tenant_id && item.status === "active"
    );
    const publicBuckets = ["business-logos", "staff-photos", "service-images", "business-portfolios"];
    if (asset.bucket === "business-documents") {
      if (!membership || !["owner", "manager"].includes(membership.role)) {
        throw errors.forbidden("Private media access denied");
      }
    } else if (!publicBuckets.includes(asset.bucket) && !membership) {
      throw errors.forbidden("Private media access denied");
    }
  }

  async deleteMedia(identity, assetId) {
    if (!UUID_PATTERN.test(assetId)) throw errors.validation("Invalid media asset UUID");
    const client = this.client(identity.accessToken);
    const { data: asset, error } = await client.from("media_assets")
      .select("tenant_id,owner_profile_id,bucket,object_path")
      .eq("id", assetId).maybeSingle();
    if (error || !asset) throw errors.notFound("Media asset not found");
    if (asset.owner_profile_id) {
      if (asset.owner_profile_id !== identity.id) throw errors.forbidden("Cross-user deletion denied");
    } else if (asset.tenant_id) {
      this.assertBusinessWrite(identity, asset.tenant_id);
    } else {
      throw errors.forbidden("Media asset has no valid owner");
    }

    const cleanupOperations = [
      client.from("business_portfolio_items").delete().eq("media_asset_id", assetId),
      client.from("business_documents").delete().eq("media_asset_id", assetId),
      client.from("tenants").update({ logo_media_id: null }).eq("logo_media_id", assetId),
      client.from("staff").update({ photo_media_id: null }).eq("photo_media_id", assetId),
      client.from("services").update({ image_media_id: null }).eq("image_media_id", assetId),
      client.from("profiles").update({ avatar_media_id: null }).eq("avatar_media_id", assetId)
    ];
    const cleanupResults = await Promise.all(cleanupOperations);
    if (cleanupResults.some((result) => result.error)) {
      throw errors.conflict("Media references could not be cleared; no files were deleted");
    }

    const { error: removeError } = await client.storage.from(asset.bucket).remove([asset.object_path]);
    if (removeError) throw errors.conflict("The file could not be deleted; metadata was retained");
    if (asset.thumbnail_path) {
      await client.storage.from(asset.bucket).remove([asset.thumbnail_path]);
      await client.from("media_assets").delete().eq("object_path", asset.thumbnail_path);
    }
    const { error: deleteError } = await client.from("media_assets").delete().eq("id", assetId);
    if (deleteError) throw errors.conflict("The file was deleted but metadata cleanup failed");
  }
}
