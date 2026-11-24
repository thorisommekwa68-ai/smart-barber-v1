# API

All endpoints use `/api/v1`.

Success:

```json
{ "success": true, "data": {}, "message": "Operation completed successfully" }
```

Error:

```json
{ "success": false, "error": { "code": "ERROR_CODE", "message": "Human-readable explanation" } }
```

## Development authentication

Send `x-user-id` to authenticated endpoints. Merchant endpoints additionally send `x-tenant-id`.
These headers are for the explicitly enabled local development identity provider only; production clients must not send them.

## Production authentication

Send a Supabase access token in the `Authorization: Bearer <token>` header for protected endpoints. The API verifies the token and derives profile and tenant membership from the database. `GET /me/profile` returns the authenticated profile and active memberships.

| Method | Endpoint | Purpose |
|---|---|---|
| GET | `/me/profile` | Retrieve the authenticated profile and active business memberships |
| GET | `/marketplace/tenants` | List businesses |
| GET | `/marketplace/tenants/:tenantId` | Retrieve business |
| GET | `/marketplace/tenants/:tenantId/services` | List services |
| GET | `/marketplace/tenants/:tenantId/staff` | List staff |
| GET | `/availability?tenantId=&locationId=&staffId=&serviceId=&date=YYYY-MM-DD` | List slots |
| POST | `/appointments` | Create booking |
| GET | `/me/appointments` | Customer booking history |
| GET | `/merchant/appointments` | Merchant tenant bookings |
| PATCH | `/merchant/appointments/:id/accept` | Confirm |
| PATCH | `/merchant/appointments/:id/decline` | Decline |
| PATCH | `/merchant/appointments/:id/start` | Start |
| PATCH | `/merchant/appointments/:id/complete` | Complete |
| PATCH | `/merchant/appointments/:id/no-show` | Mark no-show |
| POST | `/appointments/:id/cancel` | Customer cancel |
