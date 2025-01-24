import 'dart:io';
import 'package:pubspec_parse/pubspec_parse.dart';

import 'package:version/version.dart' as v;
import 'package:pub_semver/pub_semver.dart';
import '../../../core/internationalization.dart';
import '../../../core/locales.g.dart';
import '../../../exception_handler/exceptions/cli_exception.dart';
import '../../../extensions.dart';
import '../../menu/menu.dart';
import '../logger/log_utils.dart';
import '../pub_dev/pub_dev_api.dart';
import '../shell/shell.utils.dart';
import 'yaml_to.string.dart';

// ignore: avoid_classes_with_only_static_members
class PubspecUtils {
  // static final _pubspecFile = File('pubspec.yaml');

  // static PubSpec get pubSpec => PubSpec.fromYamlString(_pubspecFile.readAsStringSync());

  static final _pubspecFile = File('pubspec.yaml');
  static final pubSpecString = _pubspecFile.readAsStringSync();
  static Pubspec get pubSpec => Pubspec.parse(pubSpecString);

  /// separtor
  static final _mapSep = _PubValue<String>(() {
    var yaml = pubSpec.dependencies;
    if (yaml.containsKey('get_cli')) {
      final mapYaml = yaml['get_cli'] as Map;
      if (mapYaml.containsKey('separator')) {
        return (mapYaml['separator'] as String?) ?? ''; // Your modified dependencies map
        // if ((yaml['get_cli'] as Map).containsKey('separator')) {
        //   return (yaml['get_cli']['separator'] as String?) ?? '';
        // }
      }
    }

    return '';
  });

  static String? get separatorFileType => _mapSep.value;

  static final _mapName = _PubValue<String>(() => pubSpec.name.trim());

  static String? get projectName => _mapName.value;

  static final _extraFolder = _PubValue<bool?>(
    () {
      try {
        var yaml = pubSpec.dependencies;
        if (yaml.containsKey('get_cli')) {
          final mapYaml = yaml['get_cli'] as Map;
          if (mapYaml.containsKey('sub_folder')) {
            return (mapYaml['sub_folder'] as bool?);
          }
        }
      } on Exception catch (_) {}
      // retorno nulo está sendo tratado
      // ignore: avoid_returning_null
      return null;
    },
  );

  static bool? get extraFolder => _extraFolder.value;

  static Future<bool> addDependencies(String package, {String? version, bool isDev = false, bool runPubGet = true}) async {
    var pubSpec = Pubspec.parse(pubSpecString);

    if (containsPackage(package)) {
      LogService.info(LocaleKeys.ask_package_already_installed.trArgs([package]), false, false);
      final menu = Menu(
        [
          LocaleKeys.options_yes.tr,
          LocaleKeys.options_no.tr,
        ],
      );
      final result = menu.choose();
      if (result.index != 0) {
        return false;
      }
    }

    version = version == null || version.isEmpty ? await PubDevApi.getLatestVersionFromPackage(package) : '^$version';
    if (version == null) return false;
    if (isDev) {
      pubSpec.devDependencies[package] = HostedDependency(version: VersionConstraint.parse(version));
    } else {
      pubSpec.dependencies[package] = HostedDependency(version: VersionConstraint.parse(version));
    }

    _savePub(pubSpec);
    if (runPubGet) await ShellUtils.pubGet();
    LogService.success(LocaleKeys.success_package_installed.trArgs([package]));
    return true;
  }

  static void removeDependencies(String package, {bool logger = true}) {
    if (logger) LogService.info('Removing package: "$package"');

    if (containsPackage(package)) {
      var dependencies = pubSpec.dependencies;
      var devDependencies = pubSpec.devDependencies;

      dependencies.removeWhere((key, value) => key == package);
      devDependencies.removeWhere((key, value) => key == package);
      var newPub = Pubspec(
        pubSpec.name,
        version: pubSpec.version,
        description: pubSpec.description,
        homepage: pubSpec.homepage,
        repository: pubSpec.repository,
        issueTracker: pubSpec.issueTracker,
        documentation: pubSpec.documentation,
        environment: pubSpec.environment,
        dependencies: dependencies, // Your modified dependencies map
        devDependencies: devDependencies, // Your modified devDependencies map
        dependencyOverrides: pubSpec.dependencyOverrides,
        flutter: pubSpec.flutter,
      );
      // var newPub = pubSpec.copy(
      //   devDependencies: devDependencies,
      //   dependencies: dependencies,
      // );
      _savePub(newPub);
      if (logger) {
        LogService.success(LocaleKeys.success_package_removed.trArgs([package]));
      }
    } else if (logger) {
      LogService.info(LocaleKeys.info_package_not_installed.trArgs([package]));
    }
  }

  static bool containsPackage(String package, [bool isDev = false]) {
    var dependencies = isDev ? pubSpec.devDependencies : pubSpec.dependencies;
    return dependencies.containsKey(package.trim());
  }

  // static bool get nullSafeSupport => !pubSpec.environment!.sdkConstraint!.allowsAny(HostedReference.fromJson('<2.12.0').versionConstraint);
  // static bool get nullSafeSupport => !pubSpec.environment!.sdkConstraint!.allowsAny(VersionConstraint.parse('<2.12.0'));
  static bool get nullSafeSupport => pubSpec.environment?['sdk']?.allowsAny(VersionConstraint.parse('<2.12.0')) ?? false;

  /// make sure it is a get_server project
  static bool get isServerProject {
    return containsPackage('get_server');
  }

  static String get getPackageImport =>
      !isServerProject ? "import 'package:refreshed/refreshed.dart';" : "import 'package:get_server/get_server.dart';";

  // static v.Version? getPackageVersion(String package) {
  //   if (containsPackage(package)) {
  //     var version = pubSpec.dependencies[package]!;
  //     try {
  //       final json = version.toJson();
  //       if (json is String) {
  //         return v.Version.parse(json);
  //       }
  //       return null;
  //     } on FormatException catch (_) {
  //       return null;
  //     } on Exception catch (_) {
  //       rethrow;
  //     }
  //   } else {
  //     throw CliException(LocaleKeys.info_package_not_installed.trArgs([package]));
  //   }
  // }

  static v.Version? getPackageVersion(String package) {
    if (containsPackage(package)) {
      var dependency = pubSpec.dependencies[package];

      if (dependency is HostedDependency) {
        try {
          // The version constraint may be a simple string, which we can parse.
          final versionConstraint = dependency.version;
          // Check if the version constraint is a simple version (not a range)
          if (versionConstraint is VersionRange &&
              versionConstraint.min != null &&
              versionConstraint.min == versionConstraint.max &&
              !versionConstraint.includeMax) {
            return v.Version.parse(versionConstraint.min.toString());
          }
        } on FormatException catch (_) {
          // Handle the case where the version string is not valid semver.
          return null;
        } on Exception catch (_) {
          // Rethrow other exceptions that might occur
          rethrow;
        }
      }

      // If the dependency is not a HostedDependency or version extraction fails, return null.
      return null;
    } else {
      throw CliException(LocaleKeys.info_package_not_installed.trArgs([package]));
    }
  }

  static void _savePub(dynamic pub) {
    var value = CliYamlToString().toYamlString(pub);
    _pubspecFile.writeAsStringSync(value);
  }
}

/// avoids multiple reads in one file
class _PubValue<T> {
  final T Function() _setValue;
  bool _isChecked = false;
  T? _value;

  /// takes the value of the file,
  /// if not already called it will call the first time
  T? get value {
    if (!_isChecked) {
      _isChecked = true;
      _value = _setValue.call();
    }
    return _value;
  }

  _PubValue(this._setValue);
}
