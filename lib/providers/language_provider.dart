import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LanguageProvider extends ChangeNotifier {
  Locale _locale = const Locale('en');
  Locale get locale => _locale;

  Future<void> loadSavedLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString('language_code') ?? 'en';
    _locale = Locale(code);
    notifyListeners();
  }

  Future<void> setLanguage(String code) async {
    _locale = Locale(code);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('language_code', code);
    notifyListeners();
  }

  String get currentLanguageName {
    switch (_locale.languageCode) {
      case 'ml':
        return 'മലയാളം';
      case 'hi':
        return 'हिन्दी';
      default:
        return 'English';
    }
  }
}
