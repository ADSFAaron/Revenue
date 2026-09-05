/**
 * The half of a vision call that cannot be unit-tested: a socket, a secret and
 * a clock.
 *
 * Extracted when a second caller arrived. `menu_import.ts` had grown the whole
 * of this inside it — the endpoint, the ladder wiring, the abort alarm, the
 * response reader, the error translation — and reading an order slip needs
 * every one of those and differs only in the prompt and the schema. Copying it
 * would have meant two places to fix the next time Google moves a field, and
 * the fields in here have already moved twice.
 *
 * The *deciding* — which model next, how many tries, when to stop — is not in
 * here. That lives in `model_ladder.ts`, which has no I/O in it and is tested.
 */

import { HttpsError, CallableRequest } from "firebase-functions/v2/https";
import { defineSecret } from "firebase-functions/params";

import { Attempt, LadderFailure, runLadder } from "./model_ladder.js";

/**
 * Set with `firebase functions:secrets:set GEMINI_API_KEY`. Declared once and
 * bound per function, so a callable that does not read images never sees it.
 */
export const GEMINI_API_KEY = defineSecret("GEMINI_API_KEY");

/**
 * `models.{model}:generateContent`, taken from the API's own discovery
 * document rather than from a documentation page.
 *
 * That distinction cost a release. The docs describe an "Interactions API" at
 * `/v1beta2/interactions` and recommend it for new work; no such resource
 * exists in the discovery document for v1, v1beta, v1beta2 or v1alpha, and
 * calling it returns a 404 with an empty body. `models.generateContent` is
 * what the service actually publishes. When the two disagree, the discovery
 * document is the one that is generated from the running service:
 *
 *   curl 'https://generativelanguage.googleapis.com/$discovery/rest?version=v1beta'
 */
const ENDPOINT_FOR = (model: string) =>
  `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent`;

export interface Photo {
  mimeType: string;
  data: string;
}

/**
 * One line of "what is happening right now", on its way to the phone.
 *
 * This exists because the honest answer to "why is nothing happening" used to
 * be unavailable to the only person who needed it. Recognition is one call
 * that can take two minutes, and a spinner with no words under it is
 * indistinguishable from a hang — so people back out, which costs the call and
 * loses the photographs, and then try again into the same overloaded model.
 *
 * Sent with `response.sendChunk`, which is a no-op when the caller did not ask
 * for a stream. Nothing here is required for the result to arrive, so a client
 * that calls rather than streams still works unchanged.
 */
export type Report = (update: Record<string, unknown>) => Promise<void>;

/** What a particular job asks of the model, and how long it may take. */
export interface VisionJob {
  /** How the failures name the thing, e.g. "menu reader". */
  subject: string;
  models: string[];
  attemptTimeoutMs: number;
  budgetMs: number;
  retryDelaysMs: number[];
  maxOutputTokens: number;
}

/**
 * Sends the photographs with the instructions and returns the parsed JSON.
 *
 * Shape taken from GenerateContentRequest in the discovery document:
 * `contents` is an array of Content, each with `parts`, and an image part is a
 * `Blob` under `inlineData`.
 */
export async function readPhotosAsJson(
  job: VisionJob,
  options: {
    instructions: string;
    photos: Photo[];
    schema: unknown;
    report: Report;
  }
): Promise<unknown> {
  const body = {
    contents: [
      {
        role: "user",
        parts: [
          { text: options.instructions },
          ...options.photos.map((photo) => ({
            inlineData: { mimeType: photo.mimeType, data: photo.data },
          })),
        ],
      },
    ],
    generationConfig: {
      responseMimeType: "application/json",
      responseSchema: options.schema,
      maxOutputTokens: job.maxOutputTokens,
    },
    // Not stored. `store` defaults to true, which keeps the request — the
    // photograph included — on Google's servers. Nothing here needs it: this
    // is one call, never continued, and what a shop sells and to whom is its
    // own business.
    store: false,
  };

  const text = await callModel(job, JSON.stringify(body), options.report);

  await options.report({ stage: "parsing" });

  try {
    return JSON.parse(text);
  } catch {
    // The schema is supposed to make this impossible. It is checked anyway,
    // because "impossible" here would surface as a type error at the far end
    // of a callable, on a phone, with no stack.
    throw new HttpsError(
      "internal",
      `The ${job.subject} returned something unreadable.`
    );
  }
}

async function callModel(
  job: VisionJob,
  payload: string,
  report: Report
): Promise<string> {
  try {
    return await runLadder({
      models: job.models,
      attemptTimeoutMs: job.attemptTimeoutMs,
      budgetMs: job.budgetMs,
      retryDelaysMs: job.retryDelaysMs,
      report,
      attempt: (model, timeoutMs) =>
        attemptOnce(job, ENDPOINT_FOR(model), payload, model, timeoutMs),
    });
  } catch (error) {
    if (error instanceof LadderFailure) throw translate(job, error);
    throw error;
  }
}

/**
 * The failure the caller is shown, with the technical half in `details`.
 *
 * `details` reaches the client — it is the payload the app puts behind
 * "Details" on the error, so that a test run says `gemini-3.6-flash · 503 ·
 * This model is currently experiencing high demand` instead of a sentence that
 * could mean anything. What it never carries is the response body itself: the
 * request that produced it is the one place here the API key appears, and only
 * Google's own `error.message`, already parsed out and truncated, makes the
 * trip.
 */
function translate(job: VisionJob, failure: LadderFailure): HttpsError {
  const attempt = failure.attempt;

  // Out of budget rather than out of models. Said differently on purpose:
  // "every model refused" and "there was no time left to ask" lead to
  // different next steps.
  if (failure.reason === "outOfTime") {
    return new HttpsError(
      "deadline-exceeded",
      `Reading ran out of time before a model answered. Try again, or with ` +
        `fewer photos.`,
      attempt ? describeAttempt(job, attempt) : { models: job.models }
    );
  }

  if (!attempt) {
    return new HttpsError(
      "internal",
      `The ${job.subject} failed. Please try again.`
    );
  }

  const busy = attempt.status === 429 || attempt.status === 503;
  const stalled = attempt.status === 0;

  return new HttpsError(
    busy ? "resource-exhausted" : stalled ? "deadline-exceeded" : "internal",
    busy
      ? `Every ${job.subject} is busy right now. Try again in a moment.`
      : stalled
        ? `The ${job.subject} did not answer in time. Try again, or with fewer photos.`
        : `The ${job.subject} failed. Please try again.`,
    describeAttempt(job, attempt)
  );
}

function describeAttempt(
  job: VisionJob,
  attempt: Attempt
): Record<string, unknown> {
  return {
    model: attempt.model,
    status: attempt.status,
    upstream: attempt.detail,
    attemptMs: attempt.ms,
    models: job.models,
  };
}

/** The model's text on success, or an [Attempt] saying why not. */
async function attemptOnce(
  job: VisionJob,
  url: string,
  payload: string,
  model: string,
  timeoutMs: number
): Promise<string | Attempt> {
  const started = Date.now();
  // `fetch` has no timeout of its own. Without this an overloaded model can
  // hold the connection for minutes and the only thing that ends it is the
  // function being killed, which is the least informative failure available.
  const controller = new AbortController();
  const alarm = setTimeout(() => controller.abort(), timeoutMs);

  let response: Response;
  try {
    response = await fetch(url, {
      method: "POST",
      headers: {
        "x-goog-api-key": GEMINI_API_KEY.value(),
        "Content-Type": "application/json",
      },
      body: payload,
      signal: controller.signal,
    });
  } catch (error) {
    // Nothing about a transport failure goes back verbatim. It carries the
    // request that produced it, and the request is the one place here the API
    // key appears.
    const aborted = controller.signal.aborted;
    console.error(`${job.subject} transport failure`, model, describe(error));
    return {
      model,
      status: 0,
      detail: aborted
        ? `no answer within ${Math.round(timeoutMs / 1000)}s`
        : "could not reach the model",
      ms: Date.now() - started,
    };
  } finally {
    clearTimeout(alarm);
  }

  if (response.ok) return readText(job, await response.json());

  // Logged in full, returned in part. Cloud Logging is inside the project and
  // an HttpsError is not, so the whole body stays here — a 404 says which
  // model went away and what replaced it — while only the parsed
  // `error.message` travels.
  const body = await response.text();
  console.error(
    `${job.subject} upstream failure`,
    model,
    response.status,
    body.slice(0, 2000)
  );

  return {
    model,
    status: response.status,
    detail: upstreamMessage(body, response.status),
    ms: Date.now() - started,
  };
}

/**
 * Google's own sentence about the failure, or a stand-in.
 *
 * Parsed rather than sliced: an error body is JSON with the useful part at
 * `error.message`, and forwarding raw bytes on the off chance would be
 * forwarding whatever happens to be in them.
 */
function upstreamMessage(body: string, status: number): string {
  try {
    const message = (JSON.parse(body) as { error?: { message?: string } })?.error
      ?.message;
    if (typeof message === "string" && message.trim()) {
      return message.trim().slice(0, 300);
    }
  } catch {
    // Not JSON. Nothing worth forwarding.
  }
  return `HTTP ${status}`;
}

/**
 * Pulls the answer out of a GenerateContentResponse.
 *
 * Two things this must not do. It must not read `parts[0]` — the answer can
 * arrive split across parts. And it must not join parts marked `thought`: the
 * model's own reasoning rides in the same array, and concatenating it into the
 * JSON turns a valid response into a parse error.
 */
function readText(job: VisionJob, payload: unknown): string {
  const candidate = (
    payload as {
      candidates?: {
        finishReason?: string;
        content?: { parts?: { text?: string; thought?: boolean }[] };
      }[];
    }
  )?.candidates?.[0];

  if (!candidate) {
    throw new HttpsError(
      "internal",
      `The ${job.subject} returned nothing to read.`
    );
  }

  // STOP means it finished. MAX_TOKENS means the JSON is cut off mid-object,
  // and parsing it would fail three lines later with a far less useful message.
  if (candidate.finishReason && candidate.finishReason !== "STOP") {
    console.error(`${job.subject} finishReason`, candidate.finishReason);
    throw new HttpsError(
      "internal",
      candidate.finishReason === "MAX_TOKENS"
        ? "That was too long to read in one go. Try one page at a time."
        : `The ${job.subject} stopped early. Please try again.`
    );
  }

  const text = (candidate.content?.parts ?? [])
    .filter((part) => part.thought !== true && typeof part.text === "string")
    .map((part) => part.text)
    .join("");

  if (!text.trim()) {
    throw new HttpsError(
      "internal",
      `The ${job.subject} returned nothing to read.`
    );
  }
  return text;
}

// ---------------------------------------------------------------------------
// What the caller sent, and whether they may
// ---------------------------------------------------------------------------

export function requireUid(request: CallableRequest, action: string): string {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", `Sign in before ${action}.`);
  }
  return uid;
}

export function readPhotos(
  value: unknown,
  limits: { maxPhotos: number; maxChars: number }
): Photo[] {
  if (!Array.isArray(value) || value.length === 0) {
    throw new HttpsError("invalid-argument", "Send at least one photo.");
  }
  if (value.length > limits.maxPhotos) {
    throw new HttpsError(
      "invalid-argument",
      `Send at most ${limits.maxPhotos} photos.`
    );
  }

  return value.map((entry) => {
    const photo = (entry ?? {}) as Record<string, unknown>;
    const data = photo.data;
    const mimeType = photo.mimeType;

    if (typeof data !== "string" || !data) {
      throw new HttpsError(
        "invalid-argument",
        "A photo arrived with no image data."
      );
    }
    if (data.length > limits.maxChars) {
      throw new HttpsError(
        "invalid-argument",
        "That photo is too large. Take it again at a lower resolution."
      );
    }
    if (
      mimeType !== "image/jpeg" &&
      mimeType !== "image/png" &&
      mimeType !== "image/webp"
    ) {
      throw new HttpsError("invalid-argument", "Photos must be JPEG, PNG or WebP.");
    }

    return { mimeType, data };
  });
}

/** For the log only — never for a client, and never the key. */
function describe(error: unknown): string {
  return error instanceof Error ? error.message : "Recognition failed.";
}
