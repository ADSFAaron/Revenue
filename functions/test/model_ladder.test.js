// CommonJS: `functions/package.json` has no `"type": "module"`, so tsc's
// NodeNext output is CJS and this has to match it.
const assert = require("node:assert/strict");
const { describe, it } = require("node:test");

const { LadderFailure, runLadder } = require("../lib/model_ladder.js");

/**
 * The retry ladder, under a fake clock.
 *
 * This exists because the first version of this logic was wrong in a way no
 * amount of reading caught. It was sized on the assumption that a failing
 * attempt costs about what a successful one costs; production said a 503 from
 * an overloaded model takes two minutes to arrive, and the ladder spent its
 * entire budget on one sick model without ever reaching the fallbacks it was
 * written to reach. The arithmetic was the bug, so the arithmetic is what is
 * tested.
 */

/** The values `menu_import.ts` actually passes. */
const MODELS = ["gemini-3.6-flash", "gemini-3.7-flash", "gemini-3.5-flash"];
const ATTEMPT_TIMEOUT_MS = 60_000;
const BUDGET_MS = 240_000;
const RETRY_DELAYS_MS = [2_000];

/** The function's own ceiling, which nothing here may reach. */
const FUNCTION_TIMEOUT_MS = 300_000;

function clock() {
  let t = 0;
  return {
    now: () => t,
    sleep: async (ms) => {
      t += ms;
    },
    spend: (ms) => {
      t += ms;
    },
    get elapsed() {
      return t;
    },
  };
}

/** An attempt that costs `ms` and fails with `status`. */
const fails = (status, ms) => (model) => ({
  model,
  status,
  detail: `status ${status}`,
  ms,
});

/** An attempt that never comes back inside the cap. */
const times_out = (model, timeoutMs) => ({
  model,
  status: 0,
  detail: "no answer",
  ms: timeoutMs,
});

/**
 * Runs the ladder with the real settings and a scripted sequence of outcomes.
 * Each outcome is a function of (model, timeoutMs); the clock advances by
 * whatever the outcome says it cost.
 */
async function run(script, { models = MODELS } = {}) {
  const time = clock();
  const tried = [];
  const reports = [];
  let step = 0;

  const promise = runLadder({
    models,
    attemptTimeoutMs: ATTEMPT_TIMEOUT_MS,
    budgetMs: BUDGET_MS,
    retryDelaysMs: RETRY_DELAYS_MS,
    now: time.now,
    sleep: time.sleep,
    report: async (update) => {
      reports.push(update);
    },
    attempt: async (model, timeoutMs) => {
      tried.push(model);
      const outcome = script[Math.min(step, script.length - 1)](model, timeoutMs);
      step += 1;
      time.spend(typeof outcome === "string" ? 20_000 : outcome.ms);
      return outcome;
    },
  });

  try {
    return { answer: await promise, tried, reports, time };
  } catch (error) {
    return { error, tried, reports, time };
  }
}

describe("the model ladder", () => {
  it("asks the first model and stops when it answers", async () => {
    const { answer, tried } = await run([() => "{}"]);

    assert.equal(answer, "{}");
    assert.deepEqual(tried, ["gemini-3.6-flash"]);
  });

  it("leads with gemini-3.6-flash, which is the point of the reorder",
    async () => {
      const { tried } = await run([fails(503, 4_000)]);
      assert.deepEqual(tried, [
        // 3.6 twice — a 503 is fast and does clear, so it earns its retry.
        "gemini-3.6-flash",
        "gemini-3.6-flash",
        "gemini-3.7-flash",
        "gemini-3.7-flash",
        "gemini-3.5-flash",
        "gemini-3.5-flash",
      ]);
    });

  it("falls to the next model and returns its answer", async () => {
    const { answer, tried } = await run([
      fails(503, 4_000),
      fails(503, 4_000),
      () => "{}",
    ]);

    assert.equal(answer, "{}");
    assert.deepEqual(tried, [
      "gemini-3.6-flash",
      "gemini-3.6-flash",
      "gemini-3.7-flash",
    ]);
  });

  it("does not retry a model that timed out — that is the expensive bet",
    async () => {
      const { error, tried, time } = await run([times_out]);

      // One attempt each, not two. Two full timeouts on one model is 122
      // seconds of the 240 available, which is how the fallbacks went untried.
      assert.deepEqual(tried, [
        "gemini-3.6-flash",
        "gemini-3.7-flash",
        "gemini-3.5-flash",
      ]);
      assert.equal(time.elapsed, 180_000);
      assert.ok(error instanceof LadderFailure);
      assert.equal(error.reason, "exhausted");
    });

  it("gives up immediately on a status no retry can fix", async () => {
    const { error, tried } = await run([fails(400, 500)]);

    assert.deepEqual(tried, ["gemini-3.6-flash"]);
    assert.equal(error.reason, "refused");
    assert.equal(error.attempt.status, 400);
  });

  it("stops before starting an attempt it cannot finish", async () => {
    // The case that actually runs the budget out: a 503 that takes 55 seconds
    // to arrive is not a timeout, so it earns its retry, and each model then
    // costs 55 + 2 + 55. Two models fit and the third does not — at which
    // point the ladder must *say so* rather than start an attempt that Cloud
    // Run would sever halfway through.
    const { error, tried, time } = await run([fails(503, 55_000)]);

    assert.equal(error.reason, "outOfTime");
    assert.deepEqual(tried, [
      "gemini-3.6-flash",
      "gemini-3.6-flash",
      "gemini-3.7-flash",
      "gemini-3.7-flash",
    ]);
    assert.ok(
      time.elapsed <= BUDGET_MS,
      `spent ${time.elapsed}ms of a ${BUDGET_MS}ms budget`
    );
  });

  it("still reaches every model when the slow failures are timeouts",
    async () => {
      // The same shape as the run that shipped: one slow refusal, then
      // nothing coming back at all. Because a timeout does not buy a second
      // attempt on the same model, all three are reached inside the budget —
      // which is the behaviour the original ladder could not manage.
      const { error, tried, time } = await run([
        fails(503, 55_000),
        times_out,
      ]);

      assert.deepEqual(tried, [
        "gemini-3.6-flash",
        "gemini-3.6-flash",
        "gemini-3.7-flash",
        "gemini-3.5-flash",
      ]);
      assert.equal(error.reason, "exhausted");
      assert.ok(time.elapsed <= BUDGET_MS);
    });

  it("reports a reading frame before every attempt and a busy frame after " +
    "every failure", async () => {
      const { reports } = await run([fails(503, 4_000), () => "{}"]);

      assert.deepEqual(
        reports.map((r) => `${r.stage} ${r.model}`),
        [
          "reading gemini-3.6-flash",
          "busy gemini-3.6-flash",
          "reading gemini-3.6-flash",
        ]
      );
      assert.equal(reports[0].attempt, 1);
      assert.equal(reports[0].attempts, 2);
      assert.equal(reports[1].status, 503);
    });

  /**
   * The claim the whole file exists to make: whatever the models do, this
   * function answers — with words — inside the 300 seconds Cloud Run gives it.
   * Being severed mid-request is the failure that reaches the phone as an
   * unexplained "took too long", and it is the one that shipped.
   */
  it("always finishes inside the function's own timeout", async () => {
    const costs = [
      0,
      500,
      4_000,
      20_000,
      55_000,
      ATTEMPT_TIMEOUT_MS,
    ];
    const statuses = [0, 429, 503];

    for (const cost of costs) {
      for (const status of statuses) {
        for (const secondCost of costs) {
          const { error, answer, time } = await run([
            status === 0
              ? (model) => times_out(model, ATTEMPT_TIMEOUT_MS)
              : fails(status, cost),
            status === 0
              ? (model) => times_out(model, ATTEMPT_TIMEOUT_MS)
              : fails(status, secondCost),
          ]);

          // It ended, one way or the other.
          assert.ok(
            error instanceof LadderFailure || typeof answer === "string",
            `no outcome for status ${status}, costs ${cost}/${secondCost}`
          );
          // The real invariant, and the one the guard is there to hold: an
          // attempt only ever starts with a full timeout left, so nothing can
          // end later than the budget. The platform's limit then has sixty
          // seconds of headroom it never needs.
          assert.ok(
            time.elapsed <= BUDGET_MS,
            `status ${status}, costs ${cost}/${secondCost} took ` +
              `${time.elapsed}ms of a ${BUDGET_MS}ms budget`
          );
          assert.ok(time.elapsed < FUNCTION_TIMEOUT_MS);
        }
      }
    }
  });
});
