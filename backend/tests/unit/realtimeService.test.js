import test from "node:test";
import assert from "node:assert/strict";
import { RealtimeSubscriptionService } from "../../../packages/shared-utils/realtimeService.js";

test("realtime subscription only accepts duplicate notification IDs once", () => {
  const service = new RealtimeSubscriptionService({
    supabase: {},
    profileId: "10000000-0000-4000-8000-000000000001",
    onUpdate: () => {}
  });
  assert.equal(service.remember("notification-1"), true);
  assert.equal(service.remember("notification-1"), false);
  assert.equal(service.remember("notification-2"), true);
});

test("realtime stop removes all channels and clears deduplication", async () => {
  const removed = [];
  const channel = { topic: "smart-barber-notifications-test" };
  const supabase = {
    channel() {
      return {
        on() { return this; },
        subscribe() { return channel; }
      };
    },
    async removeChannel(value) { removed.push(value); }
  };
  const service = new RealtimeSubscriptionService({
    supabase,
    profileId: "10000000-0000-4000-8000-000000000001",
    onUpdate: () => {}
  });
  service.subscribe();
  assert.equal(service.channels.length, 1);
  await service.stop();
  assert.equal(service.channels.length, 0);
  assert.equal(removed.length, 1);
  assert.equal(service.seen.size, 0);
});
