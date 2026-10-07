/// sibermobile entry point.
///
/// The AI runs against a single custom OpenAI-compatible gateway (the user
/// supplies base URL, API key and model) and can optionally call selected
/// Android device tools. Settings and history live on-device only.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app/chat_controller.dart';
import 'app/screens/chat_screen.dart';
import 'app/theme/app_theme.dart';
import 'app/widgets/common_widgets.dart';
import 'core/settings/settings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SiberMobileApp());
}

class SiberMobileApp extends StatelessWidget {
  const SiberMobileApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => ChatController()..bootstrap(),
      child: Consumer<ChatController>(
        builder: (context, controller, _) => MaterialApp(
          title: 'SiberMobile',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: _flutterThemeMode(controller.settings.themeMode),
          home: const _BootstrapGate(child: ChatScreen()),
        ),
      ),
    );
  }
}

ThemeMode _flutterThemeMode(AppThemeMode mode) => switch (mode) {
  AppThemeMode.system => ThemeMode.system,
  AppThemeMode.light => ThemeMode.light,
  AppThemeMode.dark => ThemeMode.dark,
};

/// Waits for settings + API key to load before showing the chat screen, so the
/// first frame already knows whether the provider is configured.
class _BootstrapGate extends StatelessWidget {
  const _BootstrapGate({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ChatController>();
    if (controller.isLoading) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SiberLogo(size: 68),
              const SizedBox(height: 24),
              Text(
                'SiberMobile',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 18),
              const SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
            ],
          ),
        ),
      );
    }
    if (controller.loadError != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('SiberMobile')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(controller.loadError!, textAlign: TextAlign.center),
          ),
        ),
      );
    }
    return child;
  }
}
