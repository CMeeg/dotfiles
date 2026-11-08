/**
 * Errors: a small `Error` subclass per kind of failure a caller might handle, with `name` set (logs and
 * name checks rely on it) and the original error kept as `cause` when one is wrapped.
 */

export class QuotaError extends Error {
  override name = "QuotaError";

  constructor(message: string, options?: ErrorOptions) {
    super(message, options);
  }
}

// Wrapping a lower-level failure without losing it:
//
//   try { await storage.put(key, value) }
//   catch (error) { throw new QuotaError(`Saving ${key} would exceed the quota`, { cause: error }) }

/**
 * Whether an error is a `QuotaError`, by name. `instanceof` compares class identity, which fails when the
 * error comes from another copy of this module (some bundlers include a module once per entry point).
 */
export const isQuotaError = (error: unknown): error is QuotaError =>
  error instanceof Error && error.name === "QuotaError";
