import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/theme/app_theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// SignatureScreen
// Full-screen landscape-friendly pad where the customer draws their signature.
// Returns a Uint8List (PNG bytes) via Navigator.pop when the user taps Done.
// ─────────────────────────────────────────────────────────────────────────────

class SignatureScreen extends StatefulWidget {
  final String customerName;
  final String taskName;

  const SignatureScreen({
    super.key,
    required this.customerName,
    required this.taskName,
  });

  @override
  State<SignatureScreen> createState() => _SignatureScreenState();
}

class _SignatureScreenState extends State<SignatureScreen> {
  final List<List<Offset>> _strokes = []; // each inner list = one continuous stroke
  bool _isSaving = false;
  bool _hasSignature = false;

  // Key used to capture the signature canvas as an image
  final GlobalKey _canvasKey = GlobalKey();

  void _onPanStart(DragStartDetails d) {
    setState(() {
      _strokes.add([d.localPosition]);
      _hasSignature = true;
    });
  }

  void _onPanUpdate(DragUpdateDetails d) {
    setState(() {
      if (_strokes.isNotEmpty) {
        _strokes.last.add(d.localPosition);
      }
    });
  }

  void _onPanEnd(DragEndDetails _) {
    // stroke is already complete — no action needed
    setState(() {});
  }

  void _clear() {
    setState(() {
      _strokes.clear();
      _hasSignature = false;
    });
  }

  Future<void> _done() async {
    if (!_hasSignature) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Please sign before tapping Done.',
            style: GoogleFonts.inter(fontSize: 13)),
        backgroundColor: Colors.orange.shade700,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
      return;
    }

    setState(() => _isSaving = true);

    try {
      // Capture the RepaintBoundary as a PNG image
      final boundary = _canvasKey.currentContext!.findRenderObject()
          as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final pngBytes = byteData!.buffer.asUint8List();

      if (mounted) Navigator.pop(context, pngBytes);
    } catch (e) {
      debugPrint('[SignatureScreen] capture error: $e');
      setState(() => _isSaving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed to capture signature. Try again.',
              style: GoogleFonts.inter(fontSize: 13)),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: AppTheme.textDark),
          onPressed: () => Navigator.pop(context, null),
        ),
        title: Text('Customer Signature',
            style: GoogleFonts.inter(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppTheme.textDark)),
        centerTitle: true,
        actions: [
          TextButton.icon(
            onPressed: _hasSignature ? _clear : null,
            icon: Icon(Icons.refresh,
                color: _hasSignature ? Colors.red.shade400 : Colors.grey.shade300,
                size: 18),
            label: Text('Clear',
                style: GoogleFonts.inter(
                    color: _hasSignature ? Colors.red.shade400 : Colors.grey.shade300,
                    fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          // ── Header info ────────────────────────────────────────────────
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            color: AppTheme.primary.withOpacity(0.06),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Customer: ${widget.customerName}',
                    style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textDark)),
                const SizedBox(height: 2),
                Text('Task: ${widget.taskName}',
                    style: GoogleFonts.inter(
                        fontSize: 12, color: AppTheme.textGrey),
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),

          // ── Signature canvas ───────────────────────────────────────────
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Stack(
                children: [
                  // White canvas with border
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                          color: _hasSignature
                              ? AppTheme.primary.withOpacity(0.4)
                              : Colors.grey.shade300,
                          width: 2),
                      boxShadow: [
                        BoxShadow(
                            color: Colors.black.withOpacity(0.04),
                            blurRadius: 12,
                            offset: const Offset(0, 4))
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: RepaintBoundary(
                        key: _canvasKey,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onPanStart: _onPanStart,
                          onPanUpdate: _onPanUpdate,
                          onPanEnd: _onPanEnd,
                          child: SizedBox.expand(
                            child: CustomPaint(
                              painter: _SignaturePainter(strokes: _strokes),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                  // Placeholder hint when canvas is empty
                  if (!_hasSignature)
                    IgnorePointer(
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.draw_outlined,
                                size: 48,
                                color: Colors.grey.shade300),
                            const SizedBox(height: 12),
                            Text('Sign here',
                                style: GoogleFonts.inter(
                                    fontSize: 16,
                                    color: Colors.grey.shade400,
                                    fontWeight: FontWeight.w500)),
                          ],
                        ),
                      ),
                    ),

                  // Baseline at bottom of canvas
                  Positioned(
                    left: 24, right: 24, bottom: 40,
                    child: Container(
                        height: 1, color: Colors.grey.shade300),
                  ),
                  Positioned(
                    left: 24, bottom: 24,
                    child: Text('Sign above the line',
                        style: GoogleFonts.inter(
                            fontSize: 10,
                            color: Colors.grey.shade400)),
                  ),
                ],
              ),
            ),
          ),

          // ── Done button ────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
            child: SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton.icon(
                onPressed: (_isSaving || !_hasSignature) ? null : _done,
                style: ElevatedButton.styleFrom(
                    backgroundColor: _hasSignature
                        ? AppTheme.primary
                        : Colors.grey.shade300,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16))),
                icon: _isSaving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2.5))
                    : Icon(Icons.check_circle_outline,
                        color: _hasSignature
                            ? Colors.white
                            : Colors.grey.shade500,
                        size: 22),
                label: Text(
                    _isSaving ? 'Saving…' : 'Done – Save Signature',
                    style: GoogleFonts.inter(
                        color: _hasSignature
                            ? Colors.white
                            : Colors.grey.shade600,
                        fontWeight: FontWeight.w800,
                        fontSize: 15)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Custom painter that draws the signature strokes
// ─────────────────────────────────────────────────────────────────────────────
class _SignaturePainter extends CustomPainter {
  final List<List<Offset>> strokes;

  _SignaturePainter({required this.strokes});

  @override
  void paint(Canvas canvas, Size size) {
    // Fill white background (needed for RepaintBoundary image capture)
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = Colors.white,
    );

    final paint = Paint()
      ..color = const Color(0xFF1A1A2E)
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    for (final stroke in strokes) {
      final points = stroke.whereType<Offset>().toList();
      if (points.isEmpty) continue;

      final path = Path();
      path.moveTo(points[0].dx, points[0].dy);

      if (points.length == 1) {
        // Single tap — draw a dot
        canvas.drawCircle(points[0], 2.0, paint..style = PaintingStyle.fill);
        paint.style = PaintingStyle.stroke;
        continue;
      }

      // Smooth curve through points using quadratic bezier
      for (int i = 0; i < points.length - 1; i++) {
        final mid = Offset(
          (points[i].dx + points[i + 1].dx) / 2,
          (points[i].dy + points[i + 1].dy) / 2,
        );
        if (i == 0) {
          path.lineTo(mid.dx, mid.dy);
        } else {
          path.quadraticBezierTo(
              points[i].dx, points[i].dy, mid.dx, mid.dy);
        }
      }
      path.lineTo(points.last.dx, points.last.dy);
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_SignaturePainter old) => true;
}
