import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LanguageState {
  final Locale locale;
  const LanguageState(this.locale);
}

class LanguageCubit extends Cubit<LanguageState> {
  LanguageCubit() : super(const LanguageState(Locale('en')));

  static const Map<String, String> supportedLanguages = {
    'English': 'en',
    'العربية': 'ar',
  };

  Locale get locale => state.locale;

  String get currentLanguageName =>
      supportedLanguages.entries
          .firstWhere(
            (e) => e.value == state.locale.languageCode,
            orElse: () => const MapEntry('English', 'en'),
          )
          .key;

  Future<void> loadSavedLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString('lang_code') ?? 'en';
    emit(LanguageState(Locale(code)));
  }

  Future<void> setLanguage(String languageName) async {
    final code = supportedLanguages[languageName] ?? 'en';
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('lang_code', code);
    emit(LanguageState(Locale(code)));
  }
}
