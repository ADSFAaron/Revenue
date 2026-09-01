import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../database/repositories.dart';
import '../models/order_import.dart';
import '../models/store.dart';
import '../widgets/feedback.dart';
import '../widgets/money.dart';
import '../widgets/page_body.dart';

/// How a statement gets off the device and into [StoreImportOrders].
///
/// A seam rather than a call, because the picker is an open question: the app
/// carries `image_picker`, which offers photographs and nothing else, and
/// choosing an arbitrary CSV or XLSX means another dependency with its own
/// per-platform setup on Android, iOS, web and Windows. That is not worth
/// adding for a screen with no format to read yet, and it is one line to wire
/// in when there is.
typedef StatementChooser = Future<StatementFile?> Function();

/// Reads a delivery platform's statement into the till.
///
/// The entry point exists ahead of the formats on purpose. Everything except
/// the two named pieces — a file chooser, and at least one entry in
/// [kOrderStatementParsers] — is wired: pick, recognise, parse, preview. The
/// button turns itself on when both arrive, and the reason it is off is on
/// screen rather than in a comment.
///
/// See `models/order_import.dart` for why no parser is shipped: nobody has
/// seen a real statement, and a parser written against a guess imports numbers
/// that look right.
class StoreImportOrders extends StatefulWidget {
  const StoreImportOrders(
    this.storeId, {
    this.chooseStatement,
    this.parsers = kOrderStatementParsers,
    super.key,
  });

  final String storeId;

  /// Null until the app has a file picker. Injectable so the whole path can be
  /// exercised in a test with a file made in memory.
  final StatementChooser? chooseStatement;

  final List<OrderStatementParser> parsers;

  @override
  State<StoreImportOrders> createState() => _StoreImportOrdersState();
}

class _StoreImportOrdersState extends State<StoreImportOrders> {
  List<ImportedOrder>? _preview;
  String? _sourceName;
  bool _busy = false;

  /// Only for the currency the preview is shown in, so a failed read is not
  /// worth reporting — the default currency is a fine stand-in for a list of
  /// figures nothing is written from.
  Store? _store;

  bool get _ready =>
      widget.chooseStatement != null && widget.parsers.isNotEmpty;

  NumberFormat get _money => moneyFormat(_store);

  @override
  void initState() {
    super.initState();
    _loadStore();
  }

  Future<void> _loadStore() async {
    try {
      final store = await storeRepository.fetch(widget.storeId);
      if (mounted) setState(() => _store = store);
    } catch (_) {
      // Falls back to the default currency.
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Import Orders')),
      body: SafeArea(
        child: ReadingWidth(
          builder: (context, insets) => ListView(
            padding: insets + const EdgeInsets.all(16),
            children: [
              Text(
                'Orders sold through a delivery platform are in that '
                'platform’s back office and nowhere else, so a day that '
                'sold well on foodpanda still reads as a quiet day here. '
                'Every platform lets a merchant download a statement; this is '
                'where one gets read in.',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _ready && !_busy ? _pick : null,
                icon: const Icon(Icons.upload_file_outlined),
                label: const Text('Choose a statement file'),
              ),
              if (!_ready) ...[
                const SizedBox(height: 12),
                _NotYetCard(
                  chooser: widget.chooseStatement != null,
                  parsers: widget.parsers.length,
                ),
              ],
              if (_preview != null) ...[
                const SizedBox(height: 24),
                _buildPreview(_preview!),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pick() async {
    final chooser = widget.chooseStatement;
    if (chooser == null) return;

    setState(() => _busy = true);
    try {
      final file = await chooser();
      if (file == null || !mounted) return;

      final parser = parserFor(file, parsers: widget.parsers);
      if (parser == null) {
        // Named, not guessed at. A parser applied to a file it does not
        // understand produces numbers, and numbers get believed.
        _snack(
          '${file.name} is not a format this app can read yet.',
          isError: true,
        );
        setState(() {
          _preview = null;
          _sourceName = null;
        });
        return;
      }

      final orders = parser.parse(file);
      if (!mounted) return;
      setState(() {
        _preview = orders;
        _sourceName = '${parser.platformName} · ${file.name}';
      });
    } catch (e) {
      if (mounted) showFailure(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _buildPreview(List<ImportedOrder> orders) {
    final theme = Theme.of(context);
    if (orders.isEmpty) {
      return Text('No orders in that file.', style: theme.textTheme.bodyMedium);
    }

    final money = _money;
    final dates = orders.map((o) => o.placedAt).toList()..sort();
    final total = orders.fold<int>(0, (sum, o) => sum + o.total);
    final day = DateFormat.yMd();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(_sourceName ?? 'Statement', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(
          '${orders.length} orders · ${day.format(dates.first)} to '
          '${day.format(dates.last)} · ${money.format(total)}',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        // Read-only, and it stops here deliberately: writing these in needs the
        // order document to have somewhere to keep the platform's own order
        // number, or importing the same statement twice doubles the month.
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Reading is wired up; writing is not. Before these can be added '
              'to the till, an order needs to carry the platform’s own '
              'order number, so that importing the same statement twice '
              'cannot count it twice.',
              style: theme.textTheme.bodySmall,
            ),
          ),
        ),
        const SizedBox(height: 8),
        for (final order in orders.take(20))
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text('#${order.externalId}'),
            subtitle: Text(DateFormat.yMd().add_Hm().format(order.placedAt)),
            trailing: Text(money.format(order.total)),
          ),
        if (orders.length > 20)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('…and ${orders.length - 20} more',
                style: theme.textTheme.bodySmall),
          ),
      ],
    );
  }

  void _snack(String message, {bool isError = false}) {
    if (!mounted) return;
    showSnack(context, message, isError: isError);
  }
}

/// Says which of the two missing pieces is missing, rather than leaving a
/// disabled button with no explanation.
class _NotYetCard extends StatelessWidget {
  const _NotYetCard({required this.chooser, required this.parsers});

  final bool chooser;
  final int parsers;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final missing = <String>[
      if (parsers == 0)
        'No platform format has been wired up yet. The columns in a real '
            'UberEats or foodpanda statement have not been seen, and a reader '
            'written against a guess would import numbers that look right.',
      if (!chooser)
        'The app cannot open a file from the device yet — it carries a photo '
            'picker only.',
    ];

    return Card(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.construction_outlined,
                    size: 20, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: 8),
                Text('Not ready yet', style: theme.textTheme.titleSmall),
              ],
            ),
            const SizedBox(height: 8),
            for (final line in missing)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(line, style: theme.textTheme.bodySmall),
              ),
            Text(
              'Send a real statement — any month, any platform — and it '
              'becomes a reader.',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
