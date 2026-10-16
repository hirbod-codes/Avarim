// ignore_for_file: avoid_print

import 'dart:io';

void main(List<String> args) {
  final version = Platform.environment['VERSION'];
  final build = Platform.environment['BUILD_NUMBER'];

  if (version == null || build == null) {
    throw Exception('VERSION or BUILD_NUMBER missing');
  }

  print('version: $version');
  print('build: $build');

  final file = File('pubspec.yaml');
  final content = file.readAsStringSync();

  file.writeAsStringSync(content.replaceFirst(RegExp(r'^version:.*$', multiLine: true), 'version: $version+$build'));
}
