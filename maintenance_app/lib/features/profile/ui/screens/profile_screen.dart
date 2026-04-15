import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../auth/logic/language_cubit.dart';
import '../../../auth/logic/session_cubit.dart';
import '../../../../core/di/odoo_cubit.dart';
import '../../../../core/l10n/app_localizations.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _isEditing = false;
  late TextEditingController _nameCtrl;
  late TextEditingController _phoneCtrl;

  @override
  void initState() {
    super.initState();
    final s = context.read<SessionCubit>();
    _nameCtrl  = TextEditingController(text: s.name);
    _phoneCtrl = TextEditingController(text: s.phone);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picked = await ImagePicker()
        .pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (picked == null || !mounted) return;

    final session = context.read<SessionCubit>();
    final l = AppLocalizations.of(context);

    // Save photo path to DB immediately
    await session.updateProfile(
      newName     : session.name,
      newPhone    : session.phone,
      newPhotoPath: picked.path,
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(l.t('photo_saved'),
          style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
      backgroundColor: AppTheme.success,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  Future<void> _save() async {
    final l = AppLocalizations.of(context);
    final session = context.read<SessionCubit>();

    final error = await session.updateProfile(
      newName     : _nameCtrl.text.trim(),
      newPhone    : _phoneCtrl.text.trim(),
      newPhotoPath: session.photoPath, // keep existing photo
    );

    if (!mounted) return;
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(error, style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
        backgroundColor: AppTheme.error,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
    } else {
      setState(() => _isEditing = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(l.t('profile_updated'),
            style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
        backgroundColor: AppTheme.success,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l       = AppLocalizations.of(context);
    final session = context.watch<SessionCubit>();
    final lang    = context.watch<LanguageCubit>();

    // Sync controllers when not editing
    if (!_isEditing) {
      _nameCtrl.text  = session.name;
      _phoneCtrl.text = session.phone;
    }

    // Resolve photo widget
    Widget photoWidget;
    if (session.photoPath.isNotEmpty && File(session.photoPath).existsSync()) {
      photoWidget = Image.file(File(session.photoPath), fit: BoxFit.cover);
    } else {
      photoWidget = Image.network(
        'https://images.unsplash.com/photo-1560250097-0b93528c311a?w=200&h=200&fit=crop&crop=face',
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(
            color: Colors.grey.shade200,
            child: const Icon(Icons.person, size: 50, color: Colors.grey)),
      );
    }

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.background, elevation: 0,
        leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios, size: 18),
            onPressed: () => Navigator.pop(context)),
        title: Text(l.t('profile'),
            style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w700, color: AppTheme.textDark)),
        centerTitle: true,
        actions: [
          TextButton(
            onPressed: () => _isEditing ? _save() : setState(() => _isEditing = true),
            child: Text(_isEditing ? l.t('save') : l.t('edit'),
                style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.primary)),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Avatar ──────────────────────────────────────────────────
            Center(
              child: Stack(
                children: [
                  Container(
                    width: 90, height: 90,
                    decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: AppTheme.primary, width: 3)),
                    child: ClipOval(child: photoWidget),
                  ),
                  // Camera button always visible so user can change photo anytime
                  Positioned(
                    bottom: 0, right: 0,
                    child: GestureDetector(
                      onTap: _pickImage,
                      child: Container(
                          width: 28, height: 28,
                          decoration: const BoxDecoration(
                              color: AppTheme.primary, shape: BoxShape.circle),
                          child: const Icon(Icons.camera_alt, size: 14, color: Colors.white)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // ── Name ────────────────────────────────────────────────────
            Center(
              child: _isEditing
                  ? SizedBox(
                  width: 220,
                  child: TextField(
                    controller: _nameCtrl,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.w800, color: AppTheme.textDark),
                    decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.zero, border: InputBorder.none),
                  ))
                  : Text(session.name,
                  style: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.w800, color: AppTheme.textDark)),
            ),
            const SizedBox(height: 4),
            Center(child: Text(l.t('personal_info'),
                style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textGrey))),
            const SizedBox(height: 24),

            // ── Phone (editable) ─────────────────────────────────────────
            _infoCard(icon: Icons.phone_outlined, label: l.t('phone'),
                ctrl: _phoneCtrl, kb: TextInputType.phone),
            const SizedBox(height: 10),



            // ── Settings ─────────────────────────────────────────────────
            Text(l.t('settings'),
                style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700, color: AppTheme.textDark)),
            const SizedBox(height: 14),

            GestureDetector(
                onTap: () => _showLangPicker(context, lang, l),
                child: _row(icon: Icons.language_outlined, label: l.t('language'),
                    trailing: lang.currentLanguageName)),
            _div(),
            _row(icon: Icons.notifications_outlined,       label: l.t('notifications')),
            _div(),
            _row(icon: Icons.info_outline,                 label: l.t('about_app')),
            _div(),
            _row(icon: Icons.confirmation_number_outlined, label: l.t('tickets')),
            _div(),
            _row(icon: Icons.history_outlined,             label: l.t('previous_tasks')),

          ],
        ),
      ),
    );
  }
  // Editable card
  Widget _infoCard({
    required IconData icon,
    required String label,
    required TextEditingController ctrl,
    TextInputType kb = TextInputType.text,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(color: const Color(0xFFFFF8E1), borderRadius: BorderRadius.circular(14)),
      child: Row(children: [
        Container(width: 36, height: 36,
            decoration: BoxDecoration(color: AppTheme.primary.withOpacity(0.2), shape: BoxShape.circle),
            child: Icon(icon, size: 18, color: AppTheme.primary)),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: GoogleFonts.inter(fontSize: 10, color: AppTheme.textGrey, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
          const SizedBox(height: 2),
          _isEditing
              ? TextField(
              controller: ctrl, keyboardType: kb,
              style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.textDark),
              decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.zero, border: InputBorder.none))
              : Text(ctrl.text,
              style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.textDark)),
        ])),
      ]),
    );
  }

  // Always read-only card
  Widget _readonlyCard({required IconData icon, required String label, required String value}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(color: const Color(0xFFFFF8E1), borderRadius: BorderRadius.circular(14)),
      child: Row(children: [
        Container(width: 36, height: 36,
            decoration: BoxDecoration(color: AppTheme.primary.withOpacity(0.2), shape: BoxShape.circle),
            child: Icon(icon, size: 18, color: AppTheme.primary)),
        const SizedBox(width: 14),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: GoogleFonts.inter(fontSize: 10, color: AppTheme.textGrey, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
          const SizedBox(height: 2),
          Text(value, style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.textDark)),
        ]),
      ]),
    );
  }

  Widget _row({required IconData icon, required String label, String? trailing}) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(children: [
        Icon(icon, size: 20, color: AppTheme.primary),
        const SizedBox(width: 14),
        Expanded(child: Text(label,
            style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w500, color: AppTheme.textDark))),
        if (trailing != null) ...[
          Text(trailing, style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textGrey)),
          const SizedBox(width: 8),
        ],
        const Icon(Icons.chevron_right, color: Colors.grey, size: 20),
      ]),
    );
  }

  Widget _div() => Divider(color: Colors.grey.shade200, height: 1, thickness: 1);

  void _showLangPicker(BuildContext ctx, LanguageCubit lang, AppLocalizations l) {
    showModalBottomSheet(
      context: ctx,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 40, height: 4,
              decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 20),
          Text(l.t('select_language'),
              style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700, color: AppTheme.textDark)),
          const SizedBox(height: 16),
          ...LanguageCubit.supportedLanguages.keys.map((name) => ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(name, style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w500, color: AppTheme.textDark)),
            trailing: lang.currentLanguageName == name
                ? const Icon(Icons.check_circle, color: AppTheme.primary) : null,
            onTap: () async {
              await lang.setLanguage(name);
              if (ctx.mounted) Navigator.pop(ctx);
            },
          )),
        ]),
      ),
    );
  }
}