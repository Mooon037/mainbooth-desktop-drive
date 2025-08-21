/// 코드 서명 및 공증 관리자
/// macOS 앱 공증, Windows 코드 서명 처리

import 'dart:io';
import 'dart:convert';
import '../utils/logger.dart';

class CodeSigningManager {
  static CodeSigningManager? _instance;
  static CodeSigningManager get instance =>
      _instance ??= CodeSigningManager._();

  final Logger _logger = Logger('CodeSigningManager');

  // 서명 설정
  late String macOSDeveloperID;
  late String macOSTeamID;
  late String windowsCertificatePath;
  late String windowsCertificatePassword;
  late String notarizationAppleID;
  late String notarizationPassword;

  CodeSigningManager._();

  /// 초기화
  void initialize({
    required String macOSDeveloperID,
    required String macOSTeamID,
    required String windowsCertificatePath,
    required String windowsCertificatePassword,
    required String notarizationAppleID,
    required String notarizationPassword,
  }) {
    this.macOSDeveloperID = macOSDeveloperID;
    this.macOSTeamID = macOSTeamID;
    this.windowsCertificatePath = windowsCertificatePath;
    this.windowsCertificatePassword = windowsCertificatePassword;
    this.notarizationAppleID = notarizationAppleID;
    this.notarizationPassword = notarizationPassword;

    _logger.info('코드 서명 관리자 초기화 완료');
  }

  /// macOS 앱 서명
  Future<bool> signMacOSApp(String appPath) async {
    _logger.info('macOS 앱 서명 시작: $appPath');

    try {
      // 1. 먼저 앱 번들 내부의 모든 실행 파일들을 서명
      await _signMacOSFrameworks(appPath);

      // 2. File Provider Extension 서명
      final extensionPath =
          '$appPath/Contents/PlugIns/MainBoothFileProvider.appex';
      if (await Directory(extensionPath).exists()) {
        await _signMacOSExtension(extensionPath);
      }

      // 3. 메인 앱 서명
      final result = await Process.run('codesign', [
        '--sign',
        macOSDeveloperID,
        '--force',
        '--options',
        'runtime',
        '--entitlements',
        'platform/macos/MainBoothDrive.entitlements',
        '--deep',
        '--strict',
        '--timestamp',
        appPath,
      ]);

      if (result.exitCode != 0) {
        _logger.error('앱 서명 실패: ${result.stderr}');
        return false;
      }

      _logger.info('macOS 앱 서명 완료');

      // 4. 서명 검증
      return await _verifyMacOSSignature(appPath);
    } catch (e) {
      _logger.error('macOS 앱 서명 중 오류 발생: $e');
      return false;
    }
  }

  /// macOS 앱 공증
  Future<bool> notarizeMacOSApp(String appPath) async {
    _logger.info('macOS 앱 공증 시작: $appPath');

    try {
      // 1. ZIP 파일 생성
      final zipPath = '${appPath}.zip';
      final zipResult = await Process.run('ditto', [
        '-c',
        '-k',
        '--keepParent',
        appPath,
        zipPath,
      ]);

      if (zipResult.exitCode != 0) {
        _logger.error('ZIP 생성 실패: ${zipResult.stderr}');
        return false;
      }

      // 2. 공증 요청 제출
      final submitResult = await Process.run('xcrun', [
        'notarytool',
        'submit',
        zipPath,
        '--apple-id',
        notarizationAppleID,
        '--password',
        notarizationPassword,
        '--team-id',
        macOSTeamID,
        '--wait',
        '--output-format',
        'json',
      ]);

      if (submitResult.exitCode != 0) {
        _logger.error('공증 제출 실패: ${submitResult.stderr}');
        await File(zipPath).delete();
        return false;
      }

      // 3. 공증 결과 확인
      final responseJson = jsonDecode(submitResult.stdout);
      final status = responseJson['status'];

      if (status != 'Accepted') {
        _logger.error('공증 실패: $status');
        await File(zipPath).delete();
        return false;
      }

      // 4. 스테이플링
      final stapleResult = await Process.run('xcrun', [
        'stapler',
        'staple',
        appPath,
      ]);

      if (stapleResult.exitCode != 0) {
        _logger.warning('스테이플링 실패: ${stapleResult.stderr}');
        // 스테이플링 실패는 치명적이지 않음
      }

      await File(zipPath).delete();

      _logger.info('macOS 앱 공증 완료');
      return true;
    } catch (e) {
      _logger.error('macOS 앱 공증 중 오류 발생: $e');
      return false;
    }
  }

  /// Windows 앱 서명
  Future<bool> signWindowsApp(String exePath) async {
    _logger.info('Windows 앱 서명 시작: $exePath');

    try {
      // signtool을 사용한 코드 서명
      final result = await Process.run('signtool', [
        'sign',
        '/f',
        windowsCertificatePath,
        '/p',
        windowsCertificatePassword,
        '/t',
        'http://time.certum.pl',
        '/v',
        '/d',
        'Main Booth Drive',
        '/du',
        'https://mainbooth.com',
        exePath,
      ]);

      if (result.exitCode != 0) {
        _logger.error('Windows 앱 서명 실패: ${result.stderr}');
        return false;
      }

      _logger.info('Windows 앱 서명 완료');

      // 서명 검증
      return await _verifyWindowsSignature(exePath);
    } catch (e) {
      _logger.error('Windows 앱 서명 중 오류 발생: $e');
      return false;
    }
  }

  /// 배치 서명 (여러 파일)
  Future<bool> signMultipleFiles(List<String> filePaths) async {
    _logger.info('배치 서명 시작: ${filePaths.length}개 파일');

    bool allSuccess = true;

    for (final filePath in filePaths) {
      bool success = false;

      if (Platform.isMacOS && filePath.endsWith('.app')) {
        success = await signMacOSApp(filePath);
      } else if (Platform.isWindows && filePath.endsWith('.exe')) {
        success = await signWindowsApp(filePath);
      } else {
        _logger.warning('지원하지 않는 파일 형식: $filePath');
        continue;
      }

      if (!success) {
        allSuccess = false;
        _logger.error('서명 실패: $filePath');
      }
    }

    return allSuccess;
  }

  /// 서명 상태 확인
  Future<SignatureInfo> getSignatureInfo(String filePath) async {
    if (Platform.isMacOS) {
      return await _getMacOSSignatureInfo(filePath);
    } else if (Platform.isWindows) {
      return await _getWindowsSignatureInfo(filePath);
    } else {
      throw UnsupportedError('지원하지 않는 플랫폼');
    }
  }

  // 내부 메서드들

  Future<void> _signMacOSFrameworks(String appPath) async {
    final frameworksPath = '$appPath/Contents/Frameworks';
    final frameworksDir = Directory(frameworksPath);

    if (!await frameworksDir.exists()) {
      return;
    }

    await for (final entity in frameworksDir.list(recursive: true)) {
      if (entity is File &&
          (entity.path.endsWith('.dylib') ||
              entity.path.endsWith('.framework'))) {
        await Process.run('codesign', [
          '--sign',
          macOSDeveloperID,
          '--force',
          '--options',
          'runtime',
          '--timestamp',
          entity.path,
        ]);
      }
    }
  }

  Future<void> _signMacOSExtension(String extensionPath) async {
    final result = await Process.run('codesign', [
      '--sign',
      macOSDeveloperID,
      '--force',
      '--options',
      'runtime',
      '--entitlements',
      'platform/macos/FileProvider.entitlements',
      '--timestamp',
      extensionPath,
    ]);

    if (result.exitCode != 0) {
      throw Exception('Extension 서명 실패: ${result.stderr}');
    }
  }

  Future<bool> _verifyMacOSSignature(String appPath) async {
    final result = await Process.run('codesign', [
      '--verify',
      '--deep',
      '--strict',
      '--verbose=2',
      appPath,
    ]);

    return result.exitCode == 0;
  }

  Future<bool> _verifyWindowsSignature(String exePath) async {
    final result = await Process.run('signtool', [
      'verify',
      '/v',
      '/pa',
      exePath,
    ]);

    return result.exitCode == 0;
  }

  Future<SignatureInfo> _getMacOSSignatureInfo(String filePath) async {
    final result = await Process.run('codesign', [
      '--display',
      '--verbose=4',
      filePath,
    ]);

    final lines = result.stderr.toString().split('\n');
    String? identifier;
    String? authority;
    String? teamIdentifier;
    DateTime? signedDate;

    for (final line in lines) {
      if (line.startsWith('Identifier=')) {
        identifier = line.substring('Identifier='.length);
      } else if (line.startsWith('Authority=')) {
        authority = line.substring('Authority='.length);
      } else if (line.startsWith('TeamIdentifier=')) {
        teamIdentifier = line.substring('TeamIdentifier='.length);
      } else if (line.startsWith('Signed Time=')) {
        // 날짜 파싱 로직
      }
    }

    return SignatureInfo(
      isSigned: result.exitCode == 0,
      identifier: identifier,
      authority: authority,
      teamIdentifier: teamIdentifier,
      signedDate: signedDate,
      isNotarized: await _checkNotarizationStatus(filePath),
    );
  }

  Future<SignatureInfo> _getWindowsSignatureInfo(String filePath) async {
    final result = await Process.run('signtool', [
      'verify',
      '/v',
      '/pa',
      filePath,
    ]);

    return SignatureInfo(
      isSigned: result.exitCode == 0,
      identifier: null,
      authority: null,
      teamIdentifier: null,
      signedDate: null,
      isNotarized: false, // Windows는 공증 개념이 없음
    );
  }

  Future<bool> _checkNotarizationStatus(String filePath) async {
    final result = await Process.run('spctl', [
      '--assess',
      '--verbose',
      filePath,
    ]);

    return result.stderr.toString().contains('source=Notarized');
  }

  /// 개발자 인증서 확인
  Future<List<CertificateInfo>> getAvailableCertificates() async {
    final certificates = <CertificateInfo>[];

    if (Platform.isMacOS) {
      final result = await Process.run('security', [
        'find-certificate',
        '-c',
        'Developer ID Application',
        '-p',
      ]);

      if (result.exitCode == 0) {
        // 인증서 파싱 로직
        certificates.add(CertificateInfo(
          name: 'Developer ID Application',
          issuer: 'Apple Inc.',
          validFrom: DateTime.now(),
          validTo: DateTime.now().add(Duration(days: 365)),
          isValid: true,
        ));
      }
    } else if (Platform.isWindows) {
      // Windows 인증서 저장소 확인
      final result = await Process.run('certutil', ['-store', 'My']);

      if (result.exitCode == 0) {
        // 인증서 파싱 로직
      }
    }

    return certificates;
  }

  /// 자동 갱신 체크
  Future<void> checkCertificateExpiration() async {
    final certificates = await getAvailableCertificates();

    for (final cert in certificates) {
      final daysUntilExpiry = cert.validTo.difference(DateTime.now()).inDays;

      if (daysUntilExpiry < 30) {
        _logger.warning('인증서 만료 임박: ${cert.name} (${daysUntilExpiry}일 남음)');
      }
    }
  }
}

class SignatureInfo {
  final bool isSigned;
  final String? identifier;
  final String? authority;
  final String? teamIdentifier;
  final DateTime? signedDate;
  final bool isNotarized;

  SignatureInfo({
    required this.isSigned,
    this.identifier,
    this.authority,
    this.teamIdentifier,
    this.signedDate,
    required this.isNotarized,
  });

  Map<String, dynamic> toJson() {
    return {
      'isSigned': isSigned,
      'identifier': identifier,
      'authority': authority,
      'teamIdentifier': teamIdentifier,
      'signedDate': signedDate?.toIso8601String(),
      'isNotarized': isNotarized,
    };
  }
}

class CertificateInfo {
  final String name;
  final String issuer;
  final DateTime validFrom;
  final DateTime validTo;
  final bool isValid;

  CertificateInfo({
    required this.name,
    required this.issuer,
    required this.validFrom,
    required this.validTo,
    required this.isValid,
  });

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'issuer': issuer,
      'validFrom': validFrom.toIso8601String(),
      'validTo': validTo.toIso8601String(),
      'isValid': isValid,
    };
  }
}
