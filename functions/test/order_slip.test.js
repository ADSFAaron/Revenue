// CommonJS: `functions/package.json` has no `"type": "module"`, so tsc's
// NodeNext output is CJS and this has to match it.
const assert = require("node:assert/strict");
const { describe, it } = require("node:test");

const { normalise } = require("../lib/order_slip.js");

/**
 * The check that makes this a closed-set match rather than free-text OCR
 * wearing one as a costume.
 *
 * Everything else in `order_slip.ts` is a socket, a prompt or a permission.
 * This function is the safety property: whatever the model says, only ids that
 * were on the menu it was handed may come out. Without it, a model that
 * invented `beef-noodle-large` would put a dish on somebody's order that the
 * shop does not sell, at a price nothing knows.
 */
const MENU = [
  { id: "noodles", name: "牛肉麵", aliases: [] },
  { id: "rice", name: "滷肉飯", aliases: ["肉燥飯"] },
];

describe("normalise", () => {
  it("keeps the lines that name a dish on the menu", () => {
    const out = normalise(
      { lines: [{ itemId: "noodles", qty: 2, sure: true }], unreadable: [] },
      MENU
    );

    assert.deepEqual(out.lines, [{ itemId: "noodles", qty: 2, sure: true }]);
    assert.equal(out.unmatched, 0);
  });

  it("drops an id the model invented, and says how many", () => {
    // The whole reason the menu goes into the prompt. A non-zero `unmatched`
    // reaching the app means the closed set is not holding.
    const out = normalise(
      {
        lines: [
          { itemId: "noodles", qty: 1, sure: true },
          { itemId: "beef-noodle-large", qty: 1, sure: true },
        ],
        unreadable: [],
      },
      MENU
    );

    assert.deepEqual(out.lines.map((l) => l.itemId), ["noodles"]);
    assert.equal(out.unmatched, 1);
  });

  it("merges the same dish ticked twice into one line", () => {
    // Two lines for one dish is a basket somebody has to reconcile by eye.
    const out = normalise(
      {
        lines: [
          { itemId: "rice", qty: 1, sure: true },
          { itemId: "rice", qty: 2, sure: false },
        ],
        unreadable: [],
      },
      MENU
    );

    assert.equal(out.lines.length, 1);
    assert.equal(out.lines[0].qty, 3);
    assert.equal(out.lines[0].sure, false, "unsure is sticky across a merge");
  });

  it("caps a quantity rather than trusting it", () => {
    // A misread `11` for `1` is a mistake somebody catches. A misread that puts
    // 8,000 bowls in the basket is a scroll they have to fight out of.
    const out = normalise(
      { lines: [{ itemId: "rice", qty: 8000, sure: true }], unreadable: [] },
      MENU
    );

    assert.equal(out.lines[0].qty, 99);
  });

  it("throws away a line with no usable quantity", () => {
    const out = normalise(
      {
        lines: [
          { itemId: "rice", qty: 0, sure: true },
          { itemId: "rice", qty: -3, sure: true },
          { itemId: "noodles", qty: "two", sure: true },
        ],
        unreadable: [],
      },
      MENU
    );

    assert.deepEqual(out.lines, []);
    assert.equal(out.unmatched, 0, "these named real dishes; they had no count");
  });

  it("survives a response that is not the shape it asked for", () => {
    // The schema is meant to make this impossible. It is handled anyway,
    // because "impossible" here would be a crash on a phone with no stack.
    for (const junk of [null, {}, { lines: "no" }, { lines: [null, 7] }]) {
      const out = normalise(junk, MENU);
      assert.deepEqual(out.lines, []);
      assert.deepEqual(out.unreadable, []);
    }
  });

  it("clips what it echoes back to the screen", () => {
    const out = normalise(
      {
        lines: [],
        unreadable: [
          "x".repeat(500),
          ...Array.from({ length: 40 }, (_, i) => `note ${i}`),
        ],
      },
      MENU
    );

    assert.equal(out.unreadable.length, 20);
    assert.equal(out.unreadable[0].length, 120);
  });
});
