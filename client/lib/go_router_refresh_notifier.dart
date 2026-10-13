import 'package:avarim/auth/auth_controller.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// GoRouter's `redirect` only re-runs when something notifies its
/// `refreshListenable` — it has no idea Riverpod state exists otherwise.
/// This adapts authControllerProvider into a ChangeNotifier so that
/// logging in (or out) actually triggers GoRouter to re-check whether
/// the current route still makes sense.
class GoRouterRefreshNotifier extends ChangeNotifier {
  GoRouterRefreshNotifier(Ref ref) {
    ref.listen(authControllerProvider, (previous, next) {
      if (previous?.status != next.status) notifyListeners();
    });
  }
}
