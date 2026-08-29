import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import 'menu_capture_page.dart';

import '../database/repositories.dart';
import '../models/menu_import.dart';
import '../models/menu_item.dart';
import '../models/store.dart';
import '../widgets/feedback.dart';
import '../widgets/money.dart';

/// Photograph a menu, correct what came back, then write it.
///
/// The middle step is the whole point and is not skippable. A price read
/// wrongly is not a typo that shows up later — it is every future order for
/// that dish, every daily total, and every figure on the analysis pages,
/// wrong in a way nothing downstream can detect. So nothing reaches Firestore
/// until somebody has said yes on this screen.
///
/// Rows are shown in two groups. Anything flagged — by the model's own doubt
/// or by the app's arithmetic checks — is up top and expanded; everything else
/// is folded away behind a single line. A menu is forty to eighty dishes, and
/// asking somebody to read eighty rows on a phone is asking them to stop
/// reading at about row twelve.
class StoreImportMenu extends StatefulWidget {
  final String storeID;

  const StoreImportMenu(this.storeID, {super.key});

  @override
  State<StoreImportMenu> createState() => _StoreImportMenuState();
}

enum _Phase { capture, reading, review, saving }

/// A photograph waiting to be sent, held with its bytes so it can be shown as
/// a thumbnail without reading it off disk again.
class _Shot {
  const _Shot({required this.bytes, required this.mimeType});

  final Uint8List bytes;
  final String mimeType;
}

class _StoreImportMenuState extends State<StoreImportMenu> {
  final _picker = ImagePicker();

  _Phase _phase = _Phase.capture;
  final List<_Shot> _shots = [];

  List<MenuImportItem> _items = const [];
  List<String> _draftCategories = const [];

  Store? _store;
  List<MenuItem> _existing = const [];

  String? _error;

  @override
  void initState() {
    super.initState();
    _loadStore();
  }

  /// Needed before the write, not before the photo — but fetched now so the
  /// category dropdown on the review screen already knows what this store
  /// calls things, and so a failure to read the store surfaces before somebody
  /// has spent a minute checking rows.
  ///
  /// That second reason only holds if the failure is actually shown. Unguarded
  /// it was not: the exception went nowhere, `_store` stayed null, and the one
  /// place it surfaced was `_commit` — after every row had been checked, which
  /// is precisely the moment this was meant to come before.
  Future<void> _loadStore() async {
    try {
      final store = await storeRepository.fetch(widget.storeID);
      final existing = await menuRepository.fetchAll(widget.storeID);
      if (!mounted) return;
      setState(() {
        _store = store;
        _existing = existing;
        _error = store == null
            ? 'This store could not be found. Nothing can be imported into it.'
            : null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = describeFailure(e).message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_phase == _Phase.review ? 'Check the menu' : 'Import menu'),
      ),
      body: switch (_phase) {
        _Phase.capture => _captureBody(),
        _Phase.reading => const _Busy('Reading the menu…\nThis takes a moment.'),
        _Phase.review => _reviewBody(),
        _Phase.saving => const _Busy('Adding dishes…'),
      },
      bottomNavigationBar: switch (_phase) {
        _Phase.capture => _captureActions(),
        _Phase.review => _reviewActions(),
        _ => null,
      },
    );
  }

  // -------------------------------------------------------------------------
  // Taking the photographs
  // -------------------------------------------------------------------------

  Widget _captureBody() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      children: [
        const Text(
          'Photograph the menu. Fill the frame with it, keep it flat, and take '
          'a second photo if it does not all fit — a folded card has two '
          'sides.',
        ),
        const SizedBox(height: 16),
        if (_error != null) _ErrorNote(_error!),
        if (_shots.isEmpty)
          const _EmptyShots()
        else
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (var i = 0; i < _shots.length; i++) _thumbnail(i),
            ],
          ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _shots.length >= MenuImportRepository.maxPhotos
                    ? null
                    : _takePhoto,
                icon: const Icon(Icons.photo_camera_outlined),
                label: const Text('Take photo'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _shots.length >= MenuImportRepository.maxPhotos
                    ? null
                    : () => _addShot(ImageSource.gallery),
                icon: const Icon(Icons.image_outlined),
                label: const Text('Choose image'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Up to ${MenuImportRepository.maxPhotos} photos per menu.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  Widget _thumbnail(int index) => Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.memory(
              _shots[index].bytes,
              width: 120,
              height: 160,
              fit: BoxFit.cover,
            ),
          ),
          Positioned(
            top: -4,
            right: -4,
            child: IconButton(
              tooltip: 'Remove this photo',
              icon: Icon(Icons.cancel,
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
              onPressed: () => setState(() => _shots.removeAt(index)),
            ),
          ),
        ],
      );

  Widget _captureActions() => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: FilledButton(
            onPressed: _shots.isEmpty ? null : _recognise,
            child: Text(_shots.length <= 1
                ? 'Read the menu'
                : 'Read the menu (${_shots.length} photos)'),
          ),
        ),
      );

  /// Opens the app's own viewfinder rather than asking another app to take the
  /// picture — see [MenuCapturePage] for why borrowing one is not dependable.
  ///
  /// Web is the exception, and not for a small reason: in a browser there is no
  /// sensor to open, only `getUserMedia` behind a permission prompt and an
  /// HTTPS origin. The file input is what browsers are actually good at, and on
  /// a phone browser it offers the camera anyway. So on web this stays with
  /// `image_picker`, which is doing something different underneath and the
  /// right thing for the platform.
  Future<void> _takePhoto() async {
    if (kIsWeb) return _addShot(ImageSource.camera);

    final bytes = await captureMenuPhoto(context);
    if (bytes == null || !mounted) return;
    setState(() {
      _error = null;
      // `takePicture` writes JPEG on every platform the viewfinder runs on.
      _shots.add(_Shot(bytes: bytes, mimeType: 'image/jpeg'));
    });
  }

  /// `maxWidth` and `imageQuality` do the downsampling in the platform's own
  /// image pipeline on the way out. A 12MP original is several seconds of
  /// upload and no more legible to the recogniser than a 1568px edge, which is
  /// what it works at anyway.
  Future<void> _addShot(ImageSource source) async {
    try {
      final file = await _picker.pickImage(
        source: source,
        maxWidth: 1568,
        maxHeight: 1568,
        imageQuality: 85,
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      setState(() {
        _error = null;
        _shots.add(_Shot(bytes: bytes, mimeType: _mimeTypeOf(file)));
      });
    } on PlatformException catch (e) {
      if (mounted) setState(() => _error = _pickerFailure(e, source));
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not open the camera: $e');
    }
  }

  /// The platform's vocabulary is not a shop owner's.
  ///
  /// `no_available_camera` is the one worth naming precisely, because it lies:
  /// it means the capture intent resolved to nothing, which on Android 11 and
  /// up is usually package visibility rather than a missing camera — see the
  /// `<queries>` block in AndroidManifest.xml. On a device that genuinely has
  /// no camera, a tablet or a desktop browser, there is still a way through,
  /// and the message should point at it rather than at a stack trace.
  static String _pickerFailure(PlatformException e, ImageSource source) =>
      switch (e.code) {
        'no_available_camera' =>
          'No camera is available on this device. Use Choose image instead.',
        'camera_access_denied' =>
          'Camera access was refused. Allow it for Revenue in the system '
              'settings, or use Choose image instead.',
        'photo_access_denied' =>
          'Access to your photos was refused. Allow it for Revenue in the '
              'system settings.',
        'multiple_request' =>
          'Still waiting for the last photo. Try again in a moment.',
        _ => source == ImageSource.camera
            ? 'Could not open the camera (${e.code}).'
            : 'Could not open that image (${e.code}).',
      };

  /// Android usually leaves `mimeType` null, and the recogniser rejects
  /// anything it cannot name. `imageQuality` above re-encodes to JPEG on both
  /// mobile platforms, which is what makes that the right default rather than
  /// a guess.
  static String _mimeTypeOf(XFile file) {
    final declared = file.mimeType;
    if (declared != null && declared.startsWith('image/')) {
      const supported = {'image/jpeg', 'image/png', 'image/webp'};
      if (supported.contains(declared)) return declared;
    }
    final name = file.name.toLowerCase();
    if (name.endsWith('.png')) return 'image/png';
    if (name.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }

  Future<void> _recognise() async {
    setState(() {
      _phase = _Phase.reading;
      _error = null;
    });

    try {
      final draft = await menuImportRepository.recognise([
        for (final shot in _shots)
          MenuImportPhoto(bytes: shot.bytes, mimeType: shot.mimeType),
      ]);
      if (!mounted) return;

      if (draft.isEmpty) {
        setState(() {
          _phase = _Phase.capture;
          _error = 'No dishes were found in that photo. Try again with the '
              'menu filling more of the frame.';
        });
        return;
      }

      setState(() {
        _items = draft.items;
        _draftCategories = draft.categories;
        _phase = _Phase.review;
      });
    } catch (e) {
      // Catch-all rather than `on MenuImportException`. Anything the repository
      // did not translate — a malformed payload, a plugin that threw, an
      // `Error` rather than an `Exception` — used to leave this screen on the
      // reading spinner with no way off it but the back button, and the photos
      // already taken lost with it.
      if (mounted) {
        setState(() {
          _phase = _Phase.capture;
          _error = describeFailure(e).message;
        });
      }
    }
  }

  // -------------------------------------------------------------------------
  // Checking what came back
  // -------------------------------------------------------------------------

  Widget _reviewBody() {
    final flagged = _items.where((i) => i.needsReview).toList();
    final clean = _items.where((i) => !i.needsReview).toList();

    return ListView(
      padding: const EdgeInsets.only(bottom: 16),
      children: [
        // A failed save leaves the screen here, so the reason has to be
        // readable here too — the snack bar that carried it has faded by the
        // time somebody has worked out what to do about it.
        if (_error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: _ErrorNote(_error!),
          ),
        if (flagged.isNotEmpty) ...[
          _SectionHeader(
            flagged.length == 1
                ? '1 dish needs checking'
                : '${flagged.length} dishes need checking',
            subtitle: 'Either the photo was unclear or the price looks wrong. '
                'Tap a row to correct it.',
            colour: Theme.of(context).colorScheme.error,
          ),
          for (final item in flagged) _row(item),
        ],
        if (clean.isNotEmpty)
          ExpansionTile(
            initiallyExpanded: flagged.isEmpty,
            title: Text(clean.length == 1
                ? '1 dish read cleanly'
                : '${clean.length} dishes read cleanly'),
            subtitle: const Text('Worth a glance before adding them.'),
            children: [for (final item in clean) _row(item)],
          ),
      ],
    );
  }

  Widget _row(MenuImportItem item) {
    final index = _items.indexOf(item);
    final reasons = item.flags.map((f) => f.label).join(' · ');
    final subtitle = StringBuffer(moneyFormat(_store).format(item.price));
    if (item.categoryName != null) subtitle.write('  ·  ${item.categoryName}');

    return ListTile(
      leading: item.needsReview
          ? Icon(Icons.error_outline, color: Theme.of(context).colorScheme.error)
          : const Icon(Icons.restaurant),
      title: Text(item.displayName),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(subtitle.toString()),
          if (item.needsReview)
            Text(
              item.modelNote == null ? reasons : '$reasons — ${item.modelNote}',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (item.needsReview)
            IconButton(
              tooltip: 'This one is right',
              icon: const Icon(Icons.check),
              onPressed: () => _replace(index, item.copyWith(reviewed: true)),
            ),
          IconButton(
            tooltip: 'Remove this dish',
            icon: const Icon(Icons.delete_outlined),
            onPressed: () => _remove(index),
          ),
        ],
      ),
      onTap: () => _edit(index),
    );
  }

  Widget _reviewActions() {
    final outstanding = _items.where((i) => i.needsReview).length;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (outstanding > 0)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  '$outstanding still flagged. They will be added as they are.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            FilledButton(
              onPressed: _items.isEmpty ? null : _commit,
              child: Text(_items.length == 1
                  ? 'Add 1 dish'
                  : 'Add ${_items.length} dishes'),
            ),
          ],
        ),
      ),
    );
  }

  /// Every change goes back through [MenuImportRepository.flag], because two
  /// of the checks are about a row's neighbours: correcting one price can
  /// clear an outlier flag on a different row, and renaming a dish can create
  /// or resolve a duplicate.
  void _replace(int index, MenuImportItem item) {
    final next = [..._items];
    next[index] = item;
    setState(() => _items = MenuImportRepository.flag(next));
  }

  void _remove(int index) {
    final next = [..._items]..removeAt(index);
    setState(() => _items = MenuImportRepository.flag(next));
  }

  /// The categories offered are the store's own plus whatever the menu was
  /// headed with. The second group does not exist yet — it is created at the
  /// moment of writing, by [MenuImportRepository.commit], and only for the
  /// headings dishes actually ended up under.
  List<String> get _categoryChoices {
    final names = <String>[
      for (final c in _store?.categories ?? const <StoreCategory>[]) c.name,
    ];
    for (final name in _draftCategories) {
      if (!names.any((n) => n.toLowerCase() == name.toLowerCase())) {
        names.add(name);
      }
    }
    return names;
  }

  Future<void> _edit(int index) async {
    final item = _items[index];
    final nameController = TextEditingController(text: item.name);
    final variantController = TextEditingController(text: item.variant ?? '');
    final priceController = TextEditingController(text: '${item.price}');
    var category = item.categoryName;

    final choices = _categoryChoices;
    if (category != null && !choices.contains(category)) choices.add(category);

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          title: const Text('Correct this dish'),
          content: SingleChildScrollView(
            child: Column(
              spacing: 8,
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'Dish Name'),
                  controller: nameController,
                  textInputAction: TextInputAction.next,
                ),
                TextField(
                  decoration: const InputDecoration(
                    labelText: 'Portion',
                    helperText: 'Optional — 大, 小, 套餐',
                  ),
                  controller: variantController,
                  textInputAction: TextInputAction.next,
                ),
                TextField(
                  decoration: const InputDecoration(labelText: 'Price (NTD)'),
                  controller: priceController,
                  keyboardType: TextInputType.number,
                  inputFormatters: <TextInputFormatter>[
                    FilteringTextInputFormatter.digitsOnly
                  ],
                ),
                DropdownButtonFormField<String?>(
                  initialValue: category,
                  decoration: const InputDecoration(labelText: 'Category'),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('No category'),
                    ),
                    for (final name in choices)
                      DropdownMenuItem<String?>(value: name, child: Text(name)),
                  ],
                  onChanged: (value) => setStateDialog(() => category = value),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                if (nameController.text.trim().isEmpty ||
                    int.tryParse(priceController.text) == null) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Enter a name and a numeric price'),
                  ));
                  return;
                }
                Navigator.pop(context, true);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    if (saved == true) {
      final variant = variantController.text.trim();
      _replace(
        index,
        item.copyWith(
          name: nameController.text.trim(),
          variant: variant.isEmpty ? null : variant,
          clearVariant: variant.isEmpty,
          price: int.parse(priceController.text),
          categoryName: category,
          clearCategory: category == null,
          // Corrected by hand, so it stops asking for attention. The
          // arithmetic checks still run — if the new price is also out of
          // line, the flag comes straight back.
          reviewed: true,
        ),
      );
    }

    // Disposed here rather than in `dispose`: these are created per dialog and
    // the route is gone by now, so there is nothing left reading them.
    nameController.dispose();
    variantController.dispose();
    priceController.dispose();
  }

  Future<void> _commit() async {
    final store = _store;
    if (store == null) {
      setState(() => _error = 'Could not read the store. Try again.');
      return;
    }

    setState(() => _phase = _Phase.saving);
    try {
      final added = await menuImportRepository.commit(
        store: store,
        items: _items,
        existing: _existing,
      );
      if (!mounted) return;
      Navigator.of(context).pop(added);
    } catch (e) {
      // Back to review rather than out of the screen: every correction made so
      // far is still in `_items`, and losing that to a dropped connection would
      // mean checking eighty rows twice.
      if (!mounted) return;
      setState(() {
        _phase = _Phase.review;
        _error = describeFailure(e).message;
      });
      showFailure(context, e);
    }
  }
}

// ---------------------------------------------------------------------------

class _Busy extends StatelessWidget {
  const _Busy(this.message);

  final String message;

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(message, textAlign: TextAlign.center),
          ],
        ),
      );
}

class _EmptyShots extends StatelessWidget {
  const _EmptyShots();

  @override
  Widget build(BuildContext context) => Container(
        height: 160,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border.all(
              color: Theme.of(context).colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Text('No photos yet'),
      );
}

class _ErrorNote extends StatelessWidget {
  const _ErrorNote(this.message);

  final String message;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Text(
          message,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      );
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title, {required this.subtitle, this.colour});

  final String title;
  final String subtitle;
  final Color? colour;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(color: colour),
            ),
            const SizedBox(height: 4),
            Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      );
}
