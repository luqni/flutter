// Copyright 2015 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';

import 'artifacts.dart';
import 'asset.dart';
import 'base/build.dart';
import 'base/common.dart';
import 'base/file_system.dart';
import 'build_info.dart';
import 'compile.dart';
import 'dart/package_map.dart';
import 'devfs.dart';
import 'globals.dart';

const String defaultMainPath = 'lib/main.dart';
const String defaultAssetBasePath = '.';
const String defaultManifestPath = 'pubspec.yaml';
String get defaultSnapshotPath => fs.path.join(getBuildDirectory(), 'snapshot_blob.bin');
String get defaultDepfilePath => fs.path.join(getBuildDirectory(), 'snapshot_blob.bin.d');
String get defaultApplicationKernelPath => fs.path.join(getBuildDirectory(), 'app.dill');
const String defaultPrivateKeyPath = 'privatekey.der';

const String _kKernelKey = 'kernel_blob.bin';
const String _kVMSnapshotData = 'vm_snapshot_data';
const String _kVMSnapshotInstr = 'vm_snapshot_instr';
const String _kIsolateSnapshotData = 'isolate_snapshot_data';
const String _kIsolateSnapshotInstr = 'isolate_snapshot_instr';
const String _kDylibKey = 'libapp.so';
const String _kPlatformKernelKey = 'platform_strong.dill';

Future<void> build({
  TargetPlatform platform,
  BuildMode buildMode,
  String mainPath = defaultMainPath,
  String manifestPath = defaultManifestPath,
  String snapshotPath,
  String applicationKernelFilePath,
  String depfilePath,
  String privateKeyPath = defaultPrivateKeyPath,
  String assetDirPath,
  String packagesPath,
  bool precompiledSnapshot = false,
  bool reportLicensedPackages = false,
  bool trackWidgetCreation = false,
  String compilationTraceFilePath,
  List<String> extraFrontEndOptions = const <String>[],
  List<String> extraGenSnapshotOptions = const <String>[],
  List<String> fileSystemRoots,
  String fileSystemScheme,
}) async {
  snapshotPath ??= defaultSnapshotPath;
  depfilePath ??= defaultDepfilePath;
  assetDirPath ??= getAssetBuildDirectory();
  packagesPath ??= fs.path.absolute(PackageMap.globalPackagesPath);
  applicationKernelFilePath ??= defaultApplicationKernelPath;

  DevFSContent kernelContent;
  if (!precompiledSnapshot) {
    if ((extraFrontEndOptions != null) && extraFrontEndOptions.isNotEmpty)
      printTrace('Extra front-end options: $extraFrontEndOptions');
    ensureDirectoryExists(applicationKernelFilePath);
    final CompilerOutput compilerOutput = await kernelCompiler.compile(
      sdkRoot: artifacts.getArtifactPath(Artifact.flutterPatchedSdkPath),
      incrementalCompilerByteStorePath: compilationTraceFilePath != null ? null :
          fs.path.absolute(getIncrementalCompilerByteStoreDirectory()),
      mainPath: fs.file(mainPath).absolute.path,
      outputFilePath: applicationKernelFilePath,
      depFilePath: depfilePath,
      trackWidgetCreation: trackWidgetCreation,
      extraFrontEndOptions: extraFrontEndOptions,
      fileSystemRoots: fileSystemRoots,
      fileSystemScheme: fileSystemScheme,
      packagesPath: packagesPath,
      linkPlatformKernelIn: compilationTraceFilePath != null,
    );
    if (compilerOutput?.outputFilename == null) {
      throwToolExit('Compiler failed on $mainPath');
    }
    kernelContent = DevFSFileContent(fs.file(compilerOutput.outputFilename));

    await fs.directory(getBuildDirectory()).childFile('frontend_server.d')
        .writeAsString('frontend_server.d: ${artifacts.getArtifactPath(Artifact.frontendServerSnapshotForEngineDartSdk)}\n');

    if (compilationTraceFilePath != null) {
      final CoreJITSnapshotter snapshotter = CoreJITSnapshotter();
      final int snapshotExitCode = await snapshotter.build(
        platform: platform,
        buildMode: buildMode,
        mainPath: applicationKernelFilePath,
        outputPath: getBuildDirectory(),
        packagesPath: packagesPath,
        compilationTraceFilePath: compilationTraceFilePath,
        extraGenSnapshotOptions: extraGenSnapshotOptions,
      );
      if (snapshotExitCode != 0) {
        throwToolExit('Snapshotting exited with non-zero exit code: $snapshotExitCode');
      }
    }
  }

  final AssetBundle assets = await buildAssets(
    manifestPath: manifestPath,
    assetDirPath: assetDirPath,
    packagesPath: packagesPath,
    reportLicensedPackages: reportLicensedPackages,
  );
  if (assets == null)
    throwToolExit('Error building assets', exitCode: 1);

  await assemble(
    buildMode: buildMode,
    assetBundle: assets,
    kernelContent: kernelContent,
    privateKeyPath: privateKeyPath,
    assetDirPath: assetDirPath,
    compilationTraceFilePath: compilationTraceFilePath,
  );
}

Future<AssetBundle> buildAssets({
  String manifestPath,
  String assetDirPath,
  String packagesPath,
  bool includeDefaultFonts = true,
  bool reportLicensedPackages = false
}) async {
  assetDirPath ??= getAssetBuildDirectory();
  packagesPath ??= fs.path.absolute(PackageMap.globalPackagesPath);

  // Build the asset bundle.
  final AssetBundle assetBundle = AssetBundleFactory.instance.createBundle();
  final int result = await assetBundle.build(
    manifestPath: manifestPath,
    assetDirPath: assetDirPath,
    packagesPath: packagesPath,
    includeDefaultFonts: includeDefaultFonts,
    reportLicensedPackages: reportLicensedPackages
  );
  if (result != 0)
    return null;

  return assetBundle;
}

Future<void> assemble({
  BuildMode buildMode,
  AssetBundle assetBundle,
  DevFSContent kernelContent,
  File dylibFile,
  String privateKeyPath = defaultPrivateKeyPath,
  String assetDirPath,
  String compilationTraceFilePath,
}) async {
  assetDirPath ??= getAssetBuildDirectory();
  printTrace('Building bundle');

  final Map<String, DevFSContent> assetEntries = Map<String, DevFSContent>.from(assetBundle.entries);
  if (kernelContent != null) {
    if (compilationTraceFilePath != null) {
      final String vmSnapshotData = fs.path.join(getBuildDirectory(), _kVMSnapshotData);
      final String vmSnapshotInstr = fs.path.join(getBuildDirectory(), _kVMSnapshotInstr);
      final String isolateSnapshotData = fs.path.join(getBuildDirectory(), _kIsolateSnapshotData);
      final String isolateSnapshotInstr = fs.path.join(getBuildDirectory(), _kIsolateSnapshotInstr);
      assetEntries[_kVMSnapshotData] = DevFSFileContent(fs.file(vmSnapshotData));
      assetEntries[_kVMSnapshotInstr] = DevFSFileContent(fs.file(vmSnapshotInstr));
      assetEntries[_kIsolateSnapshotData] = DevFSFileContent(fs.file(isolateSnapshotData));
      assetEntries[_kIsolateSnapshotInstr] = DevFSFileContent(fs.file(isolateSnapshotInstr));
    } else {
      final String platformKernelDill = artifacts.getArtifactPath(Artifact.platformKernelDill);
      final String vmSnapshotData = artifacts.getArtifactPath(Artifact.vmSnapshotData, null, buildMode);
      final String isolateSnapshotData = artifacts.getArtifactPath(Artifact.isolateSnapshotData, null, buildMode);
      assetEntries[_kKernelKey] = kernelContent;
      assetEntries[_kPlatformKernelKey] = DevFSFileContent(fs.file(platformKernelDill));
      assetEntries[_kVMSnapshotData] = DevFSFileContent(fs.file(vmSnapshotData));
      assetEntries[_kIsolateSnapshotData] = DevFSFileContent(fs.file(isolateSnapshotData));
    }
  }
  if (dylibFile != null)
    assetEntries[_kDylibKey] = DevFSFileContent(dylibFile);

  printTrace('Writing asset files to $assetDirPath');
  ensureDirectoryExists(assetDirPath);

  await writeBundle(fs.directory(assetDirPath), assetEntries);
  printTrace('Wrote $assetDirPath');
}

Future<void> writeBundle(
    Directory bundleDir, Map<String, DevFSContent> assetEntries) async {
  if (bundleDir.existsSync())
    bundleDir.deleteSync(recursive: true);
  bundleDir.createSync(recursive: true);

  await Future.wait(
      assetEntries.entries.map((MapEntry<String, DevFSContent> entry) async {
    final File file = fs.file(fs.path.join(bundleDir.path, entry.key));
    file.parent.createSync(recursive: true);
    await file.writeAsBytes(await entry.value.contentsAsBytes());
  }));
}
