import 'package:avarim/account/avatar/avatar_bytes_notifier.dart';
import 'package:avarim/auth/auth_controller.dart';
import 'package:avarim/auth/auth_state.dart';
import 'package:avarim/components/button.dart';
import 'package:avarim/components/theme_swtich_button.dart';
import 'package:avarim/l10n/app_localizations.dart';
import 'package:avarim/theme/app_colors.dart';
import 'package:avarim/theme/app_theme.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class TopBar extends ConsumerWidget implements PreferredSizeWidget {
  final Widget? title;

  const TopBar({super.key, this.title});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    final isAuthenticated = ref.watch(authControllerProvider).status == AuthStatus.authenticated;
    final avatarBytes = ref.watch(avatarBytesProvider);

    AppLocalizations l10n = AppLocalizations.of(context)!;

    return AppBar(
      backgroundColor: theme.appBarTheme.backgroundColor,
      foregroundColor: theme.appBarTheme.foregroundColor,
      elevation: 5,
      shadowColor: themeModeNotifier.value == ThemeMode.dark ? Colors.white12 : Colors.black,
      shape: BoxBorder.fromLTRB(bottom: BorderSide(width: 1.0, color: theme.colorScheme.outlineVariant)),
      surfaceTintColor: Colors.transparent,
      title: title ?? _buildDefaultTitle(context, l10n),
      centerTitle: false,
      actions: [
        Button(
          icon: themeModeNotifier.value == ThemeMode.dark ? Icons.light_mode : Icons.dark_mode,
          color: theme.colorScheme.primary,
          type: ButtonType.text,
          onPressed: () {
            themeModeNotifier.value = themeModeNotifier.value == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
          },
        ),
        if (!isAuthenticated)
          Button(
            icon: Icons.login,
            color: theme.extension<AppColors>()!.success,
            type: ButtonType.text,
            onPressed: () {
              context.go('/login');
            },
          ),
        if (isAuthenticated) ...[
          // Set by AuthController._onAuthenticated() during login/signup/
          // startup — falls back to a plain person icon when null (no
          // avatarKey on the account, or the fetch failed silently).
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: CircleAvatar(
              radius: 16,
              backgroundImage: avatarBytes != null ? MemoryImage(avatarBytes) : null,
              child: avatarBytes == null ? const Icon(Icons.person, size: 18) : null,
            ),
          ),
          Button(
            icon: Icons.logout,
            type: ButtonType.text,
            color: theme.colorScheme.error,
            onPressed: () async {
              await ref.read(authControllerProvider.notifier).logout();
              try {
                context.go('/');
              } catch (_) {}
            },
          ),
        ],
      ],
    );
  }

  Widget _buildDefaultTitle(BuildContext context, AppLocalizations l10n) {
    final text = Text(l10n.appTitle);

    // '/' is only a registered route on web (see _publicPaths /
    // routes in go_router.dart) — non-web has no landing page, so
    // the title stays non-interactive there.
    if (!kIsWeb) return text;

    return InkWell(
      onTap: () => context.go('/'),
      borderRadius: BorderRadius.circular(4),
      child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2), child: text),
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(40);
}
