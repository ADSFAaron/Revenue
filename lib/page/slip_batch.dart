import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../database/repositories.dart';
import '../models/menu_item.dart';
import '../models/order_slip.dart';
import '../models/store.dart';
import '../settings/menu_capture_page.dart';
import '../widgets/page_body.dart';
import 'addorder.dart';
import 'order_slip_review.dart';

/// A stack of paper slips, worked through one at a time.
///
/// **Why this is separate from the camera button on the order screen.** That
/// one reads a slip into *this* basket — a customer adding to an order that is
/// already being rung up. This is the other shape entirely: a pile of slips
/// from a busy service, each of which is its own order.
///
/// The shop owner described the workflow that makes it worth building, and it
/// is the opposite of the one the reader was first sized for: when service is
/// busy the slips pile up and get entered *afterwards*, in a quiet half hour,
/// precisely because there was no time to type them in while it was busy.
///
/// So the expensive part is decoupled from the person. Photographing is
/// instant and recognition is not, so photographs are taken back to back and
/// each read starts the moment it is taken — by the time somebody has finished
/// photographing a stack, the first few are already waiting. Standing at the
/// camera waiting forty seconds between slips is the thing this exists to
/// avoid.
///
/// Ringing up goes through [AddOrder], not through anything here. That screen
/// is the money path: tax, commission, the offline queue, attribution, and the
/// decision about what happens when the connection drops mid-submit. A second
/// copy of it that only slips went through would be the copy that drifts, and
/// it would drift on the takings.
class SlipBatch extends StatefulWidget {
  const SlipBatch({required this.store, super.key});

  final Store store;

  @override
  State<SlipBatch> createState() => _SlipBatchState();
}

class _SlipBatchState extends State<SlipBatch> {
  final List<_Slip> _slips = [];
  List<MenuItem> _menu = const [];
  bool _capturing = false;

  /// How many reads may be in flight at once.
  ///
  /// Photographs arrive faster than the model answers, so without a cap a
  /// twenty-slip stack is twenty simultaneous calls — which is the shop's
  /// whole daily allowance spent in one gesture, and twenty chances to hit the
  /// same overloaded model at the same moment.
  static const int _maxInFlight = 2;

  int _inFlight = 0;

  @override
  void initState() {
    super.initState();
    menuRepository.fetchActive(widget.store.id).then((menu) {
      if (mounted) setState(() => _menu = menu);
    }).catchError((Object _) {
      // The menu is only needed to show names and prices on the review screen,
      // which is reached later and reloads nothing. A failure here is not
      // worth stopping somebody photographing.
    });
  }

  @override
  void dispose() {
    for (final slip in _slips) {
      slip.subscription?.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final done = _slips.where((slip) => slip.orderNo != null).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan slips'),
        bottom: _slips.isEmpty
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(28),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    '$done of ${_slips.length} rung up',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _capturing ? null : _capture,
        icon: const Icon(Icons.photo_camera_outlined),
        label: Text(_slips.isEmpty ? 'Photograph a slip' : 'Next slip'),
      ),
      body: SafeArea(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_slips.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.receipt_long_outlined,
                size: 48,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 16),
              Text(
                'Photograph the slips one after another — each one becomes its '
                'own order.\n\n'
                'Reading starts as soon as a photo is taken, so keep going: by '
                'the time the stack is photographed the first few are ready to '
                'ring up.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      itemCount: _slips.length,
      separatorBuilder: (context, index) => const Divider(height: 1),
      itemBuilder: (context, index) => PageBody(
        child: _buildRow(_slips[index], index),
      ),
    );
  }

  Widget _buildRow(_Slip slip, int index) {
    final theme = Theme.of(context);

    final (Widget trailing, String subtitle, VoidCallback? onTap) =
        switch (slip) {
      _Slip(orderNo: final no?) => (
          Icon(Icons.check_circle, color: theme.colorScheme.tertiary),
          'Rung up as order #$no',
          null,
        ),
      _Slip(error: final error?) => (
          IconButton(
            tooltip: 'Try again',
            icon: const Icon(Icons.refresh),
            onPressed: () => _startRead(slip),
          ),
          describeFailure(error).message,
          null,
        ),
      _Slip(reading: final reading?) => (
          const Icon(Icons.chevron_right),
          reading.isEmpty
              ? 'Nothing on it matched the menu'
              : '${reading.lines.length} '
                  '${reading.lines.length == 1 ? 'dish' : 'dishes'}'
                  '${reading.lines.any((l) => !l.sure) ? ' · some unsure' : ''}',
          reading.isEmpty ? null : () => _ringUp(slip),
        ),
      _ => (
          const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          slip.queued ? 'Waiting its turn' : 'Reading',
          null,
        ),
    };

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.memory(
          slip.photo,
          width: 48,
          height: 48,
          fit: BoxFit.cover,
          // Slips look alike, so the thumbnail alone does not say which is
          // which. It is here to make the row feel like a thing rather than a
          // status line; the number beside it is what identifies it.
          gaplessPlayback: true,
        ),
      ),
      title: Text('Slip ${index + 1}'),
      subtitle: Text(subtitle),
      trailing: trailing,
      onTap: onTap,
    );
  }

  Future<void> _capture() async {
    setState(() => _capturing = true);
    try {
      final bytes = await captureMenuPhoto(context);
      if (bytes == null || !mounted) return;
      final slip = _Slip(photo: bytes);
      setState(() => _slips.add(slip));
      _pump();
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  /// Starts as many queued reads as the cap allows.
  void _pump() {
    for (final slip in _slips) {
      if (_inFlight >= _maxInFlight) return;
      if (slip.queued) _startRead(slip);
    }
  }

  void _startRead(_Slip slip) {
    slip.subscription?.cancel();
    setState(() {
      slip.error = null;
      slip.reading = null;
      slip.queued = false;
    });
    _inFlight++;

    slip.subscription = orderSlipRepository.read([
      SlipPhoto(bytes: slip.photo, mimeType: 'image/jpeg'),
    ]).listen(
      (event) {
        if (!mounted) return;
        if (event is SlipRead) {
          setState(() => slip.reading = event.reading);
        }
      },
      onError: (Object error) {
        if (!mounted) return;
        setState(() => slip.error = error);
        _finish();
      },
      onDone: _finish,
    );
  }

  void _finish() {
    _inFlight = (_inFlight - 1).clamp(0, _maxInFlight);
    if (mounted) _pump();
  }

  Future<void> _ringUp(_Slip slip) async {
    final reading = slip.reading;
    if (reading == null) return;

    final picked = await Navigator.of(context).push<Map<String, int>>(
      MaterialPageRoute(
        builder: (_) => OrderSlipReview(
          reading: reading,
          menu: _menu,
          store: widget.store,
        ),
      ),
    );
    if (picked == null || picked.isEmpty || !mounted) return;

    // Through the order screen, never around it. That is where tax, commission,
    // the offline queue and attribution live, and where a dropped connection
    // is already handled properly.
    final orderNo = await Navigator.of(context).push<int>(
      MaterialPageRoute(
        builder: (_) => AddOrder(
          widget.store.id,
          initialQuantities: picked,
          closeAfterSubmit: true,
        ),
      ),
    );
    if (orderNo == null || !mounted) return;
    setState(() => slip.orderNo = orderNo);
  }
}

/// One photographed slip, and wherever it has got to.
class _Slip {
  _Slip({required this.photo});

  final Uint8List photo;

  /// True until a read has been started for it — the cap on simultaneous
  /// reads means a photograph can sit for a moment before its turn.
  bool queued = true;

  /// Cancelled by whoever owns this row — on dispose, and again before a
  /// re-read replaces it. The analyzer cannot see either from here, because a
  /// field's lifetime is not something it can follow out of the class.
  // ignore: cancel_subscriptions
  StreamSubscription<SlipEvent>? subscription;

  SlipReading? reading;
  Object? error;

  /// Set once this slip has been rung up. The row is finished at that point
  /// and cannot be rung up twice, which is the mistake worth making
  /// impossible: a stack of near-identical slips is exactly where somebody
  /// double-enters one.
  int? orderNo;
}
