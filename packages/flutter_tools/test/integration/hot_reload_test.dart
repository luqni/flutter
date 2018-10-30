// Copyright 2018 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:file/file.dart';
import 'package:flutter_tools/src/base/file_system.dart';
import 'package:flutter_tools/src/base/platform.dart';

import 'package:vm_service_client/vm_service_client.dart';

import '../src/common.dart';
import 'test_data/basic_project.dart';
import 'test_driver.dart';

void main() {
  group('hot', () {
    Directory tempDir;
    final BasicProject _project = BasicProject();
    FlutterTestDriver _flutter;

    setUp(() async {
      tempDir = fs.systemTempDirectory.createTempSync('flutter_hot_reload_test_app.');
      await _project.setUpIn(tempDir);
      _flutter = FlutterTestDriver(tempDir);
    });

    tearDown(() async {
      await _flutter.stop();
      tryToDelete(tempDir);
    });

    test('reload works without error', () async {
      await _flutter.run();
      await _flutter.hotReload();
    });

    test('restart works without error', () async {
      await _flutter.run();
      await _flutter.hotRestart();
      // TODO(dantup): Unskip after flutter-tester restart issue is fixed on Windows:
      // https://github.com/flutter/flutter/issues/21348.
    }, skip: platform.isWindows);

    test('reload hits breakpoints with file:// prefixes after reload', () async {
      await _flutter.run(withDebugger: true);

      // Hit breakpoint using a file:// URI.
      final VMIsolate isolate = await _flutter.breakAt(
          Uri.file(_project.breakpointFile).toString(),
          _project.breakpointLine);
      expect(isolate.pauseEvent, isInstanceOf<VMPauseBreakpointEvent>());
    });
  }, timeout: const Timeout.factor(6));
}
