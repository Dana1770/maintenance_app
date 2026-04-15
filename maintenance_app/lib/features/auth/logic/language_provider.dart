import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LanguageProvider extends ChangeNotifier {
  Locale _locale = const Locale('en');

  Locale get locale => _locale;

  static const Map<String, String> supportedLanguages = {
    'English'  : 'en',
    'العربية'  : 'ar',
  };

  String get currentLanguageName =>
      supportedLanguages.entries
          .firstWhere((e) => e.value == _locale.languageCode,
          orElse: () => const MapEntry('English', 'en'))
          .key;

  Future<void> loadSavedLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    final code  = prefs.getString('lang_code') ?? 'en';
    _locale = Locale(code);
    notifyListeners();
  }

  Future<void> setLanguage(String languageName) async {
    final code = supportedLanguages[languageName] ?? 'en';
    _locale = Locale(code);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('lang_code', code);
    notifyListeners();
  }
}