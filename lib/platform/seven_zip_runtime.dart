import 'dart:io';

import 'package:path/path.dart' as p;

/// Returns native executables only; resolving PATH does not need a shell or
/// the Unix-only `which` utility. Kept separate for cross-platform tests.
List<String> sevenZipExecutableCandidates({
  required bool windows,
  required bool macOS,
  required String appExecutable,
  required String currentDirectory,
  required Map<String, String> environment,
  String? configuredPath,
}) {
  final context = p.Context(style: windows ? p.Style.windows : p.Style.posix);
  final appDirectory = context.dirname(appExecutable);
  final names = windows ? ['7z.exe', '7zz.exe'] : ['7zz'];
  return [
    if (configuredPath?.isNotEmpty == true) configuredPath!,
    if (environment['JUCIER_7ZZ_PATH']?.isNotEmpty == true)
      environment['JUCIER_7ZZ_PATH']!,
    if (windows) ...[
      context.join(appDirectory, 'bin', '7z.exe'),
      for (final name in names)
        context.join(
          appDirectory,
          'data',
          'flutter_assets',
          'assets',
          'sevenzip',
          'windows',
          name,
        ),
      for (final name in names)
        context.join(currentDirectory, 'assets', 'sevenzip', 'windows', name),
      for (final variable in [
        'ProgramW6432',
        'ProgramFiles',
        'ProgramFiles(x86)',
      ])
        if (environment[variable]?.isNotEmpty == true)
          context.join(environment[variable]!, '7-Zip', '7z.exe'),
    ],
    if (macOS) ...[
      context.normalize(
        context.join(appDirectory, '..', 'Resources', 'bin', '7zz'),
      ),
      context.normalize(
        context.join(
          appDirectory,
          '..',
          'Frameworks',
          'App.framework',
          'Resources',
          'flutter_assets',
          'assets',
          'sevenzip',
          '7zz',
        ),
      ),
    ],
    if (!windows) context.join(currentDirectory, 'assets', 'sevenzip', '7zz'),
    for (final directory
        in (environment['PATH'] ?? environment['Path'] ?? '')
            .split(windows ? ';' : ':')
            .map((value) => value.replaceAll('"', '').trim())
            .where((value) => value.isNotEmpty))
      for (final name in names) context.join(directory, name),
  ];
}

Future<String?> findSevenZipExecutable({String? configuredPath}) async {
  for (final candidate in sevenZipExecutableCandidates(
    windows: Platform.isWindows,
    macOS: Platform.isMacOS,
    appExecutable: Platform.resolvedExecutable,
    currentDirectory: Directory.current.path,
    environment: Platform.environment,
    configuredPath: configuredPath,
  )) {
    if (await File(candidate).exists()) return p.absolute(candidate);
  }
  return null;
}
