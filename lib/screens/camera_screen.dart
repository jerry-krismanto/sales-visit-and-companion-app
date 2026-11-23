import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

/// In-app camera: photos can only come from this viewfinder, never from the
/// gallery or another camera app. Pops the captured XFile, or null if cancelled.
class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> with WidgetsBindingObserver {
  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  CameraDescription? _camera;
  bool _initializing = false;
  String? _error;
  bool _permissionDenied = false;
  bool _taking = false;
  XFile? _captured;
  FlashMode _flash = FlashMode.off;

  bool get _canSwitch {
    final dirs = _cameras.map((c) => c.lensDirection).toSet();
    return dirs.contains(CameraLensDirection.back) &&
        dirs.contains(CameraLensDirection.front);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  /// Release the camera when the app goes to the background; reopen it on return
  /// (also picks up a permission granted in the phone's settings).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive) {
      final c = _controller;
      if (c != null) {
        _controller = null;
        c.dispose();
        if (mounted) setState(() {});
      }
    } else if (state == AppLifecycleState.resumed) {
      if (_controller == null && _captured == null) _init();
    }
  }

  /// Opens [_camera] (the back camera the first time).
  Future<void> _init() async {
    if (_initializing) return;
    _initializing = true;
    setState(() {
      _error = null;
      _permissionDenied = false;
    });
    try {
      if (_cameras.isEmpty) {
        _cameras = await availableCameras();
        if (_cameras.isEmpty) {
          if (mounted) setState(() => _error = 'Kamera tidak ditemukan.');
          return;
        }
      }
      _camera ??= _cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => _cameras.first,
      );

      final controller = CameraController(
        _camera!,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await controller.initialize();
      try {
        await controller.setFlashMode(_flash);
      } catch (_) {
        // no flash on this camera
      }

      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() => _controller = controller);
    } on CameraException catch (e) {
      if (!mounted) return;
      final denied = e.code.startsWith('CameraAccess');
      setState(() {
        _permissionDenied = denied;
        _error = denied
            ? 'Izin kamera diperlukan untuk mengambil foto kunjungan.'
            : 'Kamera tidak dapat dibuka (${e.code}).';
      });
    } finally {
      _initializing = false;
    }
  }

  /// Back <-> front.
  Future<void> _switchCamera() async {
    if (!_canSwitch || _initializing || _taking) return;

    final target = _camera?.lensDirection == CameraLensDirection.front
        ? CameraLensDirection.back
        : CameraLensDirection.front;
    final next = _cameras.firstWhere((c) => c.lensDirection == target);

    final old = _controller;
    setState(() {
      _controller = null;
      _camera = next;
      _flash = FlashMode.off; // most front cameras have no flash
    });
    await old?.dispose();
    await _init();
  }

  Future<void> _takePicture() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized || _taking || c.value.isTakingPicture) {
      return;
    }
    setState(() => _taking = true);
    try {
      final file = await c.takePicture();
      if (mounted) setState(() => _captured = file);
    } on CameraException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal mengambil foto (${e.code}).')),
        );
      }
    } finally {
      if (mounted) setState(() => _taking = false);
    }
  }

  void _retake() {
    final f = _captured;
    setState(() => _captured = null);
    if (f != null) File(f.path).delete().ignore();
    if (_controller == null) _init();
  }

  Future<void> _toggleFlash() async {
    final next = switch (_flash) {
      FlashMode.off => FlashMode.auto,
      FlashMode.auto => FlashMode.always,
      _ => FlashMode.off,
    };
    try {
      await _controller?.setFlashMode(next);
      if (mounted) setState(() => _flash = next);
    } on CameraException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Flash tidak tersedia di kamera ini.')),
        );
      }
    }
  }

  IconData get _flashIcon => switch (_flash) {
        FlashMode.auto => Icons.flash_auto,
        FlashMode.always => Icons.flash_on,
        _ => Icons.flash_off,
      };

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // back on the review screen returns to the viewfinder instead of closing
      canPop: _captured == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _retake();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(child: _captured != null ? _review() : _viewfinder()),
      ),
    );
  }

  Widget _viewfinder() {
    final c = _controller;
    final ready = c != null && c.value.isInitialized;

    final Widget preview;
    if (_error != null) {
      preview = _errorView();
    } else if (!ready) {
      preview = const CircularProgressIndicator();
    } else {
      preview = CameraPreview(c);
    }

    return Column(
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: IconButton(
            icon: const Icon(Icons.close, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        Expanded(child: Center(child: preview)),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IconButton(
                tooltip: 'Flash',
                icon: Icon(_flashIcon, color: ready ? Colors.white : Colors.white38),
                onPressed: ready ? _toggleFlash : null,
              ),
              GestureDetector(
                onTap: ready ? _takePicture : null,
                child: Container(
                  width: 72,
                  height: 72,
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 4),
                  ),
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: (!ready || _taking) ? Colors.white38 : Colors.white,
                    ),
                  ),
                ),
              ),
              if (_canSwitch)
                IconButton(
                  tooltip: 'Ganti kamera',
                  icon: Icon(
                    Icons.cameraswitch_outlined,
                    color: ready ? Colors.white : Colors.white38,
                  ),
                  onPressed: ready ? _switchCamera : null,
                )
              else
                const SizedBox(width: 48), // keeps the shutter centered
            ],
          ),
        ),
      ],
    );
  }

  Widget _errorView() {
    final style = OutlinedButton.styleFrom(
      foregroundColor: Colors.white,
      side: const BorderSide(color: Colors.white54),
    );
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white),
          ),
          const SizedBox(height: 16),
          if (_permissionDenied)
            OutlinedButton(
              style: style,
              onPressed: () => Geolocator.openAppSettings(),
              child: const Text('Buka Pengaturan'),
            )
          else
            OutlinedButton(
              style: style,
              onPressed: _init,
              child: const Text('Coba Lagi'),
            ),
        ],
      ),
    );
  }

  Widget _review() {
    return Column(
      children: [
        Expanded(
          child: Center(
            child: Image.file(File(_captured!.path), fit: BoxFit.contain),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white54),
                  ),
                  onPressed: _retake,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Ulangi'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => Navigator.pop(context, _captured),
                  icon: const Icon(Icons.check),
                  label: const Text('Gunakan Foto'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}