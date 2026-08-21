import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../database/repositories.dart';
import '../models/audit_log.dart';

/// The trail of changes that moved money without a sale happening: voids,
/// edits, discounts and repricings.
///
/// Manager-only, enforced by the security rules rather than by hiding the
/// screen — a check that lives only in the UI is not a check. Staff who reach
/// it are shown why they cannot read it instead of a raw permission error.
class StoreAuditLog extends StatelessWidget {
  const StoreAuditLog(this.storeId, {super.key});

  final String storeId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Change history')),
      body: StreamBuilder<List<AuditLog>>(
        stream: auditLogRepository.watchRecent(storeId),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _buildError(context, snapshot.error!);
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final logs = snapshot.data!;
          if (logs.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'Nothing recorded yet.\n\n'
                  'Voided orders, edited orders and menu price changes appear '
                  'here as they happen.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          return ListView.separated(
            itemCount: logs.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) => _AuditTile(log: logs[index]),
          );
        },
      ),
    );
  }

  Widget _buildError(BuildContext context, Object error) {
    final denied = error.toString().contains('permission-denied');
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(denied ? Icons.lock_outline : Icons.error_outline,
                size: 48, color: Colors.grey),
            const SizedBox(height: 16),
            Text(
              denied
                  ? 'Only the store owner and managers can read the change '
                      'history.'
                  : 'Error: $error',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _AuditTile extends StatelessWidget {
  const _AuditTile({required this.log});

  final AuditLog log;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(_iconFor(log.action)),
      title: Text(log.summary),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_detail()),
          if (log.note?.isNotEmpty == true)
            Text('“${log.note}”',
                style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
      trailing: Text(
        // A pending server timestamp reads back as null for the moment before
        // it lands; showing nothing beats showing the epoch.
        log.at == null ? '' : DateFormat.MMMd().add_Hm().format(log.at!),
        style: Theme.of(context).textTheme.bodySmall,
      ),
      isThreeLine: log.note?.isNotEmpty == true,
    );
  }

  /// What actually changed, in one line.
  String _detail() {
    switch (log.action) {
      case AuditAction.voidOrder:
        final orderNo = log.before?['orderNo'];
        final total = log.before?['total'];
        return 'Order #${orderNo ?? '?'} · ${total ?? '?'} removed from the day';
      case AuditAction.editOrder:
        final orderNo = log.after?['orderNo'] ?? log.before?['orderNo'];
        final from = log.before?['total'];
        final to = log.after?['total'];
        return 'Order #${orderNo ?? '?'} · total $from → $to';
      case AuditAction.editMenuPrice:
        final name = log.after?['name'] ?? log.before?['name'] ?? 'A dish';
        return '$name · ${log.before?['price']} → ${log.after?['price']}';
      case AuditAction.applyDiscount:
        return 'Order #${log.after?['orderNo'] ?? '?'} · '
            '${log.after?['discountAmount'] ?? '?'} off';
      case AuditAction.unknown:
        return log.targetId ?? '';
    }
  }

  static IconData _iconFor(AuditAction action) => switch (action) {
        AuditAction.voidOrder => Icons.cancel_outlined,
        AuditAction.editOrder => Icons.edit_outlined,
        AuditAction.applyDiscount => Icons.local_offer_outlined,
        AuditAction.editMenuPrice => Icons.price_change_outlined,
        AuditAction.unknown => Icons.help_outline,
      };
}
