import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

const defaultSettings = <String, dynamic>{
  'name': '',
  'email': '',
  'age': 18,
  'registrationDate': null,
  'theme': 'system',
  'fontSize': 16,
  'language': 'uk',
  'compact': false,
  'push': true,
  'emailNotifications': false,
  'sounds': true,
  'reminderHours': 24,
  'categories': <String>[],
};

class PreferencesManager {
  PreferencesManager._(this.preferences);

  static const key = 'user_settings_v1';
  static Future<PreferencesManager>? _instance;
  final SharedPreferences preferences;

  static Future<PreferencesManager> getInstance() {
    return _instance ??= _initialize();
  }

  static Future<PreferencesManager> _initialize() async {
    try {
      return PreferencesManager._(await SharedPreferences.getInstance());
    } catch (_) {
      _instance = null;
      rethrow;
    }
  }

  Map<String, dynamic> read() {
    final saved = preferences.getString(key);
    if (saved == null) return {...defaultSettings};
    return {...defaultSettings, ...jsonDecode(saved) as Map<String, dynamic>};
  }

  Future<void> save(Map<String, dynamic> settings) async {
    if (!await preferences.setString(key, jsonEncode(settings))) {
      throw StateError('Не вдалося зберегти налаштування');
    }
  }

  Future<void> reset() async {
    if (!await preferences.remove(key)) {
      throw StateError('Не вдалося скинути налаштування');
    }
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    final storage = await PreferencesManager.getInstance();
    runApp(SettingsApp(storage: storage, initial: storage.read()));
  } catch (_) {
    runApp(const MaterialApp(
      home: Scaffold(
        body: Center(child: Text('Не вдалося прочитати налаштування')),
      ),
    ));
  }
}

class SettingsApp extends StatefulWidget {
  const SettingsApp({super.key, required this.storage, required this.initial});

  final PreferencesManager storage;
  final Map<String, dynamic> initial;

  @override
  State<SettingsApp> createState() => _SettingsAppState();
}

class _SettingsAppState extends State<SettingsApp> {
  final messenger = GlobalKey<ScaffoldMessengerState>();
  late Map<String, dynamic> settings = {...widget.initial};
  late final name = TextEditingController(text: settings['name'] as String);
  late final email = TextEditingController(text: settings['email'] as String);
  Future<void> pending = Future<void>.value();

  String tr(String uk, String en) => settings['language'] == 'en' ? en : uk;

  List<String> get categories => List<String>.from(settings['categories']);

  @override
  void dispose() {
    name.dispose();
    email.dispose();
    super.dispose();
  }

  void notify(String text) {
    messenger.currentState
      ?..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text(text),
        duration: const Duration(seconds: 1),
      ));
  }

  void queue(Future<void> Function() operation, String Function() message) {
    pending = pending.then((_) async {
      try {
        await operation();
        if (mounted) notify(message());
      } catch (_) {
        if (mounted) notify(tr('Помилка збереження', 'Save error'));
      }
    });
  }

  void change(String key, Object? value) {
    final updated = {...settings, key: value};
    setState(() => settings = updated);
    queue(() => widget.storage.save(updated), () => tr('Збережено', 'Saved'));
  }

  void reset() {
    setState(() => settings = {...defaultSettings});
    name.clear();
    email.clear();
    queue(widget.storage.reset, () => tr('Налаштування скинуто', 'Defaults restored'));
  }

  Future<void> selectDate(BuildContext context) async {
    final now = DateTime.now();
    final saved = settings['registrationDate'] as String?;
    final selected = await showDatePicker(
      context: context,
      initialDate: saved == null ? now : DateTime.tryParse(saved) ?? now,
      firstDate: DateTime(1900),
      lastDate: now,
    );
    if (mounted && selected != null) {
      change('registrationDate', selected.toIso8601String());
    }
  }

  Future<void> addCategory(BuildContext context) async {
    final form = GlobalKey<FormState>();
    var value = '';
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(tr('Нова категорія', 'New category')),
        content: Form(
          key: form,
          child: TextFormField(
            autofocus: true,
            maxLength: 30,
            decoration: InputDecoration(labelText: tr('Назва', 'Name')),
            onChanged: (text) => value = text.trim(),
            validator: (_) {
              if (value.isEmpty) return tr('Введи назву', 'Enter a name');
              if (categories.any((item) => item.toLowerCase() == value.toLowerCase())) {
                return tr('Ця категорія вже є', 'This category already exists');
              }
              return null;
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(tr('Скасувати', 'Cancel')),
          ),
          FilledButton(
            onPressed: () {
              if (form.currentState!.validate()) Navigator.pop(dialogContext, value);
            },
            child: Text(tr('Додати', 'Add')),
          ),
        ],
      ),
    );
    if (mounted && result != null) change('categories', [...categories, result]);
  }

  void export(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(tr('Експорт налаштувань', 'Export preferences')),
        content: SingleChildScrollView(
          child: SelectableText(const JsonEncoder.withIndent('  ').convert(settings)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(tr('Закрити', 'Close')),
          ),
        ],
      ),
    );
  }

  Widget numberPicker(String label, String key, int min, int max) {
    final value = settings[key] as int;
    return ListTile(
      title: Text(label),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            onPressed: value > min ? () => change(key, value - 1) : null,
            icon: const Icon(Icons.remove_circle_outline),
          ),
          Text('$value'),
          IconButton(
            onPressed: value < max ? () => change(key, value + 1) : null,
            icon: const Icon(Icons.add_circle_outline),
          ),
        ],
      ),
    );
  }

  Widget toggle(String label, String key) => SwitchListTile(
    title: Text(label),
    value: settings[key] as bool,
    onChanged: (value) => change(key, value),
  );

  Widget section(String title, List<Widget> children) => Card(
    child: Padding(
      padding: EdgeInsets.all(settings['compact'] == true ? 10 : 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final title = tr('Мої налаштування', 'My preferences');
    final fontSize = (settings['fontSize'] as num).toDouble();
    final date = (settings['registrationDate'] as String?)?.split('T').first;

    return MaterialApp(
      title: title,
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: messenger,
      locale: Locale(settings['language'] as String),
      supportedLocales: const [Locale('uk'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: ThemeData(colorSchemeSeed: Colors.teal),
      darkTheme: ThemeData(colorSchemeSeed: Colors.teal, brightness: Brightness.dark),
      themeMode: ThemeMode.values.byName(settings['theme'] as String),
      builder: (context, child) {
        final media = MediaQuery.of(context);
        return MediaQuery(
          data: media.copyWith(
            textScaler: TextScaler.linear(media.textScaler.scale(fontSize) / 16),
          ),
          child: child!,
        );
      },
      home: Builder(
        builder: (pageContext) => Scaffold(
          appBar: AppBar(title: Text(title)),
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 700),
              child: ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  Wrap(
                    spacing: 8,
                    children: [
                      FilledButton(
                        onPressed: () => export(pageContext),
                        child: Text(tr('Експортувати налаштування', 'Export preferences')),
                      ),
                      OutlinedButton(
                        onPressed: reset,
                        child: Text(tr('Скинути до типових', 'Restore defaults')),
                      ),
                    ],
                  ),
                  section(tr('Профіль', 'Profile'), [
                    TextField(
                      controller: name,
                      decoration: InputDecoration(labelText: tr('Ім’я', 'Name')),
                      onChanged: (value) => change('name', value),
                    ),
                    TextField(
                      controller: email,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(labelText: 'Email'),
                      onChanged: (value) => change('email', value),
                    ),
                    numberPicker(tr('Вік', 'Age'), 'age', 1, 120),
                    OutlinedButton(
                      onPressed: () => selectDate(pageContext),
                      child: Text(date ?? tr('Дата реєстрації', 'Registration date')),
                    ),
                  ]),
                  section(tr('Вигляд', 'Appearance'), [
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SegmentedButton<String>(
                        segments: [
                          ButtonSegment(value: 'light', label: Text(tr('Світла', 'Light'))),
                          ButtonSegment(value: 'dark', label: Text(tr('Темна', 'Dark'))),
                          ButtonSegment(value: 'system', label: Text(tr('Системна', 'System'))),
                        ],
                        selected: {settings['theme'] as String},
                        onSelectionChanged: (value) => change('theme', value.single),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(tr('Розмір шрифту', 'Font size') + ' ${fontSize.round()}'),
                    Slider(
                      value: fontSize,
                      min: 12,
                      max: 24,
                      divisions: 12,
                      onChanged: (value) => change('fontSize', value),
                    ),
                    DropdownButton<String>(
                      value: settings['language'] as String,
                      items: const [
                        DropdownMenuItem(value: 'uk', child: Text('Українська')),
                        DropdownMenuItem(value: 'en', child: Text('English')),
                      ],
                      onChanged: (value) {
                        if (value != null) change('language', value);
                      },
                    ),
                    toggle(tr('Компактний режим', 'Compact mode'), 'compact'),
                  ]),
                  section(tr('Сповіщення', 'Notifications'), [
                    toggle('Push', 'push'),
                    toggle('Email', 'emailNotifications'),
                    toggle(tr('Звуки', 'Sounds'), 'sounds'),
                    numberPicker(tr('Інтервал, год', 'Interval, hours'), 'reminderHours', 1, 168),
                  ]),
                  section(tr('Улюблені категорії', 'Favorite categories'), [
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final category in categories)
                          InputChip(
                            label: Text(category),
                            onDeleted: () => change(
                              'categories',
                              categories.where((item) => item != category).toList(),
                            ),
                          ),
                      ],
                    ),
                    TextButton.icon(
                      onPressed: () => addCategory(pageContext),
                      icon: const Icon(Icons.add),
                      label: Text(tr('Додати категорію', 'Add category')),
                    ),
                  ]),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}