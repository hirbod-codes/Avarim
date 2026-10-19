import 'package:avarim/api/root_navigator_key.dart';
import 'package:avarim/app_shell.dart';
import 'package:avarim/auth/auth_controller.dart';
import 'package:avarim/auth/auth_state.dart';
import 'package:avarim/go_router_refresh_notifier.dart';
import 'package:avarim/localization/on_boarding_status.dart';
import 'package:avarim/pages/about_page.dart';
import 'package:avarim/pages/artist_page.dart';
import 'package:avarim/pages/edit_album/edit_album_page.dart';
import 'package:avarim/pages/edit_artist/edit_artist_page.dart';
import 'package:avarim/pages/edit_audio/edit_audio_page.dart';
import 'package:avarim/pages/search/search_page.dart';
import 'package:avarim/pages/auth/auth_page.dart';
import 'package:avarim/pages/contact_page.dart';
import 'package:avarim/pages/on_boarding_page.dart';
import 'package:avarim/pages/payment_result_page.dart';
import 'package:avarim/pages/plan/pricing_page.dart';
import 'package:avarim/pages/settings/settings_page.dart';
import 'package:avarim/pages/test/test_page.dart';
import 'package:avarim/pages/web/landing_page.dart';
import 'package:avarim/private_gate.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Routes that don't require authentication. Differs by platform:
/// web has a public landing page at '/'; non-web has an onboarding
/// step instead, and no '/' route at all.
final Set<String> _publicPaths = {'/login', '/pricing', '/about', '/contact', if (kIsWeb) '/', if (!kIsWeb) '/onboarding'};

final goRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    navigatorKey: rootNavigatorKey,
    refreshListenable: GoRouterRefreshNotifier(ref),
    redirect: (context, state) async {
      final path = state.matchedLocation;

      if (kIsWeb) {
        if (path.contains('/payment/result')) {
          return null;
        }
      }

      final authStatus = ref.read(authControllerProvider).status;
      if (authStatus == AuthStatus.loading) return null;

      final loggedIn = authStatus == AuthStatus.authenticated;
      final isPublicRoute = _publicPaths.contains(path);

      if (kIsWeb) {
        if (path.contains('/payment/result')) {
          return null;
        }

        // '/' is the public landing page. An authenticated visitor
        // lands straight in the app instead of seeing marketing copy.
        if (loggedIn && path == '/') return '/app';

        if (!loggedIn && !isPublicRoute) {
          final from = Uri.encodeComponent(state.uri.toString());
          return '/login?from=$from';
        }

        if (loggedIn && path == '/login') {
          final from = state.uri.queryParameters['from'];
          return (from != null && from.isNotEmpty) ? from : '/app';
        }

        return null;
      }

      // Non-web: no landing page, so a bare '/' is never a real
      // destination — always bounce it somewhere real first, before
      // any other check, since '/' isn't a registered route here and
      // would otherwise fall through to NotFoundPage.
      final onBoarded = await hasChosenLocaleAndCalendar();

      if (path == '/') {
        if (!onBoarded) return '/onboarding';
        return loggedIn ? '/app' : '/login';
      }

      // Onboarding (language + calendar) gates everything else,
      // including login — asked once, before the very first
      // login/signup attempt.
      if (!onBoarded && path != '/onboarding') return '/onboarding';
      if (onBoarded && path == '/onboarding') return loggedIn ? '/app' : '/login';

      if (!loggedIn && !isPublicRoute) {
        final from = Uri.encodeComponent(state.uri.toString());
        return '/login?from=$from';
      }

      if (loggedIn && path == '/login') {
        final from = state.uri.queryParameters['from'];
        return (from != null && from.isNotEmpty) ? from : '/app';
      }

      return null;
    },
    routes: [
      if (kIsWeb)
        GoRoute(
          path: '/',
          builder: (context, state) => const AppShell(child: LandingPage()),
        ),
      if (!kIsWeb) GoRoute(path: '/onboarding', builder: (context, state) => const OnboardingPage()),
      GoRoute(
        path: '/login',
        builder: (context, state) {
          final from = state.uri.queryParameters['from'];
          return AppShell(child: AuthPage(onAuthenticated: (_) => context.go((from != null && from.isNotEmpty) ? from : '/app')));
        },
      ),
      GoRoute(
        path: '/pricing',
        builder: (context, state) => const AppShell(child: PricingPage()),
      ),
      if (kIsWeb)
        GoRoute(
          path: '/payment/result',
          builder: (context, state) {
            final status = state.uri.queryParameters['status'] ?? 'error';
            final data = state.uri.queryParameters['data'] ?? '';
            return PaymentResultPage(status: status, data: data);
          },
        ),
      GoRoute(
        path: '/about',
        builder: (context, state) => const AppShell(child: AboutPage()),
      ),
      GoRoute(
        path: '/contact',
        builder: (context, state) => const AppShell(child: ContactPage()),
      ),
      GoRoute(
        path: '/app',
        builder: (context, state) => const PrivateWidget(child: AppShell(child: SearchPage())),
      ),
      GoRoute(
        path: '/settings',
        builder: (context, state) => const PrivateWidget(child: AppShell(child: SettingsPage())),
      ),
      if (kDebugMode)
        GoRoute(
          path: '/test',
          builder: (context, state) => const PrivateWidget(child: AppShell(child: TestPage())),
        ),
      GoRoute(
        path: '/artist/edit',
        builder: (context, state) {
          return PrivateWidget(
            child: AppShell(child: EditArtistPage(artistId: state.uri.queryParameters['artistId'])),
          );
        },
      ),
      GoRoute(
        path: '/album/edit',
        builder: (context, state) {
          return PrivateWidget(
            child: AppShell(child: EditAlbumPage(albumId: state.uri.queryParameters['albumId'])),
          );
        },
      ),
      GoRoute(
        path: '/audio/edit',
        builder: (context, state) {
          return PrivateWidget(
            child: AppShell(child: EditAudioPage(audioId: state.uri.queryParameters['audioId'])),
          );
        },
      ),
      GoRoute(
        path: '/artist',
        builder: (context, state) => ArtistPage(artistId: state.uri.queryParameters['artistId'], artistName: state.uri.queryParameters['name']),
      ),
    ],
  );
});
