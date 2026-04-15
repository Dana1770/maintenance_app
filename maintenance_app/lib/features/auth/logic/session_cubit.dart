import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ── State ─────────────────────────────────────────────────────────────────────

class SessionState {
  final String serverUrl;
  final String odooLogin;
  final String odooPass;
  final String name;
  final String email;
  final String phone;
  final String photoPath;

  const SessionState({
    this.serverUrl = '',
    this.odooLogin = '',
    this.odooPass  = '',
    this.name      = '',
    this.email     = '',
    this.phone     = '',
    this.photoPath = '',
  });

  bool get isLoggedIn =>
      serverUrl.isNotEmpty && odooLogin.isNotEmpty && odooPass.isNotEmpty;

  /// Kept for profile_screen compatibility
  String get idCode => '';

  SessionState copyWith({
    String? serverUrl,
    String? odooLogin,
    String? odooPass,
    String? name,
    String? email,
    String? phone,
    String? photoPath,
  }) =>
      SessionState(
        serverUrl: serverUrl ?? this.serverUrl,
        odooLogin: odooLogin ?? this.odooLogin,
        odooPass:  odooPass  ?? this.odooPass,
        name:      name      ?? this.name,
        email:     email     ?? this.email,
        phone:     phone     ?? this.phone,
        photoPath: photoPath ?? this.photoPath,
      );
}

// ── Cubit ─────────────────────────────────────────────────────────────────────

class SessionCubit extends Cubit<SessionState> {
  SessionCubit() : super(const SessionState());

  // Convenience getters (mirrors old provider API so screens need minimal edits)
  String get serverUrl  => state.serverUrl;
  String get odooLogin  => state.odooLogin;
  String get odooPass   => state.odooPass;
  String get name       => state.name;
  String get email      => state.email;
  String get phone      => state.phone;
  String get photoPath  => state.photoPath;
  String get idCode     => '';
  bool   get isLoggedIn => state.isLoggedIn;

  Future<void> saveSession({
    required String serverUrl,
    required String odooLogin,
    required String odooPass,
    required String name,
    required String email,
    String phone = '',
  }) async {
    final url  = serverUrl.trim().replaceAll(RegExp(r'/$'), '');
    final resolvedName  = name.isNotEmpty  ? name  : odooLogin.split('@').first;
    final resolvedEmail = email.isNotEmpty ? email : odooLogin;

    final p = await SharedPreferences.getInstance();
    await p.setString('odoo_server_url', url);
    await p.setString('odoo_login',      odooLogin.trim());
    await p.setString('odoo_pass',       odooPass);
    await p.setString('odoo_name',       resolvedName);
    await p.setString('odoo_email',      resolvedEmail);
    await p.setString('odoo_phone',      phone);

    emit(state.copyWith(
      serverUrl: url,
      odooLogin: odooLogin.trim(),
      odooPass:  odooPass,
      name:      resolvedName,
      email:     resolvedEmail,
      phone:     phone,
    ));
  }

  Future<bool> tryRestoreSession() async {
    final p     = await SharedPreferences.getInstance();
    final url   = p.getString('odoo_server_url') ?? '';
    final login = p.getString('odoo_login')      ?? '';
    final pass  = p.getString('odoo_pass')        ?? '';
    if (url.isEmpty || login.isEmpty || pass.isEmpty) return false;

    emit(SessionState(
      serverUrl: url,
      odooLogin: login,
      odooPass:  pass,
      name:      p.getString('odoo_name')       ?? login.split('@').first,
      email:     p.getString('odoo_email')      ?? login,
      phone:     p.getString('odoo_phone')      ?? '',
      photoPath: p.getString('odoo_photo_path') ?? '',
    ));
    return true;
  }

  Future<String?> updateProfile({
    required String newName,
    required String newPhone,
    required String newPhotoPath,
  }) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString('odoo_name',       newName.trim());
      await p.setString('odoo_phone',      newPhone.trim());
      await p.setString('odoo_photo_path', newPhotoPath);

      emit(state.copyWith(
        name:      newName.trim(),
        phone:     newPhone.trim(),
        photoPath: newPhotoPath,
      ));
      return null; // null = success
    } catch (e) {
      return e.toString();
    }
  }

  Future<void> logout() async {
    final p = await SharedPreferences.getInstance();
    for (final k in [
      'odoo_server_url', 'odoo_login', 'odoo_pass',
      'odoo_name', 'odoo_email', 'odoo_phone', 'odoo_photo_path',
    ]) {
      await p.remove(k);
    }
    emit(const SessionState());
  }
}
