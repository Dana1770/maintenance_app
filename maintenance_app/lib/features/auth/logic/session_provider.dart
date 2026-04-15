import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SessionProvider extends ChangeNotifier {
  String _serverUrl  = '';
  String _odooLogin  = '';
  String _odooPass   = '';
  String _name       = '';
  String _email      = '';
  String _phone      = '';
  String _photoPath  = '';

  String get serverUrl  => _serverUrl;
  String get odooLogin  => _odooLogin;
  String get odooPass   => _odooPass;
  String get name       => _name;
  String get email      => _email;
  String get phone      => _phone;
  String get photoPath  => _photoPath;
  String get idCode     => ''; // kept for profile_screen compatibility

  bool get isLoggedIn =>
      _serverUrl.isNotEmpty && _odooLogin.isNotEmpty && _odooPass.isNotEmpty;

  Future<void> saveSession({
    required String serverUrl,
    required String odooLogin,
    required String odooPass,
    required String name,
    required String email,
    String phone = '',
  }) async {
    _serverUrl = serverUrl.trim().replaceAll(RegExp(r'/$'), '');
    _odooLogin = odooLogin.trim();
    _odooPass  = odooPass;
    _name      = name.isNotEmpty ? name : odooLogin.split('@').first;
    _email     = email.isNotEmpty ? email : odooLogin;
    _phone     = phone;

    final p = await SharedPreferences.getInstance();
    await p.setString('odoo_server_url', _serverUrl);
    await p.setString('odoo_login',      _odooLogin);
    await p.setString('odoo_pass',       _odooPass);
    await p.setString('odoo_name',       _name);
    await p.setString('odoo_email',      _email);
    await p.setString('odoo_phone',      _phone);
    notifyListeners();
  }

  Future<bool> tryRestoreSession() async {
    final p     = await SharedPreferences.getInstance();
    final url   = p.getString('odoo_server_url') ?? '';
    final login = p.getString('odoo_login')      ?? '';
    final pass  = p.getString('odoo_pass')       ?? '';
    if (url.isEmpty || login.isEmpty || pass.isEmpty) return false;

    _serverUrl = url;
    _odooLogin = login;
    _odooPass  = pass;
    _name      = p.getString('odoo_name')       ?? login.split('@').first;
    _email     = p.getString('odoo_email')      ?? login;
    _phone     = p.getString('odoo_phone')      ?? '';
    _photoPath = p.getString('odoo_photo_path') ?? '';
    notifyListeners();
    return true;
  }

  Future<String?> updateProfile({
    required String newName,
    required String newPhone,
    required String newPhotoPath,
  }) async {
    _name      = newName.trim();
    _phone     = newPhone.trim();
    _photoPath = newPhotoPath;
    final p = await SharedPreferences.getInstance();
    await p.setString('odoo_name',       _name);
    await p.setString('odoo_phone',      _phone);
    await p.setString('odoo_photo_path', _photoPath);
    notifyListeners();
    return null;
  }

  Future<void> logout() async {
    _serverUrl = _odooLogin = _odooPass = '';
    _name = _email = _phone = _photoPath = '';
    final p = await SharedPreferences.getInstance();
    for (final k in [
      'odoo_server_url', 'odoo_login', 'odoo_pass',
      'odoo_name', 'odoo_email', 'odoo_phone', 'odoo_photo_path',
    ]) {
      await p.remove(k);
    }
    notifyListeners();
  }
}
