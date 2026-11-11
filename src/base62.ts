const ALPHABET = "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ";

export function encode(n: number): string {
  if (!Number.isSafeInteger(n) || n < 0) throw new RangeError("n must be a non-negative safe integer");
  if (n === 0) return ALPHABET[0];
  let out = "";
  while (n > 0) {
    out = ALPHABET[n % 62] + out;
    n = Math.floor(n / 62);
  }
  return out;
}
