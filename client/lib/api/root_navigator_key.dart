import 'package:flutter/material.dart';

/// Lets non-widget code (Dio interceptors, background handlers, anything
/// outside the widget tree) obtain a BuildContext to show UI — most
/// importantly, so the global error interceptor can call
/// NotificationService without every caller threading a context through.
///
/// Wire this into your MaterialApp:
///   MaterialApp(navigatorKey: rootNavigatorKey, ...)
final rootNavigatorKey = GlobalKey<NavigatorState>();

/// The context to use from non-widget code. Null very briefly during
/// app startup before the first frame — callers should no-op if null
/// rather than throw, since a notification that can't show yet is not
/// worth crashing over.
BuildContext? get rootContext => rootNavigatorKey.currentContext;
