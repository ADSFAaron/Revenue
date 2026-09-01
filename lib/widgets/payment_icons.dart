import 'package:flutter/material.dart';

/// The icons a payment method is allowed to wear.
///
/// A fixed list of `const IconData`, and keyed by a name rather than by a code
/// point, for the reason spelled out at length in `dish_icons.dart`: a release
/// build runs `--tree-shake-icons` and keeps only the glyphs it can see used in
/// `const IconData` expressions, so an icon reconstructed from a number in
/// Firestore renders as whatever happens to have survived. Storing the key
/// means a shop's 悠遊卡 icon is still that icon after the next build.
class PaymentIcon {
  const PaymentIcon(this.key, this.name, this.icon);

  /// What is written to Firestore.
  final String key;

  /// What it is called in the picker.
  final String name;

  final IconData icon;
}

/// The fallback, and what an unrecognised key resolves to.
const PaymentIcon kDefaultPaymentIcon =
    PaymentIcon('more', 'Other', Icons.more_horiz_rounded);

const List<PaymentIcon> kPaymentIcons = [
  PaymentIcon('cash', 'Cash', Icons.payments_rounded),
  PaymentIcon('coins', 'Coins', Icons.savings_rounded),
  PaymentIcon('card', 'Card', Icons.credit_card_rounded),
  PaymentIcon('contactless', 'Contactless', Icons.contactless_rounded),
  PaymentIcon('phone', 'Mobile pay', Icons.smartphone_rounded),
  PaymentIcon('qr', 'QR code', Icons.qr_code_2_rounded),
  PaymentIcon('wallet', 'Wallet', Icons.account_balance_wallet_rounded),
  PaymentIcon('bank', 'Bank transfer', Icons.account_balance_rounded),
  PaymentIcon('receipt', 'On account', Icons.receipt_long_rounded),
  PaymentIcon('voucher', 'Voucher', Icons.confirmation_number_rounded),
  PaymentIcon('gift', 'Gift card', Icons.card_giftcard_rounded),
  PaymentIcon('loyalty', 'Points', Icons.loyalty_rounded),
  PaymentIcon('percent', 'Staff / comp', Icons.percent_rounded),
  kDefaultPaymentIcon,
];

PaymentIcon resolvePaymentIcon(String? key) {
  for (final candidate in kPaymentIcons) {
    if (candidate.key == key) return candidate;
  }
  return kDefaultPaymentIcon;
}

/// The glyph for a stored key — what nearly every caller actually wants.
IconData paymentIconData(String? key) => resolvePaymentIcon(key).icon;

/// Opens the grid and returns what was chosen, or null if it was dismissed.
Future<PaymentIcon?> pickPaymentIcon(
  BuildContext context, {
  String? selected,
}) =>
    showDialog<PaymentIcon>(
      context: context,
      builder: (context) => _PaymentIconDialog(selected: selected),
    );

class _PaymentIconDialog extends StatelessWidget {
  const _PaymentIconDialog({this.selected});

  final String? selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final current = resolvePaymentIcon(selected);

    return AlertDialog(
      title: const Text('Pick an icon'),
      content: SizedBox(
        width: 320,
        child: SingleChildScrollView(
          child: Wrap(
            spacing: 4,
            runSpacing: 4,
            // Centred: a `Wrap` piles its leftover width on the right, which
            // leaves a grid of buttons hugging the left edge of the dialog.
            alignment: WrapAlignment.center,
            runAlignment: WrapAlignment.center,
            children: [
              for (final choice in kPaymentIcons)
                Tooltip(
                  message: choice.name,
                  child: IconButton(
                    icon: Icon(choice.icon),
                    iconSize: 28,
                    isSelected: choice.key == current.key,
                    selectedIcon: Icon(choice.icon, color: scheme.onPrimary),
                    style: IconButton.styleFrom(
                      backgroundColor:
                          choice.key == current.key ? scheme.primary : null,
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
