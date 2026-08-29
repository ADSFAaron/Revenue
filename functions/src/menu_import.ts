/**
 * Reading a menu off a photograph.
 *
 * The hard part of this is not the OCR. It is that a menu is a *layout*: two
 * columns, prices right-aligned, a decorative heading every ten dishes, and
 * half a page of whitespace between "牛肉麵" and the "120" that belongs to it.
 * A text recogniser hands back lines and bounding boxes and leaves the pairing
 * to whoever called it — which is the whole job, and it is different for every
 * shop. A vision model does the pairing itself, because it is reading for
 * meaning rather than for glyphs, so that is the route taken here.
 *
 * This function recognises and returns. **It writes nothing.** The draft goes
 * back to the app, a person corrects it on screen, and the existing
 * `MenuRepository` does the writing under the rules that already govern it.
 * Writing here would mean a store that wanted to undo an import had to delete
 * dishes one at a time — and menu items are retired rather than deleted, so
 * "undo" would leave a drawer full of inactive dishes nobody can explain.
 *
 * It also cannot live in the app: the model needs an API key, and a key
 * shipped inside an APK is a key anybody can read out of it.
 */

import { getFirestore } from "firebase-admin/firestore";
import { HttpsError, onCall, CallableRequest } from "firebase-functions/v2/https";
import { defineSecret } from "firebase-functions/params";

import { MAX_INSTANCES, REGION } from "./config.js";

/**
 * Set with `firebase functions:secrets:set GEMINI_API_KEY`. Bound to this one
 * function rather than the project, so the passkey functions never see it.
 */
const GEMINI_API_KEY = defineSecret("GEMINI_API_KEY");

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

/**
 * Tried in order. Every one was verified against `GET /v1beta/models` on this
 * project's key and then called with this exact request: all four returned the
 * same seventeen dishes off the same photograph.
 *
 * The list is not belt-and-braces. `gemini-3.7-flash` answered 503 UNAVAILABLE
 * four times in a row during testing — often enough that retrying one model is
 * not a plan, because the thing that is failing is that model. Falling to the
 * previous generation costs a little quality on a job that is checked by a
 * person anyway, and costs nothing at all when the first choice is healthy.
 *
 * `gemini-2.5-flash` is deliberately absent: it returns 404 with "no longer
 * available to new users".
 */
const MODELS = ["gemini-3.7-flash", "gemini-3.6-flash", "gemini-3.5-flash"];

/**
 * Enough room for a long menu plus the model's own reasoning, which is billed
 * and capped as output. Seventeen dishes measured 1,014 output tokens, so an
 * eighty-dish menu lands near 5,000; the ceiling is set well clear of that
 * because the failure mode is a `MAX_TOKENS` finish and a half-written JSON
 * object, which is worse than a slightly larger bill.
 */
const MAX_OUTPUT_TOKENS = 32768;

/**
 * Backoff between attempts on one model before moving to the next. A recognised
 * menu took roughly 22 seconds, so two attempts each across three models still
 * lands inside the function's 300-second budget with room to spare.
 */
const RETRY_DELAYS_MS = [2_000, 6_000];

/**
 * A menu is one to four photographs — a folded card has two sides, a wall
 * board might take two shots to stay legible. The cap is here because inline
 * image bytes are capped at 20MB for the whole request and because a hundred
 * photos is not a menu, it is somebody holding down the shutter.
 */
const MAX_PHOTOS = 4;

/** Per photo, base64. The app downsamples to a 1568px long edge first. */
const MAX_PHOTO_CHARS = 4_000_000;

/**
 * Recognition takes a while — twenty to forty seconds for one photo, more for
 * four. The v2 default is sixty seconds, which a two-page menu would trip over
 * often enough to look broken. The Dart side has to agree; see
 * `menuImportTimeout` in lib/database/menu_import_repository.dart.
 */
const TIMEOUT_SECONDS = 300;

/**
 * What the model is required to fill in.
 *
 * Two decisions are worth naming. **`variant` is separate from `name`** so the
 * app composes the displayed string itself: asked for one field the model
 * returns "牛肉麵 大" one time and "牛肉麵(大)" the next, and two dishes that
 * differ only by their separator are two dishes forever. **`needsReview` is
 * the model's own hedge**, and it is not trusted on its own — the app applies
 * arithmetic checks of its own on top, because a price read confidently and
 * wrongly is exactly the case a self-reported flag misses.
 */
const RESPONSE_SCHEMA = {
  type: "OBJECT",
  properties: {
    categories: {
      type: "ARRAY",
      description:
        "Section headings printed on the menu, in the order they appear. " +
        "Empty if the menu has no headings.",
      items: { type: "STRING" },
    },
    items: {
      type: "ARRAY",
      items: {
        type: "OBJECT",
        properties: {
          name: {
            type: "STRING",
            description:
              "The dish name alone. No price, no portion size, no currency.",
          },
          variant: {
            type: "STRING",
            nullable: true,
            description:
              "The portion or option this price is for — 大, 小, 套餐, 加蛋 — " +
              "or null when the dish is sold at a single price.",
          },
          price: {
            type: "INTEGER",
            description: "Price in whole New Taiwan dollars.",
          },
          category: {
            type: "STRING",
            nullable: true,
            description:
              "Which of `categories` this dish sits under, copied exactly, " +
              "or null if the menu has no headings.",
          },
          needsReview: {
            type: "BOOLEAN",
            description:
              "True when the photo does not let you be certain of this row — " +
              "blurred, cut off, obscured, or a price you had to guess at.",
          },
          reviewNote: {
            type: "STRING",
            nullable: true,
            description:
              "One short phrase saying what was unclear. Null when " +
              "needsReview is false.",
          },
        },
        required: ["name", "variant", "price", "category", "needsReview", "reviewNote"],
        propertyOrdering: ["name", "variant", "price", "category", "needsReview", "reviewNote"],
      },
    },
  },
  required: ["categories", "items"],
  propertyOrdering: ["categories", "items"],
};

const INSTRUCTIONS = [
  "You are reading a restaurant menu from Taiwan so it can be typed into a",
  "point-of-sale app. Transcribe every dish you can see, with its price.",
  "",
  "Rules:",
  "- Prices are New Taiwan dollars and are whole numbers. Drop any $ or NT$.",
  "- A dish sold at more than one price is more than one entry. 牛肉麵 大130/小100",
  "  is two entries: {name:牛肉麵, variant:大, price:130} and",
  "  {name:牛肉麵, variant:小, price:100}. Never put two prices in one entry and",
  "  never put the portion word in `name`.",
  "- Keep the characters exactly as printed. This menu is Traditional Chinese;",
  "  do not convert anything to Simplified.",
  "- Transcribe what is printed. Do not invent dishes a real menu would have,",
  "  do not complete a section that is cut off, and do not tidy up names.",
  "- If a price is unreadable, still return the dish, set needsReview to true",
  "  and put your best guess in price. A dish flagged for checking is useful;",
  "  a dish silently dropped is not.",
  "- Ignore anything that is not a dish and a price: opening hours, the phone",
  "  number, the wifi password, 內用/外帶 notices.",
].join("\n");

/** One dish as the model returned it, before the app has looked at it. */
interface DraftItem {
  name: string;
  variant: string | null;
  price: number;
  category: string | null;
  needsReview: boolean;
  reviewNote: string | null;
}

export const importMenuFromPhotos = onCall(
  {
    region: REGION,
    maxInstances: MAX_INSTANCES,
    timeoutSeconds: TIMEOUT_SECONDS,
    // Four photos held as base64 in memory, plus the response. The 256MiB
    // default is enough until it is not, and the failure mode is an opaque
    // crash rather than an error.
    memory: "512MiB",
    secrets: [GEMINI_API_KEY],
  },
  async (request) => {
    const uid = requireUid(request);
    await requireMenuEditor(uid);

    const photos = readPhotos(request.data?.photos);
    const draft = await recognise(photos);

    return {
      categories: draft.categories,
      items: draft.items,
    };
  }
);

// ---------------------------------------------------------------------------
// The model call
// ---------------------------------------------------------------------------

async function recognise(
  photos: { mimeType: string; data: string }[]
): Promise<{ categories: string[]; items: DraftItem[] }> {
  const body = {
    // One user turn holding the instructions and every photograph. Shape taken
    // from GenerateContentRequest in the discovery document: `contents` is an
    // array of Content, each with `parts`, and an image part is a `Blob` under
    // `inlineData`.
    contents: [
      {
        role: "user",
        parts: [
          { text: INSTRUCTIONS },
          ...photos.map((photo) => ({
            inlineData: { mimeType: photo.mimeType, data: photo.data },
          })),
        ],
      },
    ],
    generationConfig: {
      responseMimeType: "application/json",
      responseSchema: RESPONSE_SCHEMA,
      maxOutputTokens: MAX_OUTPUT_TOKENS,
    },
    // Not stored. `store` defaults to true, which keeps the request — the menu
    // photograph included — on Google's servers. Nothing here needs it: this is
    // one call, never continued, and a shop's price list is its own business.
    store: false,
  };

  const text = await callModel(JSON.stringify(body));

  let parsed: unknown;
  try {
    parsed = JSON.parse(text);
  } catch {
    // The schema is supposed to make this impossible. It is checked anyway,
    // because "impossible" here would surface as a type error at the far end
    // of a callable, on a phone, with no stack.
    throw new HttpsError("internal", "The menu reader returned something unreadable.");
  }

  return normalise(parsed);
}

/**
 * Posts the request and returns the model's text, retrying the failures that
 * are worth retrying.
 *
 * 503 is not an edge case here. `gemini-3.7-flash` returns it under load often
 * enough to hit twice in a handful of manual calls, and a shop photographing a
 * menu once should not be told to come back later because the model was busy
 * for two seconds.
 */
async function callModel(payload: string): Promise<string> {
  let lastStatus = 0;

  for (const model of MODELS) {
    for (let attempt = 0; attempt <= RETRY_DELAYS_MS.length; attempt++) {
      if (attempt > 0) {
        await new Promise((r) => setTimeout(r, RETRY_DELAYS_MS[attempt - 1]));
      }

      const outcome = await attemptOnce(ENDPOINT_FOR(model), payload, model);
      if (typeof outcome === "string") return outcome;

      lastStatus = outcome;
      // 503 is the model being busy and 429 is the quota being hot; both are
      // worth another go, and then worth another model. A 400 or a 403 is this
      // code or this key being wrong, and no amount of waiting or switching
      // fixes either — retrying those just spends the timeout.
      if (outcome !== 503 && outcome !== 429) {
        throw failure(outcome);
      }
    }
  }

  throw failure(lastStatus);
}

function failure(status: number): HttpsError {
  const busy = status === 429 || status === 503;
  return new HttpsError(
    busy ? "resource-exhausted" : "internal",
    busy
      ? "The menu reader is busy right now. Try again in a moment."
      : "The menu reader failed. Please try again."
  );
}

/** The model's text on success, or the HTTP status that says why not. */
async function attemptOnce(
  url: string,
  payload: string,
  model: string
): Promise<string | number> {
  {
    let response: Response;
    try {
      response = await fetch(url, {
        method: "POST",
        headers: {
          "x-goog-api-key": GEMINI_API_KEY.value(),
          "Content-Type": "application/json",
        },
        body: payload,
      });
    } catch (error) {
      // Nothing about a transport failure goes back to the caller. It carries
      // the request that produced it, and the request is the one place in this
      // file the API key appears.
      console.error("menu import transport failure", describe(error));
      throw new HttpsError(
        "unavailable",
        "Could not reach the menu reader. Check the connection and try again."
      );
    }

    if (response.ok) return readText(await response.json());

    // Logged, never returned, and truncated. Google's error bodies do not echo
    // the key back, but they are not this codebase's to guarantee, and Cloud
    // Logging is inside the project while an HttpsError detail is not. The
    // body is the useful half: a 404 here says which model went away and what
    // replaced it.
    console.error(
      "menu import upstream failure",
      model,
      response.status,
      (await response.text()).slice(0, 2000)
    );
    return response.status;
  }
}

/**
 * Pulls the answer out of a GenerateContentResponse.
 *
 * Two things this must not do. It must not read `parts[0]` — the answer can
 * arrive split across parts. And it must not join parts marked `thought`: the
 * model's own reasoning rides in the same array, and concatenating it into the
 * JSON turns a valid response into a parse error.
 */
function readText(payload: unknown): string {
  const candidate = (payload as {
    candidates?: {
      finishReason?: string;
      content?: { parts?: { text?: string; thought?: boolean }[] };
    }[];
  })?.candidates?.[0];

  if (!candidate) {
    throw new HttpsError("internal", "The menu reader returned nothing to read.");
  }

  // STOP means it finished. MAX_TOKENS means the JSON is cut off mid-object,
  // and parsing it would fail three lines later with a far less useful message.
  if (candidate.finishReason && candidate.finishReason !== "STOP") {
    console.error("menu import finishReason", candidate.finishReason);
    throw new HttpsError(
      "internal",
      candidate.finishReason === "MAX_TOKENS"
        ? "That menu was too long to read in one go. Try one page at a time."
        : "The menu reader stopped early. Please try again."
    );
  }

  const text = (candidate.content?.parts ?? [])
    .filter((part) => part.thought !== true && typeof part.text === "string")
    .map((part) => part.text)
    .join("");

  if (!text.trim()) {
    throw new HttpsError("internal", "The menu reader returned nothing to read.");
  }
  return text;
}

/**
 * Trims the model's answer down to what the app can use.
 *
 * Deliberately shallow: it drops rows that cannot become a dish and clamps
 * prices into range, and it does no judging. Deciding which rows look wrong
 * happens in the app, where the checks can run again each time somebody edits
 * a row — a rule that only ever runs here would go stale the moment a price
 * was corrected on screen.
 */
function normalise(parsed: unknown): { categories: string[]; items: DraftItem[] } {
  const root = (parsed ?? {}) as { categories?: unknown; items?: unknown };

  const categories = Array.isArray(root.categories)
    ? root.categories
        .filter((c): c is string => typeof c === "string" && c.trim().length > 0)
        .map((c) => c.trim())
    : [];

  const rows = Array.isArray(root.items) ? root.items : [];
  const items: DraftItem[] = [];

  for (const row of rows) {
    if (typeof row !== "object" || row === null) continue;
    const r = row as Record<string, unknown>;

    const name = typeof r.name === "string" ? r.name.trim() : "";
    if (!name) continue;

    // A negative price, or one with more digits than money has, is a
    // misreading rather than a bargain. Clamped rather than dropped, and the
    // app's own checks will push it to the top of the review list.
    const raw = typeof r.price === "number" ? Math.round(r.price) : 0;
    const price = Number.isFinite(raw) ? Math.min(Math.max(raw, 0), 100_000) : 0;

    const variant = typeof r.variant === "string" && r.variant.trim() ? r.variant.trim() : null;
    const category = typeof r.category === "string" && r.category.trim() ? r.category.trim() : null;
    const reviewNote =
      typeof r.reviewNote === "string" && r.reviewNote.trim() ? r.reviewNote.trim() : null;

    items.push({
      name,
      variant,
      price,
      category,
      needsReview: r.needsReview === true,
      reviewNote,
    });
  }

  return { categories, items };
}

// ---------------------------------------------------------------------------
// What the caller is allowed to do
// ---------------------------------------------------------------------------

function requireUid(request: CallableRequest): string {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Sign in before importing a menu.");
  }
  return uid;
}

/**
 * Only an owner or a manager may import.
 *
 * The same rule already guards `menuItems` in firestore.rules, but rules
 * cannot reach this far: they govern documents, and this is a paid call to a
 * third party. Without the check here, any signed-in member of staff could
 * spend the store's quota by photographing whatever they liked.
 *
 * The role is read from `users/{uid}` rather than taken from the request. A
 * client that could name its own role would not be a check.
 */
async function requireMenuEditor(uid: string): Promise<void> {
  const doc = await getFirestore().collection("users").doc(uid).get();
  const role = doc.data()?.role;
  if (role !== "owner" && role !== "manager") {
    throw new HttpsError(
      "permission-denied",
      "Only an owner or a manager can import a menu."
    );
  }
}

function readPhotos(value: unknown): { mimeType: string; data: string }[] {
  if (!Array.isArray(value) || value.length === 0) {
    throw new HttpsError("invalid-argument", "Send at least one photo.");
  }
  if (value.length > MAX_PHOTOS) {
    throw new HttpsError(
      "invalid-argument",
      `A menu can be up to ${MAX_PHOTOS} photos.`
    );
  }

  return value.map((entry) => {
    const photo = (entry ?? {}) as Record<string, unknown>;
    const data = photo.data;
    const mimeType = photo.mimeType;

    if (typeof data !== "string" || !data) {
      throw new HttpsError("invalid-argument", "A photo arrived with no image data.");
    }
    if (data.length > MAX_PHOTO_CHARS) {
      throw new HttpsError(
        "invalid-argument",
        "That photo is too large. Take it again at a lower resolution."
      );
    }
    if (mimeType !== "image/jpeg" && mimeType !== "image/png" && mimeType !== "image/webp") {
      throw new HttpsError("invalid-argument", "Photos must be JPEG, PNG or WebP.");
    }

    return { mimeType, data };
  });
}

/** For the log only — never for a client, and never the key. */
function describe(error: unknown): string {
  return error instanceof Error ? error.message : "Recognition failed.";
}
