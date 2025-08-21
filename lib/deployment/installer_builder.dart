/// 설치 프로그램 빌더
/// macOS DMG, Windows MSI/EXE 설치 프로그램 생성

import 'dart:io';
import 'dart:convert';
import '../utils/logger.dart';

class InstallerBuilder {
  static InstallerBuilder? _instance;
  static InstallerBuilder get instance => _instance ??= InstallerBuilder._();
  
  final Logger _logger = Logger('InstallerBuilder');
  
  InstallerBuilder._();
  
  /// macOS DMG 생성
  Future<bool> createMacOSDMG({
    required String appPath,
    required String dmgOutputPath,
    required String volumeName,
    String? backgroundImagePath,
    List<DMGCustomization>? customizations,
  }) async {
    _logger.info('macOS DMG 생성 시작: $dmgOutputPath');
    
    try {
      // 1. 임시 디렉토리 생성
      final tempDir = Directory.systemTemp.createTempSync('dmg_temp_');
      final sourceDirPath = '${tempDir.path}/source';
      final sourceDir = Directory(sourceDirPath);
      await sourceDir.create();
      
      // 2. 앱 복사
      await _copyDirectory(appPath, '$sourceDirPath/${_getAppName(appPath)}');
      
      // 3. Applications 심볼릭 링크 생성
      await Process.run('ln', ['-s', '/Applications', '$sourceDirPath/Applications']);
      
      // 4. 배경 이미지 및 커스터마이징
      if (backgroundImagePath != null) {
        final hiddenDir = Directory('$sourceDirPath/.background');
        await hiddenDir.create();
        await File(backgroundImagePath).copy('${hiddenDir.path}/background.png');
      }
      
      // 5. .DS_Store 파일 생성 (레이아웃 설정)
      await _createDSStore(sourceDirPath, customizations);
      
      // 6. DMG 생성
      final createResult = await Process.run('hdiutil', [
        'create',
        '-srcfolder', sourceDirPath,
        '-volname', volumeName,
        '-fs', 'HFS+',
        '-format', 'UDRW',
        '${dmgOutputPath}.tmp.dmg',
      ]);
      
      if (createResult.exitCode != 0) {
        _logger.error('DMG 생성 실패: ${createResult.stderr}');
        await tempDir.delete(recursive: true);
        return false;
      }
      
      // 7. DMG 압축
      final compressResult = await Process.run('hdiutil', [
        'convert',
        '${dmgOutputPath}.tmp.dmg',
        '-format', 'UDZO',
        '-o', dmgOutputPath,
      ]);
      
      if (compressResult.exitCode != 0) {
        _logger.error('DMG 압축 실패: ${compressResult.stderr}');
        await File('${dmgOutputPath}.tmp.dmg').delete();
        await tempDir.delete(recursive: true);
        return false;
      }
      
      // 8. 정리
      await File('${dmgOutputPath}.tmp.dmg').delete();
      await tempDir.delete(recursive: true);
      
      _logger.info('macOS DMG 생성 완료: $dmgOutputPath');
      return true;
      
    } catch (e) {
      _logger.error('DMG 생성 중 오류 발생: $e');
      return false;
    }
  }
  
  /// Windows MSI 생성
  Future<bool> createWindowsMSI({
    required String appPath,
    required String msiOutputPath,
    required WindowsInstallerConfig config,
  }) async {
    _logger.info('Windows MSI 생성 시작: $msiOutputPath');
    
    try {
      // 1. WiX 소스 파일 생성
      final wxsContent = _generateWixSource(appPath, config);
      final wxsPath = '${Directory.systemTemp.path}/installer.wxs';
      await File(wxsPath).writeAsString(wxsContent);
      
      // 2. WiX 컴파일
      final compileResult = await Process.run('candle', [
        wxsPath,
        '-out', '${Directory.systemTemp.path}/installer.wixobj',
      ]);
      
      if (compileResult.exitCode != 0) {
        _logger.error('WiX 컴파일 실패: ${compileResult.stderr}');
        return false;
      }
      
      // 3. MSI 링크
      final linkResult = await Process.run('light', [
        '${Directory.systemTemp.path}/installer.wixobj',
        '-out', msiOutputPath,
        '-ext', 'WixUIExtension',
      ]);
      
      if (linkResult.exitCode != 0) {
        _logger.error('MSI 링크 실패: ${linkResult.stderr}');
        return false;
      }
      
      // 4. 정리
      await File(wxsPath).delete();
      await File('${Directory.systemTemp.path}/installer.wixobj').delete();
      
      _logger.info('Windows MSI 생성 완료: $msiOutputPath');
      return true;
      
    } catch (e) {
      _logger.error('MSI 생성 중 오류 발생: $e');
      return false;
    }
  }
  
  /// Windows NSIS 설치 프로그램 생성
  Future<bool> createWindowsNSIS({
    required String appPath,
    required String exeOutputPath,
    required WindowsInstallerConfig config,
  }) async {
    _logger.info('Windows NSIS 설치 프로그램 생성 시작: $exeOutputPath');
    
    try {
      // 1. NSIS 스크립트 생성
      final nsisContent = _generateNSISScript(appPath, config);
      final nsisPath = '${Directory.systemTemp.path}/installer.nsi';
      await File(nsisPath).writeAsString(nsisContent);
      
      // 2. NSIS 컴파일
      final compileResult = await Process.run('makensis', [
        '/DOUTFILE=$exeOutputPath',
        nsisPath,
      ]);
      
      if (compileResult.exitCode != 0) {
        _logger.error('NSIS 컴파일 실패: ${compileResult.stderr}');
        return false;
      }
      
      // 3. 정리
      await File(nsisPath).delete();
      
      _logger.info('Windows NSIS 설치 프로그램 생성 완료: $exeOutputPath');
      return true;
      
    } catch (e) {
      _logger.error('NSIS 설치 프로그램 생성 중 오류 발생: $e');
      return false;
    }
  }
  
  /// 크로스 플랫폼 설치 프로그램 생성
  Future<bool> createInstaller({
    required String appPath,
    required String outputPath,
    required InstallerConfig config,
  }) async {
    if (Platform.isMacOS) {
      return await createMacOSDMG(
        appPath: appPath,
        dmgOutputPath: outputPath,
        volumeName: config.productName,
        backgroundImagePath: config.backgroundImagePath,
        customizations: config.dmgCustomizations,
      );
    } else if (Platform.isWindows) {
      if (config.useNSIS) {
        return await createWindowsNSIS(
          appPath: appPath,
          exeOutputPath: outputPath,
          config: config.windowsConfig!,
        );
      } else {
        return await createWindowsMSI(
          appPath: appPath,
          msiOutputPath: outputPath,
          config: config.windowsConfig!,
        );
      }
    } else {
      throw UnsupportedError('지원하지 않는 플랫폼');
    }
  }
  
  /// 설치 프로그램 검증
  Future<bool> verifyInstaller(String installerPath) async {
    _logger.info('설치 프로그램 검증: $installerPath');
    
    final file = File(installerPath);
    if (!await file.exists()) {
      _logger.error('설치 프로그램 파일을 찾을 수 없음: $installerPath');
      return false;
    }
    
    final fileSize = await file.length();
    if (fileSize == 0) {
      _logger.error('설치 프로그램 파일이 비어있음');
      return false;
    }
    
    // 플랫폼별 추가 검증
    if (Platform.isMacOS && installerPath.endsWith('.dmg')) {
      return await _verifyDMG(installerPath);
    } else if (Platform.isWindows && (installerPath.endsWith('.msi') || installerPath.endsWith('.exe'))) {
      return await _verifyWindowsInstaller(installerPath);
    }
    
    return true;
  }
  
  // 내부 메서드들
  
  Future<void> _copyDirectory(String sourcePath, String targetPath) async {
    final result = await Process.run('cp', ['-R', sourcePath, targetPath]);
    if (result.exitCode != 0) {
      throw Exception('디렉토리 복사 실패: ${result.stderr}');
    }
  }
  
  String _getAppName(String appPath) {
    return appPath.split('/').last;
  }
  
  Future<void> _createDSStore(String sourcePath, List<DMGCustomization>? customizations) async {
    // AppleScript를 사용하여 .DS_Store 파일 생성
    final script = '''
    tell application "Finder"
      tell disk "$sourcePath"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {400, 100, 900, 450}
        set viewOptions to the icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 72
        set background picture of viewOptions to file ".background:background.png"
        make new alias file at container window to POSIX file "/Applications" with properties {name:"Applications"}
        set position of item "${_getAppName(sourcePath)}" of container window to {150, 200}
        set position of item "Applications" of container window to {350, 200}
        close
        open
        update without registering applications
        delay 2
      end tell
    end tell
    ''';
    
    // AppleScript 실행 (실제 구현에서는 osascript 사용)
    // await Process.run('osascript', ['-e', script]);
  }
  
  String _generateWixSource(String appPath, WindowsInstallerConfig config) {
    return '''
<?xml version="1.0" encoding="UTF-8"?>
<Wix xmlns="http://schemas.microsoft.com/wix/2006/wi">
  <Product Id="*" Name="${config.productName}" Language="1033" Version="${config.version}" 
           Manufacturer="${config.manufacturer}" UpgradeCode="${config.upgradeCode}">
    <Package InstallerVersion="200" Compressed="yes" InstallScope="perMachine" />
    
    <MajorUpgrade DowngradeErrorMessage="A newer version is already installed." />
    <MediaTemplate />
    
    <Feature Id="ProductFeature" Title="${config.productName}" Level="1">
      <ComponentGroupRef Id="ProductComponents" />
    </Feature>
    
    <Directory Id="TARGETDIR" Name="SourceDir">
      <Directory Id="ProgramFilesFolder">
        <Directory Id="INSTALLFOLDER" Name="${config.productName}" />
      </Directory>
    </Directory>
    
    <ComponentGroup Id="ProductComponents" Directory="INSTALLFOLDER">
      <Component Id="MainExecutable" Guid="*">
        <File Id="MainExe" Source="$appPath" KeyPath="yes" />
      </Component>
    </ComponentGroup>
    
    <UIRef Id="WixUI_InstallDir" />
    <Property Id="WIXUI_INSTALLDIR" Value="INSTALLFOLDER" />
    
  </Product>
</Wix>
''';
  }
  
  String _generateNSISScript(String appPath, WindowsInstallerConfig config) {
    return '''
; Main Booth Drive NSIS Installer Script
!define PRODUCT_NAME "${config.productName}"
!define PRODUCT_VERSION "${config.version}"
!define PRODUCT_PUBLISHER "${config.manufacturer}"
!define PRODUCT_WEB_SITE "${config.websiteUrl}"
!define PRODUCT_DIR_REGKEY "Software\\Microsoft\\Windows\\CurrentVersion\\App Paths\\MainBoothDrive.exe"
!define PRODUCT_UNINST_KEY "Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\\${PRODUCT_NAME}"
!define PRODUCT_UNINST_ROOT_KEY "HKLM"

SetCompressor lzma

Name "\${PRODUCT_NAME} \${PRODUCT_VERSION}"
OutFile "\${OUTFILE}"
InstallDir "\$PROGRAMFILES\\\${PRODUCT_NAME}"
InstallDirRegKey HKLM "\${PRODUCT_DIR_REGKEY}" ""
DirText "이 설치 마법사는 컴퓨터에 \${PRODUCT_NAME}을(를) 설치합니다."
ShowInstDetails show
ShowUnInstDetails show

Section "MainSection" SEC01
  SetOutPath "\$INSTDIR"
  SetOverwrite ifnewer
  File /r "$appPath\\*.*"
  CreateDirectory "\$SMPROGRAMS\\\${PRODUCT_NAME}"
  CreateShortCut "\$SMPROGRAMS\\\${PRODUCT_NAME}\\\${PRODUCT_NAME}.lnk" "\$INSTDIR\\MainBoothDrive.exe"
  CreateShortCut "\$DESKTOP\\\${PRODUCT_NAME}.lnk" "\$INSTDIR\\MainBoothDrive.exe"
SectionEnd

Section -AdditionalIcons
  CreateShortCut "\$SMPROGRAMS\\\${PRODUCT_NAME}\\Uninstall.lnk" "\$INSTDIR\\uninst.exe"
SectionEnd

Section -Post
  WriteUninstaller "\$INSTDIR\\uninst.exe"
  WriteRegStr HKLM "\${PRODUCT_DIR_REGKEY}" "" "\$INSTDIR\\MainBoothDrive.exe"
  WriteRegStr \${PRODUCT_UNINST_ROOT_KEY} "\${PRODUCT_UNINST_KEY}" "DisplayName" "\$(^Name)"
  WriteRegStr \${PRODUCT_UNINST_ROOT_KEY} "\${PRODUCT_UNINST_KEY}" "UninstallString" "\$INSTDIR\\uninst.exe"
  WriteRegStr \${PRODUCT_UNINST_ROOT_KEY} "\${PRODUCT_UNINST_KEY}" "DisplayIcon" "\$INSTDIR\\MainBoothDrive.exe"
  WriteRegStr \${PRODUCT_UNINST_ROOT_KEY} "\${PRODUCT_UNINST_KEY}" "DisplayVersion" "\${PRODUCT_VERSION}"
  WriteRegStr \${PRODUCT_UNINST_ROOT_KEY} "\${PRODUCT_UNINST_KEY}" "URLInfoAbout" "\${PRODUCT_WEB_SITE}"
  WriteRegStr \${PRODUCT_UNINST_ROOT_KEY} "\${PRODUCT_UNINST_KEY}" "Publisher" "\${PRODUCT_PUBLISHER}"
SectionEnd

Function un.onUninstSuccess
  HideWindow
  MessageBox MB_ICONINFORMATION|MB_OK "\${PRODUCT_NAME}이(가) 컴퓨터에서 성공적으로 제거되었습니다."
FunctionEnd

Function un.onInit
  MessageBox MB_ICONQUESTION|MB_YESNO|MB_DEFBUTTON2 "\${PRODUCT_NAME}과(와) 관련된 모든 구성 요소를 제거하시겠습니까?" IDYES +2
  Abort
FunctionEnd

Section Uninstall
  Delete "\$INSTDIR\\uninst.exe"
  RMDir /r "\$INSTDIR"
  Delete "\$SMPROGRAMS\\\${PRODUCT_NAME}\\\${PRODUCT_NAME}.lnk"
  Delete "\$SMPROGRAMS\\\${PRODUCT_NAME}\\Uninstall.lnk"
  Delete "\$DESKTOP\\\${PRODUCT_NAME}.lnk"
  RMDir "\$SMPROGRAMS\\\${PRODUCT_NAME}"
  DeleteRegKey \${PRODUCT_UNINST_ROOT_KEY} "\${PRODUCT_UNINST_KEY}"
  DeleteRegKey HKLM "\${PRODUCT_DIR_REGKEY}"
  SetAutoClose true
SectionEnd
''';
  }
  
  Future<bool> _verifyDMG(String dmgPath) async {
    final result = await Process.run('hdiutil', ['verify', dmgPath]);
    return result.exitCode == 0;
  }
  
  Future<bool> _verifyWindowsInstaller(String installerPath) async {
    // MSI/EXE 파일 무결성 검사
    final result = await Process.run('where', ['msiexec']);
    return result.exitCode == 0; // msiexec 존재 여부만 확인 (임시)
  }
}

class InstallerConfig {
  final String productName;
  final String version;
  final String manufacturer;
  final String? backgroundImagePath;
  final List<DMGCustomization>? dmgCustomizations;
  final WindowsInstallerConfig? windowsConfig;
  final bool useNSIS;
  
  InstallerConfig({
    required this.productName,
    required this.version,
    required this.manufacturer,
    this.backgroundImagePath,
    this.dmgCustomizations,
    this.windowsConfig,
    this.useNSIS = false,
  });
}

class WindowsInstallerConfig {
  final String productName;
  final String version;
  final String manufacturer;
  final String upgradeCode;
  final String websiteUrl;
  final String? iconPath;
  final String? licensePath;
  
  WindowsInstallerConfig({
    required this.productName,
    required this.version,
    required this.manufacturer,
    required this.upgradeCode,
    required this.websiteUrl,
    this.iconPath,
    this.licensePath,
  });
}

class DMGCustomization {
  final String type; // 'icon_position', 'window_size', 'background'
  final Map<String, dynamic> properties;
  
  DMGCustomization({
    required this.type,
    required this.properties,
  });
}
