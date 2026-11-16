import 'package:flutter_riverpod/flutter_riverpod.dart';

final editModeProvider = NotifierProvider<EditMode, bool>(EditMode.new);

class EditMode extends Notifier<bool> {
  @override
  bool build() => false;

  void toggle() {
    state = !state;
  }
}
