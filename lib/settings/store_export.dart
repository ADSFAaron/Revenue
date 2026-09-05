import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../database/repositories.dart';
import '../export/data_export.dart';
import '../export/file_saver.dart';
import '../models/order.dart';
import '../models/store.dart';
import '../widgets/feedback.dart';
import '../widgets/page_body.dart';
import '../widgets/setting_tile.dart';

/// What the shop can take away with it.
///
/// **Not the Excel report, and the difference is the reason this exists.** The
/// workbook on Reports is a *report*: a period's rollups, laid out in sheets
/// with headings and totals for somebody to read. It is right for reading and
/// wrong for everything else — nobody pivots a workbook laid out for reading,
/// no bookkeeper's software imports one, and nothing can be restored from one.
///
/// Backup is a different need with different tests: completeness, and being
/// readable by something that is not this app in ten years. Hence a flat table
/// per row of the thing itself, and one JSON document that holds the whole
/// shop.
///
/// It is the twin of account deletion (`functions/src/account.ts`): the same
/// shop, written out instead of removed. A product that can delete everything
/// and cannot hand it over is only half of a promise.
class StoreExport extends StatefulWidget {
  const StoreExport({required this.storeId, super.key});

  final String storeId;

  @override
  State<StoreExport> createState() => _StoreExportState();
}

class _StoreExportState extends State<StoreExport> {
  Session? _session;
  Object? _error;

  DateTimeRange? _range;
  String? _busy;

  Store get _store => _session!.store;

  @override
  void initState() {
    super.initState();
    loadSession().then((session) {
      if (!mounted) return;
      setState(() {
        _session = session;
        final today = parseBusinessDate(session.store.currentBusinessDate);
        // Ninety days rather than everything. It is the range somebody
        // actually wants most of the time, and it means the first tap on this
        // screen cannot be an accidental read of every order the shop has ever
        // taken.
        _range = DateTimeRange(
          start: DateTime(today.year, today.month, today.day - 89),
          end: today,
        );
      });
    }).catchError((Object error) {
      if (mounted) setState(() => _error = error);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Export & backup')),
      body: SafeArea(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_error != null) return ErrorView(_error!);
    if (_session == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final range = _range!;
    return ReadingWidth(
      builder: (context, insets) => ListView(
        padding: insets + const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          const SettingSection('What to include', first: true),
          SettingTile.inline(
            icon: Icons.date_range_outlined,
            title: 'Trading days',
            subtitle: '${_formatDate(range.start)} to '
                '${_formatDate(range.end)}',
            trailing: const Icon(Icons.edit_calendar_outlined),
            onTap: _busy == null ? _pickRange : null,
          ),
          const SettingSection('Files'),
          _exportTile(
            id: 'orders',
            icon: Icons.table_rows_outlined,
            title: 'Orders (CSV)',
            subtitle: 'One row per order — totals, tax, payment method, who '
                'rang it up',
            run: _exportOrders,
          ),
          _exportTile(
            id: 'lines',
            icon: Icons.list_alt_outlined,
            title: 'Order lines (CSV)',
            subtitle: 'One row per dish sold — the table to pivot from',
            run: _exportLines,
          ),
          _exportTile(
            id: 'backup',
            icon: Icons.inventory_2_outlined,
            title: 'Everything (JSON)',
            subtitle: 'Orders, menu, settings and staff, in one document',
            run: _exportBackup,
          ),
          const SizedBox(height: 16),
          _buildNote(context),
        ],
      ),
    );
  }

  Widget _exportTile({
    required String id,
    required IconData icon,
    required String title,
    required String subtitle,
    required Future<void> Function() run,
  }) {
    final running = _busy == id;
    return SettingTile.inline(
      icon: icon,
      title: title,
      subtitle: subtitle,
      trailing: running
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.download_outlined),
      // Every tile is disabled while any one of them runs, not just the one
      // that is going. They read the same orders, and two of these at once on
      // a year's worth is the same fetch twice for no reason.
      onTap: _busy == null ? () => _run(id, run) : null,
    );
  }

  Widget _buildNote(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('What these are for',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(
              'The Excel file on Reports is for reading — a period laid out in '
              'sheets. These are for everything else: handing a flat table to '
              'a bookkeeper, and keeping a copy of the shop that does not '
              'depend on this app still existing.\n\n'
              'Voided orders are included and marked rather than left out, so '
              'the export can be reconciled against the till.\n\n'
              'Nothing here contains a password, a passkey or anything else '
              'that could sign somebody in.',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickRange() async {
    final today = parseBusinessDate(_store.currentBusinessDate);
    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: _range,
      // The shop cannot have traded before it existed, and a range ending
      // after today would silently export nothing for the tail of it.
      firstDate: _store.createdAt ?? DateTime(2015),
      lastDate: today,
    );
    if (picked != null && mounted) setState(() => _range = picked);
  }

  Future<void> _run(String id, Future<void> Function() body) async {
    setState(() => _busy = id);
    try {
      await body();
    } catch (error) {
      if (!mounted) return;
      // Raw, like the workbook export and for the same reason: nothing here
      // that fails is a Firestore error `describeFailure` has a sentence for,
      // and "No space left on device" is the message that tells somebody what
      // to do.
      showError(context, 'Export failed: $error');
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  (String from, String to) get _businessRange => (
        formatBusinessDate(_range!.start),
        formatBusinessDate(_range!.end),
      );

  Future<List<Order>> _orders() {
    final (from, to) = _businessRange;
    return orderRepository.fetchRange(
      widget.storeId,
      fromBusinessDate: from,
      toBusinessDate: to,
    );
  }

  Future<void> _exportOrders() async {
    final orders = await _orders();
    if (!_hasSomething(orders)) return;
    final names = await userRepository.staffNames(widget.storeId);
    await _write(
      DataExport.ordersCsv(
        orders,
        store: _store,
        // Blank rather than "Not recorded" for an order with no uid on it: a
        // spreadsheet column reads better empty than filled with a sentence,
        // and an empty cell is what every tool downstream expects.
        nameFor: (uid) => names.labelFor(uid, missing: ''),
      ),
      'orders',
      'csv',
      'text/csv',
      orders.length,
    );
  }

  Future<void> _exportLines() async {
    final orders = await _orders();
    if (!_hasSomething(orders)) return;
    await _write(
      DataExport.orderLinesCsv(
        orders,
        categoryNames: {
          for (final category in _store.categories) category.id: category.name,
        },
      ),
      'order-lines',
      'csv',
      'text/csv',
      orders.length,
    );
  }

  Future<void> _exportBackup() async {
    final orders = await _orders();
    final menu = await menuRepository.fetchAll(widget.storeId);
    final staff = await userRepository.watchStaff(widget.storeId).first;
    final info = await PackageInfo.fromPlatform();
    final (from, to) = _businessRange;
    await _write(
      DataExport.backupJson(
        store: _store,
        orders: orders,
        menu: menu,
        staff: staff,
        fromBusinessDate: from,
        toBusinessDate: to,
        appVersion: '${info.version}+${info.buildNumber}',
      ),
      'backup',
      'json',
      'application/json',
      orders.length,
      // A backup of a shop that has not traded yet is still a backup: the
      // menu and the settings are in it, and those are the parts somebody
      // spent an evening typing in.
      allowEmpty: true,
    );
  }

  bool _hasSomething(List<Order> orders) {
    if (orders.isNotEmpty) return true;
    if (mounted) {
      showInfo(context, 'No orders in those dates — nothing to write');
    }
    return false;
  }

  Future<void> _write(
    String content,
    String kind,
    String extension,
    String mimeType,
    int orderCount, {
    bool allowEmpty = false,
  }) async {
    final (from, to) = _businessRange;
    final outcome = await saveBytes(
      // `utf8.encode` rather than handing the string over: the BOM the CSV
      // opens with is only worth anything if the bytes behind it are UTF-8,
      // and letting a platform pick an encoding is how it stops being.
      bytes: Uint8List.fromList(utf8.encode(content)),
      fileName: 'revenue-$kind-${from}_$to.$extension',
      mimeType: mimeType,
    );
    if (!mounted) return;
    showInfo(
      context,
      orderCount == 0 && allowEmpty
          ? outcome.description
          : '$orderCount ${orderCount == 1 ? 'order' : 'orders'} — '
              '${outcome.description}',
    );
  }

  static String _formatDate(DateTime date) => formatBusinessDate(date);
}
