// Copyright 2017 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:convert';

import 'package:collection/collection.dart' show ListEquality;
import 'package:mockito/mockito.dart';
import 'package:process/process.dart';
import 'package:quiver/time.dart';

import 'package:flutter_tools/src/base/context.dart';
import 'package:flutter_tools/src/base/io.dart';
import 'package:flutter_tools/src/base/logger.dart';
import 'package:flutter_tools/src/cache.dart';
import 'package:flutter_tools/src/version.dart';

import 'src/common.dart';
import 'src/context.dart';

final Clock _testClock = Clock.fixed(DateTime(2015, 1, 1));
final DateTime _upToDateVersion = _testClock.agoBy(FlutterVersion.kVersionAgeConsideredUpToDate ~/ 2);
final DateTime _outOfDateVersion = _testClock.agoBy(FlutterVersion.kVersionAgeConsideredUpToDate * 2);
final DateTime _stampUpToDate = _testClock.agoBy(FlutterVersion.kCheckAgeConsideredUpToDate ~/ 2);
final DateTime _stampOutOfDate = _testClock.agoBy(FlutterVersion.kCheckAgeConsideredUpToDate * 2);

void main() {
  MockProcessManager mockProcessManager;
  MockCache mockCache;

  setUp(() {
    mockProcessManager = MockProcessManager();
    mockCache = MockCache();
  });

  group('$FlutterVersion', () {
    setUpAll(() {
      Cache.disableLocking();
      FlutterVersion.timeToPauseToLetUserReadTheMessage = Duration.zero;
    });

    testUsingContext('prints nothing when Flutter installation looks fresh', () async {
      fakeData(
        mockProcessManager,
        mockCache,
        localCommitDate: _upToDateVersion,
        // Server will be pinged because we haven't pinged within last x days
        expectServerPing: true,
        remoteCommitDate: _outOfDateVersion,
        expectSetStamp: true);
      await FlutterVersion.instance.checkFlutterVersionFreshness();
      _expectVersionMessage('');
    }, overrides: <Type, Generator>{
      FlutterVersion: () => FlutterVersion(_testClock),
      ProcessManager: () => mockProcessManager,
      Cache: () => mockCache,
    });

    testUsingContext('prints nothing when Flutter installation looks out-of-date by is actually up-to-date', () async {
      fakeData(
        mockProcessManager,
        mockCache,
        localCommitDate: _outOfDateVersion,
        stamp: VersionCheckStamp(
          lastTimeVersionWasChecked: _stampOutOfDate,
          lastKnownRemoteVersion: _outOfDateVersion,
        ),
        remoteCommitDate: _outOfDateVersion,
        expectSetStamp: true,
        expectServerPing: true,
      );
      final FlutterVersion version = FlutterVersion.instance;

      await version.checkFlutterVersionFreshness();
      _expectVersionMessage('');
    }, overrides: <Type, Generator>{
      FlutterVersion: () => FlutterVersion(_testClock),
      ProcessManager: () => mockProcessManager,
      Cache: () => mockCache,
    });

    testUsingContext('does not ping server when version stamp is up-to-date', () async {
      fakeData(
        mockProcessManager,
        mockCache,
        localCommitDate: _outOfDateVersion,
        stamp: VersionCheckStamp(
          lastTimeVersionWasChecked: _stampUpToDate,
          lastKnownRemoteVersion: _upToDateVersion,
        ),
        expectSetStamp: true,
      );

      final FlutterVersion version = FlutterVersion.instance;
      await version.checkFlutterVersionFreshness();
      _expectVersionMessage(FlutterVersion.newVersionAvailableMessage());
    }, overrides: <Type, Generator>{
      FlutterVersion: () => FlutterVersion(_testClock),
      ProcessManager: () => mockProcessManager,
      Cache: () => mockCache,
    });

    testUsingContext('does not print warning if printed recently', () async {
      fakeData(
        mockProcessManager,
        mockCache,
        localCommitDate: _outOfDateVersion,
        stamp: VersionCheckStamp(
            lastTimeVersionWasChecked: _stampUpToDate,
            lastKnownRemoteVersion: _upToDateVersion,
        ),
        expectSetStamp: true,
      );

      final FlutterVersion version = FlutterVersion.instance;
      await version.checkFlutterVersionFreshness();
      _expectVersionMessage(FlutterVersion.newVersionAvailableMessage());
      expect((await VersionCheckStamp.load()).lastTimeWarningWasPrinted, _testClock.now());

      await version.checkFlutterVersionFreshness();
      _expectVersionMessage('');
    }, overrides: <Type, Generator>{
      FlutterVersion: () => FlutterVersion(_testClock),
      ProcessManager: () => mockProcessManager,
      Cache: () => mockCache,
    });

    testUsingContext('pings server when version stamp is missing then does not', () async {
      fakeData(
        mockProcessManager,
        mockCache,
        localCommitDate: _outOfDateVersion,
        remoteCommitDate: _upToDateVersion,
        expectSetStamp: true,
        expectServerPing: true,
      );
      final FlutterVersion version = FlutterVersion.instance;

      await version.checkFlutterVersionFreshness();
      _expectVersionMessage(FlutterVersion.newVersionAvailableMessage());

      // Immediate subsequent check is not expected to ping the server.
      fakeData(
        mockProcessManager,
        mockCache,
        localCommitDate: _outOfDateVersion,
        stamp: await VersionCheckStamp.load(),
      );
      await version.checkFlutterVersionFreshness();
      _expectVersionMessage('');
    }, overrides: <Type, Generator>{
      FlutterVersion: () => FlutterVersion(_testClock),
      ProcessManager: () => mockProcessManager,
      Cache: () => mockCache,
    });

    testUsingContext('pings server when version stamp is out-of-date', () async {
      fakeData(
        mockProcessManager,
        mockCache,
        localCommitDate: _outOfDateVersion,
        stamp: VersionCheckStamp(
            lastTimeVersionWasChecked: _stampOutOfDate,
            lastKnownRemoteVersion: _testClock.ago(days: 2),
        ),
        remoteCommitDate: _upToDateVersion,
        expectSetStamp: true,
        expectServerPing: true,
      );
      final FlutterVersion version = FlutterVersion.instance;

      await version.checkFlutterVersionFreshness();
      _expectVersionMessage(FlutterVersion.newVersionAvailableMessage());
    }, overrides: <Type, Generator>{
      FlutterVersion: () => FlutterVersion(_testClock),
      ProcessManager: () => mockProcessManager,
      Cache: () => mockCache,
    });

    testUsingContext('does not print warning when unable to connect to server if not out of date', () async {
      fakeData(
        mockProcessManager,
        mockCache,
        localCommitDate: _upToDateVersion,
        errorOnFetch: true,
        expectServerPing: true,
        expectSetStamp: true,
      );
      final FlutterVersion version = FlutterVersion.instance;

      await version.checkFlutterVersionFreshness();
      _expectVersionMessage('');
    }, overrides: <Type, Generator>{
      FlutterVersion: () => FlutterVersion(_testClock),
      ProcessManager: () => mockProcessManager,
      Cache: () => mockCache,
    });

    testUsingContext('prints warning when unable to connect to server if really out of date', () async {
      fakeData(
        mockProcessManager,
        mockCache,
        localCommitDate: _outOfDateVersion,
        errorOnFetch: true,
        expectServerPing: true,
        expectSetStamp: true
      );
      final FlutterVersion version = FlutterVersion.instance;

      await version.checkFlutterVersionFreshness();
      _expectVersionMessage(FlutterVersion.versionOutOfDateMessage(_testClock.now().difference(_outOfDateVersion)));
    }, overrides: <Type, Generator>{
      FlutterVersion: () => FlutterVersion(_testClock),
      ProcessManager: () => mockProcessManager,
      Cache: () => mockCache,
    });

    testUsingContext('versions comparison', () async {
      fakeData(
          mockProcessManager,
          mockCache,
          localCommitDate: _outOfDateVersion,
          errorOnFetch: true,
          expectServerPing: true,
          expectSetStamp: true
      );
      final FlutterVersion version = FlutterVersion.instance;

      when(mockProcessManager.runSync(
        <String>['git', 'merge-base', '--is-ancestor', 'abcdef', '123456'],
        workingDirectory: anyNamed('workingDirectory'),
      )).thenReturn(ProcessResult(1, 0, '', ''));

      expect(
        version.checkRevisionAncestry(
          tentativeDescendantRevision: '123456',
          tentativeAncestorRevision: 'abcdef',
        ),
        true
      );

      verify(mockProcessManager.runSync(
        <String>['git', 'merge-base', '--is-ancestor', 'abcdef', '123456'],
        workingDirectory: anyNamed('workingDirectory'),
      ));
    },
    overrides: <Type, Generator>{
      FlutterVersion: () => FlutterVersion(_testClock),
      ProcessManager: () => mockProcessManager,
    });
  });

  group('$VersionCheckStamp', () {
    void _expectDefault(VersionCheckStamp stamp) {
      expect(stamp.lastKnownRemoteVersion, isNull);
      expect(stamp.lastTimeVersionWasChecked, isNull);
      expect(stamp.lastTimeWarningWasPrinted, isNull);
    }

    testUsingContext('loads blank when stamp file missing', () async {
      fakeData(mockProcessManager, mockCache);
      _expectDefault(await VersionCheckStamp.load());
    }, overrides: <Type, Generator>{
      FlutterVersion: () => FlutterVersion(_testClock),
      ProcessManager: () => mockProcessManager,
      Cache: () => mockCache,
    });

    testUsingContext('loads blank when stamp file is malformed JSON', () async {
      fakeData(mockProcessManager, mockCache, stampJson: '<');
      _expectDefault(await VersionCheckStamp.load());
    }, overrides: <Type, Generator>{
      FlutterVersion: () => FlutterVersion(_testClock),
      ProcessManager: () => mockProcessManager,
      Cache: () => mockCache,
    });

    testUsingContext('loads blank when stamp file is well-formed but invalid JSON', () async {
      fakeData(mockProcessManager, mockCache, stampJson: '[]');
      _expectDefault(await VersionCheckStamp.load());
    }, overrides: <Type, Generator>{
      FlutterVersion: () => FlutterVersion(_testClock),
      ProcessManager: () => mockProcessManager,
      Cache: () => mockCache,
    });

    testUsingContext('loads valid JSON', () async {
      fakeData(mockProcessManager, mockCache, stampJson: '''
      {
        "lastKnownRemoteVersion": "${_testClock.ago(days: 1)}",
        "lastTimeVersionWasChecked": "${_testClock.ago(days: 2)}",
        "lastTimeWarningWasPrinted": "${_testClock.now()}"
      }
      ''');

      final VersionCheckStamp stamp = await VersionCheckStamp.load();
      expect(stamp.lastKnownRemoteVersion, _testClock.ago(days: 1));
      expect(stamp.lastTimeVersionWasChecked, _testClock.ago(days: 2));
      expect(stamp.lastTimeWarningWasPrinted, _testClock.now());
    }, overrides: <Type, Generator>{
      FlutterVersion: () => FlutterVersion(_testClock),
      ProcessManager: () => mockProcessManager,
      Cache: () => mockCache,
    });

    testUsingContext('stores version stamp', () async {
      fakeData(mockProcessManager, mockCache, expectSetStamp: true);

      _expectDefault(await VersionCheckStamp.load());

      final VersionCheckStamp stamp = VersionCheckStamp(
        lastKnownRemoteVersion: _testClock.ago(days: 1),
        lastTimeVersionWasChecked: _testClock.ago(days: 2),
        lastTimeWarningWasPrinted: _testClock.now(),
      );
      await stamp.store();

      final VersionCheckStamp storedStamp = await VersionCheckStamp.load();
      expect(storedStamp.lastKnownRemoteVersion, _testClock.ago(days: 1));
      expect(storedStamp.lastTimeVersionWasChecked, _testClock.ago(days: 2));
      expect(storedStamp.lastTimeWarningWasPrinted, _testClock.now());
    }, overrides: <Type, Generator>{
      FlutterVersion: () => FlutterVersion(_testClock),
      ProcessManager: () => mockProcessManager,
      Cache: () => mockCache,
    });

    testUsingContext('overwrites individual fields', () async {
      fakeData(mockProcessManager, mockCache, expectSetStamp: true);

      _expectDefault(await VersionCheckStamp.load());

      final VersionCheckStamp stamp = VersionCheckStamp(
        lastKnownRemoteVersion: _testClock.ago(days: 10),
        lastTimeVersionWasChecked: _testClock.ago(days: 9),
        lastTimeWarningWasPrinted: _testClock.ago(days: 8),
      );
      await stamp.store(
        newKnownRemoteVersion: _testClock.ago(days: 1),
        newTimeVersionWasChecked: _testClock.ago(days: 2),
        newTimeWarningWasPrinted: _testClock.now(),
      );

      final VersionCheckStamp storedStamp = await VersionCheckStamp.load();
      expect(storedStamp.lastKnownRemoteVersion, _testClock.ago(days: 1));
      expect(storedStamp.lastTimeVersionWasChecked, _testClock.ago(days: 2));
      expect(storedStamp.lastTimeWarningWasPrinted, _testClock.now());
    }, overrides: <Type, Generator>{
      FlutterVersion: () => FlutterVersion(_testClock),
      ProcessManager: () => mockProcessManager,
      Cache: () => mockCache,
    });
  });
}

void _expectVersionMessage(String message) {
  final BufferLogger logger = context[Logger];
  expect(logger.statusText.trim(), message.trim());
  logger.clear();
}

void fakeData(
  ProcessManager pm,
  Cache cache, {
  DateTime localCommitDate,
  DateTime remoteCommitDate,
  VersionCheckStamp stamp,
  String stampJson,
  bool errorOnFetch = false,
  bool expectSetStamp = false,
  bool expectServerPing = false,
}) {
  ProcessResult success(String standardOutput) {
    return ProcessResult(1, 0, standardOutput, '');
  }

  ProcessResult failure(int exitCode) {
    return ProcessResult(1, exitCode, '', 'error');
  }

  when(cache.getStampFor(any)).thenAnswer((Invocation invocation) {
    expect(invocation.positionalArguments.single, VersionCheckStamp.kFlutterVersionCheckStampFile);

    if (stampJson != null)
      return stampJson;

    if (stamp != null)
      return json.encode(stamp.toJson());

    return null;
  });

  when(cache.setStampFor(any, any)).thenAnswer((Invocation invocation) {
    expect(invocation.positionalArguments.first, VersionCheckStamp.kFlutterVersionCheckStampFile);

    if (expectSetStamp) {
      stamp = VersionCheckStamp.fromJson(json.decode(invocation.positionalArguments[1]));
      return null;
    }

    throw StateError('Unexpected call to Cache.setStampFor(${invocation.positionalArguments}, ${invocation.namedArguments})');
  });

  final Answering<ProcessResult> syncAnswer = (Invocation invocation) {
    bool argsAre(String a1, [String a2, String a3, String a4, String a5, String a6, String a7, String a8]) {
      const ListEquality<String> equality = ListEquality<String>();
      final List<String> args = invocation.positionalArguments.single;
      final List<String> expectedArgs =
      <String>[a1, a2, a3, a4, a5, a6, a7, a8]
          .where((String arg) => arg != null)
          .toList();
      return equality.equals(args, expectedArgs);
    }

    if (argsAre('git', 'log', '-n', '1', '--pretty=format:%ad', '--date=iso')) {
      return success(localCommitDate.toString());
    } else if (argsAre('git', 'remote')) {
      return success('');
    } else if (argsAre('git', 'remote', 'add', '__flutter_version_check__', 'https://github.com/flutter/flutter.git')) {
      return success('');
    } else if (argsAre('git', 'fetch', '__flutter_version_check__', 'master')) {
      if (!expectServerPing)
        fail('Did not expect server ping');
      return errorOnFetch ? failure(128) : success('');
    } else if (remoteCommitDate != null && argsAre('git', 'log', '__flutter_version_check__/master', '-n', '1', '--pretty=format:%ad', '--date=iso')) {
      return success(remoteCommitDate.toString());
    }

    throw StateError('Unexpected call to ProcessManager.run(${invocation.positionalArguments}, ${invocation.namedArguments})');
  };

  when(pm.runSync(any, workingDirectory: anyNamed('workingDirectory'))).thenAnswer(syncAnswer);
  when(pm.run(any, workingDirectory: anyNamed('workingDirectory'))).thenAnswer((Invocation invocation) async {
    return syncAnswer(invocation);
  });

  when(pm.runSync(
    <String>['git', 'rev-parse', '--abbrev-ref', '--symbolic', '@{u}'],
    workingDirectory: anyNamed('workingDirectory'),
    environment: anyNamed('environment'),
  )).thenReturn(ProcessResult(101, 0, 'master', ''));
  when(pm.runSync(
    <String>['git', 'rev-parse', '--abbrev-ref', 'HEAD'],
    workingDirectory: anyNamed('workingDirectory'),
    environment: anyNamed('environment'),
  )).thenReturn(ProcessResult(102, 0, 'branch', ''));
  when(pm.runSync(
    <String>['git', 'log', '-n', '1', '--pretty=format:%H'],
    workingDirectory: anyNamed('workingDirectory'),
    environment: anyNamed('environment'),
  )).thenReturn(ProcessResult(103, 0, '1234abcd', ''));
  when(pm.runSync(
    <String>['git', 'log', '-n', '1', '--pretty=format:%ar'],
    workingDirectory: anyNamed('workingDirectory'),
    environment: anyNamed('environment'),
  )).thenReturn(ProcessResult(104, 0, '1 second ago', ''));
  when(pm.runSync(
    <String>['git', 'describe', '--match', 'v*.*.*', '--first-parent', '--long', '--tags'],
    workingDirectory: anyNamed('workingDirectory'),
    environment: anyNamed('environment'),
  )).thenReturn(ProcessResult(105, 0, 'v0.1.2-3-1234abcd', ''));
}

class MockProcessManager extends Mock implements ProcessManager {}
class MockCache extends Mock implements Cache {}
