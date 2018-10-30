// Copyright 2016 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as path;

const String kDocRoot = 'dev/docs/doc';

/// This script expects to run with the cwd as the root of the flutter repo. It
/// will generate documentation for the packages in `//packages/` and write the
/// documentation to `//dev/docs/doc/api/`.
///
/// This script also updates the index.html file so that it can be placed
/// at the root of docs.flutter.io. We are keeping the files inside of
/// docs.flutter.io/flutter for now, so we need to manipulate paths
/// a bit. See https://github.com/flutter/flutter/issues/3900 for more info.
///
/// This will only work on UNIX systems, not Windows. It requires that 'git' be
/// in your path. It requires that 'flutter' has been run previously. It uses
/// the version of Dart downloaded by the 'flutter' tool in this repository and
/// will crash if that is absent.
Future<Null> main(List<String> arguments) async {
  final ArgParser argParser = _createArgsParser();
  final ArgResults args = argParser.parse(arguments);
  if (args['help']) {
    print ('Usage:');
    print (argParser.usage);
    exit(0);
  }
  // If we're run from the `tools` dir, set the cwd to the repo root.
  if (path.basename(Directory.current.path) == 'tools')
    Directory.current = Directory.current.parent.parent;

  final ProcessResult flutter = Process.runSync('flutter', <String>[]);
  final File versionFile = File('version');
  if (flutter.exitCode != 0 || !versionFile.existsSync())
    throw Exception('Failed to determine Flutter version.');
  final String version = versionFile.readAsStringSync();

  // Create the pubspec.yaml file.
  final StringBuffer buf = StringBuffer();
  buf.writeln('name: Flutter');
  buf.writeln('homepage: https://flutter.io');
  buf.writeln('version: $version');
  buf.writeln('dependencies:');
  for (String package in findPackageNames()) {
    buf.writeln('  $package:');
    buf.writeln('    sdk: flutter');
  }
  buf.writeln('  platform_integration: 0.0.1');
  buf.writeln('dependency_overrides:');
  buf.writeln('  platform_integration:');
  buf.writeln('    path: platform_integration');
  File('dev/docs/pubspec.yaml').writeAsStringSync(buf.toString());

  // Create the library file.
  final Directory libDir = Directory('dev/docs/lib');
  libDir.createSync();

  final StringBuffer contents = StringBuffer('library temp_doc;\n\n');
  for (String libraryRef in libraryRefs()) {
    contents.writeln('import \'package:$libraryRef\';');
  }
  File('dev/docs/lib/temp_doc.dart').writeAsStringSync(contents.toString());

  final String flutterRoot = Directory.current.path;
  final Map<String, String> pubEnvironment = <String, String>{
    'FLUTTER_ROOT': flutterRoot,
  };

  // If there's a .pub-cache dir in the flutter root, use that.
  final String pubCachePath = '$flutterRoot/.pub-cache';
  if (Directory(pubCachePath).existsSync()) {
    pubEnvironment['PUB_CACHE'] = pubCachePath;
  }

  final String pubExecutable = '$flutterRoot/bin/cache/dart-sdk/bin/pub';

  // Run pub.
  Process process = await Process.start(
    pubExecutable,
    <String>['get'],
    workingDirectory: 'dev/docs',
    environment: pubEnvironment,
  );
  printStream(process.stdout, prefix: 'pub:stdout: ');
  printStream(process.stderr, prefix: 'pub:stderr: ');
  final int code = await process.exitCode;
  if (code != 0)
    exit(code);

  createFooter('dev/docs/lib/footer.html');

  final List<String> dartdocBaseArgs = <String>['global', 'run'];
  if (args['checked']) {
    dartdocBaseArgs.add('-c');
  }
  dartdocBaseArgs.add('dartdoc');

  // Verify which version of dartdoc we're using.
  final ProcessResult result = Process.runSync(
    pubExecutable,
    <String>[]..addAll(dartdocBaseArgs)..add('--version'),
    workingDirectory: 'dev/docs',
    environment: pubEnvironment,
  );
  print('\n${result.stdout}flutter version: $version\n');

  if (args['json']) {
    dartdocBaseArgs.add('--json');
  }
  if (args['validate-links']) {
    dartdocBaseArgs.add('--validate-links');
  } else {
    dartdocBaseArgs.add('--no-validate-links');
  }
  // Generate the documentation.
  // We don't need to exclude flutter_tools in this list because it's not in the
  // recursive dependencies of the package defined at dev/docs/pubspec.yaml
  final List<String> dartdocArgs = <String>[]..addAll(dartdocBaseArgs)..addAll(<String>[
    '--header', 'styles.html',
    '--header', 'analytics.html',
    '--header', 'survey.html',
    '--footer-text', 'lib/footer.html',
    '--exclude-packages',
'analyzer,args,barback,cli_util,csslib,flutter_goldens,front_end,fuchsia_remote_debug_protocol,glob,html,http_multi_server,io,isolate,js,kernel,logging,mime,mockito,node_preamble,plugin,shelf,shelf_packages_handler,shelf_static,shelf_web_socket,utf,watcher,yaml',
    '--exclude',
  'package:Flutter/temp_doc.dart,package:http/browser_client.dart,package:intl/intl_browser.dart,package:matcher/mirror_matchers.dart,package:quiver/mirrors.dart,package:quiver/io.dart,package:vm_service_client/vm_service_client.dart,package:web_socket_channel/html.dart',
    '--favicon=favicon.ico',
    '--package-order', 'flutter,Dart,flutter_test,flutter_driver',
    '--show-warnings',
    '--auto-include-dependencies',
  ]);

  // Explicitly list all the packages in //flutter/packages/* that are
  // not listed 'nodoc' in their pubspec.yaml.
  for (String libraryRef in libraryRefs(diskPath: true)) {
    dartdocArgs.add('--include-external');
    dartdocArgs.add(libraryRef);
  }

  String quote(String arg) => arg.contains(' ') ? "'$arg'" : arg;
  print('Executing: (cd dev/docs ; $pubExecutable ${dartdocArgs.map(quote).join(' ')})');

  process = await Process.start(
    pubExecutable,
    dartdocArgs,
    workingDirectory: 'dev/docs',
    environment: pubEnvironment,
  );
  printStream(process.stdout, prefix: args['json'] ? '' : 'dartdoc:stdout: ',
    filter: args['verbose'] ? const <Pattern>[] : <Pattern>[
      RegExp(r'^generating docs for library '), // unnecessary verbosity
      RegExp(r'^pars'), // unnecessary verbosity
    ],
  );
  printStream(process.stderr, prefix: args['json'] ? '' : 'dartdoc:stderr: ',
    filter: args['verbose'] ? const <Pattern>[] : <Pattern>[
      RegExp(r'^[ ]+warning: generic type handled as HTML:'), // https://github.com/dart-lang/dartdoc/issues/1475
      RegExp(r'^ warning: .+: \(.+/\.pub-cache/hosted/pub.dartlang.org/.+\)'), // packages outside our control
    ],
  );
  final int exitCode = await process.exitCode;

  if (exitCode != 0)
    exit(exitCode);

  sanityCheckDocs();

  createIndexAndCleanup();
}

ArgParser _createArgsParser() {
  final ArgParser parser = ArgParser();
  parser.addFlag('help', abbr: 'h', negatable: false,
      help: 'Show command help.');
  parser.addFlag('verbose', negatable: true, defaultsTo: true,
      help: 'Whether to report all error messages (on) or attempt to '
          'filter out some known false positives (off).  Shut this off '
          'locally if you want to address Flutter-specific issues.');
  parser.addFlag('checked', abbr: 'c', negatable: true,
      help: 'Run dartdoc in checked mode.');
  parser.addFlag('json', negatable: true,
      help: 'Display json-formatted output from dartdoc and skip stdout/stderr prefixing.');
  parser.addFlag('validate-links', negatable: true,
      help: 'Display warnings for broken links generated by dartdoc (slow)');
  return parser;
}

final RegExp gitBranchRegexp = RegExp(r'^## (.*)');

void createFooter(String footerPath) {
  const int kGitRevisionLength = 10;

  ProcessResult gitResult = Process.runSync('git', <String>['rev-parse', 'HEAD']);
  if (gitResult.exitCode != 0)
    throw 'git rev-parse exit with non-zero exit code: ${gitResult.exitCode}';
  String gitRevision = gitResult.stdout.trim();

  gitResult = Process.runSync('git', <String>['status', '-b', '--porcelain']);
   if (gitResult.exitCode != 0)
    throw 'git status exit with non-zero exit code: ${gitResult.exitCode}';
  final Match gitBranchMatch = gitBranchRegexp.firstMatch(
      gitResult.stdout.trim().split('\n').first);
  final String gitBranchOut = gitBranchMatch == null ? '' : '• </span class="no-break">${gitBranchMatch.group(1).split('...').first}</span>';

  gitRevision = gitRevision.length > kGitRevisionLength ? gitRevision.substring(0, kGitRevisionLength) : gitRevision;

  final String timestamp = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());

  File(footerPath).writeAsStringSync(<String>[
    '• </span class="no-break">$timestamp<span>',
    '• </span class="no-break">$gitRevision</span>',
    gitBranchOut].join(' '));
}

void sanityCheckDocs() {
  final List<String> canaries = <String>[
    '$kDocRoot/api/dart-io/File-class.html',
    '$kDocRoot/api/dart-ui/Canvas-class.html',
    '$kDocRoot/api/dart-ui/Canvas/drawRect.html',
    '$kDocRoot/api/flutter_driver/FlutterDriver/FlutterDriver.connectedTo.html',
    '$kDocRoot/api/flutter_test/WidgetTester/pumpWidget.html',
    '$kDocRoot/api/material/Material-class.html',
    '$kDocRoot/api/material/Tooltip-class.html',
    '$kDocRoot/api/widgets/Widget-class.html',
  ];
  for (String canary in canaries) {
    if (!File(canary).existsSync())
      throw Exception('Missing "$canary", which probably means the documentation failed to build correctly.');
  }
}

/// Creates a custom index.html because we try to maintain old
/// paths. Cleanup unused index.html files no longer needed.
void createIndexAndCleanup() {
  print('\nCreating a custom index.html in $kDocRoot/index.html');
  removeOldFlutterDocsDir();
  renameApiDir();
  copyIndexToRootOfDocs();
  addHtmlBaseToIndex();
  changePackageToSdkInTitlebar();
  putRedirectInOldIndexLocation();
  print('\nDocs ready to go!');
}

void removeOldFlutterDocsDir() {
  try {
    Directory('$kDocRoot/flutter').deleteSync(recursive: true);
  } on FileSystemException {
    // If the directory does not exist, that's OK.
  }
}

void renameApiDir() {
  Directory('$kDocRoot/api').renameSync('$kDocRoot/flutter');
}

void copyIndexToRootOfDocs() {
  File('$kDocRoot/flutter/index.html').copySync('$kDocRoot/index.html');
}

void changePackageToSdkInTitlebar() {
  final File indexFile = File('$kDocRoot/index.html');
  String indexContents = indexFile.readAsStringSync();
  indexContents = indexContents.replaceFirst(
    '<li><a href="https://flutter.io">Flutter package</a></li>',
    '<li><a href="https://flutter.io">Flutter SDK</a></li>',
  );

  indexFile.writeAsStringSync(indexContents);
}

void addHtmlBaseToIndex() {
  final File indexFile = File('$kDocRoot/index.html');
  String indexContents = indexFile.readAsStringSync();
  indexContents = indexContents.replaceFirst(
    '</title>\n',
    '</title>\n  <base href="./flutter/">\n',
  );
  indexContents = indexContents.replaceAll(
    'href="Android/Android-library.html"',
    'href="/javadoc/"',
  );
  indexContents = indexContents.replaceAll(
      'href="iOS/iOS-library.html"',
      'href="/objcdoc/"',
  );

  indexFile.writeAsStringSync(indexContents);
}

void putRedirectInOldIndexLocation() {
  const String metaTag = '<meta http-equiv="refresh" content="0;URL=../index.html">';
  File('$kDocRoot/flutter/index.html').writeAsStringSync(metaTag);
}

List<String> findPackageNames() {
  return findPackages().map((FileSystemEntity file) => path.basename(file.path)).toList();
}

/// Finds all packages in the Flutter SDK
List<FileSystemEntity> findPackages() {
  return Directory('packages')
    .listSync()
    .where((FileSystemEntity entity) {
      if (entity is! Directory)
        return false;
      final File pubspec = File('${entity.path}/pubspec.yaml');
      // TODO(ianh): Use a real YAML parser here
      return !pubspec.readAsStringSync().contains('nodoc: true');
    })
    .cast<Directory>()
    .toList();
}

/// Returns import or on-disk paths for all libraries in the Flutter SDK.
///
/// diskPath toggles between import paths vs. disk paths.
Iterable<String> libraryRefs({ bool diskPath = false }) sync* {
  for (Directory dir in findPackages()) {
    final String dirName = path.basename(dir.path);
    for (FileSystemEntity file in Directory('${dir.path}/lib').listSync()) {
      if (file is File && file.path.endsWith('.dart')) {
        if (diskPath)
          yield '$dirName/lib/${path.basename(file.path)}';
        else
          yield '$dirName/${path.basename(file.path)}';
       }
    }
  }

  // Add a fake package for platform integration APIs.
  if (diskPath) {
    yield 'platform_integration/lib/android.dart';
    yield 'platform_integration/lib/ios.dart';
  } else {
    yield 'platform_integration/android.dart';
    yield 'platform_integration/ios.dart';
  }
}

void printStream(Stream<List<int>> stream, { String prefix = '', List<Pattern> filter = const <Pattern>[] }) {
  assert(prefix != null);
  assert(filter != null);
  stream
    .transform(utf8.decoder)
    .transform(const LineSplitter())
    .listen((String line) {
      if (!filter.any((Pattern pattern) => line.contains(pattern)))
        print('$prefix$line'.trim());
    });
}
