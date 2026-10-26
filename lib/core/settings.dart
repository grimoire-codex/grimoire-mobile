import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Overridden in `main()` once SharedPreferences has loaded.
final preferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('preferencesProvider must be overridden'),
);

enum PageQuality {
  /// Pages rendered at the screen's pixel width.
  standard(1.0),

  /// 1.5x the screen width, for sharper text when zooming.
  high(1.5);

  const PageQuality(this.multiplier);
  final double multiplier;
}

class AppSettings {
  const AppSettings({
    this.preferDeviceRendering = false,
    this.quality = PageQuality.standard,
    this.verticalPaging = false,
  });

  /// Read downloaded books on the device even when the server is reachable.
  /// Off by default: Grimoire renders while online, and the downloaded copy is
  /// the fallback when it can't be reached.
  final bool preferDeviceRendering;
  final PageQuality quality;

  /// Swipe up/down between pages instead of left/right.
  final bool verticalPaging;

  AppSettings copyWith({bool? preferDeviceRendering, PageQuality? quality, bool? verticalPaging}) =>
      AppSettings(
        preferDeviceRendering: preferDeviceRendering ?? this.preferDeviceRendering,
        quality: quality ?? this.quality,
        verticalPaging: verticalPaging ?? this.verticalPaging,
      );
}

class SettingsController extends Notifier<AppSettings> {
  static const _device = 'settings.preferDeviceRendering';
  static const _quality = 'settings.quality';
  static const _vertical = 'settings.verticalPaging';

  SharedPreferences get _prefs => ref.read(preferencesProvider);

  @override
  AppSettings build() {
    final prefs = ref.watch(preferencesProvider);
    return AppSettings(
      preferDeviceRendering: prefs.getBool(_device) ?? false,
      quality: PageQuality.values.asNameMap()[prefs.getString(_quality)] ?? PageQuality.standard,
      verticalPaging: prefs.getBool(_vertical) ?? false,
    );
  }

  void setPreferDeviceRendering(bool value) {
    _prefs.setBool(_device, value);
    state = state.copyWith(preferDeviceRendering: value);
  }

  void setQuality(PageQuality value) {
    _prefs.setString(_quality, value.name);
    state = state.copyWith(quality: value);
  }

  void setVerticalPaging(bool value) {
    _prefs.setBool(_vertical, value);
    state = state.copyWith(verticalPaging: value);
  }
}

final settingsProvider = NotifierProvider<SettingsController, AppSettings>(SettingsController.new);
