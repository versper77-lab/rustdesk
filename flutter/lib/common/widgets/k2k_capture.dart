// K2K capture: area or full capture of the remote screen, taken from the
// image this side already shows (instant, full resolution, no remote round
// trip). The result goes to the local clipboard and is saved under
// Pictures\K2K. Bound to Ctrl+Shift+Z by default (see shortcuts.rs).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/models/model.dart';
import 'package:flutter_hbb/models/platform_model.dart';

const kShortcutActionK2kCapture = 'k2k_capture';

bool _k2kCaptureOpen = false;

Future<void> k2kCapture(BuildContext context, FFI ffi) async {
  if (_k2kCaptureOpen) return;
  final image = ffi.imageModel.image;
  if (image == null) {
    showToast(translate('k2k_capture_no_image'));
    return;
  }
  _k2kCaptureOpen = true;
  try {
    final rect = await showDialog<Rect>(
      context: context,
      barrierColor: Colors.black54,
      builder: (_) => _K2kCaptureDialog(image: image),
    );
    if (rect == null) return;
    await _k2kSave(ffi, image, rect);
  } finally {
    _k2kCaptureOpen = false;
  }
}

Future<void> _k2kSave(FFI ffi, ui.Image image, Rect rect) async {
  final r = rect.intersect(
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()));
  final w = r.width.round(), h = r.height.round();
  if (w < 2 || h < 2) return;
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawImageRect(
      image, r, Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()), Paint());
  final cropped = await recorder.endRecording().toImage(w, h);
  final png = await cropped.toByteData(format: ui.ImageByteFormat.png);
  cropped.dispose();
  if (png == null) return;
  final bytes = png.buffer.asUint8List();

  final err =
      await bind.sessionK2kCopyPng(sessionId: ffi.sessionId, data: bytes);
  String? saved;
  try {
    final home = Platform.environment['USERPROFILE'] ??
        Platform.environment['HOME'] ??
        '.';
    final sep = Platform.pathSeparator;
    final dir = Directory('$home${sep}Pictures${sep}K2K');
    await dir.create(recursive: true);
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final name = 'K2K_${now.year}${two(now.month)}${two(now.day)}_'
        '${two(now.hour)}${two(now.minute)}${two(now.second)}.png';
    final file = File('${dir.path}$sep$name');
    await file.writeAsBytes(bytes);
    saved = file.path;
  } catch (_) {}
  showToast(err.isEmpty
      ? '${translate('k2k_capture_done')}${saved != null ? '\n$saved' : ''}'
      : '${translate('Failed')}: $err');
}

class _K2kCaptureDialog extends StatefulWidget {
  final ui.Image image;
  const _K2kCaptureDialog({required this.image});

  @override
  State<_K2kCaptureDialog> createState() => _K2kCaptureDialogState();
}

class _K2kCaptureDialogState extends State<_K2kCaptureDialog> {
  Offset? _start;
  Offset? _end;

  Rect _full() => Rect.fromLTWH(
      0, 0, widget.image.width.toDouble(), widget.image.height.toDouble());

  @override
  Widget build(BuildContext context) {
    final img = widget.image;
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.black87,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.crop, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Text(translate('k2k_capture_hint'),
                    style: const TextStyle(color: Colors.white)),
                const SizedBox(width: 16),
                FilledButton.icon(
                  icon: const Icon(Icons.fullscreen, size: 18),
                  label: Text(translate('k2k_capture_full')),
                  onPressed: () => Navigator.of(context).pop(_full()),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(translate('Cancel'),
                      style: const TextStyle(color: Colors.white)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Flexible(
            child: LayoutBuilder(builder: (context, c) {
              final scale = [
                c.maxWidth / img.width,
                c.maxHeight / img.height,
                1.0
              ].reduce((a, b) => a < b ? a : b);
              final vw = img.width * scale, vh = img.height * scale;
              Rect? sel;
              if (_start != null && _end != null) {
                sel = Rect.fromPoints(_start!, _end!);
              }
              return GestureDetector(
                onSecondaryTap: () => Navigator.of(context).pop(),
                onPanStart: (d) => setState(() {
                  _start = d.localPosition;
                  _end = d.localPosition;
                }),
                onPanUpdate: (d) => setState(() => _end = Offset(
                    d.localPosition.dx.clamp(0, vw),
                    d.localPosition.dy.clamp(0, vh))),
                onPanEnd: (_) {
                  final s = sel;
                  if (s == null || s.width < 4 || s.height < 4) {
                    setState(() => _start = _end = null);
                    return;
                  }
                  Navigator.of(context).pop(Rect.fromLTRB(
                      s.left / scale, s.top / scale, s.right / scale,
                      s.bottom / scale));
                },
                child: MouseRegion(
                  cursor: SystemMouseCursors.precise,
                  child: SizedBox(
                    width: vw,
                    height: vh,
                    child: CustomPaint(
                      painter: _K2kCapturePainter(img, sel),
                    ),
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}

class _K2kCapturePainter extends CustomPainter {
  final ui.Image image;
  final Rect? sel;
  _K2kCapturePainter(this.image, this.sel);

  @override
  void paint(Canvas canvas, Size size) {
    final dst = Offset.zero & size;
    canvas.drawImageRect(
        image,
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        dst,
        Paint()..filterQuality = FilterQuality.medium);
    final s = sel;
    if (s == null) return;
    final shade = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(dst)
      ..addRect(s);
    canvas.drawPath(shade, Paint()..color = Colors.black45);
    canvas.drawRect(
        s,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = const Color(0xFF7C5CFF));
  }

  @override
  bool shouldRepaint(_K2kCapturePainter old) =>
      old.sel != sel || old.image != image;
}
