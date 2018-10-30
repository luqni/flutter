// Copyright 2016 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';

import '../base/context.dart';
import '../base/os.dart';
import '../base/platform.dart';
import '../base/process.dart';
import '../base/version.dart';
import '../doctor.dart';
import 'cocoapods.dart';
import 'mac.dart';
import 'plist_utils.dart' as plist;

IOSWorkflow get iosWorkflow => context[IOSWorkflow];
IOSValidator get iosValidator => context[IOSValidator];
CocoaPodsValidator get cocoapodsValidator => context[CocoaPodsValidator];

class IOSWorkflow implements Workflow {
  const IOSWorkflow();

  @override
  bool get appliesToHostPlatform => platform.isMacOS;

  // We need xcode (+simctl) to list simulator devices, and libimobiledevice to list real devices.
  @override
  bool get canListDevices => xcode.isInstalledAndMeetsVersionCheck && xcode.isSimctlInstalled;

  // We need xcode to launch simulator devices, and ideviceinstaller and ios-deploy
  // for real devices.
  @override
  bool get canLaunchDevices => xcode.isInstalledAndMeetsVersionCheck;

  @override
  bool get canListEmulators => false;

  String getPlistValueFromFile(String path, String key) {
    return plist.getValueFromFile(path, key);
  }
}

class IOSValidator extends DoctorValidator {

  const IOSValidator() : super('iOS toolchain - develop for iOS devices');

  Future<bool> get hasIDeviceInstaller => exitsHappyAsync(<String>['ideviceinstaller', '-h']);

  Future<bool> get hasIosDeploy => exitsHappyAsync(<String>['ios-deploy', '--version']);

  String get iosDeployMinimumVersion => '1.9.2';

  Future<String> get iosDeployVersionText async => (await runAsync(<String>['ios-deploy', '--version'])).processResult.stdout.replaceAll('\n', '');

  bool get hasHomebrew => os.which('brew') != null;

  Future<String> get macDevMode async => (await runAsync(<String>['DevToolsSecurity', '-status'])).processResult.stdout;

  Future<bool> get _iosDeployIsInstalledAndMeetsVersionCheck async {
    if (!await hasIosDeploy)
      return false;
    try {
      final Version version = Version.parse(await iosDeployVersionText);
      return version >= Version.parse(iosDeployMinimumVersion);
    } on FormatException catch (_) {
      return false;
    }
  }

  @override
  Future<ValidationResult> validate() async {
    final List<ValidationMessage> messages = <ValidationMessage>[];
    ValidationType xcodeStatus = ValidationType.missing;
    ValidationType brewStatus = ValidationType.missing;
    String xcodeVersionInfo;

    if (xcode.isInstalled) {
      xcodeStatus = ValidationType.installed;

      messages.add(ValidationMessage('Xcode at ${xcode.xcodeSelectPath}'));

      xcodeVersionInfo = xcode.versionText;
      if (xcodeVersionInfo.contains(','))
        xcodeVersionInfo = xcodeVersionInfo.substring(0, xcodeVersionInfo.indexOf(','));
      messages.add(ValidationMessage(xcode.versionText));

      if (!xcode.isInstalledAndMeetsVersionCheck) {
        xcodeStatus = ValidationType.partial;
        messages.add(ValidationMessage.error(
          'Flutter requires a minimum Xcode version of $kXcodeRequiredVersionMajor.$kXcodeRequiredVersionMinor.0.\n'
          'Download the latest version or update via the Mac App Store.'
        ));
      }

      if (!xcode.eulaSigned) {
        xcodeStatus = ValidationType.partial;
        messages.add(ValidationMessage.error(
          'Xcode end user license agreement not signed; open Xcode or run the command \'sudo xcodebuild -license\'.'
        ));
      }
      if (!xcode.isSimctlInstalled) {
        xcodeStatus = ValidationType.partial;
        messages.add(ValidationMessage.error(
          'Xcode requires additional components to be installed in order to run.\n'
          'Launch Xcode and install additional required components when prompted.'
        ));
      }

    } else {
      xcodeStatus = ValidationType.missing;
      if (xcode.xcodeSelectPath == null || xcode.xcodeSelectPath.isEmpty) {
        messages.add(ValidationMessage.error(
            'Xcode not installed; this is necessary for iOS development.\n'
            'Download at https://developer.apple.com/xcode/download/.'
        ));
      } else {
        messages.add(ValidationMessage.error(
            'Xcode installation is incomplete; a full installation is necessary for iOS development.\n'
            'Download at: https://developer.apple.com/xcode/download/\n'
            'Or install Xcode via the App Store.\n'
            'Once installed, run:\n'
            '  sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer'
        ));
      }
    }

    // brew installed
    if (hasHomebrew) {
      brewStatus = ValidationType.installed;

      if (!iMobileDevice.isInstalled) {
        brewStatus = ValidationType.partial;
        messages.add(ValidationMessage.error(
            'libimobiledevice and ideviceinstaller are not installed. To install, run:\n'
            '  brew install --HEAD libimobiledevice\n'
            '  brew install ideviceinstaller'
        ));
      } else if (!await iMobileDevice.isWorking) {
        brewStatus = ValidationType.partial;
        messages.add(ValidationMessage.error(
            'Verify that all connected devices have been paired with this computer in Xcode.\n'
            'If all devices have been paired, libimobiledevice and ideviceinstaller may require updating.\n'
            'To update, run:\n'
            '  brew uninstall --ignore-dependencies libimobiledevice\n'
            '  brew install --HEAD libimobiledevice\n'
            '  brew install ideviceinstaller'
        ));
      } else if (!await hasIDeviceInstaller) {
        brewStatus = ValidationType.partial;
        messages.add(ValidationMessage.error(
          'ideviceinstaller is not installed; this is used to discover connected iOS devices.\n'
          'To install, run:\n'
          '  brew install --HEAD libimobiledevice\n'
          '  brew install ideviceinstaller'
        ));
      }

      // Check ios-deploy is installed at meets version requirements.
      if (await hasIosDeploy) {
        messages.add(ValidationMessage('ios-deploy ${await iosDeployVersionText}'));
      }
      if (!await _iosDeployIsInstalledAndMeetsVersionCheck) {
        brewStatus = ValidationType.partial;
        if (await hasIosDeploy) {
          messages.add(ValidationMessage.error(
            'ios-deploy out of date ($iosDeployMinimumVersion is required). To upgrade:\n'
            '  brew upgrade ios-deploy'
          ));
        } else {
          messages.add(ValidationMessage.error(
            'ios-deploy not installed. To install:\n'
            '  brew install ios-deploy'
          ));
        }
      }

    } else {
      brewStatus = ValidationType.missing;
      messages.add(ValidationMessage.error(
          'Brew not installed; use this to install tools for iOS device development.\n'
              'Download brew at https://brew.sh/.'
      ));
    }

    return ValidationResult(
        <ValidationType>[xcodeStatus, brewStatus].reduce(_mergeValidationTypes),
        messages,
        statusInfo: xcodeVersionInfo
    );
  }

  ValidationType _mergeValidationTypes(ValidationType t1, ValidationType t2) {
    return t1 == t2 ? t1 : ValidationType.partial;
  }
}

class CocoaPodsValidator extends DoctorValidator {
  const CocoaPodsValidator() : super('CocoaPods subvalidator');

  bool get hasHomebrew => os.which('brew') != null;

  @override
  Future<ValidationResult> validate() async {
    final List<ValidationMessage> messages = <ValidationMessage>[];

    ValidationType status = ValidationType.installed;
    if (hasHomebrew) {
      final CocoaPodsStatus cocoaPodsStatus = await cocoaPods
          .evaluateCocoaPodsInstallation;

      if (cocoaPodsStatus == CocoaPodsStatus.recommended) {
        if (await cocoaPods.isCocoaPodsInitialized) {
          messages.add(ValidationMessage('CocoaPods version ${await cocoaPods.cocoaPodsVersionText}'));
        } else {
          status = ValidationType.partial;
          messages.add(ValidationMessage.error(
            'CocoaPods installed but not initialized.\n'
            '$noCocoaPodsConsequence\n'
            'To initialize CocoaPods, run:\n'
            '  pod setup\n'
            'once to finalize CocoaPods\' installation.'
          ));
        }
      } else {
        if (cocoaPodsStatus == CocoaPodsStatus.notInstalled) {
          status = ValidationType.missing;
          messages.add(ValidationMessage.error(
            'CocoaPods not installed.\n'
            '$noCocoaPodsConsequence\n'
            'To install:\n'
            '$cocoaPodsInstallInstructions'
          ));
        } else {
          status = ValidationType.partial;
          messages.add(ValidationMessage.hint(
            'CocoaPods out of date (${cocoaPods.cocoaPodsRecommendedVersion} is recommended).\n'
            '$noCocoaPodsConsequence\n'
            'To upgrade:\n'
            '$cocoaPodsUpgradeInstructions'
          ));
        }
      }
    } else {
      // Only set status. The main validator handles messages for missing brew.
      status = ValidationType.missing;
    }
    return ValidationResult(status, messages);
  }
}
