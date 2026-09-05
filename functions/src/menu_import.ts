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
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { reserveMenuImport } from "./quota.js";

import { CALLABLE_OPTIONS } from "./config.js";
import {
  GEMINI_API_KEY,
  Photo,
  Report,
  VisionJob,
  readPhotos,
  readPhotosAsJson,
  requireUid,
} from "./gemini.js";

/**
 * Tried in order. Every one was verified against `GET /v1beta/models` on this
 * project's key and then called with this exact request: all four returned the
 * same seventeen dishes off the same photograph.
 *
 * **`gemini-3.6-flash` leads, not `gemini-3.7-flash`.** The newer model is the
 * better one and it is still on the list, but across every run logged so far it
 * has answered 503 UNAVAILABLE or not answered at all — and it does not refuse
 * quickly, it holds the connection for the full minute first. Leading with it
 * meant every single import paid sixty seconds for a model that was down before
 * the fallback was even reached. Order is a claim about availability, not about
 * quality, and this is a job a person checks line by line afterwards.
 *
 * Worth revisiting when the congestion clears: put 3.7 back in front and the
 * ladder costs nothing when it is healthy.
 *
 * `gemini-2.5-flash` is deliberately absent: it returns 404 with "no longer
 * available to new users".
 */
const MODELS = ["gemini-3.6-flash", "gemini-3.7-flash", "gemini-3.5-flash"];

/**
 * Enough room for a long menu plus the model's own reasoning, which is billed
 * and capped as output. Seventeen dishes measured 1,014 output tokens, so an
 * eighty-dish menu lands near 5,000; the ceiling is set well clear of that
 * because the failure mode is a `MAX_TOKENS` finish and a half-written JSON
 * object, which is worse than a slightly larger bill.
 */
const MAX_OUTPUT_TOKENS = 32768;

/**
 * Backoff between the two attempts on one model before moving to the next.
 *
 * There used to be two delays here — three attempts per model — sized on the
 * assumption that an attempt costs about what a successful one costs, roughly
 * twenty-two seconds. A production trace says otherwise. When
 * `gemini-3.7-flash` is overloaded it does not refuse quickly; it holds the
 * connection and *then* returns 503:
 *
 *   05:53:26 call arrives
 *   05:55:42 gemini-3.7-flash 503   (136s)
 *   05:55:56 gemini-3.7-flash 503   ( 12s)
 *   05:57:47 gemini-3.7-flash 503   (105s)
 *            budget gone; the fallback models were never tried
 *
 * Nine attempts is a plan for fast failures. Against slow ones it is a way to
 * spend the entire budget on the one model that is down — the exact case the
 * fallback list exists for. Two attempts per model, and [ATTEMPT_TIMEOUT_MS]
 * to stop a hung one eating the rest.
 */
const RETRY_DELAYS_MS = [2_000];

/**
 * How long one call to the model may take before it is abandoned.
 *
 * A successful recognition is twenty to forty seconds, so sixty leaves room
 * for a slow four-photo menu and still cuts off the two-minute non-answer
 * above. Enforced with an `AbortController`: without one `fetch` has no
 * timeout at all and the only limit is the function's, which is the whole
 * problem.
 */
const ATTEMPT_TIMEOUT_MS = 60_000;

/**
 * The wall clock this function gives itself, against [TIMEOUT_SECONDS] of 300.
 *
 * Set below the platform's limit on purpose. Run out of this and the caller
 * gets a written error naming the model and the status that caused it; run out
 * of the platform's and the request is simply severed, which reaches the phone
 * as the same "took too long" whatever actually happened. The sixty seconds of
 * headroom is one attempt's worth, so the check before each attempt can be
 * honest about whether there is time for it.
 */
const OVERALL_BUDGET_MS = 240_000;

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
    ...CALLABLE_OPTIONS,
    timeoutSeconds: TIMEOUT_SECONDS,
    // Four photos held as base64 in memory, plus the response. The 256MiB
    // default is enough until it is not, and the failure mode is an opaque
    // crash rather than an error.
    memory: "512MiB",
    secrets: [GEMINI_API_KEY],
  },
  async (request, response) => {
    const started = Date.now();
    const report: Report = async (update) => {
      await response?.sendChunk({ ...update, elapsedMs: Date.now() - started });
    };

    const uid = requireUid(request, "importing a menu");
    const storeId = await requireMenuEditor(uid);

    const photos = readPhotos(request.data?.photos, {
      maxPhotos: MAX_PHOTOS,
      maxChars: MAX_PHOTO_CHARS,
    });
    // After the photos are validated and before any model is reached: a
    // request that was never going to be sent should not spend an allowance,
    // and one that is about to be sent must not escape counting.
    await reserveMenuImport(storeId);
    // "received", not "sending" — the app has already said it is sending, and
    // this frame is what lets it tick that step off. The gap between the two is
    // the upload, which on a shop's connection is the part worth showing.
    await report({ stage: "received", photos: photos.length });

    const draft = await recognise(photos, report);

    return {
      categories: draft.categories,
      items: draft.items,
    };
  }
);

// ---------------------------------------------------------------------------
// The model call
// ---------------------------------------------------------------------------

/** Everything the transport needs to know about this particular job. */
const JOB: VisionJob = {
  subject: "menu reader",
  models: MODELS,
  attemptTimeoutMs: ATTEMPT_TIMEOUT_MS,
  budgetMs: OVERALL_BUDGET_MS,
  retryDelaysMs: RETRY_DELAYS_MS,
  maxOutputTokens: MAX_OUTPUT_TOKENS,
};

async function recognise(
  photos: Photo[],
  report: Report
): Promise<{ categories: string[]; items: DraftItem[] }> {
  const parsed = await readPhotosAsJson(JOB, {
    instructions: INSTRUCTIONS,
    photos,
    schema: RESPONSE_SCHEMA,
    report,
  });

  return normalise(parsed);
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
 *
 * Note what this does *not* do. Registration makes you the owner of a new
 * store, so a stranger is an owner as soon as they want to be — this check
 * protects a shop from its own staff, not the project from the internet. That
 * is what the counters in quota.ts are for.
 */
async function requireMenuEditor(uid: string): Promise<string> {
  const doc = await getFirestore().collection("users").doc(uid).get();
  const data = doc.data();
  const role = data?.role;
  if (role !== "owner" && role !== "manager") {
    throw new HttpsError(
      "permission-denied",
      "Only an owner or a manager can import a menu."
    );
  }
  // Returned rather than read again: the usage counter is per store, and this
  // is the only place the store is established from something the caller
  // cannot choose.
  const storeId = data?.storeId;
  if (typeof storeId !== "string" || !storeId) {
    throw new HttpsError(
      "failed-precondition",
      "This account is not linked to a store."
    );
  }
  return storeId;
}
