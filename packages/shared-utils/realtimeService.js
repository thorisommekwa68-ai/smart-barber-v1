export class RealtimeSubscriptionService {
  constructor({ supabase, profileId, onUpdate, onReconnect = null }) {
    if (!supabase || !profileId) throw new Error("Supabase and profile UUID are required");
    this.supabase = supabase;
    this.profileId = profileId;
    this.onUpdate = onUpdate;
    this.onReconnect = onReconnect;
    this.channels = [];
    this.seen = new Set();
    this.wasDisconnected = false;
  }

  remember(eventId) {
    if (!eventId) return true;
    if (this.seen.has(eventId)) return false;
    this.seen.add(eventId);
    if (this.seen.size > 500) {
      const oldest = this.seen.values().next().value;
      this.seen.delete(oldest);
    }
    return true;
  }

  subscribe() {
    const channelName = `smart-barber-notifications-${this.profileId}`;
    const channel = this.supabase.channel(channelName).on(
      "postgres_changes",
      {
        event: "INSERT",
        schema: "public",
        table: "notifications",
        filter: `recipient_profile_id=eq.${this.profileId}`
      },
      (payload) => {
        const row = payload.new;
        const eventId = row?.id;
        if (this.remember(eventId)) this.onUpdate?.({
          source: "notification",
          event: "INSERT",
          row
        });
      }
    ).subscribe((status) => {
      if (status === "SUBSCRIBED") {
        if (this.wasDisconnected) this.onReconnect?.();
        this.wasDisconnected = false;
      } else if (status === "CHANNEL_ERROR" || status === "TIMED_OUT" || status === "CLOSED") {
        this.wasDisconnected = true;
      }
    });
    this.channels.push(channel);
    return this;
  }

  async stop() {
    const channels = [...this.channels];
    this.channels = [];
    for (const channel of channels) {
      await this.supabase.removeChannel(channel);
    }
    this.seen.clear();
  }
}

export function createRealtimeSubscriptionService(options) {
  return new RealtimeSubscriptionService(options).subscribe();
}
