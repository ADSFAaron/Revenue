import 'package:excel/excel.dart';

import '../models/daily_stats.dart';
import '../models/order.dart';
import '../models/stats_period.dart';
import '../models/store.dart';

/// Builds the spreadsheet a shop takes to its accountant.
///
/// Kept apart from both the screen and the file system: this turns figures into
/// a workbook and nothing else, so what ends up in the file can be checked
/// without a picker, a permission prompt or a browser download.
///
/// Money is written as numbers rather than as formatted strings. A column of
/// "NT$1,234" is text to a spreadsheet and will not sum, which defeats the
/// point of exporting at all.
class StatisticsWorkbook {
  const StatisticsWorkbook({
    required this.store,
    required this.period,
    required this.days,
  });

  final Store store;
  final StatsPeriod period;

  /// The trading days in the period, oldest first.
  final List<DailyStats> days;

  /// A filename that sorts and reads sensibly in a folder of other exports.
  String get fileName => '${_slug(store.name.isEmpty ? store.id : store.name)}_'
      '${period.fromBusinessDate}_to_${period.toBusinessDate}.xlsx';

  Excel build() {
    final excel = Excel.createExcel();
    // createExcel seeds a 'Sheet1'; the summary takes its place so the workbook
    // opens on something meaningful.
    final defaultSheet = excel.getDefaultSheet();

    _buildSummary(excel);
    _buildDaily(excel);
    _buildItems(excel);
    _buildCategories(excel);
    _buildBreakdown(excel, 'Payment methods', _paymentTotals());
    _buildBreakdown(excel, 'Channels', _channelTotals());

    if (defaultSheet != null && excel.sheets.length > 1) {
      excel.delete(defaultSheet);
    }
    return excel;
  }

  DailyStats get _total => DailyStats.sum(days, label: period.toString());

  void _buildSummary(Excel excel) {
    final total = _total;
    final sheet = excel['Summary'];

    void row(String label, CellValue? value) =>
        sheet.appendRow([TextCellValue(label), value]);

    row('Store', TextCellValue(store.name.isEmpty ? store.id : store.name));
    row('Currency', TextCellValue(store.currency));
    row('From', TextCellValue(period.fromBusinessDate));
    row('To', TextCellValue(period.toBusinessDate));
    row('Trading days with sales', IntCellValue(days.length));
    sheet.appendRow([]);

    row('Revenue', IntCellValue(total.revenue));
    row('Cost of goods', IntCellValue(total.cost));
    row('Delivery commission', IntCellValue(total.commissionTotal));
    row('Gross profit', IntCellValue(total.grossProfit));
    row('Discounts given', IntCellValue(total.discountTotal));
    row('Tax', IntCellValue(total.taxTotal));
    sheet.appendRow([]);

    row('Orders', IntCellValue(total.orderCount));
    row('Voided orders', IntCellValue(total.voidedCount));
    row('Guests', IntCellValue(total.guestCount));
    row('Average order value', DoubleCellValue(total.averageOrderValue));
    row('Average spend per guest', DoubleCellValue(total.averageGuestSpend));
    sheet.appendRow([]);

    // Stated rather than left for the reader to work out from the dates: a
    // sheet that silently covers a part-finished month is how a comparison
    // ends up being made against a full one.
    row(
      'Note',
      TextCellValue(days.length < period.dayCount
          ? 'Covers ${days.length} of ${period.dayCount} days in this period — '
              'days with no sales have no record.'
          : 'Covers the full period.'),
    );
  }

  void _buildDaily(Excel excel) {
    final sheet = excel['Daily'];
    sheet.appendRow([
      TextCellValue('Business date'),
      TextCellValue('Weekday'),
      TextCellValue('Orders'),
      TextCellValue('Guests'),
      TextCellValue('Voided'),
      TextCellValue('Revenue'),
      TextCellValue('Cost'),
      TextCellValue('Commission'),
      TextCellValue('Gross profit'),
      TextCellValue('Discounts'),
      TextCellValue('Tax'),
    ]);

    for (final day in days) {
      final date = DateTime.tryParse(day.businessDate);
      sheet.appendRow([
        TextCellValue(day.businessDate),
        TextCellValue(date == null ? '' : _weekdayNames[date.weekday - 1]),
        IntCellValue(day.orderCount),
        IntCellValue(day.guestCount),
        IntCellValue(day.voidedCount),
        IntCellValue(day.revenue),
        IntCellValue(day.cost),
        IntCellValue(day.commissionTotal),
        IntCellValue(day.grossProfit),
        IntCellValue(day.discountTotal),
        IntCellValue(day.taxTotal),
      ]);
    }
  }

  void _buildItems(Excel excel) {
    final sheet = excel['Items'];
    sheet.appendRow([
      TextCellValue('Item'),
      TextCellValue('Units sold'),
      TextCellValue('Revenue'),
      TextCellValue('Cost'),
      TextCellValue('Profit'),
      TextCellValue('Margin'),
    ]);

    for (final item in _total.itemsByRevenue) {
      final margin = item.marginRate;
      sheet.appendRow([
        TextCellValue(item.name),
        IntCellValue(item.qty),
        IntCellValue(item.revenue),
        IntCellValue(item.cost),
        IntCellValue(item.profit),
        // Blank, not zero and not 100%, when the dish has no cost on file —
        // the same rule the on-screen reports follow. A spreadsheet full of
        // spurious 100% margins would be worse than one with gaps.
        margin == null ? null : DoubleCellValue(margin),
      ]);
    }
  }

  void _buildCategories(Excel excel) {
    final total = _total;
    final sheet = excel['Categories'];
    sheet.appendRow([
      TextCellValue('Category'),
      TextCellValue('Units sold'),
      TextCellValue('Revenue'),
      TextCellValue('Cost'),
      TextCellValue('Profit'),
      TextCellValue('Share of revenue'),
    ]);

    for (final category in total.byCategory.values) {
      sheet.appendRow([
        TextCellValue(
            store.categoryName(category.categoryId) ?? category.categoryId),
        IntCellValue(category.qty),
        IntCellValue(category.revenue),
        IntCellValue(category.cost),
        IntCellValue(category.profit),
        DoubleCellValue(
            total.revenue == 0 ? 0 : category.revenue / total.revenue),
      ]);
    }
  }

  void _buildBreakdown(
      Excel excel, String sheetName, List<(String, StatBucket)> rows) {
    final total = _total;
    final sheet = excel[sheetName];
    sheet.appendRow([
      TextCellValue(sheetName),
      TextCellValue('Orders'),
      TextCellValue('Guests'),
      TextCellValue('Revenue'),
      TextCellValue('Share of revenue'),
    ]);

    for (final (label, bucket) in rows) {
      sheet.appendRow([
        TextCellValue(label),
        IntCellValue(bucket.orders),
        IntCellValue(bucket.guests),
        IntCellValue(bucket.revenue),
        DoubleCellValue(
            total.revenue == 0 ? 0 : bucket.revenue / total.revenue),
      ]);
    }
  }

  List<(String, StatBucket)> _paymentTotals() => [
        for (final entry in _total.byPayment.entries)
          (PaymentMethod.fromId(entry.key).label, entry.value),
      ];

  List<(String, StatBucket)> _channelTotals() => [
        for (final entry in _total.byChannel.entries)
          (OrderChannel.fromId(entry.key).label, entry.value),
      ];

  static const List<String> _weekdayNames = [
    'Mon',
    'Tue',
    'Wed',
    'Thu',
    'Fri',
    'Sat',
    'Sun',
  ];

  /// Strips what a file system will not take, so the export cannot fail on a
  /// shop whose name contains a slash.
  static String _slug(String value) => value
      .replaceAll(RegExp(r'[^\w一-鿿-]+'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_|_$'), '');
}
