# Environment Variables

| Variable | Backend/Worker | Required in production | Purpose |
|---|---|---:|---|
| `NODE_ENV` | Both | Yes | Must be `production` |
| `IDENTITY_PROVIDER_TYPE` | Both | Yes | Must be `supabase` |
| `REPOSITORY_TYPE` | Both | Yes | Must be `supabase` |
| `SUPABASE_URL` | Both | Yes | Supabase project URL |
| `SUPABASE_ANON_KEY` | Both | Yes | Browser/backend public key only |
| `SUPABASE_SERVICE_ROLE_KEY` | Server only if needed | No/optional | Never expose to frontend or public logs |
| `CORS_ALLOWED_ORIGINS` | Both | Yes | Exact HTTPS frontend origins |
| `MAX_REQUEST_BODY_BYTES` | Both | Recommended | Default 1,048,576 bytes |
| `MOCK_AUTH_ENABLED` | Both | Yes false | Must be `false` |
| `VITE_API_BASE_URL` | Frontends | Yes | HTTPS backend API base |
| `VITE_SUPABASE_URL` | Frontends | Yes | Public project URL |
| `VITE_SUPABASE_ANON_KEY` | Frontends | Yes | Public anonymous key |

## Secret management

Configure provider secrets in Cloudflare, the Node host, or CI secret facilities. Rotate keys after suspected exposure. Do not copy credentials into committed `.env` files, Wrangler variables, build arguments, screenshots, or logs.

The service-role key has administrative Storage/Auth privileges and must not be added to `VITE_*` variables or browser bundles.
