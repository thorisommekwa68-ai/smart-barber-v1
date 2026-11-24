export function strictDateKey(value) {
  if (typeof value !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(value)) return null;
  const [year, month, day] = value.split("-").map(Number);
  const probe = new Date(Date.UTC(year, month - 1, day));
  if (probe.getUTCFullYear() !== year || probe.getUTCMonth() !== month - 1 || probe.getUTCDate() !== day) return null;
  return { year, month, day };
}

export function localDateParts(date, timeZone) {
  const parts = new Intl.DateTimeFormat("en-GB", {
    timeZone,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    weekday: "short",
    hour: "2-digit",
    minute: "2-digit",
    hourCycle: "h23"
  }).formatToParts(date);
  const value = Object.fromEntries(parts.filter((part) => part.type !== "literal").map((part) => [part.type, part.value]));
  return {
    dateKey: `${value.year}-${value.month}-${value.day}`,
    time: `${value.hour}:${value.minute}`,
    dayOfWeek: ({ Sun: 7, Mon: 1, Tue: 2, Wed: 3, Thu: 4, Fri: 5, Sat: 6 })[value.weekday]
  };
}

export function zonedDateTimeToIso(dateKey, time, timeZone) {
  const [year, month, day] = dateKey.split("-").map(Number);
  const [hour, minute] = time.split(":").map(Number);
  let guess = Date.UTC(year, month - 1, day, hour, minute);
  for (let iteration = 0; iteration < 3; iteration += 1) {
    const actual = localDateParts(new Date(guess), timeZone);
    const desired = Date.UTC(year, month - 1, day, hour, minute);
    const actualParts = new Date(`${actual.dateKey}T${actual.time}:00Z`).getTime();
    const adjustment = desired - actualParts;
    guess += adjustment;
    if (adjustment === 0) break;
  }
  return new Date(guess).toISOString();
}

export function minutesFromTime(value) {
  const [hour, minute] = value.split(":").map(Number);
  return hour * 60 + minute;
}
