/// 배포 관리자
/// 코드 서명, 설치 프로그램 생성, 자동 업데이트를 통합 관리

import 'dart:io';
import 'dart:convert';
import 'code_signing.dart';
import 'installer_builder.dart';
import 'auto_updater.dart';
import '../utils/logger.dart';

class DeploymentManager {
  static DeploymentManager? _instance;
  static DeploymentManager get instance => _instance ??= DeploymentManager._();

  final Logger _logger = Logger('DeploymentManager');
  final CodeSigningManager _codeSigningManager = CodeSigningManager.instance;
  final InstallerBuilder _installerBuilder = InstallerBuilder.instance;
  final AutoUpdater _autoUpdater = AutoUpdater.instance;

  DeploymentManager._();

  /// 배포 관리자 초기화
  void initialize(DeploymentConfig config) {
    _logger.info('배포 관리자 초기화');

    // 코드 서명 설정
    _codeSigningManager.initialize(
      macOSDeveloperID: config.macOSDeveloperID,
      macOSTeamID: config.macOSTeamID,
      windowsCertificatePath: config.windowsCertificatePath,
      windowsCertificatePassword: config.windowsCertificatePassword,
      notarizationAppleID: config.notarizationAppleID,
      notarizationPassword: config.notarizationPassword,
    );

    // 자동 업데이터 설정
    _autoUpdater.initialize(
      updateServerUrl: config.updateServerUrl,
      currentVersion: config.currentVersion,
      checkInterval: config.updateCheckInterval,
      autoDownload: config.autoDownload,
      autoInstall: config.autoInstall,
    );

    _logger.info('배포 관리자 초기화 완료');
  }

  /// 전체 배포 프로세스 실행
  Future<bool> performFullDeployment({
    required String appPath,
    required String outputDirectory,
    required DeploymentConfig config,
    bool skipSigning = false,
    bool skipInstaller = false,
    Function(String)? onProgress,
  }) async {
    _logger.info('전체 배포 프로세스 시작');

    try {
      onProgress?.call('배포 프로세스 시작');

      // 1. 코드 서명
      if (!skipSigning) {
        onProgress?.call('코드 서명 중...');
        final signSuccess = await _performCodeSigning(appPath);
        if (!signSuccess) {
          _logger.error('코드 서명 실패');
          return false;
        }
      }

      // 2. 설치 프로그램 생성
      if (!skipInstaller) {
        onProgress?.call('설치 프로그램 생성 중...');
        final installerSuccess =
            await _createInstaller(appPath, outputDirectory, config);
        if (!installerSuccess) {
          _logger.error('설치 프로그램 생성 실패');
          return false;
        }
      }

      // 3. 배포 검증
      onProgress?.call('배포 검증 중...');
      final verifySuccess = await _verifyDeployment(outputDirectory);
      if (!verifySuccess) {
        _logger.error('배포 검증 실패');
        return false;
      }

      // 4. 메타데이터 생성
      onProgress?.call('메타데이터 생성 중...');
      await _generateMetadata(outputDirectory, config);

      onProgress?.call('배포 완료');
      _logger.info('전체 배포 프로세스 완료');
      return true;
    } catch (e) {
      _logger.error('배포 프로세스 실패: $e');
      onProgress?.call('배포 실패: $e');
      return false;
    }
  }

  /// 업데이트 패키지 생성
  Future<bool> createUpdatePackage({
    required String appPath,
    required String outputPath,
    required String fromVersion,
    required String toVersion,
    DeploymentConfig? config,
  }) async {
    _logger.info('업데이트 패키지 생성: $fromVersion -> $toVersion');

    try {
      // 델타 패키지 생성 (변경된 파일만)
      final deltaFiles =
          await _createDeltaPackage(appPath, fromVersion, toVersion);

      // 업데이트 스크립트 생성
      final updateScript = _generateUpdateScript(deltaFiles, toVersion);

      // 패키지 압축
      await _compressUpdatePackage(deltaFiles, updateScript, outputPath);

      _logger.info('업데이트 패키지 생성 완료: $outputPath');
      return true;
    } catch (e) {
      _logger.error('업데이트 패키지 생성 실패: $e');
      return false;
    }
  }

  /// 배포 상태 모니터링
  Future<DeploymentStatus> getDeploymentStatus() async {
    final status = DeploymentStatus();

    // 코드 서명 상태
    try {
      final certificates = await _codeSigningManager.getAvailableCertificates();
      status.codeSigningAvailable = certificates.isNotEmpty;
      status.certificateInfo =
          certificates.isNotEmpty ? certificates.first : null;
    } catch (e) {
      status.codeSigningError = e.toString();
    }

    // 업데이터 상태
    status.updaterStatus = _autoUpdater.getStatus();

    // 시스템 정보
    status.platform = Platform.operatingSystem;
    status.architecture = Platform.version;

    return status;
  }

  /// 롤백 실행
  Future<bool> performRollback({
    required String backupPath,
    required String targetPath,
    Function(String)? onProgress,
  }) async {
    _logger.info('롤백 시작: $targetPath <- $backupPath');

    try {
      onProgress?.call('백업 검증 중...');

      // 백업 파일 검증
      if (!await Directory(backupPath).exists() &&
          !await File(backupPath).exists()) {
        throw Exception('백업 파일을 찾을 수 없음: $backupPath');
      }

      onProgress?.call('현재 버전 백업 중...');

      // 현재 버전을 임시로 백업
      final tempBackup = '${targetPath}.rollback_temp';
      if (await Directory(targetPath).exists()) {
        await Directory(targetPath).rename(tempBackup);
      } else if (await File(targetPath).exists()) {
        await File(targetPath).rename(tempBackup);
      }

      onProgress?.call('이전 버전 복원 중...');

      // 이전 버전 복원
      if (await Directory(backupPath).exists()) {
        await _copyDirectory(backupPath, targetPath);
      } else {
        await File(backupPath).copy(targetPath);
      }

      onProgress?.call('권한 설정 중...');

      // 권한 복원
      if (Platform.isMacOS) {
        await Process.run('chmod', ['+x', '$targetPath/Contents/MacOS/*']);
      } else if (Platform.isWindows) {
        // Windows 권한 설정 필요시
      }

      // 임시 백업 삭제
      if (await Directory(tempBackup).exists()) {
        await Directory(tempBackup).delete(recursive: true);
      } else if (await File(tempBackup).exists()) {
        await File(tempBackup).delete();
      }

      onProgress?.call('롤백 완료');
      _logger.info('롤백 완료');
      return true;
    } catch (e) {
      _logger.error('롤백 실패: $e');
      onProgress?.call('롤백 실패: $e');
      return false;
    }
  }

  /// 배포 환경 설정 검증
  Future<List<String>> validateDeploymentEnvironment() async {
    final issues = <String>[];

    _logger.info('배포 환경 검증 시작');

    // Flutter 설치 확인
    try {
      final result = await Process.run('flutter', ['--version']);
      if (result.exitCode != 0) {
        issues.add('Flutter가 제대로 설치되지 않았습니다');
      }
    } catch (e) {
      issues.add('Flutter를 찾을 수 없습니다');
    }

    // 플랫폼별 도구 확인
    if (Platform.isMacOS) {
      // Xcode 확인
      try {
        final result = await Process.run('xcodebuild', ['-version']);
        if (result.exitCode != 0) {
          issues.add('Xcode가 제대로 설치되지 않았습니다');
        }
      } catch (e) {
        issues.add('Xcode를 찾을 수 없습니다');
      }

      // 코드 서명 도구 확인
      try {
        await Process.run('codesign', ['--version']);
      } catch (e) {
        issues.add('codesign 도구를 찾을 수 없습니다');
      }
    } else if (Platform.isWindows) {
      // Visual Studio Build Tools 확인
      final msbuildPaths = [
        r'C:\Program Files (x86)\Microsoft Visual Studio\2019\BuildTools\MSBuild\Current\Bin\MSBuild.exe',
        r'C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\MSBuild\Current\Bin\MSBuild.exe',
        r'C:\Program Files\Microsoft Visual Studio\2022\Community\MSBuild\Current\Bin\MSBuild.exe',
      ];

      bool msbuildFound = false;
      for (final path in msbuildPaths) {
        if (await File(path).exists()) {
          msbuildFound = true;
          break;
        }
      }

      if (!msbuildFound) {
        issues.add('Visual Studio Build Tools를 찾을 수 없습니다');
      }
    }

    // 인증서 확인
    final certificates = await _codeSigningManager.getAvailableCertificates();
    if (certificates.isEmpty) {
      issues.add('코드 서명 인증서를 찾을 수 없습니다');
    } else {
      for (final cert in certificates) {
        final daysUntilExpiry = cert.validTo.difference(DateTime.now()).inDays;
        if (daysUntilExpiry < 30) {
          issues.add('인증서 "${cert.name}"이 ${daysUntilExpiry}일 후 만료됩니다');
        }
      }
    }

    _logger.info('배포 환경 검증 완료: ${issues.length}개 이슈 발견');
    return issues;
  }

  // 내부 메서드들

  Future<bool> _performCodeSigning(String appPath) async {
    if (Platform.isMacOS) {
      final signSuccess = await _codeSigningManager.signMacOSApp(appPath);
      if (signSuccess) {
        return await _codeSigningManager.notarizeMacOSApp(appPath);
      }
      return false;
    } else if (Platform.isWindows) {
      return await _codeSigningManager.signWindowsApp(appPath);
    }
    return true;
  }

  Future<bool> _createInstaller(
      String appPath, String outputDirectory, DeploymentConfig config) async {
    final installerConfig = InstallerConfig(
      productName: config.productName,
      version: config.currentVersion,
      manufacturer: config.manufacturer,
      backgroundImagePath: config.backgroundImagePath,
      windowsConfig: config.windowsInstallerConfig,
      useNSIS: config.useNSIS,
    );

    final outputPath = Platform.isMacOS
        ? '$outputDirectory/${config.productName}-v${config.currentVersion}.dmg'
        : '$outputDirectory/${config.productName}-v${config.currentVersion}.exe';

    return await _installerBuilder.createInstaller(
      appPath: appPath,
      outputPath: outputPath,
      config: installerConfig,
    );
  }

  Future<bool> _verifyDeployment(String outputDirectory) async {
    final dir = Directory(outputDirectory);
    if (!await dir.exists()) {
      return false;
    }

    // 설치 프로그램 파일 확인
    final files = await dir.list().toList();
    final installerFiles = files
        .where((file) =>
            file.path.endsWith('.dmg') ||
            file.path.endsWith('.exe') ||
            file.path.endsWith('.msi'))
        .toList();

    if (installerFiles.isEmpty) {
      _logger.error('설치 프로그램 파일을 찾을 수 없음');
      return false;
    }

    // 각 설치 프로그램 검증
    for (final file in installerFiles) {
      final verified = await _installerBuilder.verifyInstaller(file.path);
      if (!verified) {
        _logger.error('설치 프로그램 검증 실패: ${file.path}');
        return false;
      }
    }

    return true;
  }

  Future<void> _generateMetadata(
      String outputDirectory, DeploymentConfig config) async {
    final metadata = {
      'version': config.currentVersion,
      'buildDate': DateTime.now().toIso8601String(),
      'platform': Platform.operatingSystem,
      'architecture': Platform.version,
      'productName': config.productName,
      'manufacturer': config.manufacturer,
    };

    final metadataFile = File('$outputDirectory/metadata.json');
    await metadataFile
        .writeAsString(JsonEncoder.withIndent('  ').convert(metadata));
  }

  Future<List<String>> _createDeltaPackage(
      String appPath, String fromVersion, String toVersion) async {
    // 실제 구현에서는 파일 변경 사항을 분석하여 델타 패키지 생성
    return [appPath]; // 임시
  }

  String _generateUpdateScript(List<String> deltaFiles, String toVersion) {
    // 업데이트 스크립트 생성
    return '''
    #!/bin/bash
    # Auto-generated update script for version $toVersion
    echo "Applying update to version $toVersion..."
    # Update logic here
    ''';
  }

  Future<void> _compressUpdatePackage(
      List<String> files, String script, String outputPath) async {
    // 업데이트 패키지 압축
  }

  Future<void> _copyDirectory(String sourcePath, String targetPath) async {
    final result = await Process.run('cp', ['-R', sourcePath, targetPath]);
    if (result.exitCode != 0) {
      throw Exception('디렉토리 복사 실패: ${result.stderr}');
    }
  }
}

class DeploymentConfig {
  final String productName;
  final String currentVersion;
  final String manufacturer;

  // 코드 서명 설정
  final String macOSDeveloperID;
  final String macOSTeamID;
  final String windowsCertificatePath;
  final String windowsCertificatePassword;
  final String notarizationAppleID;
  final String notarizationPassword;

  // 업데이트 설정
  final String updateServerUrl;
  final Duration updateCheckInterval;
  final bool autoDownload;
  final bool autoInstall;

  // 설치 프로그램 설정
  final String? backgroundImagePath;
  final WindowsInstallerConfig? windowsInstallerConfig;
  final bool useNSIS;

  DeploymentConfig({
    required this.productName,
    required this.currentVersion,
    required this.manufacturer,
    required this.macOSDeveloperID,
    required this.macOSTeamID,
    required this.windowsCertificatePath,
    required this.windowsCertificatePassword,
    required this.notarizationAppleID,
    required this.notarizationPassword,
    required this.updateServerUrl,
    this.updateCheckInterval = const Duration(hours: 24),
    this.autoDownload = true,
    this.autoInstall = false,
    this.backgroundImagePath,
    this.windowsInstallerConfig,
    this.useNSIS = false,
  });
}

class DeploymentStatus {
  bool codeSigningAvailable = false;
  CertificateInfo? certificateInfo;
  String? codeSigningError;
  UpdaterStatus? updaterStatus;
  String platform = '';
  String architecture = '';

  Map<String, dynamic> toJson() {
    return {
      'codeSigningAvailable': codeSigningAvailable,
      'certificateInfo': certificateInfo?.toJson(),
      'codeSigningError': codeSigningError,
      'updaterStatus': updaterStatus?.toJson(),
      'platform': platform,
      'architecture': architecture,
    };
  }
}
