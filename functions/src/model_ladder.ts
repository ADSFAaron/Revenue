/**
 * Working down a list of models until one of them answers.
 *
 * This is a separate file so it can be *tested*, which the version that lived
 * inside `menu_import.ts` could not be: it reached for `fetch`, a secret and a
 * wall clock, so the only way to find out what it did under load was to put a
 * shop's phone under load. That is how the first version shipped with a retry
 * plan that could never reach its own fallbacks — nine attempts sized for
 * failures that take a second, against failures that took two minutes.
 *
 * Nothing here knows about HTTP, Gemini, or Firebase. It is handed a way to
 * make one attempt and a clock, and it decides what to try next.
 */

/** One attempt that did not produce an answer. */
export interface Attempt {
  model: string;
  /** The HTTP status, or 0 when the request never came back at all. */
  status: number;
  /** A short sentence about why. Never a raw response body. */
  detail: string;
  ms: number;
}

/** Why the ladder ran out. */
export type LadderReason =
  /** A status no amount of retrying or switching fixes — a 400, a 403. */
  | "refused"
  /** Every model was tried and every one failed. */
  | "exhausted"
  /** There was not enough budget left to start another attempt. */
  | "outOfTime";

export class LadderFailure extends Error {
  constructor(
    readonly reason: LadderReason,
    readonly attempt: Attempt | null
  ) {
    super(`model ladder ${reason}`);
    this.name = "LadderFailure";
  }
}

export interface LadderOptions {
  models: readonly string[];
  /** How long one attempt may take before it is abandoned. */
  attemptTimeoutMs: number;
  /** The wall clock for the whole ladder. */
  budgetMs: number;
  /** Waits between the retries of one model. Length + 1 = attempts per model. */
  retryDelaysMs: readonly number[];

  /** Makes one attempt. Resolves to the answer, or to why there wasn't one. */
  attempt: (model: string, timeoutMs: number) => Promise<string | Attempt>;
  /** Says what is happening. Never required for correctness. */
  report?: (update: Record<string, unknown>) => Promise<void>;

  now?: () => number;
  sleep?: (ms: number) => Promise<void>;
}

/**
 * A status worth trying again. 503 is the model being busy and 429 is the
 * quota being hot; both pass, and both usually clear. Anything else is this
 * code or this key being wrong, and waiting does not fix either.
 */
const RETRYABLE = new Set([429, 503]);

export async function runLadder(options: LadderOptions): Promise<string> {
  const {
    models,
    attemptTimeoutMs,
    budgetMs,
    retryDelaysMs,
    attempt: makeAttempt,
    report = async () => {},
    now = () => Date.now(),
    sleep = (ms: number) => new Promise<void>((r) => setTimeout(r, ms)),
  } = options;

  const deadline = now() + budgetMs;
  const attempts = retryDelaysMs.length + 1;
  let last: Attempt | null = null;

  for (const model of models) {
    for (let attempt = 1; attempt <= attempts; attempt++) {
      if (attempt > 1) await sleep(retryDelaysMs[attempt - 2]);

      // Never start an attempt there is not room to finish. Running out of
      // budget here means the caller gets a written failure naming the model
      // and the status; running out of the platform's means the request is
      // severed, which reaches the phone as an unexplained "took too long"
      // whatever actually went wrong.
      if (deadline - now() < attemptTimeoutMs) {
        throw new LadderFailure("outOfTime", last);
      }

      await report({ stage: "reading", model, attempt, attempts });

      const outcome = await makeAttempt(model, attemptTimeoutMs);
      if (typeof outcome === "string") return outcome;

      last = outcome;
      if (outcome.status !== 0 && !RETRYABLE.has(outcome.status)) {
        throw new LadderFailure("refused", outcome);
      }

      await report({
        stage: "busy",
        model,
        attempt,
        attempts,
        status: outcome.status,
        detail: outcome.detail,
      });

      // A model that did not answer inside the cap gets one chance, not two.
      // Another full timeout on the same model is the same bet placed twice,
      // and it is the expensive one: two of those is most of the budget, which
      // is exactly how the fallbacks went untried the first time. A 503 is
      // different — it comes back fast and it does clear — so that one still
      // gets its retry.
      if (outcome.status === 0) break;
    }
  }

  throw new LadderFailure("exhausted", last);
}
