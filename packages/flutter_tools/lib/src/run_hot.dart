// Copyright 2016 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:convert';

import 'package:json_rpc_2/error_code.dart' as rpc_error_code;
import 'package:json_rpc_2/json_rpc_2.dart' as rpc;
import 'package:meta/meta.dart';

import 'base/common.dart';
import 'base/context.dart';
import 'base/file_system.dart';
import 'base/logger.dart';
import 'base/terminal.dart';
import 'base/utils.dart';
import 'build_info.dart';
import 'compile.dart';
import 'dart/dependencies.dart';
import 'dart/pub.dart';
import 'device.dart';
import 'globals.dart';
import 'resident_runner.dart';
import 'usage.dart';
import 'vmservice.dart';

class HotRunnerConfig {
  /// Should the hot runner compute the minimal Dart dependencies?
  bool computeDartDependencies = true;
  /// Should the hot runner assume that the minimal Dart dependencies do not change?
  bool stableDartDependencies = false;
  /// A hook for implementations to perform any necessary initialization prior
  /// to a hot restart. Should return true if the hot restart should continue.
  Future<bool> setupHotRestart() async {
    return true;
  }
}

HotRunnerConfig get hotRunnerConfig => context[HotRunnerConfig];

const bool kHotReloadDefault = true;

class HotRunner extends ResidentRunner {
  HotRunner(
    List<FlutterDevice> devices, {
    String target,
    DebuggingOptions debuggingOptions,
    bool usesTerminalUI = true,
    this.benchmarkMode = false,
    this.applicationBinary,
    this.hostIsIde = false,
    String projectRootPath,
    String packagesFilePath,
    this.dillOutputPath,
    bool stayResident = true,
    bool ipv6 = false,
  }) : super(devices,
             target: target,
             debuggingOptions: debuggingOptions,
             usesTerminalUI: usesTerminalUI,
             projectRootPath: projectRootPath,
             packagesFilePath: packagesFilePath,
             stayResident: stayResident,
             ipv6: ipv6);

  final bool benchmarkMode;
  final File applicationBinary;
  final bool hostIsIde;
  bool _didAttach = false;
  Set<String> _dartDependencies;
  final String dillOutputPath;

  final Map<String, List<int>> benchmarkData = <String, List<int>>{};
  // The initial launch is from a snapshot.
  bool _runningFromSnapshot = true;
  DateTime firstBuildTime;

  void _addBenchmarkData(String name, int value) {
    benchmarkData[name] ??= <int>[];
    benchmarkData[name].add(value);
  }

  Future<bool> _refreshDartDependencies() async {
    if (!hotRunnerConfig.computeDartDependencies) {
      // Disabled.
      return true;
    }
    if (_dartDependencies != null) {
      // Already computed.
      return true;
    }

    try {
      // Will return immediately if pubspec.yaml is up-to-date.
      await pubGet(
        context: PubContext.pubGet,
        directory: projectRootPath,
      );
    } on ToolExit catch (error) {
      printError(
        'Unable to reload your application because "flutter packages get" failed to update '
        'package dependencies.\n'
        '$error'
      );
      return false;
    }

    final DartDependencySetBuilder dartDependencySetBuilder =
        DartDependencySetBuilder(mainPath, packagesFilePath);
    try {
      _dartDependencies = Set<String>.from(dartDependencySetBuilder.build());
    } on DartDependencyException catch (error) {
      printError(
        'Your application could not be compiled, because its dependencies could not be established.\n'
        '$error'
      );
      return false;
    }
    return true;
  }

  Future<Null> _reloadSourcesService(String isolateId,
      { bool force = false, bool pause = false }) async {
    // TODO(cbernaschina): check that isolateId is the id of the UI isolate.
    final OperationResult result = await restart(pauseAfterRestart: pause);
    if (!result.isOk) {
      throw rpc.RpcException(
        rpc_error_code.INTERNAL_ERROR,
        'Unable to reload sources',
      );
    }
  }

  Future<String> _compileExpressionService(String isolateId, String expression,
      List<String> definitions, List<String> typeDefinitions,
      String libraryUri, String klass, bool isStatic,
      ) async {
    for (FlutterDevice device in flutterDevices) {
      if (device.generator != null) {
        final CompilerOutput compilerOutput =
            await device.generator.compileExpression(expression, definitions,
                typeDefinitions, libraryUri, klass, isStatic);
        if (compilerOutput != null && compilerOutput.outputFilename != null) {
          return base64.encode(fs.file(compilerOutput.outputFilename).readAsBytesSync());
        }
      }
    }
    throw 'Failed to compile $expression';
  }

  Future<int> attach({
    Completer<DebugConnectionInfo> connectionInfoCompleter,
    Completer<void> appStartedCompleter,
    String viewFilter,
  }) async {
    _didAttach = true;
    try {
      await connectToServiceProtocol(viewFilter: viewFilter,
          reloadSources: _reloadSourcesService,
          compileExpression: _compileExpressionService);
    } catch (error) {
      printError('Error connecting to the service protocol: $error');
      return 2;
    }

    for (FlutterDevice device in flutterDevices)
      device.initLogReader();
    try {
      final List<Uri> baseUris = await _initDevFS();
      if (connectionInfoCompleter != null) {
        // Only handle one debugger connection.
        connectionInfoCompleter.complete(
          DebugConnectionInfo(
            httpUri: flutterDevices.first.observatoryUris.first,
            wsUri: flutterDevices.first.vmServices.first.wsAddress,
            baseUri: baseUris.first.toString()
          )
        );
      }
    } catch (error) {
      printError('Error initializing DevFS: $error');
      return 3;
    }
    final Stopwatch initialUpdateDevFSsTimer = Stopwatch()..start();
    final bool devfsResult = await _updateDevFS(fullRestart: true);
    _addBenchmarkData('hotReloadInitialDevFSSyncMilliseconds',
        initialUpdateDevFSsTimer.elapsed.inMilliseconds);
    if (!devfsResult)
      return 3;

    await refreshViews();
    for (FlutterDevice device in flutterDevices) {
      // VM must have accepted the kernel binary, there will be no reload
      // report, so we let incremental compiler know that source code was accepted.
      if (device.generator != null)
        device.generator.accept();
      for (FlutterView view in device.views)
        printTrace('Connected to $view.');
    }

    if (stayResident) {
      setupTerminal();
      registerSignalHandlers();
    }

    appStartedCompleter?.complete();

    if (benchmarkMode) {
      // We are running in benchmark mode.
      printStatus('Running in benchmark mode.');
      // Measure time to perform a hot restart.
      printStatus('Benchmarking hot restart');
      await restart(fullRestart: true);
      // TODO(johnmccutchan): Modify script entry point.
      printStatus('Benchmarking hot reload');
      // Measure time to perform a hot reload.
      await restart(fullRestart: false);
      if (stayResident) {
        await waitForAppToFinish();
      } else {
        printStatus('Benchmark completed. Exiting application.');
        await _cleanupDevFS();
        await stopEchoingDeviceLog();
        await stopApp();
      }
      final File benchmarkOutput = fs.file('hot_benchmark.json');
      benchmarkOutput.writeAsStringSync(toPrettyJson(benchmarkData));
      return 0;
    }

    if (stayResident)
      return waitForAppToFinish();
    await cleanupAtFinish();
    return 0;
  }

  @override
  Future<int> run({
    Completer<DebugConnectionInfo> connectionInfoCompleter,
    Completer<void> appStartedCompleter,
    String route,
    bool shouldBuild = true
  }) async {
    if (!fs.isFileSync(mainPath)) {
      String message = 'Tried to run $mainPath, but that file does not exist.';
      if (target == null)
        message += '\nConsider using the -t option to specify the Dart file to start.';
      printError(message);
      return 1;
    }

    // Determine the Dart dependencies eagerly.
    if (!await _refreshDartDependencies()) {
      // Some kind of source level error or missing file in the Dart code.
      return 1;
    }

    firstBuildTime = DateTime.now();

    for (FlutterDevice device in flutterDevices) {
      final int result = await device.runHot(
        hotRunner: this,
        route: route,
        shouldBuild: shouldBuild,
      );
      if (result != 0) {
        return result;
      }
    }

    return attach(
      connectionInfoCompleter: connectionInfoCompleter,
      appStartedCompleter: appStartedCompleter
    );
  }

  @override
  Future<Null> handleTerminalCommand(String code) async {
    final String lower = code.toLowerCase();
    if (lower == 'r') {
      final OperationResult result = await restart(fullRestart: code == 'R');
      if (!result.isOk) {
        // TODO(johnmccutchan): Attempt to determine the number of errors that
        // occurred and tighten this message.
        printStatus('Try again after fixing the above error(s).', emphasis: true);
      }
    }
  }

  Future<List<Uri>> _initDevFS() async {
    final String fsName = fs.path.basename(projectRootPath);
    final List<Uri> devFSUris = <Uri>[];
    for (FlutterDevice device in flutterDevices) {
      final Uri uri = await device.setupDevFS(
        fsName,
        fs.directory(projectRootPath),
        packagesFilePath: packagesFilePath
      );
      devFSUris.add(uri);
    }
    return devFSUris;
  }

  Future<bool> _updateDevFS({ bool fullRestart = false }) async {
    if (!await _refreshDartDependencies()) {
      // Did not update DevFS because of a Dart source error.
      return false;
    }
    final bool isFirstUpload = assetBundle.wasBuiltOnce() == false;
    final bool rebuildBundle = assetBundle.needsBuild();
    if (rebuildBundle) {
      printTrace('Updating assets');
      final int result = await assetBundle.build();
      if (result != 0)
        return false;
    }

    for (FlutterDevice device in flutterDevices) {
      final bool result = await device.updateDevFS(
        mainPath: mainPath,
        target: target,
        bundle: assetBundle,
        firstBuildTime: firstBuildTime,
        bundleFirstUpload: isFirstUpload,
        bundleDirty: isFirstUpload == false && rebuildBundle,
        fileFilter: _dartDependencies,
        fullRestart: fullRestart,
        projectRootPath: projectRootPath,
        pathToReload: getReloadPath(fullRestart: fullRestart),
      );
      if (!result)
        return false;
    }

    if (!hotRunnerConfig.stableDartDependencies) {
      // Clear the set after the sync so they are recomputed next time.
      _dartDependencies = null;
    }
    return true;
  }

  Future<Null> _evictDirtyAssets() async {
    for (FlutterDevice device in flutterDevices) {
      if (device.devFS.assetPathsToEvict.isEmpty)
        return;
      if (device.views.first.uiIsolate == null)
        throw 'Application isolate not found';
      for (String assetPath in device.devFS.assetPathsToEvict)
        await device.views.first.uiIsolate.flutterEvictAsset(assetPath);
      device.devFS.assetPathsToEvict.clear();
    }
  }

  void _resetDirtyAssets() {
    for (FlutterDevice device in flutterDevices)
      device.devFS.assetPathsToEvict.clear();
  }

  Future<Null> _cleanupDevFS() async {
    for (FlutterDevice device in flutterDevices) {
      if (device.devFS != null) {
        // Cleanup the devFS; don't wait indefinitely, and ignore any errors.
        await device.devFS.destroy()
          .timeout(const Duration(milliseconds: 250))
          .catchError((dynamic error) {
            printTrace('$error');
          });
      }
      device.devFS = null;
    }
  }

  Future<Null> _launchInView(FlutterDevice device,
                             Uri entryUri,
                             Uri packagesUri,
                             Uri assetsDirectoryUri) async {
    for (FlutterView view in device.views)
      await view.runFromSource(entryUri, packagesUri, assetsDirectoryUri);
  }

  Future<Null> _launchFromDevFS(String mainScript) async {
    final String entryUri = fs.path.relative(mainScript, from: projectRootPath);
    for (FlutterDevice device in flutterDevices) {
      final Uri deviceEntryUri = device.devFS.baseUri.resolveUri(
        fs.path.toUri(entryUri));
      final Uri devicePackagesUri = device.devFS.baseUri.resolve('.packages');
      final Uri deviceAssetsDirectoryUri = device.devFS.baseUri.resolveUri(
        fs.path.toUri(getAssetBuildDirectory()));
      await _launchInView(device,
                          deviceEntryUri,
                          devicePackagesUri,
                          deviceAssetsDirectoryUri);
      if (benchmarkMode) {
        for (FlutterDevice device in flutterDevices)
          for (FlutterView view in device.views)
            await view.flushUIThreadTasks();
      }
    }
  }

  Future<OperationResult> _restartFromSources() async {
    if (!_isPaused()) {
      printTrace('Refreshing active FlutterViews before restarting.');
      await refreshViews();
    }

    final Stopwatch restartTimer = Stopwatch()..start();
    // TODO(aam): Add generator reset logic once we switch to using incremental
    // compiler for full application recompilation on restart.
    final bool updatedDevFS = await _updateDevFS(fullRestart: true);
    if (!updatedDevFS) {
      for (FlutterDevice device in flutterDevices) {
        if (device.generator != null)
          device.generator.reject();
      }
      return OperationResult(1, 'DevFS synchronization failed');
    }
    _resetDirtyAssets();
    for (FlutterDevice device in flutterDevices) {
      // VM must have accepted the kernel binary, there will be no reload
      // report, so we let incremental compiler know that source code was accepted.
      if (device.generator != null)
        device.generator.accept();
    }
    // Check if the isolate is paused and resume it.
    for (FlutterDevice device in flutterDevices) {
      for (FlutterView view in device.views) {
        if (view.uiIsolate != null) {
          // Reload the isolate.
          await view.uiIsolate.reload();
          final ServiceEvent pauseEvent = view.uiIsolate.pauseEvent;
          if ((pauseEvent != null) && pauseEvent.isPauseEvent) {
            // Resume the isolate so that it can be killed by the embedder.
            await view.uiIsolate.resume();
          }
        }
      }
    }
    // We are now running from source.
    _runningFromSnapshot = false;
    await _launchFromDevFS(mainPath + '.dill');
    restartTimer.stop();
    printTrace('Hot restart performed in ${getElapsedAsMilliseconds(restartTimer.elapsed)}.');
    // We are now running from sources.
    _runningFromSnapshot = false;
    _addBenchmarkData('hotRestartMillisecondsToFrame',
        restartTimer.elapsed.inMilliseconds);
    flutterUsage.sendEvent('hot', 'restart');
    flutterUsage.sendTiming('hot', 'restart', restartTimer.elapsed);
    return OperationResult.ok;
  }

  /// Returns [true] if the reload was successful.
  /// Prints errors if [printErrors] is [true].
  static bool validateReloadReport(Map<String, dynamic> reloadReport,
      { bool printErrors = true }) {
    if (reloadReport == null) {
      if (printErrors)
        printError('Hot reload did not receive reload report.');
      return false;
    }
    if (!(reloadReport['type'] == 'ReloadReport' &&
          (reloadReport['success'] == true ||
           (reloadReport['success'] == false &&
            (reloadReport['details'] is Map<String, dynamic> &&
             reloadReport['details']['notices'] is List<dynamic> &&
             reloadReport['details']['notices'].isNotEmpty &&
             reloadReport['details']['notices'].every(
               (dynamic item) => item is Map<String, dynamic> && item['message'] is String
             )
            )
           )
          )
         )) {
      if (printErrors)
        printError('Hot reload received invalid response: $reloadReport');
      return false;
    }
    if (!reloadReport['success']) {
      if (printErrors) {
        printError('Hot reload was rejected:');
        for (Map<String, dynamic> notice in reloadReport['details']['notices'])
          printError('${notice['message']}');
      }
      return false;
    }
    return true;
  }

  @override
  bool get supportsRestart => true;

  @override
  Future<OperationResult> restart({ bool fullRestart = false, bool pauseAfterRestart = false }) async {
    final Stopwatch timer = Stopwatch()..start();
    if (fullRestart) {
      final Status status = logger.startProgress(
        'Performing hot restart...',
        progressId: 'hot.restart',
      );
      try {
        if (!(await hotRunnerConfig.setupHotRestart()))
          return OperationResult(1, 'setupHotRestart failed');
        await _restartFromSources();
      } finally {
        status.cancel();
      }
      printStatus('Restarted application in ${getElapsedAsMilliseconds(timer.elapsed)}.');
      return OperationResult.ok;
    } else {
      final bool reloadOnTopOfSnapshot = _runningFromSnapshot;
      final String progressPrefix = reloadOnTopOfSnapshot ? 'Initializing' : 'Performing';
      final Status status = logger.startProgress(
        '$progressPrefix hot reload...',
        progressId: 'hot.reload'
      );
      OperationResult result;
      try {
        result = await _reloadSources(pause: pauseAfterRestart);
      } finally {
        status.cancel();
      }
      if (result.isOk)
        printStatus('${result.message} in ${getElapsedAsMilliseconds(timer.elapsed)}.');
      if (result.hintMessage != null)
        printStatus('\n${result.hintMessage}');
      return result;
    }
  }

  Future<OperationResult> _reloadSources({ bool pause = false }) async {
    for (FlutterDevice device in flutterDevices) {
      for (FlutterView view in device.views) {
        if (view.uiIsolate == null)
          throw 'Application isolate not found';
      }
    }

    if (!_isPaused()) {
      printTrace('Refreshing active FlutterViews before reloading.');
      await refreshViews();
    }

    // The initial launch is from a script snapshot. When we reload from source
    // on top of a script snapshot, the first reload will be a worst case reload
    // because all of the sources will end up being dirty (library paths will
    // change from host path to a device path). Subsequent reloads will
    // not be affected, so we resume reporting reload times on the second
    // reload.
    final bool shouldReportReloadTime = !_runningFromSnapshot;
    final Stopwatch reloadTimer = Stopwatch()..start();

    final Stopwatch devFSTimer = Stopwatch()..start();
    final bool updatedDevFS = await _updateDevFS();
    // Record time it took to synchronize to DevFS.
    _addBenchmarkData('hotReloadDevFSSyncMilliseconds',
        devFSTimer.elapsed.inMilliseconds);
    if (!updatedDevFS)
      return OperationResult(1, 'DevFS synchronization failed');
    String reloadMessage;
    final Stopwatch vmReloadTimer = Stopwatch()..start();
    try {
      final String entryPath = fs.path.relative(
        getReloadPath(fullRestart: false),
        from: projectRootPath,
      );
      final Completer<Map<String, dynamic>> retrieveFirstReloadReport = Completer<Map<String, dynamic>>();

      int countExpectedReports = 0;
      for (FlutterDevice device in flutterDevices) {
        if (_runningFromSnapshot) {
          // Asset directory has to be set only once when we switch from
          // running from snapshot to running from uploaded files.
          await device.resetAssetDirectory();
        }

        // List has one report per Flutter view.
        final List<Future<Map<String, dynamic>>> reports = device.reloadSources(
          entryPath,
          pause: pause
        );
        countExpectedReports += reports.length;
        await Future
            .wait(reports)
            .catchError((dynamic error) {
              return <Map<String, dynamic>>[error];
            })
            .then(
              (List<Map<String, dynamic>> list) {
                // TODO(aam): Investigate why we are validating only first reload report,
                // which seems to be current behavior
                final Map<String, dynamic> firstReport = list.first;
                // Don't print errors because they will be printed further down when
                // `validateReloadReport` is called again.
                device.updateReloadStatus(
                  validateReloadReport(firstReport, printErrors: false)
                );
                if (!retrieveFirstReloadReport.isCompleted)
                  retrieveFirstReloadReport.complete(firstReport);
              },
              onError: (dynamic error, StackTrace stack) {
                retrieveFirstReloadReport.completeError(error, stack);
              },
            );
      }

      if (countExpectedReports == 0) {
        printError('Unable to hot reload. No instance of Flutter is currently running.');
        return OperationResult(1, 'No instances running');
      }
      final Map<String, dynamic> reloadReport = await retrieveFirstReloadReport.future;
      if (!validateReloadReport(reloadReport)) {
        // Reload failed.
        flutterUsage.sendEvent('hot', 'reload-reject');
        return OperationResult(1, 'Reload rejected');
      } else {
        flutterUsage.sendEvent('hot', 'reload');
        final int loadedLibraryCount = reloadReport['details']['loadedLibraryCount'];
        final int finalLibraryCount = reloadReport['details']['finalLibraryCount'];
        printTrace('reloaded $loadedLibraryCount of $finalLibraryCount libraries');
        reloadMessage = 'Reloaded $loadedLibraryCount of $finalLibraryCount libraries';
      }
    } on Map<String, dynamic> catch (error, st) {
      printError('Hot reload failed: $error\n$st');
      final int errorCode = error['code'];
      final String errorMessage = error['message'];
      if (errorCode == Isolate.kIsolateReloadBarred) {
        printError(
          'Unable to hot reload application due to an unrecoverable error in '
          'the source code. Please address the error and then use "R" to '
          'restart the app.'
        );
        flutterUsage.sendEvent('hot', 'reload-barred');
        return OperationResult(errorCode, errorMessage);
      }

      printError('Hot reload failed:\ncode = $errorCode\nmessage = $errorMessage\n$st');
      return OperationResult(errorCode, errorMessage);
    } catch (error, st) {
      printError('Hot reload failed: $error\n$st');
      return OperationResult(1, '$error');
    }
    // Record time it took for the VM to reload the sources.
    _addBenchmarkData('hotReloadVMReloadMilliseconds',
        vmReloadTimer.elapsed.inMilliseconds);
    final Stopwatch reassembleTimer = Stopwatch()..start();
    // Reload the isolate.
    for (FlutterDevice device in flutterDevices) {
      printTrace('Sending reload events to ${device.device.name}');
      for (FlutterView view in device.views) {
        printTrace('Sending reload event to "${view.uiIsolate.name}"');
        await view.uiIsolate.reload();
      }
      await device.refreshViews();
    }
    // We are now running from source.
    _runningFromSnapshot = false;
    // Check if the isolate is paused.

    final List<FlutterView> reassembleViews = <FlutterView>[];
    for (FlutterDevice device in flutterDevices) {
      for (FlutterView view in device.views) {
        // Check if the isolate is paused, and if so, don't reassemble. Ignore the
        // PostPauseEvent event - the client requesting the pause will resume the app.
        final ServiceEvent pauseEvent = view.uiIsolate.pauseEvent;
        if (pauseEvent != null && pauseEvent.isPauseEvent && pauseEvent.kind != ServiceEvent.kPausePostRequest) {
          continue;
        }
        reassembleViews.add(view);
      }
    }
    if (reassembleViews.isEmpty) {
      printTrace('Skipping reassemble because all isolates are paused.');
      return OperationResult(OperationResult.ok.code, reloadMessage);
    }
    printTrace('Evicting dirty assets');
    await _evictDirtyAssets();
    printTrace('Reassembling application');
    bool reassembleAndScheduleErrors = false;
    bool reassembleTimedOut = false;
    for (FlutterView view in reassembleViews) {
      try {
        await view.uiIsolate.flutterReassemble();
      } on TimeoutException {
        reassembleTimedOut = true;
        printTrace('Reassembling ${view.uiIsolate.name} took too long.');
        printStatus('Hot reloading ${view.uiIsolate.name} took too long; the reload may have failed.');
        continue;
      } catch (error) {
        reassembleAndScheduleErrors = true;
        printError('Reassembling ${view.uiIsolate.name} failed: $error');
        continue;
      }
      try {
        /* ensure that a frame is scheduled */
        await view.uiIsolate.uiWindowScheduleFrame();
      } catch (error) {
        reassembleAndScheduleErrors = true;
        printError('Scheduling a frame for ${view.uiIsolate.name} failed: $error');
      }
    }
    // Record time it took for Flutter to reassemble the application.
    _addBenchmarkData('hotReloadFlutterReassembleMilliseconds',
        reassembleTimer.elapsed.inMilliseconds);

    reloadTimer.stop();
    printTrace('Hot reload performed in ${getElapsedAsMilliseconds(reloadTimer.elapsed)}.');
    // Record complete time it took for the reload.
    _addBenchmarkData('hotReloadMillisecondsToFrame',
        reloadTimer.elapsed.inMilliseconds);
    // Only report timings if we reloaded a single view without any
    // errors or timeouts.
    if ((reassembleViews.length == 1) &&
        !reassembleAndScheduleErrors &&
        !reassembleTimedOut &&
        shouldReportReloadTime)
      flutterUsage.sendTiming('hot', 'reload', reloadTimer.elapsed);

    return OperationResult(
      reassembleAndScheduleErrors ? 1 : OperationResult.ok.code,
      reloadMessage,
    );
  }

  bool _isPaused() {
    for (FlutterDevice device in flutterDevices) {
      for (FlutterView view in device.views) {
        if (view.uiIsolate != null) {
          final ServiceEvent pauseEvent = view.uiIsolate.pauseEvent;
          if (pauseEvent != null && pauseEvent.isPauseEvent) {
            return true;
          }
        }
      }
    }

    return false;
  }

  @override
  void printHelp({ @required bool details }) {
    const String fire = '🔥';
    final String message = terminal.color(
      fire + terminal.bolden('  To hot reload changes while running, press "r". '
          'To hot restart (and rebuild state), press "R".'),
      TerminalColor.red,
    );
    printStatus(message);
    for (FlutterDevice device in flutterDevices) {
      final String dname = device.device.name;
      for (Uri uri in device.observatoryUris)
        printStatus('An Observatory debugger and profiler on $dname is available at: $uri');
    }
    final String quitMessage = _didAttach
        ? 'To detach, press "d"; to quit, press "q".'
        : 'To quit, press "q".';
    if (details) {
      printHelpDetails();
      printStatus('To repeat this help message, press "h". $quitMessage');
    } else {
      printStatus('For a more detailed help message, press "h". $quitMessage');
    }
  }

  @override
  Future<Null> cleanupAfterSignal() async {
    await stopEchoingDeviceLog();
    if (_didAttach) {
      appFinished();
    } else {
      await stopApp();
    }
  }

  @override
  Future<Null> preStop() => _cleanupDevFS();

  @override
  Future<Null> cleanupAtFinish() async {
    await _cleanupDevFS();
    await stopEchoingDeviceLog();
  }
}
