export class MarketplaceService {
  constructor(repository) { this.repository = repository; }
  async listTenants() { return this.repository.listTenants(); }
  async getTenant(tenantId) {
    const tenant = await this.repository.findTenantById(tenantId);
    if (!tenant) throw (await import("../domain/errors/domainErrors.js")).errors.notFound("Business not found");
    return tenant;
  }
  async listServices(tenantId) { await this.getTenant(tenantId); return this.repository.listServicesByTenant(tenantId); }
  async listStaff(tenantId) { await this.getTenant(tenantId); return this.repository.listStaffByTenant(tenantId); }
}
