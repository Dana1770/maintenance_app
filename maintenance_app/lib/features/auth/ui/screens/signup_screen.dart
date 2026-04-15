import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/helpers/db_helper.dart';
import '../../logic/session_cubit.dart';
import '../../../../core/di/odoo_cubit.dart';
import '../../../dashboard/ui/screens/dashboard_screen.dart';
import './login_screen.dart';

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});
  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _nameCtrl    = TextEditingController();
  final _urlCtrl     = TextEditingController(text: 'https://odooprosys-alqased.odoo.com');
  final _emailCtrl   = TextEditingController();
  final _passCtrl    = TextEditingController();
  final _confirmCtrl = TextEditingController();

  bool    _obscure1  = true;
  bool    _obscure2  = true;
  bool    _loading   = false;
  String? _errorMsg;
  String  _status    = '';

  @override
  void dispose() {
    _nameCtrl.dispose(); _urlCtrl.dispose(); _emailCtrl.dispose();
    _passCtrl.dispose(); _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _signUp() async {
    final name  = _nameCtrl.text.trim();
    final url   = _urlCtrl.text.trim();
    final email = _emailCtrl.text.trim();
    final pass  = _passCtrl.text;
    final conf  = _confirmCtrl.text;

    if (name.isEmpty || url.isEmpty || email.isEmpty || pass.isEmpty || conf.isEmpty) {
      setState(() => _errorMsg = 'Please fill in all fields.');
      return;
    }
    if (!email.contains('@')) {
      setState(() => _errorMsg = 'Enter a valid email address.');
      return;
    }
    if (pass.length < 6) {
      setState(() => _errorMsg = 'Password must be at least 6 characters.');
      return;
    }
    if (pass != conf) {
      setState(() => _errorMsg = 'Passwords do not match.');
      return;
    }

    setState(() { _errorMsg = null; _loading = true; _status = 'Creating account...'; });

    try {
      // Save locally
      final regError = await DBHelper.registerUser(
          name: name, email: email, password: pass, serverUrl: url);
      if (regError != null) {
        setState(() { _errorMsg = regError; _loading = false; _status = ''; });
        return;
      }

      setState(() => _status = 'Connecting to Odoo...');
      final odoo = context.read<OdooCubit>();
      await odoo.initAndAuth(serverUrl: url, login: email, password: pass);
      if (!mounted) return;

      await context.read<SessionCubit>().saveSession(
        serverUrl: url, odooLogin: email, odooPass: pass,
        name: name, email: email,
      );
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(context,
          MaterialPageRoute(builder: (_) => const DashboardScreen()), (_) => false);
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 24),
              // Back
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                      color: Colors.white, borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade200)),
                  child: const Icon(Icons.arrow_back_ios, size: 16, color: AppTheme.textDark),
                ),
              ),
              const SizedBox(height: 24),

              // Header
              Text('Create Account',
                  style: GoogleFonts.inter(fontSize: 26, fontWeight: FontWeight.w800, color: AppTheme.textDark)),
              const SizedBox(height: 6),
              Text('Fill in your details to get started',
                  style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textGrey)),
              const SizedBox(height: 32),

              // Fields
              _label('FULL NAME'),
              const SizedBox(height: 8),
              _field(ctrl: _nameCtrl, hint: 'Full Name', icon: Icons.person_outline),
              const SizedBox(height: 16),

              _label('SERVER URL'),
              const SizedBox(height: 8),
              _field(ctrl: _urlCtrl, hint: 'https://yourcompany.odoo.com',
                  icon: Icons.link_outlined, kb: TextInputType.url, readOnly: true),
              const SizedBox(height: 16),

              _label('EMAIL'),
              const SizedBox(height: 8),
              _field(ctrl: _emailCtrl, hint: 'email@company.com',
                  icon: Icons.email_outlined, kb: TextInputType.emailAddress),
              const SizedBox(height: 16),

              _label('PASSWORD'),
              const SizedBox(height: 8),
              _passField(_passCtrl, _obscure1, () => setState(() => _obscure1 = !_obscure1)),
              const SizedBox(height: 16),

              _label('CONFIRM PASSWORD'),
              const SizedBox(height: 8),
              _passField(_confirmCtrl, _obscure2, () => setState(() => _obscure2 = !_obscure2)),

              // Status
              if (_loading && _status.isNotEmpty) ...[
                const SizedBox(height: 14),
                Row(children: [
                  SizedBox(width: 14, height: 14,
                      child: CircularProgressIndicator(color: AppTheme.primary, strokeWidth: 2)),
                  const SizedBox(width: 10),
                  Text(_status, style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textGrey)),
                ]),
              ],

              // Error
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
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Icon(Icons.error_outline, color: AppTheme.error, size: 18),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_errorMsg!,
                        style: GoogleFonts.inter(fontSize: 12, color: AppTheme.error,
                            fontWeight: FontWeight.w500))),
                  ]),
                ),
              ],

              const SizedBox(height: 28),

              // Create button
              SizedBox(
                width: double.infinity, height: 52,
                child: ElevatedButton(
                  onPressed: _loading ? null : _signUp,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                  child: _loading
                      ? const SizedBox(width: 22, height: 22,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                      : Text('CREATE ACCOUNT',
                      style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700,
                          letterSpacing: 1.2, color: Colors.white)),
                ),
              ),
              const SizedBox(height: 20),

              // Login link
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('Already have an account? ',
                      style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textGrey)),
                  GestureDetector(
                    onTap: () => Navigator.pushReplacement(context,
                        MaterialPageRoute(builder: (_) => const LoginScreen())),
                    child: Text('Sign In',
                        style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700,
                            color: AppTheme.primary)),
                  ),
                ],
              ),
              const SizedBox(height: 32),
            ],
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
          border: Border.all(color: Colors.grey.shade200)),
      child: Row(children: [
        const SizedBox(width: 14),
        Icon(icon, size: 18, color: AppTheme.textGrey),
        const SizedBox(width: 10),
        Expanded(child: TextField(
          controller: ctrl, keyboardType: kb,
          readOnly: readOnly,
          style: GoogleFonts.inter(fontSize: 14, color: readOnly ? AppTheme.textGrey : AppTheme.textDark),
          decoration: InputDecoration(hintText: hint,
              hintStyle: GoogleFonts.inter(color: AppTheme.textGrey, fontSize: 13),
              border: InputBorder.none, isDense: true),
        )),
      ]),
    );
  }

  Widget _passField(TextEditingController ctrl, bool obscure, VoidCallback toggle) {
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
          controller: ctrl, obscureText: obscure,
          style: GoogleFonts.inter(fontSize: 14, color: AppTheme.textDark),
          decoration: InputDecoration(hintText: '••••••••',
              hintStyle: GoogleFonts.inter(color: AppTheme.textGrey, fontSize: 14),
              border: InputBorder.none, isDense: true),
        )),
        IconButton(
          icon: Icon(obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
              color: AppTheme.textGrey, size: 20),
          onPressed: toggle,
        ),
      ]),
    );
  }
}
