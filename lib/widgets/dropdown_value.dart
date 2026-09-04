/// The value a dropdown may safely be shown.
///
/// `DropdownButton` asserts that exactly one of its items carries its value,
/// and the assertion is fatal: the screen is replaced by a red page reading
/// "There should be exactly one item with [DropdownButton]'s value". It is not
/// a hypothetical. Every dropdown in this app is filled from data somebody else
/// can change — a dish keeps pointing at a category after the category is
/// deleted, an order keeps a delivery platform after the platform is removed
/// from the store, a hand-edited `dayCutoffHour` arrives as 25 — and each of
/// those opens a screen that then cannot be closed.
///
/// Returning null instead shows the dropdown empty, which is the truth: the
/// thing it was pointing at is gone, and picking again is the only way forward.
///
///     value: dropdownValue(item.categoryId, categories.map((c) => c.id)),
T? dropdownValue<T>(T? value, Iterable<T?> available) =>
    available.contains(value) ? value : null;
