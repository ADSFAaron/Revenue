import 'package:flutter/material.dart';

/// The icons a dish is allowed to wear.
///
/// **Why a hand-picked list rather than a picker over the whole icon font.**
///
/// Two reasons, and the second one is the reason the old picker was empty.
///
/// The first is that six thousand Material icons is not a better choice than
/// fifty, it is a worse one. Nobody arranging a menu wants to scroll past
/// `bluetooth_audio` and `flight_takeoff` to find something that looks like a
/// bowl of noodles, and the search only helps if you already guessed the
/// English word the icon was filed under. Fifty icons that are all plausibly
/// food fit on two screens and need no search at all.
///
/// The second is that Flutter only ships the glyphs it can *see* being used.
/// `flutter build --release` runs `--tree-shake-icons`, which keeps the code
/// points that appear in `const IconData` expressions and drops the rest — so
/// an `IconData(someCodePointFromTheDatabase)` renders as whatever happens to
/// still be in the font, which is how every dish on the menu ended up showing
/// `security_update_warning`. Every icon here is a `const`, and [resolve] only
/// ever returns one of them, so what a shop picks is what a shop sees.
class DishIcon {
  const DishIcon(this.name, this.icon);

  /// What it is called on screen, and what the search matches against.
  final String name;

  final IconData icon;

  /// What gets written to Firestore. Stored as a string because that is what
  /// `MenuItem.icon` has always been and existing menus are full of them.
  String get codePoint => icon.codePoint.toString();
}

/// The default, and the one every unrecognised code point falls back to.
const DishIcon kDefaultDishIcon = DishIcon('Dish', Icons.restaurant);

/// Grouped roughly the way a menu is, so the list itself reads as a menu.
const List<DishIcon> kDishIcons = [
  // Mains
  kDefaultDishIcon,
  DishIcon('Menu', Icons.restaurant_menu),
  DishIcon('Noodles', Icons.ramen_dining),
  DishIcon('Rice', Icons.rice_bowl),
  DishIcon('Set meal', Icons.set_meal),
  DishIcon('Dinner', Icons.dinner_dining),
  DishIcon('Lunch', Icons.lunch_dining),
  DishIcon('Breakfast', Icons.breakfast_dining),
  DishIcon('Brunch', Icons.brunch_dining),
  DishIcon('Dining', Icons.dining),
  DishIcon('Cutlery', Icons.flatware),
  DishIcon('Fast food', Icons.fastfood),
  DishIcon('Pizza', Icons.local_pizza),
  DishIcon('Skewers', Icons.kebab_dining),
  DishIcon('Grill', Icons.outdoor_grill),

  // Soups and sides
  DishIcon('Soup', Icons.soup_kitchen),
  DishIcon('Small plates', Icons.tapas),
  DishIcon('Egg', Icons.egg),
  DishIcon('Fried egg', Icons.egg_alt),
  DishIcon('Greens', Icons.grass),
  DishIcon('Vegetarian', Icons.eco),
  DishIcon('Herbs', Icons.spa),
  DishIcon('Produce', Icons.agriculture),
  DishIcon('Garnish', Icons.local_florist),

  // Sweet
  DishIcon('Cake', Icons.cake),
  DishIcon('Ice cream', Icons.icecream),
  DishIcon('Cookie', Icons.cookie),
  DishIcon('Bakery', Icons.bakery_dining),

  // Drinks
  DishIcon('Coffee', Icons.coffee),
  DishIcon('Cafe', Icons.local_cafe),
  DishIcon('Tea', Icons.emoji_food_beverage),
  DishIcon('Cold drink', Icons.local_drink),
  DishIcon('Water', Icons.water_drop),
  DishIcon('Coffee machine', Icons.coffee_maker),
  DishIcon('Beer', Icons.sports_bar),
  DishIcon('Wine', Icons.wine_bar),
  DishIcon('Cocktail', Icons.local_bar),
  DishIcon('Spirits', Icons.liquor),
  DishIcon('Late night', Icons.nightlife),

  // How it leaves the kitchen
  DishIcon('Takeaway', Icons.takeout_dining),
  DishIcon('Delivery', Icons.delivery_dining),
  DishIcon('Hot', Icons.local_fire_department),
  DishIcon('Spicy', Icons.whatshot),
  DishIcon('Chilled', Icons.ac_unit),
  DishIcon('Fridge', Icons.kitchen),
  DishIcon('Microwave', Icons.microwave),
  DishIcon('Blender', Icons.blender),
  DishIcon('Local dish', Icons.local_dining),
  DishIcon('Pantry', Icons.food_bank),
];

/// The icon for a stored code point.
///
/// Falls back rather than throwing, and that fallback is doing real work: a
/// menu imported before this list existed is full of code points that are not
/// on it — including `0xe56c`, which used to be the app's default and is
/// `security_update_warning` in current Flutter, which is why every dish was
/// wearing a phone with a warning triangle on it.
DishIcon resolveDishIcon(String? codePoint) {
  final parsed = codePoint == null ? null : int.tryParse(codePoint);
  if (parsed == null) return kDefaultDishIcon;
  for (final candidate in kDishIcons) {
    if (candidate.icon.codePoint == parsed) return candidate;
  }
  return kDefaultDishIcon;
}

/// Opens the grid and returns what was chosen, or null if it was dismissed.
Future<DishIcon?> pickDishIcon(
  BuildContext context, {
  String? selected,
}) =>
    showDialog<DishIcon>(
      context: context,
      builder: (context) => _DishIconDialog(selected: selected),
    );

class _DishIconDialog extends StatelessWidget {
  const _DishIconDialog({this.selected});

  final String? selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final current = resolveDishIcon(selected);

    return AlertDialog(
      title: const Text('Pick an icon'),
      // The whole list fits in a couple of screens, so there is no search box.
      // A search over fifty items is a box that asks you to think of a word
      // before it will show you anything.
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              for (final choice in kDishIcons)
                Tooltip(
                  message: choice.name,
                  child: IconButton(
                    icon: Icon(choice.icon),
                    iconSize: 28,
                    isSelected: choice.icon.codePoint == current.icon.codePoint,
                    selectedIcon: Icon(choice.icon, color: scheme.onPrimary),
                    style: IconButton.styleFrom(
                      backgroundColor:
                          choice.icon.codePoint == current.icon.codePoint
                              ? scheme.primary
                              : null,
                    ),
                    onPressed: () => Navigator.pop(context, choice),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
