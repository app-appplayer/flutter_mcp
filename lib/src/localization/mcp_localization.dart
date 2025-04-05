import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/widgets.dart';
import '../utils/logger.dart';

/// MCP localization system
class MCPLocalization {
  final MCPLogger _logger = MCPLogger('mcp.localization');

  // Current locale
  Locale _currentLocale;

  // Available locales
  final List<Locale> _supportedLocales;

  // Translations by locale
  final Map<String, Map<String, String>> _translations = {};

  // Fallback locale
  late final Locale _fallbackLocale;

  // Singleton instance
  static final MCPLocalization _instance = MCPLocalization._internal(
    const Locale('en', 'US'),
    [const Locale('en', 'US')],
  );

  /// Get singleton instance
  static MCPLocalization get instance => _instance;

  /// Internal constructor
  MCPLocalization._internal(this._fallbackLocale, this._supportedLocales)
      : _currentLocale = _fallbackLocale;

  /// Current locale
  Locale get currentLocale => _currentLocale;

  /// Supported locales
  List<Locale> get supportedLocales => List.unmodifiable(_supportedLocales);

  /// Initialize the localization system
  Future<void> initialize({
    Locale? locale,
    List<Locale>? supportedLocales,
    Locale? fallbackLocale,
    String? localizationPath,
  }) async {
    if (supportedLocales != null && supportedLocales.isNotEmpty) {
      _logger.debug('Setting supported locales: ${supportedLocales.join(', ')}');
      _supportedLocales.clear();
      _supportedLocales.addAll(supportedLocales);
    }

    if (fallbackLocale != null) {
      _logger.debug('Setting fallback locale: $fallbackLocale');
      _fallbackLocale = fallbackLocale;
    }

    if (locale != null) {
      await setLocale(locale);
    } else {
      await setLocale(_currentLocale);
    }

    if (localizationPath != null) {
      await loadTranslationsFromAssets(localizationPath);
    }
  }

  /// Set the current locale
  Future<void> setLocale(Locale locale) async {
    _logger.debug('Setting locale: $locale');

    // Find best matching locale
    final bestLocale = _findBestMatchingLocale(locale);
    if (bestLocale == null) {
      _logger.warning('No matching locale found for $locale, using fallback: $_fallbackLocale');
      _currentLocale = _fallbackLocale;
    } else {
      _currentLocale = bestLocale;
    }

    // Load translations for the locale if not already loaded
    final localeKey = _getLocaleKey(_currentLocale);
    if (!_translations.containsKey(localeKey)) {
      await _loadTranslationsForLocale(_currentLocale);
    }
  }

  /// Translate a key
  String translate(String key, [Map<String, dynamic>? args]) {
    final localeKey = _getLocaleKey(_currentLocale);

    // Try to get translation for current locale
    final translation = _translations[localeKey]?[key];

    if (translation == null) {
      // Try fallback locale
      final fallbackLocaleKey = _getLocaleKey(_fallbackLocale);
      final fallbackTranslation = _translations[fallbackLocaleKey]?[key];

      if (fallbackTranslation == null) {
        _logger.warning('Translation not found for key: $key');
        return key; // Return the key itself as fallback
      }

      return _formatTranslation(fallbackTranslation, args);
    }

    return _formatTranslation(translation, args);
  }

  /// Format a translation with arguments
  String _formatTranslation(String translation, Map<String, dynamic>? args) {
    if (args == null || args.isEmpty) {
      return translation;
    }

    String result = translation;
    args.forEach((key, value) {
      result = result.replaceAll('{$key}', value.toString());
    });

    return result;
  }

  /// Load translations from assets
  Future<void> loadTranslationsFromAssets(String path) async {
    _logger.debug('Loading translations from assets: $path');

    try {
      for (final locale in _supportedLocales) {
        await _loadTranslationsForLocale(locale, path);
      }
    } catch (e, stackTrace) {
      _logger.error('Failed to load translations from assets', e, stackTrace);
    }
  }

  /// Load translations for a specific locale
  Future<void> _loadTranslationsForLocale(Locale locale, [String? basePath]) async {
    final localeKey = _getLocaleKey(locale);
    _logger.debug('Loading translations for locale: $localeKey');

    try {
      // Determine path
      final path = basePath != null
          ? '$basePath/${locale.languageCode}${locale.countryCode != null ? '_${locale.countryCode}' : ''}.json'
          : 'assets/lang/${locale.languageCode}${locale.countryCode != null ? '_${locale.countryCode}' : ''}.json';

      // Load and parse JSON
      final jsonString = await rootBundle.loadString(path);
      final Map<String, dynamic> data = json.decode(jsonString);

      // Convert to string-string map
      final Map<String, String> stringMap = {};
      _flattenMap('', data, stringMap);

      // Store translations
      _translations[localeKey] = stringMap;

      _logger.debug('Loaded ${stringMap.length} translations for $localeKey');
    } catch (e, stackTrace) {
      _logger.error('Failed to load translations for locale: $localeKey', e, stackTrace);
    }
  }

  /// Flatten a nested map into dot notation
  void _flattenMap(String prefix, Map<String, dynamic> map, Map<String, String> result) {
    map.forEach((key, value) {
      final String newKey = prefix.isEmpty ? key : '$prefix.$key';

      if (value is Map<String, dynamic>) {
        _flattenMap(newKey, value, result);
      } else {
        result[newKey] = value.toString();
      }
    });
  }

  /// Find the best matching locale from supported locales
  Locale? _findBestMatchingLocale(Locale locale) {
    // First try exact match
    for (final supportedLocale in _supportedLocales) {
      if (supportedLocale.languageCode == locale.languageCode &&
          supportedLocale.countryCode == locale.countryCode) {
        return supportedLocale;
      }
    }

    // Then try language match
    for (final supportedLocale in _supportedLocales) {
      if (supportedLocale.languageCode == locale.languageCode) {
        return supportedLocale;
      }
    }

    return null;
  }

  /// Get locale key used for mapping
  String _getLocaleKey(Locale locale) {
    return locale.countryCode != null
        ? '${locale.languageCode}_${locale.countryCode}'
        : locale.languageCode;
  }

  /// Add translations programmatically
  void addTranslations(Locale locale, Map<String, String> translations) {
    final localeKey = _getLocaleKey(locale);

    if (!_translations.containsKey(localeKey)) {
      _translations[localeKey] = {};
    }

    _translations[localeKey]!.addAll(translations);
    _logger.debug('Added ${translations.length} translations for $localeKey');
  }

  /// Get all available translation keys
  Set<String> getAvailableKeys() {
    final keys = <String>{};

    _translations.forEach((_, translations) {
      keys.addAll(translations.keys);
    });

    return keys;
  }

  /// Add a supported locale
  void addSupportedLocale(Locale locale) {
    if (!_supportedLocales.contains(locale)) {
      _supportedLocales.add(locale);
      _logger.debug('Added supported locale: $locale');
    }
  }
}

/// Extension for easy access to translations
extension MCPLocalizationExtension on BuildContext {
  /// Translate a key
  String translate(String key, [Map<String, dynamic>? args]) {
    return MCPLocalization.instance.translate(key, args);
  }
}