const PARKING_NO_PATTERN: RegExp = /([A-Z]?\d{1,3}[-区层]?[A-Z]?\d{1,4}|[A-Z][-\s]?\d{1,4})/i;

export function normalizeParkingNo(input: string): string {
  return input
    .replace(/\s+/g, '')
    .replace(/[，。；;:：]/g, '')
    .toUpperCase();
}

export function extractParkingNo(input: string): string {
  const normalized = normalizeParkingNo(input);
  const match = normalized.match(PARKING_NO_PATTERN);
  return match ? match[0] : normalized;
}
