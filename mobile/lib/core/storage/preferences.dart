import 'package:shared_preferences/shared_preferences.dart';

class PreferencesService {
  late final SharedPreferences _prefs;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  bool get onboardingComplete => _prefs.getBool('onboarding_complete') ?? false;
  Future<void> setOnboardingComplete() =>
      _prefs.setBool('onboarding_complete', true);

  String get lastTab => _prefs.getString('last_tab') ?? '/dashboard';
  Future<void> setLastTab(String tab) => _prefs.setString('last_tab', tab);
}
