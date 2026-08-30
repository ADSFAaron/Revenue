import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

/// A viewfinder for photographing a menu, driving the camera hardware directly.
///
/// **Why not `ImageSource.camera`.** That route fires `ACTION_IMAGE_CAPTURE`
/// and depends on some *other* app on the phone answering it. Whether one does
/// is not a property of Android — it is a property of whatever the
/// manufacturer, the carrier and the owner happen to have left installed and
/// enabled, and a shop's phone is exactly the phone nobody curated. Sony ships
/// the case that proves it: the stock camera is disabled and its replacements
/// register only `STILL_IMAGE_CAMERA`, so the intent resolves to nothing and
/// the phone reports "no camera available" while holding three of them. But it
/// is one example of a general fragility, not a brand to special-case — the
/// same hole opens on any device whose camera app was replaced, disabled, or
/// restricted by a work profile.
///
/// The Android implementation underneath is `camera_android_camerax`, which is
/// CameraX — Google's own device-compatibility layer, written for precisely
/// this problem. Opening the sensor is the route that does not care whose
/// phone it is.
///
/// It is also the better screen for the job. A menu wants filling the frame and
/// holding square on, and a guide rectangle says that far more usefully than a
/// paragraph of instructions above a system camera nobody reads.
class MenuCapturePage extends StatefulWidget {
  const MenuCapturePage({super.key});

  @override
  State<MenuCapturePage> createState() => _MenuCapturePageState();
}

class _MenuCapturePageState extends State<MenuCapturePage>
    with WidgetsBindingObserver {
  CameraController? _controller;
  String? _error;
  bool _capturing = false;

  /// The one [_open] in flight, or null.
  ///
  /// This is the fix for a black viewfinder with a working shutter, and the
  /// path to it is worth writing down because nothing about it is visible in
  /// the code that produced it. On Android, `initialize()` is what raises the
  /// CAMERA permission dialog. A permission dialog pauses the activity, so
  /// Flutter reports `inactive` and then `resumed` — *while the first
  /// `initialize()` is still awaiting*. `resumed` used to call [_start] again,
  /// so first use opened the sensor twice; the second controller's `setState`
  /// overwrote the first without disposing it, and the `Texture` the page was
  /// showing pointed at a surface CameraX had already unbound. Black preview,
  /// live shutter, and it only ever reproduced on the very first run after an
  /// install, because that is the only run with a permission dialog in it.
  Future<void>? _starting;

  /// Whether this page currently wants the sensor open. False while the app is
  /// in the background, so a controller that finishes opening into a
  /// backgrounded app is closed rather than left holding the camera.
  bool _wanted = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _wanted = false;
    _controller?.dispose();
    super.dispose();
  }

  /// The plugin stopped handling lifecycle itself at 0.5.0. Without this the
  /// preview comes back black after the app has been in the background —
  /// which is exactly what happens when somebody switches away to check
  /// something and comes back.
  ///
  /// Every non-resumed state releases, not just `inactive`. `hidden` and
  /// `paused` are the ones a real backgrounding sends, and leaving the sensor
  /// open through them holds a camera the rest of the phone may want.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _wanted = true;
        _start();
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        _wanted = false;
        _release();
    }
  }

  void _release() {
    final controller = _controller;
    if (controller == null) return;
    // Cleared through setState: the old code dropped the reference without
    // one, so `build` went on handing a disposed controller to CameraPreview
    // until something else happened to rebuild.
    setState(() => _controller = null);
    controller.dispose();
  }

  /// Opens the camera, at most once at a time.
  ///
  /// Returning the in-flight future rather than starting a second open is the
  /// whole point — see [_starting].
  Future<void> _start() {
    final running = _starting;
    if (running != null) return running;

    final started = _open().whenComplete(() {
      _starting = null;
      // The app went away and came back while the sensor was opening, so the
      // controller that opening produced was thrown away for a background this
      // page is no longer in. Nothing else is going to ask.
      if (mounted && _wanted && _controller == null && _error == null) {
        _start();
      }
    });
    _starting = started;
    return started;
  }

  Future<void> _open() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (mounted) {
          setState(() => _error = 'This device has no camera.');
        }
        return;
      }

      // The back camera, falling back to whatever is first. Nobody photographs
      // a menu with the selfie camera, and on a phone with three lenses the
      // first entry is the one the platform considers primary.
      final camera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      final controller = await _openAt(camera);

      // Opening is slow enough for the page to have gone or the app to have
      // been backgrounded meanwhile. Either way this controller has nobody to
      // show it, and an undisposed one keeps the sensor.
      if (!mounted || !_wanted) {
        await controller.dispose();
        return;
      }

      final previous = _controller;
      setState(() {
        _controller = controller;
        _error = null;
      });
      // After the swap, never before: disposing the controller the widget tree
      // is still holding is what turns a live preview black.
      await previous?.dispose();
    } on CameraException catch (e) {
      if (mounted) setState(() => _error = _describe(e));
    } catch (e) {
      // A plugin that threw something other than a CameraException would
      // otherwise leave this page on a spinner for ever, with the shutter
      // showing and nothing behind it.
      if (mounted) {
        setState(() => _error = 'The camera could not be opened ($e). Go back '
            'and use Choose image instead.');
      }
    }
  }

  /// Opens at the best resolution this device will actually give.
  ///
  /// 1080p first. Deliberately not `max`: a dense menu wants resolution, but a
  /// 12MP frame is several megabytes of upload and the recogniser works at a
  /// 1568px edge anyway, so the extra pixels are paid for twice and read once.
  ///
  /// The fallbacks are not decoration. A preset is a request, and a cheap or
  /// old handset can refuse one — failing outright there would mean the app
  /// works on the developer's phone and not on the shop's. 720p still reads a
  /// menu; no camera at all does not.
  static Future<CameraController> _openAt(CameraDescription camera) async {
    const presets = [
      ResolutionPreset.veryHigh,
      ResolutionPreset.high,
      ResolutionPreset.medium,
    ];

    CameraException? last;
    for (final preset in presets) {
      final controller = CameraController(camera, preset, enableAudio: false);
      try {
        await controller.initialize();
        return controller;
      } on CameraException catch (e) {
        await controller.dispose();
        // A refusal the person has to answer — permission — is not something
        // a lower resolution fixes, so stop rather than ask three times.
        if (e.code.startsWith('CameraAccess')) rethrow;
        last = e;
      }
    }
    throw last!;
  }

  static String _describe(CameraException e) => switch (e.code) {
        'CameraAccessDenied' ||
        'CameraAccessDeniedWithoutPrompt' =>
          'Camera access was refused. Allow it for Revenue in the system '
              'settings, or go back and use Choose image instead.',
        'CameraAccessRestricted' =>
          'Camera access is restricted on this device. Go back and use Choose '
              'image instead.',
        _ => 'The camera could not be opened (${e.code}). Go back and use '
            'Choose image instead.',
      };

  Future<void> _capture() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (_capturing) return;

    setState(() => _capturing = true);
    try {
      final shot = await controller.takePicture();
      final bytes = await shot.readAsBytes();
      if (!mounted) return;
      Navigator.of(context).pop(bytes);
    } on CameraException catch (e) {
      if (mounted) {
        setState(() {
          _capturing = false;
          _error = _describe(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Photograph the menu'),
      ),
      body: switch ((controller, _error)) {
        (_, final String message) => _Message(message),
        (final CameraController c, _) when c.value.isInitialized =>
          _viewfinder(c),
        _ => const Center(child: CircularProgressIndicator()),
      },
      bottomNavigationBar: controller == null || _error != null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                // `heightFactor: 1` is not a tweak — without it this bar is the
                // whole screen and there is no viewfinder at all.
                //
                // Scaffold measures `bottomNavigationBar` with
                // `BoxConstraints.loose(size)`: the height is *bounded*, at the
                // full height of the window. A bare `Center` is an `Align` with
                // no size factors, and `RenderPositionedBox` only shrink-wraps
                // an axis whose constraint is unbounded — given a bounded one it
                // takes all of it. So the bar measured 960dp instead of 120dp,
                // Scaffold gave the body the nothing that was left, and the
                // shutter came to rest in the exact middle of a black screen.
                // Every symptom followed from that: no preview, no guide
                // rectangle, no caption, and a shutter that still took photos.
                child: Center(
                  heightFactor: 1,
                  child: _ShutterButton(
                    busy: _capturing,
                    onPressed: _capture,
                  ),
                ),
              ),
            ),
    );
  }

  Widget _viewfinder(CameraController controller) => Stack(
        fit: StackFit.expand,
        children: [
          Center(child: CameraPreview(controller)),
          // The guide is the instruction. "Fill the frame, hold it square" is
          // a sentence people skip; a rectangle they line the menu up inside
          // is one they follow without reading anything.
          IgnorePointer(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white70, width: 2),
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 16,
            child: Text(
              'Fill the frame with the menu and hold the phone square on.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70),
            ),
          ),
        ],
      );
}

class _ShutterButton extends StatelessWidget {
  const _ShutterButton({required this.busy, required this.onPressed});

  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: busy ? null : onPressed,
        child: Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: busy ? Colors.white24 : Colors.white,
            border: Border.all(color: Colors.white70, width: 4),
          ),
          child: busy
              ? const Padding(
                  padding: EdgeInsets.all(20),
                  child: CircularProgressIndicator(strokeWidth: 3),
                )
              : null,
        ),
      );
}

class _Message extends StatelessWidget {
  const _Message(this.message);

  final String message;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white),
          ),
        ),
      );
}

/// Opens the viewfinder and returns the JPEG bytes, or null if it was backed
/// out of.
Future<Uint8List?> captureMenuPhoto(BuildContext context) =>
    Navigator.of(context).push<Uint8List>(
      MaterialPageRoute(builder: (_) => const MenuCapturePage()),
    );
