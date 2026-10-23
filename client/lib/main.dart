import 'dart:async';
import 'dart:io';

import 'package:avarim/go_router.dart';
import 'package:avarim/auth/auth_controller.dart';
import 'package:avarim/auth/auth_state.dart';
import 'package:avarim/l10n/app_localizations.dart';
import 'package:avarim/localization/locale_controller.dart';
import 'package:avarim/localization/timezone/timezone_service.dart';
import 'package:avarim/theme/app_theme.dart';
import 'package:avarim/theme/theme_mode_store.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:media_kit/media_kit.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';

ProviderContainer container = ProviderContainer();

final rootPemBytesProvider = Provider<Uint8List>((_) => throw UnimplementedError());

Future<void> main() async {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    if (!kDebugMode) {
      final data = await rootBundle.load('assets/certs/fullchain.pem');
      final pem = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);

      container = ProviderContainer(overrides: [rootPemBytesProvider.overrideWithValue(pem)]);
    }

    FlutterError.onError = (d) {
      FlutterError.presentError(d);
      _log('FlutterError: ${d.exception}\n${d.stack}');
    };
    PlatformDispatcher.instance.onError = (e, s) {
      _log('Platform: $e\n$s');
      return true;
    };

    if (!kIsWeb) {
      MediaKit.ensureInitialized();
      JustAudioMediaKit.ensureInitialized();
    }

    TimezoneService.initialize();
    themeModeNotifier.value = await loadThemeMode();
    themeModeNotifier.addListener(() => saveThemeMode(themeModeNotifier.value));

    runApp(UncontrolledProviderScope(container: container, child: const MyApp()));
  }, (e, s) => _log('Zone: $e\n$s'));
}

void _log(String message) {
  debugPrint(message);
  if (kIsWeb) return;
  try {
    File('${Directory.systemTemp.path}${Platform.pathSeparator}avarim_crash.log').writeAsStringSync('$message\n', mode: FileMode.append);
  } catch (_) {}
}

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Read (not built until now) since the loading branch above already
    // guarantees the initial session check has resolved by this point —
    // goRouterProvider's redirect logic depends on that being settled.
    final router = ref.watch(goRouterProvider);
    final auth = ref.watch(authControllerProvider);
    final locale = ref.watch(localeControllerProvider);

    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeModeNotifier,
      builder: (context, mode, _) {
        return MaterialApp.router(
          theme: lightTheme,
          darkTheme: darkTheme,
          themeMode: mode,
          locale: locale,
          onGenerateTitle: (context) => AppLocalizations.of(context)!.appTitle,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            FlutterQuillLocalizations.delegate,
          ],
          supportedLocales: supportedLocales,
          routerConfig: router,
          title: 'Avarim',
          // theme: AppTheme.light(),
          // darkTheme: AppTheme.dark(),
          // themeMode: ref.watch(themeModeProvider),
          debugShowCheckedModeBanner: false,
          builder: (context, child) {
            if (auth.status == AuthStatus.loading) {
              return const MaterialApp(
                home: Scaffold(body: Center(child: CircularProgressIndicator())),
              );
            }
            return child!;
          },
        );
      },
    );
  }
}
