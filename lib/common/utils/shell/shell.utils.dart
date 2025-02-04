import 'dart:io';

import 'package:process_run/shell_run.dart';

import '../../../core/generator.dart';
import '../../../core/internationalization.dart';
import '../../../core/locales.g.dart';
import '../logger/log_utils.dart';
import '../pub_dev/pub_dev_api.dart';
import '../pubspec/pubspec_lock.dart';

class ShellUtils {
  static Future<void> pubGet() async {
    LogService.info('Running `flutter pub get` …');
    await run('flutter pub get', verbose: true);
  }

  static Future<void> flutterCreate(
    String path,
    String? org,
    String iosLang,
    String androidLang,
  ) async {
    LogService.info('Running `flutter create $path` …');

    await run(
        'flutter create --no-pub -i $iosLang -a $androidLang --org $org'
        ' "$path"',
        verbose: true);
  }

  static Future<void> update([bool isGit = false, bool forceUpdate = false]) async {
    isGit = RefreshedCli.arguments.contains('--git');
    forceUpdate = RefreshedCli.arguments.contains('-f');
    if (!isGit && !forceUpdate) {
      var versionInPubDev = await PubDevApi.getLatestVersionFromPackage('refreshed_cli');

      var versionInstalled = await PubspecLock.getVersionCli(disableLog: true);

      if (versionInstalled == versionInPubDev) {
        return LogService.info(Translation(LocaleKeys.info_cli_last_version_already_installed.tr).toString());
      }
    }

    LogService.info('Upgrading refreshed_cli …');

    try {
      if (Platform.script.path.contains('flutter')) {
        if (isGit) {
          await run('flutter pub global activate -sgit https://github.com/jonataslaw/refreshed_cli/', verbose: true);
        } else {
          await run('flutter pub global activate refreshed_cli', verbose: true);
        }
      } else {
        if (isGit) {
          await run('flutter pub global activate -sgit https://github.com/jonataslaw/refreshed_cli/', verbose: true);
        } else {
          await run('flutter pub global activate refreshed_cli', verbose: true);
        }
      }
      return LogService.success(LocaleKeys.success_update_cli.tr);
    } on Exception catch (err) {
      LogService.info(err.toString());
      return LogService.error(LocaleKeys.error_update_cli.tr);
    }
  }
}
