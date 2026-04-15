import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/theme/app_theme.dart';
import '../../logic/session_cubit.dart';
import '../../../../core/di/odoo_cubit.dart';
import './login_screen.dart';
import '../../../dashboard/ui/screens/dashboard_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late AnimationController _logoCtrl;
  late AnimationController _textCtrl;
  late AnimationController _shimmerCtrl;

  late Animation<double> _logoScale;
  late Animation<double> _logoFade;
  late Animation<double> _textFade;
  late Animation<Offset> _textSlide;
  late Animation<double> _shimmer;

  @override
  void initState() {
    super.initState();
    _logoCtrl    = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
    _textCtrl    = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
    _shimmerCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500))
      ..repeat(reverse: true);

    _logoScale = Tween<double>(begin: 0.0, end: 1.0)
        .animate(CurvedAnimation(parent: _logoCtrl, curve: Curves.elasticOut));
    _logoFade  = CurvedAnimation(parent: _logoCtrl, curve: Curves.easeIn);
    _textFade  = CurvedAnimation(parent: _textCtrl, curve: Curves.easeIn);
    _textSlide = Tween<Offset>(begin: const Offset(0, 0.4), end: Offset.zero)
        .animate(CurvedAnimation(parent: _textCtrl, curve: Curves.easeOut));
    _shimmer   = CurvedAnimation(parent: _shimmerCtrl, curve: Curves.easeInOut);

    _logoCtrl.forward().then((_) => _textCtrl.forward());
    Future.delayed(const Duration(milliseconds: 2400), _checkSession);
  }

  Future<void> _checkSession() async {
    if (!mounted) return;
    final session = context.read<SessionCubit>();
    final odoo    = context.read<OdooCubit>();
    final hasSaved = await session.tryRestoreSession();
    if (!mounted) return;
    if (hasSaved) {
      try {
        await odoo.initAndAuth(
          serverUrl: session.serverUrl,
          login    : session.odooLogin,
          password : session.odooPass,
        );
        if (!mounted) return;
        Navigator.pushReplacement(context,
            MaterialPageRoute(builder: (_) => const DashboardScreen()));
        return;
      } catch (_) {}
    }
    if (!mounted) return;
    Navigator.pushReplacement(context,
        MaterialPageRoute(builder: (_) => const LoginScreen()));
  }

  @override
  void dispose() {
    _logoCtrl.dispose();
    _textCtrl.dispose();
    _shimmerCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF1A1A2E), Color(0xFF16213E), Color(0xFF0F3460)],
          ),
        ),
        child: Stack(
          children: [
            // Decorative circles
            Positioned(top: -80, right: -80,
                child: Container(width: 260, height: 260,
                    decoration: BoxDecoration(shape: BoxShape.circle,
                        color: AppTheme.primary.withOpacity(0.08)))),
            Positioned(bottom: -100, left: -60,
                child: Container(width: 320, height: 320,
                    decoration: BoxDecoration(shape: BoxShape.circle,
                        color: AppTheme.primary.withOpacity(0.06)))),
            Positioned(top: 120, left: -40,
                child: Container(width: 180, height: 180,
                    decoration: BoxDecoration(shape: BoxShape.circle,
                        color: AppTheme.primary.withOpacity(0.04)))),

            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Logo
                  ScaleTransition(
                    scale: _logoScale,
                    child: FadeTransition(
                      opacity: _logoFade,
                      child: AnimatedBuilder(
                        animation: _shimmer,
                        builder: (_, child) => Container(
                          width: 120, height: 120,
                          decoration: BoxDecoration(
                            color: AppTheme.primary,
                            borderRadius: BorderRadius.circular(36),
                            boxShadow: [BoxShadow(
                              color: AppTheme.primary.withOpacity(0.3 + _shimmer.value * 0.25),
                              blurRadius: 30 + _shimmer.value * 20,
                              spreadRadius: 2 + _shimmer.value * 4,
                            )],
                          ),
                          child: child,
                        ),
                        child: const Icon(Icons.build_circle_outlined,
                            size: 64, color: Colors.white),
                      ),
                    ),
                  ),
                  const SizedBox(height: 36),

                  // Text
                  SlideTransition(
                    position: _textSlide,
                    child: FadeTransition(
                      opacity: _textFade,
                      child: Column(children: [
                        Text('Maintenance',
                            style: GoogleFonts.inter(
                                fontSize: 38, fontWeight: FontWeight.w900,
                                color: Colors.white, letterSpacing: 0.5)),
                        const SizedBox(height: 8),
                        AnimatedBuilder(
                          animation: _shimmer,
                          builder: (_, __) => Text('Powered by Odoo',
                              style: GoogleFonts.inter(
                                  fontSize: 14, fontWeight: FontWeight.w500,
                                  color: Colors.white.withOpacity(0.55 + _shimmer.value * 0.3),
                                  letterSpacing: 1.4)),
                        ),
                      ]),
                    ),
                  ),
                  const SizedBox(height: 72),

                  // Dots loader
                  FadeTransition(
                    opacity: _textFade,
                    child: _DotsLoader(),
                  ),
                ],
              ),
            ),

            // Version tag
            Positioned(bottom: 36, left: 0, right: 0,
              child: FadeTransition(
                opacity: _textFade,
                child: Center(
                  child: Text('v1.0.0',
                      style: GoogleFonts.inter(
                          fontSize: 12,
                          color: Colors.white.withOpacity(0.25),
                          letterSpacing: 1)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DotsLoader extends StatefulWidget {
  @override
  State<_DotsLoader> createState() => _DotsLoaderState();
}
class _DotsLoaderState extends State<_DotsLoader>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat();
  }
  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(3, (i) {
          final delay = i / 3;
          final t = ((_ctrl.value - delay) % 1.0).clamp(0.0, 1.0);
          final scale = 0.5 + 0.5 * (1 - (t - 0.5).abs() * 2).clamp(0.0, 1.0);
          return Container(
            margin: const EdgeInsets.symmetric(horizontal: 5),
            width: 10 * scale, height: 10 * scale,
            decoration: BoxDecoration(
              color: AppTheme.primary.withOpacity(0.4 + 0.6 * scale),
              shape: BoxShape.circle,
            ),
          );
        }),
      ),
    );
  }
}
