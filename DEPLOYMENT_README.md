# Main Booth Drive - 배포 가이드

이 문서는 Main Booth Drive 데스크탑 애플리케이션의 네이티브 Extension 개발, 최적화, 배포 준비에 대한 완전한 가이드입니다.

## 📋 목차

1. [네이티브 Extension 개발](#네이티브-extension-개발)
2. [성능 최적화](#성능-최적화)
3. [배포 준비](#배포-준비)
4. [빌드 및 배포 프로세스](#빌드-및-배포-프로세스)
5. [문제 해결](#문제-해결)

## 🔧 네이티브 Extension 개발

### macOS File Provider Extension

#### 개발 환경 설정

```bash
# Xcode 및 필수 도구 설치
xcode-select --install

# 개발자 계정 설정
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

#### Extension 구조

```
platform/macos/MainBoothFileProvider/
├── FileProviderExtension.swift      # 메인 Extension 클래스
├── FileProviderItem.swift          # 파일/폴더 아이템 모델
├── FileProviderEnumerator.swift    # 파일 목록 열거자
├── FirebaseManager.swift           # Firebase 연동 관리자
└── Info.plist                      # Extension 설정
```

#### 주요 기능

- **On-Demand Sync**: 파일이 필요할 때만 다운로드
- **실시간 동기화**: Firebase와 양방향 동기화
- **상태 관리**: 파일 동기화 상태 추적
- **충돌 처리**: 동시 수정 시 버전 분리

#### 개발 단계

1. **Extension 등록**
   ```swift
   // FileProviderExtension.swift에서 구현
   override func item(for identifier: NSFileProviderItemIdentifier) throws -> NSFileProviderItem
   ```

2. **Firebase 연동**
   ```swift
   // FirebaseManager.swift에서 구현
   func downloadFile(for identifier: NSFileProviderItemIdentifier, completion: @escaping (Result<URL, Error>) -> Void)
   ```

3. **테스트 및 디버깅**
   ```bash
   # Extension 디버깅
   sudo log stream --predicate 'subsystem == "com.mainbooth.drive.fileprovider"'
   ```

### Windows Cloud Files API

#### 개발 환경 설정

```bash
# Visual Studio Build Tools 설치
# Windows SDK 설치
# CMake 설치
```

#### API 구조

```
platform/windows/CloudFilesProvider/
├── CloudFilesProvider.h            # 헤더 파일
├── CloudFilesProvider.cpp          # 구현 파일
└── CMakeLists.txt                  # 빌드 설정
```

#### 주요 기능

- **동기화 루트 등록**: Explorer에 드라이브 표시
- **플레이스홀더 생성**: 0KB 파일로 표시
- **하이드레이션**: 실제 파일 내용 다운로드
- **상태 업데이트**: 동기화 상태 아이콘 표시

#### 개발 단계

1. **Cloud Files API 초기화**
   ```cpp
   HRESULT CloudFilesProvider::Initialize()
   ```

2. **동기화 루트 등록**
   ```cpp
   HRESULT RegisterSyncRoot(const std::wstring& syncRootPath, const std::wstring& displayName)
   ```

3. **콜백 처리**
   ```cpp
   void CALLBACK OnFetchData(const CF_CALLBACK_INFO* CallbackInfo, const CF_CALLBACK_PARAMETERS* CallbackParameters)
   ```

## ⚡ 성능 최적화

### 대용량 파일 처리

#### 청크 업로드/다운로드

```dart
// PerformanceOptimizer 사용 예시
await PerformanceOptimizer.instance.uploadLargeFile(
  filePath: '/path/to/large/file.wav',
  destinationUrl: 'https://storage.firebase.com/...',
  onProgress: (progress) => print('Progress: ${(progress * 100).toInt()}%'),
);
```

#### 적응적 청크 크기

- **10MB 미만**: 1MB 청크
- **100MB 미만**: 4MB 청크  
- **100MB 이상**: 8MB 청크

### 메모리 관리

#### 스마트 캐싱

```dart
// MemoryManager 사용 예시
await MemoryManager.instance.cacheData(
  'project_123_track_456',
  fileData,
  ttl: Duration(hours: 2),
);
```

#### 적응적 정리

- **95% 이상**: 50% 캐시 정리
- **90% 이상**: 30% 캐시 정리
- **80% 이상**: 20% 캐시 정리

### 동시 사용자 최적화

#### 동적 리소스 할당

```dart
// 사용자 수에 따른 최적화
PerformanceOptimizer.instance.optimizeForConcurrentUsers(userCount);
```

- **10명 이상**: 청크 크기 증가, 동시 전송 제한
- **5-10명**: 균형 잡힌 설정
- **5명 미만**: 최대 성능 설정

## 🚀 배포 준비

### 코드 서명

#### macOS 앱 서명

1. **개발자 인증서 설정**
   ```bash
   # 키체인에서 인증서 확인
   security find-identity -v -p codesigning
   ```

2. **앱 서명**
   ```dart
   await CodeSigningManager.instance.signMacOSApp('/path/to/app');
   ```

3. **공증**
   ```dart
   await CodeSigningManager.instance.notarizeMacOSApp('/path/to/app');
   ```

#### Windows 앱 서명

1. **인증서 설정**
   ```bash
   # 인증서 저장소 확인
   certlm.msc
   ```

2. **코드 서명**
   ```dart
   await CodeSigningManager.instance.signWindowsApp('/path/to/app.exe');
   ```

### 설치 프로그램 생성

#### macOS DMG

```dart
await InstallerBuilder.instance.createMacOSDMG(
  appPath: '/path/to/app',
  dmgOutputPath: '/path/to/installer.dmg',
  volumeName: 'Main Booth Drive',
  backgroundImagePath: '/path/to/background.png',
);
```

#### Windows 설치 프로그램

```dart
// NSIS 설치 프로그램
await InstallerBuilder.instance.createWindowsNSIS(
  appPath: '/path/to/app',
  exeOutputPath: '/path/to/setup.exe',
  config: windowsConfig,
);
```

### 자동 업데이트 시스템

#### 업데이트 서버 설정

```dart
AutoUpdater.instance.initialize(
  updateServerUrl: 'https://api.mainbooth.com/updates',
  currentVersion: '1.0.0',
  checkInterval: Duration(hours: 24),
  autoDownload: true,
  autoInstall: false,
);
```

#### 업데이트 체크

```dart
final updateInfo = await AutoUpdater.instance.checkForUpdates();
if (updateInfo != null) {
  print('새 업데이트 발견: v${updateInfo.version}');
}
```

## 🔨 빌드 및 배포 프로세스

### 자동 빌드 스크립트

```bash
# 전체 빌드 및 배포
./scripts/build_and_deploy.sh

# 환경 변수 설정
export MACOS_DEVELOPER_ID="Developer ID Application: Your Name"
export APPLE_ID="your@email.com"
export APPLE_PASSWORD="app-specific-password"
export APPLE_TEAM_ID="TEAM123456"
```

### 배포 관리자 사용

```dart
final deploymentManager = DeploymentManager.instance;

// 배포 설정
final config = DeploymentConfig(
  productName: 'Main Booth Drive',
  currentVersion: '1.0.0',
  manufacturer: 'Main Booth',
  // ... 기타 설정
);

// 전체 배포 실행
final success = await deploymentManager.performFullDeployment(
  appPath: '/path/to/app',
  outputDirectory: '/path/to/output',
  config: config,
  onProgress: (message) => print(message),
);
```

### CI/CD 통합

#### GitHub Actions 예시

```yaml
name: Build and Deploy

on:
  push:
    tags:
      - 'v*'

jobs:
  build-macos:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v2
      - uses: subosito/flutter-action@v2
      - name: Build and Deploy
        run: ./scripts/build_and_deploy.sh
        env:
          MACOS_DEVELOPER_ID: ${{ secrets.MACOS_DEVELOPER_ID }}
          APPLE_ID: ${{ secrets.APPLE_ID }}
          APPLE_PASSWORD: ${{ secrets.APPLE_PASSWORD }}
```

## 🐛 문제 해결

### 일반적인 문제

#### 1. macOS 공증 실패

**증상**: 공증 과정에서 오류 발생

**해결책**:
```bash
# 공증 상태 확인
xcrun notarytool log [submission-id] --apple-id [apple-id] --password [password] --team-id [team-id]

# 하드닝된 런타임 확인
codesign --display --verbose=4 /path/to/app
```

#### 2. Windows 코드 서명 실패

**증상**: signtool 오류

**해결책**:
```bash
# 타임스탬프 서버 변경
signtool sign /f certificate.p12 /p password /t http://timestamp.digicert.com app.exe

# 인증서 체인 확인
certutil -verify certificate.p12
```

#### 3. 파일 동기화 문제

**증상**: 파일이 동기화되지 않음

**해결책**:
```dart
// 동기화 상태 강제 새로고침
await SyncEngine.instance.forceSyncRefresh();

// 캐시 무효화
MemoryManager.instance.invalidateCache('project_123');
```

### 로그 및 디버깅

#### macOS 로그

```bash
# File Provider Extension 로그
sudo log stream --predicate 'subsystem == "com.mainbooth.drive.fileprovider"'

# 시스템 로그
sudo log show --last 1h --predicate 'processImagePath contains "MainBoothDrive"'
```

#### Windows 로그

```bash
# 이벤트 뷰어에서 확인
eventvwr.msc

# 애플리케이션 로그
Get-EventLog -LogName Application -Source "Main Booth Drive"
```

### 성능 최적화 팁

1. **메모리 사용량 모니터링**
   ```dart
   final stats = MemoryManager.instance.getMemoryStats();
   print('메모리 사용률: ${stats['memoryUsagePercent']}%');
   ```

2. **네트워크 대역폭 적응**
   ```dart
   // 네트워크 속도에 따른 최적화
   PerformanceOptimizer.instance.adaptToBandwidth(bandwidthMbps);
   ```

3. **프리로딩 전략**
   ```dart
   // 자주 사용되는 파일 미리 로드
   await MemoryManager.instance.preloadFiles(frequentlyUsedFiles);
   ```

## 📚 추가 리소스

- [Apple File Provider Documentation](https://developer.apple.com/documentation/fileprovider)
- [Windows Cloud Files API Documentation](https://docs.microsoft.com/en-us/windows/win32/cfapi/cloud-files-api-portal)
- [Flutter Desktop Development](https://docs.flutter.dev/desktop)
- [Firebase Flutter Documentation](https://firebase.flutter.dev/)

## 🔄 버전 관리

- **메이저 버전**: 호환성이 깨지는 변경사항
- **마이너 버전**: 새로운 기능 추가
- **패치 버전**: 버그 수정

현재 버전: v1.0.0

---

이 가이드는 Main Booth Drive의 완전한 배포 프로세스를 다루며, 프로덕션 환경에서의 안정적인 배포를 보장합니다.
