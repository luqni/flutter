// Copyright 2017 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';

import 'package:meta/meta.dart';

import '../android/android_sdk.dart';
import '../artifacts.dart';
import '../build_info.dart';
import '../compile.dart';
import '../dart/package_map.dart';
import '../globals.dart';
import '../ios/mac.dart';
import 'context.dart';
import 'file_system.dart';
import 'fingerprint.dart';
import 'process.dart';

GenSnapshot get genSnapshot => context[GenSnapshot];

/// A snapshot build configuration.
class SnapshotType {
  SnapshotType(this.platform, this.mode)
    : assert(mode != null);

  final TargetPlatform platform;
  final BuildMode mode;

  @override
  String toString() => '$platform $mode';
}

/// Interface to the gen_snapshot command-line tool.
class GenSnapshot {
  const GenSnapshot();

  static String getSnapshotterPath(SnapshotType snapshotType) {
    return artifacts.getArtifactPath(
        Artifact.genSnapshot, snapshotType.platform, snapshotType.mode);
  }

  Future<int> run({
    @required SnapshotType snapshotType,
    @required String packagesPath,
    IOSArch iosArch,
    Iterable<String> additionalArgs = const <String>[],
  }) {
    final List<String> args = <String>[
      '--await_is_keyword',
      '--causal_async_stacks',
      '--packages=$packagesPath',
    ]..addAll(additionalArgs);

    final String snapshotterPath = getSnapshotterPath(snapshotType);

    // iOS gen_snapshot is a multi-arch binary. Running as an i386 binary will
    // generate armv7 code. Running as an x86_64 binary will generate arm64
    // code. /usr/bin/arch can be used to run binaries with the specified
    // architecture.
    if (snapshotType.platform == TargetPlatform.ios) {
      final String hostArch = iosArch == IOSArch.armv7 ? '-i386' : '-x86_64';
      return runCommandAndStreamOutput(<String>['/usr/bin/arch', hostArch, snapshotterPath]..addAll(args));
    }
    return runCommandAndStreamOutput(<String>[snapshotterPath]..addAll(args));
  }
}

class AOTSnapshotter {
  /// Builds an architecture-specific ahead-of-time compiled snapshot of the specified script.
  Future<int> build({
    @required TargetPlatform platform,
    @required BuildMode buildMode,
    @required String mainPath,
    @required String packagesPath,
    @required String outputPath,
    @required bool buildSharedLibrary,
    IOSArch iosArch,
    List<String> extraGenSnapshotOptions = const <String>[],
  }) async {
    if (!_isValidAotPlatform(platform, buildMode)) {
      printError('${getNameForTargetPlatform(platform)} does not support AOT compilation.');
      return 1;
    }
    // TODO(cbracken): replace IOSArch with TargetPlatform.ios_{armv7,arm64}.
    assert(platform != TargetPlatform.ios || iosArch != null);

    // buildSharedLibrary is ignored for iOS builds.
    if (platform == TargetPlatform.ios)
      buildSharedLibrary = false;

    if (buildSharedLibrary && androidSdk.ndk == null) {
      final String explanation = AndroidNdk.explainMissingNdk(androidSdk.directory);
      printError(
        'Could not find NDK in Android SDK at ${androidSdk.directory}:\n'
        '\n'
        '  $explanation\n'
        '\n'
        'Unable to build with --build-shared-library\n'
        'To install the NDK, see instructions at https://developer.android.com/ndk/guides/'
      );
      return 1;
    }

    final PackageMap packageMap = PackageMap(packagesPath);
    final String packageMapError = packageMap.checkValid();
    if (packageMapError != null) {
      printError(packageMapError);
      return 1;
    }

    final Directory outputDir = fs.directory(outputPath);
    outputDir.createSync(recursive: true);

    final String skyEnginePkg = _getPackagePath(packageMap, 'sky_engine');
    final String uiPath = fs.path.join(skyEnginePkg, 'lib', 'ui', 'ui.dart');
    final String vmServicePath = fs.path.join(skyEnginePkg, 'sdk_ext', 'vmservice_io.dart');

    final List<String> inputPaths = <String>[uiPath, vmServicePath, mainPath];
    final Set<String> outputPaths = Set<String>();

    final String depfilePath = fs.path.join(outputDir.path, 'snapshot.d');
    final List<String> genSnapshotArgs = <String>[
      '--url_mapping=dart:ui,$uiPath',
      '--url_mapping=dart:vmservice_io,$vmServicePath',
    ];
    genSnapshotArgs.addAll(<String>[
      '--reify-generic-functions',
      '--strong',
      '--sync-async',
    ]);
    if (extraGenSnapshotOptions != null && extraGenSnapshotOptions.isNotEmpty) {
      printTrace('Extra gen_snapshot options: $extraGenSnapshotOptions');
      genSnapshotArgs.addAll(extraGenSnapshotOptions);
    }

    final String assembly = fs.path.join(outputDir.path, 'snapshot_assembly.S');
    if (buildSharedLibrary || platform == TargetPlatform.ios) {
      // Assembly AOT snapshot.
      outputPaths.add(assembly);
      genSnapshotArgs.add('--snapshot_kind=app-aot-assembly');
      genSnapshotArgs.add('--assembly=$assembly');
    } else {
      // Blob AOT snapshot.
      final String vmSnapshotData = fs.path.join(outputDir.path, 'vm_snapshot_data');
      final String isolateSnapshotData = fs.path.join(outputDir.path, 'isolate_snapshot_data');
      final String vmSnapshotInstructions = fs.path.join(outputDir.path, 'vm_snapshot_instr');
      final String isolateSnapshotInstructions = fs.path.join(outputDir.path, 'isolate_snapshot_instr');
      outputPaths.addAll(<String>[vmSnapshotData, isolateSnapshotData, vmSnapshotInstructions, isolateSnapshotInstructions]);
      genSnapshotArgs.addAll(<String>[
        '--snapshot_kind=app-aot-blobs',
        '--vm_snapshot_data=$vmSnapshotData',
        '--isolate_snapshot_data=$isolateSnapshotData',
        '--vm_snapshot_instructions=$vmSnapshotInstructions',
        '--isolate_snapshot_instructions=$isolateSnapshotInstructions',
      ]);
    }

    if (platform == TargetPlatform.android_arm || iosArch == IOSArch.armv7) {
      // Use softfp for Android armv7 devices.
      // This is the default for armv7 iOS builds, but harmless to set.
      // TODO(cbracken): eliminate this when we fix https://github.com/flutter/flutter/issues/17489
      genSnapshotArgs.add('--no-sim-use-hardfp');

      // Not supported by the Pixel in 32-bit mode.
      genSnapshotArgs.add('--no-use-integer-division');
    }

    genSnapshotArgs.add(mainPath);

    // Verify that all required inputs exist.
    final Iterable<String> missingInputs = inputPaths.where((String p) => !fs.isFileSync(p));
    if (missingInputs.isNotEmpty) {
      printError('Missing input files: $missingInputs from $inputPaths');
      return 1;
    }

    // If inputs and outputs have not changed since last run, skip the build.
    final Fingerprinter fingerprinter = Fingerprinter(
      fingerprintPath: '$depfilePath.fingerprint',
      paths: <String>[mainPath]..addAll(inputPaths)..addAll(outputPaths),
      properties: <String, String>{
        'buildMode': buildMode.toString(),
        'targetPlatform': platform.toString(),
        'entryPoint': mainPath,
        'sharedLib': buildSharedLibrary.toString(),
        'extraGenSnapshotOptions': extraGenSnapshotOptions.join(' '),
      },
      depfilePaths: <String>[],
    );
    if (await fingerprinter.doesFingerprintMatch()) {
      printTrace('Skipping AOT snapshot build. Fingerprint match.');
      return 0;
    }

    final SnapshotType snapshotType = SnapshotType(platform, buildMode);
    final int genSnapshotExitCode = await genSnapshot.run(
      snapshotType: snapshotType,
      packagesPath: packageMap.packagesPath,
      additionalArgs: genSnapshotArgs,
      iosArch: iosArch,
    );
    if (genSnapshotExitCode != 0) {
      printError('Dart snapshot generator failed with exit code $genSnapshotExitCode');
      return genSnapshotExitCode;
    }

    // Write path to gen_snapshot, since snapshots have to be re-generated when we roll
    // the Dart SDK.
    final String genSnapshotPath = GenSnapshot.getSnapshotterPath(snapshotType);
    await outputDir.childFile('gen_snapshot.d').writeAsString('gen_snapshot.d: $genSnapshotPath\n');

    // On iOS, we use Xcode to compile the snapshot into a dynamic library that the
    // end-developer can link into their app.
    if (platform == TargetPlatform.ios) {
      final RunResult result = await _buildIosFramework(iosArch: iosArch, assemblyPath: assembly, outputPath: outputDir.path);
      if (result.exitCode != 0)
        return result.exitCode;
    } else if (buildSharedLibrary) {
      final RunResult result = await _buildAndroidSharedLibrary(assemblyPath: assembly, outputPath: outputDir.path);
      if (result.exitCode != 0) {
        printError('Failed to build AOT snapshot. Compiler terminated with exit code ${result.exitCode}');
        return result.exitCode;
      }
    }

    // Compute and record build fingerprint.
    await fingerprinter.writeFingerprint();
    return 0;
  }

  /// Builds an iOS framework at [outputPath]/App.framework from the assembly
  /// source at [assemblyPath].
  Future<RunResult> _buildIosFramework({
    @required IOSArch iosArch,
    @required String assemblyPath,
    @required String outputPath,
  }) async {
    final String targetArch = iosArch == IOSArch.armv7 ? 'armv7' : 'arm64';
    printStatus('Building App.framework for $targetArch...');
    final List<String> commonBuildOptions = <String>['-arch', targetArch, '-miphoneos-version-min=8.0'];

    final String assemblyO = fs.path.join(outputPath, 'snapshot_assembly.o');
    final RunResult compileResult = await xcode.cc(commonBuildOptions.toList()..addAll(<String>['-c', assemblyPath, '-o', assemblyO]));
    if (compileResult.exitCode != 0) {
      printError('Failed to compile AOT snapshot. Compiler terminated with exit code ${compileResult.exitCode}');
      return compileResult;
    }

    final String frameworkDir = fs.path.join(outputPath, 'App.framework');
    fs.directory(frameworkDir).createSync(recursive: true);
    final String appLib = fs.path.join(frameworkDir, 'App');
    final List<String> linkArgs = commonBuildOptions.toList()..addAll(<String>[
        '-dynamiclib',
        '-Xlinker', '-rpath', '-Xlinker', '@executable_path/Frameworks',
        '-Xlinker', '-rpath', '-Xlinker', '@loader_path/Frameworks',
        '-install_name', '@rpath/App.framework/App',
        '-o', appLib,
        assemblyO,
    ]);
    final RunResult linkResult = await xcode.clang(linkArgs);
    if (linkResult.exitCode != 0) {
      printError('Failed to link AOT snapshot. Linker terminated with exit code ${compileResult.exitCode}');
    }
    return linkResult;
  }

  /// Builds an Android shared library at [outputPath]/app.so from the assembly
  /// source at [assemblyPath].
  Future<RunResult> _buildAndroidSharedLibrary({
    @required String assemblyPath,
    @required String outputPath,
  }) async {
    // A word of warning: Instead of compiling via two steps, to a .o file and
    // then to a .so file we use only one command. When using two commands
    // gcc will end up putting a .eh_frame and a .debug_frame into the shared
    // library. Without stripping .debug_frame afterwards, unwinding tools
    // based upon libunwind use just one and ignore the contents of the other
    // (which causes it to not look into the other section and therefore not
    // find the correct unwinding information).
    final String assemblySo = fs.path.join(outputPath, 'app.so');
    return await runCheckedAsync(<String>[androidSdk.ndk.compiler]
        ..addAll(androidSdk.ndk.compilerArgs)
        ..addAll(<String>[ '-shared', '-nostdlib', '-o', assemblySo, assemblyPath ]));
  }

  /// Compiles a Dart file to kernel.
  ///
  /// Returns the output kernel file path, or null on failure.
  Future<String> compileKernel({
    @required TargetPlatform platform,
    @required BuildMode buildMode,
    @required String mainPath,
    @required String outputPath,
    List<String> extraFrontEndOptions = const <String>[],
  }) async {
    final Directory outputDir = fs.directory(outputPath);
    outputDir.createSync(recursive: true);

    printTrace('Compiling Dart to kernel: $mainPath');

    if ((extraFrontEndOptions != null) && extraFrontEndOptions.isNotEmpty)
      printTrace('Extra front-end options: $extraFrontEndOptions');

    final String depfilePath = fs.path.join(outputPath, 'kernel_compile.d');
    final CompilerOutput compilerOutput = await kernelCompiler.compile(
      sdkRoot: artifacts.getArtifactPath(Artifact.flutterPatchedSdkPath),
      mainPath: mainPath,
      outputFilePath: fs.path.join(outputPath, 'app.dill'),
      depFilePath: depfilePath,
      extraFrontEndOptions: extraFrontEndOptions,
      linkPlatformKernelIn: true,
      aot: true,
      trackWidgetCreation: false,
      targetProductVm: buildMode == BuildMode.release,
    );

    // Write path to frontend_server, since things need to be re-generated when that changes.
    final String frontendPath = artifacts.getArtifactPath(Artifact.frontendServerSnapshotForEngineDartSdk);
    await fs.directory(outputPath).childFile('frontend_server.d').writeAsString('frontend_server.d: $frontendPath\n');

    return compilerOutput?.outputFilename;
  }

  bool _isValidAotPlatform(TargetPlatform platform, BuildMode buildMode) {
    if (buildMode == BuildMode.debug)
      return false;
    return const <TargetPlatform>[
      TargetPlatform.android_arm,
      TargetPlatform.android_arm64,
      TargetPlatform.ios,
    ].contains(platform);
  }

  String _getPackagePath(PackageMap packageMap, String package) {
    return fs.path.dirname(fs.path.fromUri(packageMap.map[package]));
  }
}

class CoreJITSnapshotter {
  /// Builds a "Core JIT" VM snapshot of the specified kernel. This snapshot
  /// includes data as well as either machine code or DBC, depending on build
  /// configuration.
  Future<int> build({
    @required TargetPlatform platform,
    @required BuildMode buildMode,
    @required String mainPath,
    @required String packagesPath,
    @required String outputPath,
    @required String compilationTraceFilePath,
    List<String> extraGenSnapshotOptions = const <String>[],
  }) async {
    if (!_isValidCoreJitPlatform(platform)) {
      printError('${getNameForTargetPlatform(platform)} does not support Core JIT compilation.');
      return 1;
    }

    final Directory outputDir = fs.directory(outputPath);
    outputDir.createSync(recursive: true);

    final List<String> inputPaths = <String>[mainPath, compilationTraceFilePath];
    final Set<String> outputPaths = Set<String>();

    final String depfilePath = fs.path.join(outputDir.path, 'snapshot.d');
    final List<String> genSnapshotArgs = <String>[
      '--reify-generic-functions',
      '--strong',
      '--sync-async',
    ];
    if (buildMode == BuildMode.debug) {
      genSnapshotArgs.add('--enable_asserts');
    }
    if (extraGenSnapshotOptions != null && extraGenSnapshotOptions.isNotEmpty) {
      printTrace('Extra gen_snapshot options: $extraGenSnapshotOptions');
      genSnapshotArgs.addAll(extraGenSnapshotOptions);
    }

    // Blob Core JIT snapshot.
    final String vmSnapshotData = fs.path.join(outputDir.path, 'vm_snapshot_data');
    final String isolateSnapshotData = fs.path.join(outputDir.path, 'isolate_snapshot_data');
    final String vmSnapshotInstructions = fs.path.join(outputDir.path, 'vm_snapshot_instr');
    final String isolateSnapshotInstructions = fs.path.join(outputDir.path, 'isolate_snapshot_instr');
    outputPaths.addAll(<String>[vmSnapshotData, isolateSnapshotData, vmSnapshotInstructions, isolateSnapshotInstructions]);
    genSnapshotArgs.addAll(<String>[
      '--snapshot_kind=core-jit',
      '--vm_snapshot_data=$vmSnapshotData',
      '--isolate_snapshot_data=$isolateSnapshotData',
      '--vm_snapshot_instructions=$vmSnapshotInstructions',
      '--isolate_snapshot_instructions=$isolateSnapshotInstructions',
      '--load_compilation_trace=$compilationTraceFilePath',
    ]);

    if (platform == TargetPlatform.android_arm) {
      // Use softfp for Android armv7 devices.
      // TODO(cbracken): eliminate this when we fix https://github.com/flutter/flutter/issues/17489
      genSnapshotArgs.add('--no-sim-use-hardfp');

      // Not supported by the Pixel in 32-bit mode.
      genSnapshotArgs.add('--no-use-integer-division');
    }

    genSnapshotArgs.add(mainPath);

    // Verify that all required inputs exist.
    final Iterable<String> missingInputs = inputPaths.where((String p) => !fs.isFileSync(p));
    if (missingInputs.isNotEmpty) {
      printError('Missing input files: $missingInputs from $inputPaths');
      return 1;
    }

    // If inputs and outputs have not changed since last run, skip the build.
    final Fingerprinter fingerprinter = Fingerprinter(
      fingerprintPath: '$depfilePath.fingerprint',
      paths: <String>[mainPath]..addAll(inputPaths)..addAll(outputPaths),
      properties: <String, String>{
        'buildMode': buildMode.toString(),
        'targetPlatform': platform.toString(),
        'entryPoint': mainPath,
        'extraGenSnapshotOptions': extraGenSnapshotOptions.join(' '),
      },
      depfilePaths: <String>[],
    );
    if (await fingerprinter.doesFingerprintMatch()) {
      printTrace('Skipping Core JIT snapshot build. Fingerprint match.');
      return 0;
    }

    final SnapshotType snapshotType = SnapshotType(platform, buildMode);
    final int genSnapshotExitCode = await genSnapshot.run(
      snapshotType: snapshotType,
      packagesPath: packagesPath,
      additionalArgs: genSnapshotArgs,
    );
    if (genSnapshotExitCode != 0) {
      printError('Dart snapshot generator failed with exit code $genSnapshotExitCode');
      return genSnapshotExitCode;
    }

    // Write path to gen_snapshot, since snapshots have to be re-generated when we roll
    // the Dart SDK.
    final String genSnapshotPath = GenSnapshot.getSnapshotterPath(snapshotType);
    await outputDir.childFile('gen_snapshot.d').writeAsString('gen_snapshot.d: $genSnapshotPath\n');

    // Compute and record build fingerprint.
    await fingerprinter.writeFingerprint();
    return 0;
  }

  bool _isValidCoreJitPlatform(TargetPlatform platform) {
    return const <TargetPlatform>[
      TargetPlatform.android_arm,
      TargetPlatform.android_arm64,
    ].contains(platform);
  }
}
