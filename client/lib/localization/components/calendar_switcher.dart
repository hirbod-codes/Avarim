import 'package:avarim/localization/calendars/calendar_controller.dart';
import 'package:avarim/localization/calendars/calendar_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class CalendarSwitcher extends ConsumerWidget {
  const CalendarSwitcher({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(calendarControllerProvider);

    return DropdownButton<CalendarType>(
      padding: EdgeInsets.all(4.0),
      value: current,
      onChanged: (type) {
        if (type != null) ref.read(calendarControllerProvider.notifier).setCalendarType(type);
      },
      items: [for (final type in CalendarType.values) DropdownMenuItem(value: type, child: Text(calendarSystems[type]!.name))],
    );
  }
}
