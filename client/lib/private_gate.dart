import 'package:avarim/auth/auth_controller.dart';
import 'package:avarim/auth/auth_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Shell for public/unauthenticated pages — carries the shared
/// two-row header (app name + locale/theme controls + "Log in" on the
/// first row, marketing nav links on the second) so every public page
/// gets consistent navigation instead of each one rebuilding it.
///
/// The header is fixed/pinned; only [child] scrolls, and this is the
/// ONLY place scrolling should happen for public pages now — a page
/// like LandingPage should NOT wrap itself in its own
/// SingleChildScrollView anymore. Nesting one scrollable inside
/// another with no bounded height in between is exactly what caused
/// the original bug: a SingleChildScrollView placed as a plain Column
/// child, with no Expanded around it, has no idea how much space it
/// actually has.
class PrivateWidget extends ConsumerWidget {
  final Widget child;

  const PrivateWidget({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    bool unauthenticated = ref.read(authControllerProvider).status == AuthStatus.unauthenticated;

    if (unauthenticated) {
      context.go('/login');
      return const SizedBox.shrink();
    }

    return child;
  }
}
