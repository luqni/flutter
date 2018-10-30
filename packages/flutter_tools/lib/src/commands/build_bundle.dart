// Copyright 2018 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';

import '../base/common.dart';
import '../build_info.dart';
import '../bundle.dart';
import '../runner/flutter_command.dart' show FlutterOptions;
import 'build.dart';

class BuildBundleCommand extends BuildSubCommand {
  BuildBundleCommand({bool verboseHelp = false}) {
    usesTargetOption();
    usesFilesystemOptions(hide: !verboseHelp);
    addBuildModeFlags();
    argParser
      ..addFlag('precompiled', negatable: false)
      // This option is still referenced by the iOS build scripts. We should
      // remove it once we've updated those build scripts.
      ..addOption('asset-base', help: 'Ignored. Will be removed.', hide: !verboseHelp)
      ..addOption('manifest', defaultsTo: defaultManifestPath)
      ..addOption('private-key', defaultsTo: defaultPrivateKeyPath)
      ..addOption('snapshot', defaultsTo: defaultSnapshotPath)
      ..addOption('depfile', defaultsTo: defaultDepfilePath)
      ..addOption('kernel-file', defaultsTo: defaultApplicationKernelPath)
      ..addOption('target-platform',
        defaultsTo: 'android-arm',
        allowed: <String>['android-arm', 'android-arm64', 'ios']
      )
      ..addFlag('track-widget-creation',
        hide: !verboseHelp,
        help: 'Track widget creation locations. Requires Dart 2.0 functionality.',
      )
      ..addOption('precompile',
        hide: !verboseHelp,
        help: 'Precompile functions specified in input file. This flag is only\n'
              'allowed when using --dynamic. It takes a Dart compilation trace\n'
              'file produced by the training run of the application. With this\n'
              'flag, instead of using default Dart VM snapshot provided by the\n'
              'engine, the application will use its own snapshot that includes\n'
              'additional functions.'
      )
      ..addMultiOption(FlutterOptions.kExtraFrontEndOptions,
        splitCommas: true,
        hide: true,
      )
      ..addMultiOption(FlutterOptions.kExtraGenSnapshotOptions,
        splitCommas: true,
        hide: true,
      )
      ..addOption('asset-dir', defaultsTo: getAssetBuildDirectory())
      ..addFlag('report-licensed-packages',
        help: 'Whether to report the names of all the packages that are included '
              'in the application\'s LICENSE file.',
        defaultsTo: false);
    usesPubOption();
  }

  @override
  final String name = 'bundle';

  @override
  final String description = 'Build the Flutter assets directory from your app.';

  @override
  final String usageFooter = 'The Flutter assets directory contains your '
      'application code and resources; they are used by some Flutter Android and'
      ' iOS runtimes.';

  @override
  Future<Null> runCommand() async {
    await super.runCommand();

    final String targetPlatform = argResults['target-platform'];
    final TargetPlatform platform = getTargetPlatformForName(targetPlatform);
    if (platform == null)
      throwToolExit('Unknown platform: $targetPlatform');

    final BuildMode buildMode = getBuildMode();

    await build(
      platform: platform,
      buildMode: buildMode,
      mainPath: targetFile,
      manifestPath: argResults['manifest'],
      snapshotPath: argResults['snapshot'],
      applicationKernelFilePath: argResults['kernel-file'],
      depfilePath: argResults['depfile'],
      privateKeyPath: argResults['private-key'],
      assetDirPath: argResults['asset-dir'],
      precompiledSnapshot: argResults['precompiled'],
      reportLicensedPackages: argResults['report-licensed-packages'],
      trackWidgetCreation: argResults['track-widget-creation'],
      compilationTraceFilePath: argResults['precompile'],
      extraFrontEndOptions: argResults[FlutterOptions.kExtraFrontEndOptions],
      extraGenSnapshotOptions: argResults[FlutterOptions.kExtraGenSnapshotOptions],
      fileSystemScheme: argResults['filesystem-scheme'],
      fileSystemRoots: argResults['filesystem-root'],
    );
  }
}
