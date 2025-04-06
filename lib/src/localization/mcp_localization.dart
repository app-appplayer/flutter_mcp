import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/widgets.dart';
import '../utils/logger.dart';
import '../utils/exceptions.dart';

/// MCP localization system for internationalization support
class MCPLocalization {
  final MCPLogger _logger = MCPLogger('mcp.localization');

  // Current locale
  Locale _currentLocale;

  // Available locales
  final List<Locale> _supportedLocales = [];

  // Translations by locale
  final Map<String, Map<String, String>> _translations = {};

  // Fallback locale
  late Locale _fallbackLocale;

  // Delegate for use with MaterialApp/CupertinoApp
  late LocalizationsDelegate<MCPLocalization> delegate;

  // Singleton instance
  static final MCPLocalization _instance = MCPLocalization._internal(
    const Locale('en', 'US'),
  );

  /// Get singleton instance
  static MCPLocalization get instance => _instance;

  /// Internal constructor
  MCPLocalization._internal(Locale fallbackLocale)
      : _currentLocale = fallbackLocale,
        _fallbackLocale = fallbackLocale {
    _supportedLocales.add(fallbackLocale);

    // Initialize delegate
    delegate = _MCPLocalizationDelegate();
  }

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
    Map<String, Map<String, String>>? translations,
  }) async {
    if (supportedLocales != null && supportedLocales.isNotEmpty) {
      _logger.debug('Setting supported locales: ${supportedLocales.map((l) => l.toString()).join(', ')}');
      _supportedLocales.clear();
      _supportedLocales.addAll(supportedLocales);
    }

    if (fallbackLocale != null) {
      _logger.debug('Setting fallback locale: $fallbackLocale');
      _fallbackLocale = fallbackLocale;

      // Ensure fallback locale is in supported locales
      if (!_supportedLocales.contains(fallbackLocale)) {
        _supportedLocales.add(fallbackLocale);
      }
    }

    // Add translations directly if provided
    if (translations != null) {
      _translations.addAll(translations);
      _logger.debug('Added ${translations.length} locale translations');
    }

    // Load translations from assets if path provided
    if (localizationPath != null) {
      await loadTranslationsFromAssets(localizationPath);
    }

    // Set locale (will default to fallback if specified locale is not supported)
    if (locale != null) {
      await setLocale(locale);
    } else if (_currentLocale != _fallbackLocale) {
      await setLocale(_currentLocale);
    }

    _logger.debug('Localization initialized with ${_supportedLocales.length} locales');
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

  /// Pluralize a key based on count
  String plural(String key, int count, [Map<String, dynamic>? args]) {
    final baseArgs = args ?? {};
    baseArgs['count'] = count;

    // Try specific count key first
    final countKey = '${key}_$count';
    final localeKey = _getLocaleKey(_currentLocale);

    if (_translations[localeKey]?.containsKey(countKey) == true) {
      return translate(countKey, baseArgs);
    }

    // Try plural/singular forms
    final pluralKey = count == 1 ? '${key}_one' : '${key}_many';

    if (_translations[localeKey]?.containsKey(pluralKey) == true) {
      return translate(pluralKey, baseArgs);
    }

    // Fall back to base key
    return translate(key, baseArgs);
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
      throw MCPConfigurationException('Failed to load translations: ${e.toString()}', e, stackTrace);
    }
  }

  /// Load translations for a specific locale
  Future<void> _loadTranslationsForLocale(Locale locale, [String? basePath]) async {
    final localeKey = _getLocaleKey(locale);
    _logger.debug('Loading translations for locale: $localeKey');

    try {
      // Skip if translations already loaded for this locale
      if (_translations.containsKey(localeKey)) {
        _logger.debug('Translations already loaded for locale: $localeKey');
        return;
      }

      // Determine path
      final path = basePath != null
          ? '$basePath/${locale.languageCode}${locale.countryCode != null ? '_${locale.countryCode}' : ''}.json'
          : 'assets/localization/${locale.languageCode}${locale.countryCode != null ? '_${locale.countryCode}' : ''}.json';

      // Load and parse JSON
      final jsonString = await rootBundle.loadString(path);
      final Map<String, dynamic> data = jsonDecode(jsonString);

      // Convert to string-string map
      final Map<String, String> stringMap = {};
      _flattenMap('', data, stringMap);

      // Store translations
      _translations[localeKey] = stringMap;

      _logger.debug('Loaded ${stringMap.length} translations for $localeKey');
    } catch (e, stackTrace) {
      // Log but don't fail - just use fallback locale
      _logger.warning('Failed to load translations for locale: $localeKey', e, stackTrace);
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

  /// Export translations to JSON
  Map<String, Map<String, String>> exportTranslations() {
    return Map.from(_translations);
  }
}

/// Delegate for use with MaterialApp/CupertinoApp
class _MCPLocalizationDelegate extends LocalizationsDelegate<MCPLocalization> {
  @override
  bool isSupported(Locale locale) {
    return MCPLocalization.instance.supportedLocales.contains(locale) ||
        MCPLocalization.instance.supportedLocales.any(
                (supportedLocale) => supportedLocale.languageCode == locale.languageCode
        );
  }

  @override
  Future<MCPLocalization> load(Locale locale) async {
    await MCPLocalization.instance.setLocale(locale);
    return MCPLocalization.instance;
  }

  @override
  bool shouldReload(_MCPLocalizationDelegate old) => false;
}

/// Extension for easy access to translations
extension MCPLocalizationExtension on BuildContext {
  /// Translate a key
  String translate(String key, [Map<String, dynamic>? args]) {
    return MCPLocalization.instance.translate(key, args);
  }

  /// Pluralize a key based on count
  String plural(String key, int count, [Map<String, dynamic>? args]) {
    return MCPLocalization.instance.plural(key, count, args);
  }

  /// Get current locale
  Locale get currentLocale => MCPLocalization.instance.currentLocale;
}