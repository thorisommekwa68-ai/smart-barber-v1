export const MEDIA_LIMITS = {
  business_logo: { bucket: "business-logos", maxBytes: 5 * 1024 * 1024, mimeTypes: ["image/jpeg", "image/png", "image/webp"] },
  staff_photo: { bucket: "staff-photos", maxBytes: 5 * 1024 * 1024, mimeTypes: ["image/jpeg", "image/png", "image/webp"] },
  service_image: { bucket: "service-images", maxBytes: 5 * 1024 * 1024, mimeTypes: ["image/jpeg", "image/png", "image/webp"] },
  customer_profile: { bucket: "customer-profile-images", maxBytes: 5 * 1024 * 1024, mimeTypes: ["image/jpeg", "image/png", "image/webp"] },
  portfolio_image: { bucket: "business-portfolios", maxBytes: 10 * 1024 * 1024, mimeTypes: ["image/jpeg", "image/png", "image/webp"] },
  business_document: { bucket: "business-documents", maxBytes: 20 * 1024 * 1024, mimeTypes: ["application/pdf", "image/jpeg", "image/png", "image/webp"] }
};

export function validateMediaFile(mediaType, file) {
  const config = MEDIA_LIMITS[mediaType];
  if (!config) throw new Error("Unsupported media type");
  if (!config.mimeTypes.includes(file.type)) throw new Error("File type is not allowed");
  if (!Number.isFinite(file.size) || file.size <= 0) throw new Error("File size is invalid");
  if (file.size > config.maxBytes) throw new Error("File exceeds the upload size limit");
  return config;
}

export async function resizeAndCompressImage(file, {
  maxWidth = 1600,
  maxHeight = 1600,
  quality = 0.82,
  mimeType = "image/webp"
} = {}) {
  if (typeof createImageBitmap !== "function" || typeof document === "undefined") {
    return { blob: file, mimeType: file.type, width: null, height: null };
  }
  const bitmap = await createImageBitmap(file);
  try {
    const scale = Math.min(1, maxWidth / bitmap.width, maxHeight / bitmap.height);
    const width = Math.max(1, Math.round(bitmap.width * scale));
    const height = Math.max(1, Math.round(bitmap.height * scale));
    const canvas = document.createElement("canvas");
    canvas.width = width;
    canvas.height = height;
    const context = canvas.getContext("2d");
    context.drawImage(bitmap, 0, 0, width, height);
    const blob = await new Promise((resolve, reject) => {
      canvas.toBlob((result) => result ? resolve(result) : reject(new Error("Image compression failed")), mimeType, quality);
    });
    return { blob, mimeType: blob.type || mimeType, width, height };
  } finally {
    bitmap.close();
  }
}

export function createMediaService({ apiBaseUrl, getAccessToken, supabase }) {
  async function authenticatedRequest(path, options = {}) {
    const token = await getAccessToken();
    if (!token) throw new Error("Authentication required");
    const response = await fetch(`${apiBaseUrl}${path}`, {
      ...options,
      headers: {
        "Content-Type": "application/json",
        "Authorization": `Bearer ${token}`,
        ...(options.headers || {})
      }
    });
    const body = await response.json();
    if (!response.ok) throw new Error(body.error?.message || "Media operation failed");
    return body.data;
  }

  async function uploadBlob(upload, blob, mimeType) {
    const response = await fetch(upload.signedUploadUrl, {
      method: "PUT",
      headers: { "Content-Type": mimeType },
      body: blob
    });
    if (!response.ok) throw new Error("File upload failed");
  }

  async function uploadImage({ mediaType, file, tenantId, entityId, metadata = {}, thumbnail = true }) {
    validateMediaFile(mediaType, file);
    if (mediaType === "business_document") throw new Error("Use uploadFile for documents");

    const prepared = await resizeAndCompressImage(file);
    const preparedFile = prepared.blob;
    if (preparedFile.size > MEDIA_LIMITS[mediaType].maxBytes) {
      throw new Error("Compressed file still exceeds the upload size limit");
    }

    let thumbnailPath = null;
    let thumbnailUpload = null;
    if (thumbnail && mediaType !== "customer_profile") {
      const thumbnailImage = await resizeAndCompressImage(file, {
        maxWidth: 320,
        maxHeight: 320,
        quality: 0.78,
        mimeType: "image/webp"
      });
      thumbnailUpload = await authenticatedRequest("/api/v1/media/upload", {
        method: "POST",
        body: JSON.stringify({
          mediaType: "thumbnail",
          parentMediaType: mediaType,
          mimeType: thumbnailImage.mimeType,
          byteSize: thumbnailImage.blob.size,
          tenantId,
          entityId,
          width: thumbnailImage.width,
          height: thumbnailImage.height
        })
      });
      await uploadBlob(thumbnailUpload, thumbnailImage.blob, thumbnailImage.mimeType);
      thumbnailPath = thumbnailUpload.objectPath;
    }

    const upload = await authenticatedRequest("/api/v1/media/upload", {
      method: "POST",
      body: JSON.stringify({
        mediaType,
        mimeType: prepared.mimeType,
        byteSize: preparedFile.size,
        tenantId,
        entityId,
        width: prepared.width,
        height: prepared.height,
        thumbnailPath,
        metadata
      })
    });
    await uploadBlob(upload, preparedFile, prepared.mimeType);
    return { ...upload, thumbnailAssetId: thumbnailUpload?.assetId || null };
  }

  async function uploadFile({ mediaType, file, tenantId, entityId, metadata = {} }) {
    validateMediaFile(mediaType, file);
    const upload = await authenticatedRequest("/api/v1/media/upload", {
      method: "POST",
      body: JSON.stringify({
        mediaType,
        mimeType: file.type,
        byteSize: file.size,
        tenantId,
        entityId,
        metadata
      })
    });
    await uploadBlob(upload, file, file.type);
    return upload;
  }

  function publicUrl(bucket, objectPath) {
    if (!supabase) throw new Error("Supabase browser client is required");
    return supabase.storage.from(bucket).getPublicUrl(objectPath).data.publicUrl;
  }

  async function signedUrl(assetId) {
    return authenticatedRequest(`/api/v1/media/${encodeURIComponent(assetId)}/signed-url`, { method: "POST" });
  }

  async function deleteMedia(assetId) {
    return authenticatedRequest(`/api/v1/media/${encodeURIComponent(assetId)}`, { method: "DELETE" });
  }

  return { uploadImage, uploadFile, publicUrl, signedUrl, deleteMedia, validateMediaFile };
}
