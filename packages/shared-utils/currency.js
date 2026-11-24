export function formatZarMinor(minorUnits) {
  const amount = Number(minorUnits);
  if (!Number.isFinite(amount)) throw new TypeError("Currency amount must be a finite number of minor units");
  return new Intl.NumberFormat("en-ZA", {
    style: "currency",
    currency: "ZAR",
    minimumFractionDigits: 2,
    maximumFractionDigits: 2
  }).format(amount / 100);
}
