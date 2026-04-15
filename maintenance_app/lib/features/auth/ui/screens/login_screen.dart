import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/theme/app_theme.dart';
import '../../logic/session_cubit.dart';
import '../../../../core/di/odoo_cubit.dart';
import '../../../../core/helpers/db_helper.dart';
import '../../../dashboard/ui/screens/dashboard_screen.dart';
import './signup_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _urlCtrl        = TextEditingController(text: 'https://odooprosys-alqased-main-27173048.dev.odoo.com');
  final _emailCtrl      = TextEditingController();
  final _passCtrl       = TextEditingController();

  bool    _obscure       = true;
  bool    _loading       = false;
  String? _errorMsg;
  String  _status        = '';

  @override
  void dispose() {
    _urlCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final url   = _urlCtrl.text.trim();
    final email = _emailCtrl.text.trim();
    final pass  = _passCtrl.text;

    if (url.isEmpty || email.isEmpty || pass.isEmpty) {
      setState(() => _errorMsg = 'Please fill in all fields.');
      return;
    }
    final parsedUri = Uri.tryParse(url.startsWith('http') ? url : 'https://$url');
    if (parsedUri == null || parsedUri.host.isEmpty) {
      setState(() => _errorMsg = 'Invalid Server URL. Example: https://yourcompany.odoo.com');
      return;
    }

    setState(() { _errorMsg = null; _loading = true; _status = 'Connecting to server...'; });

    try {
      final odoo    = context.read<OdooCubit>();
      final session = context.read<SessionCubit>();

      setState(() => _status = 'Connecting to server...');
      await odoo.initAndAuth(serverUrl: url, login: email, password: pass);
      if (!mounted) return;
      setState(() => _status = 'Saving session...');
      await session.saveSession(
        serverUrl: url, odooLogin: email, odooPass: pass,
        name: email.split('@').first, email: email,
      );
      await DBHelper.registerUser(name: email.split('@').first, email: email, password: pass, serverUrl: url);
      if (!mounted) return;
      Navigator.pushReplacement(context,
          MaterialPageRoute(builder: (_) => const DashboardScreen()));
    } catch (e) {
      setState(() {
        _errorMsg = e.toString().replaceAll('OdooException: ', '');
        _loading  = false;
        _status   = '';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: MediaQuery.of(context).size.height
                  - MediaQuery.of(context).padding.top
                  - MediaQuery.of(context).padding.bottom,
            ),
            child: IntrinsicHeight(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Spacer(flex: 2),

                  // ── Logo ────────────────────────────────────────────────
                  Center(
                    child: Container(
                      width: 80, height: 80,
                      decoration: BoxDecoration(
                        color: AppTheme.primary,
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [BoxShadow(
                          color: AppTheme.primary.withOpacity(0.35),
                          blurRadius: 24, offset: const Offset(0, 8),
                        )],
                      ),
                      child: const Icon(Icons.build_circle_outlined,
                          size: 44, color: Colors.white),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Center(child: Text('Sign In to Odoo',
                      style: GoogleFonts.inter(fontSize: 26, fontWeight: FontWeight.w800,
                          color: AppTheme.textDark))),
                  const SizedBox(height: 6),
                  Center(child: Text('Enter your Odoo server credentials',
                      style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textGrey))),
                  const SizedBox(height: 36),

                  // ── Server URL ─────────────────────────────────────────
                  _label('SERVER URL'),
                  const SizedBox(height: 8),
                  _field(ctrl: _urlCtrl, hint: 'https://yourcompany.odoo.com',
                      icon: Icons.link_outlined, kb: TextInputType.url, readOnly: true),
                  const SizedBox(height: 18),

                  // ── Username ───────────────────────────────────────────
                  _label('USERNAME'),
                  const SizedBox(height: 8),
                  _field(ctrl: _emailCtrl, hint: 'e.g. admin or you@company.com',
                      icon: Icons.person_outline, kb: TextInputType.text),
                  const SizedBox(height: 18),

                  // ── Password ───────────────────────────────────────────
                  _label('PASSWORD'),
                  const SizedBox(height: 8),
                  _passField(),

                  const SizedBox(height: 14),

                  // ── Status ─────────────────────────────────────────────
                  if (_loading && _status.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Row(children: [
                      SizedBox(width: 14, height: 14,
                          child: CircularProgressIndicator(
                              color: AppTheme.primary, strokeWidth: 2)),
                      const SizedBox(width: 10),
                      Text(_status, style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textGrey)),
                    ]),
                  ],

                  // ── Error ──────────────────────────────────────────────
                  if (_errorMsg != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: AppTheme.error.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppTheme.error.withOpacity(0.4)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.error_outline, color: AppTheme.error, size: 18),
                          const SizedBox(width: 8),
                          Expanded(child: Text(_errorMsg!,
                              style: GoogleFonts.inter(fontSize: 12, color: AppTheme.error,
                                  fontWeight: FontWeight.w500, height: 1.5))),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 28),

                  // ── Login Button ───────────────────────────────────────
                  SizedBox(
                    width: double.infinity, height: 52,
                    child: ElevatedButton(
                      onPressed: _loading ? null : _login,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                        elevation: 0,
                      ),
                      child: _loading
                          ? const SizedBox(width: 22, height: 22,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                          : Text('CONNECT TO ODOO',
                          style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700,
                              letterSpacing: 1.2, color: Colors.white)),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // ── Sign Up link ───────────────────────────────────────
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text("Don't have an account? ",
                          style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textGrey)),
                      GestureDetector(
                        onTap: () => Navigator.push(context,
                            MaterialPageRoute(builder: (_) => const SignUpScreen())),
                        child: Text('Sign Up',
                            style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700,
                                color: AppTheme.primary)),
                      ),
                    ],
                  ),

                  const Spacer(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _label(String t) => Text(t,
      style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700,
          color: AppTheme.textDark, letterSpacing: 0.6));

  Widget _field({required TextEditingController ctrl, required String hint,
    required IconData icon, TextInputType kb = TextInputType.text, bool readOnly = false}) {
    return Container(
      height: 52,
      decoration: BoxDecoration(
        color: readOnly ? Colors.grey.shade50 : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(children: [
        const SizedBox(width: 14),
        Icon(icon, size: 18, color: AppTheme.textGrey),
        const SizedBox(width: 10),
        Expanded(child: TextField(
          controller: ctrl,
          keyboardType: kb,
          readOnly: readOnly,
          style: GoogleFonts.inter(fontSize: 14, color: readOnly ? AppTheme.textGrey : AppTheme.textDark),
          decoration: InputDecoration(hintText: hint,
              hintStyle: GoogleFonts.inter(color: AppTheme.textGrey, fontSize: 13),
              border: InputBorder.none, isDense: true),
        )),
      ]),
    );
  }

  Widget _passField() {
    return Container(
      height: 52,
      decoration: BoxDecoration(color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200)),
      child: Row(children: [
        const SizedBox(width: 14),
        Icon(Icons.lock_outline, size: 18, color: AppTheme.textGrey),
        const SizedBox(width: 10),
        Expanded(child: TextField(
          controller: _passCtrl, obscureText: _obscure,
          style: GoogleFonts.inter(fontSize: 14, color: AppTheme.textDark),
          decoration: InputDecoration(
            hintText: '••••••••',
            hintStyle: GoogleFonts.inter(color: AppTheme.textGrey, fontSize: 14),
            border: InputBorder.none, isDense: true,
          ),
        )),
        IconButton(
          icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
              color: AppTheme.textGrey, size: 20),
          onPressed: () => setState(() => _obscure = !_obscure),
        ),
      ]),
    );
  }
}
