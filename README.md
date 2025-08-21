# Main Booth Drive 🎵

> 음악 협업을 위한 데스크탑 클라우드 드라이브

[![Release](https://img.shields.io/github/v/release/mainbooth/desktop-drive)](https://github.com/mainbooth/desktop-drive/releases)
[![Downloads](https://img.shields.io/github/downloads/mainbooth/desktop-drive/total)](https://github.com/mainbooth/desktop-drive/releases)
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Flutter](https://img.shields.io/badge/Flutter-3.16.0-blue.svg)](https://flutter.dev)

## 📖 개요

Main Booth Drive는 음악 제작자들이 DAW 환경에서 직접 프로젝트 파일을 관리하고 협업할 수 있도록 하는 데스크탑 애플리케이션입니다. macOS의 Finder와 Windows의 Explorer에 네이티브하게 통합되어 일반 폴더처럼 사용할 수 있습니다.

## ✨ 주요 기능

### 🖥️ OS 네이티브 통합
- **macOS**: File Provider Extension을 통한 Finder 통합
- **Windows**: Cloud Files API를 통한 Explorer 통합
- **Linux**: FUSE 파일시스템을 통한 네이티브 지원
- 일반 폴더처럼 파일 관리 가능

### ⚡ 실시간 동기화
- Firebase Realtime Database를 통한 실시간 동기화
- 온디맨드 다운로드 (필요할 때만 다운로드)
- 자동 충돌 감지 및 해결
- 스마트 캐싱으로 빠른 파일 접근

### 🎼 프로젝트 구조
```
Main Booth Drive/
└── Projects/
    └── [프로젝트명]/
        ├── Tracks/          # 오디오 파일
        ├── References/      # 레퍼런스 자료
        └── WorkRequests/    # 작업 요청
```

### 🤝 협업 기능
- 모바일 앱과 완벽한 연동
- 실시간 파일 업데이트
- 권한 기반 접근 제어
- 버전 관리 및 히스토리

## 💻 시스템 요구사항

### macOS
- macOS 10.15 (Catalina) 이상
- File Provider Extension 지원
- Apple Silicon 및 Intel 모두 지원

### Windows
- Windows 10 버전 1903 이상
- Cloud Files API 지원
- x64 아키텍처

### Linux
- Ubuntu 18.04+ / CentOS 7+ / Fedora 30+
- FUSE 파일시스템 지원
- GTK 3.0+

## 📥 다운로드

최신 버전은 [공식 다운로드 페이지](https://drive.mainbooth.com)에서 받으실 수 있습니다.

### 직접 다운로드
- [macOS (.dmg)](https://github.com/mainbooth/desktop-drive/releases/latest/download/MainBoothDrive-mac.dmg)
- [Windows (.exe)](https://github.com/mainbooth/desktop-drive/releases/latest/download/MainBoothDrive-windows.exe)
- [Linux (.AppImage)](https://github.com/mainbooth/desktop-drive/releases/latest/download/MainBoothDrive-linux.AppImage)

## 🚀 설치 방법

### macOS
1. DMG 파일을 다운로드합니다
2. DMG 파일을 더블클릭하여 마운트합니다
3. Main Booth Drive 앱을 Applications 폴더로 드래그합니다
4. 앱을 실행하고 Main Booth 계정으로 로그인합니다

### Windows
1. EXE 파일을 다운로드합니다
2. 파일을 우클릭하여 "관리자 권한으로 실행"을 선택합니다
3. 설치 마법사의 안내에 따라 설치를 완료합니다
4. 앱을 실행하고 로그인합니다

### Linux
1. AppImage 파일을 다운로드합니다
2. 터미널에서 실행 권한을 부여합니다:
   ```bash
   chmod +x MainBoothDrive-linux.AppImage
   ```
3. FUSE를 설치합니다 (필요한 경우):
   ```bash
   # Ubuntu/Debian
   sudo apt install fuse
   
   # CentOS/RHEL
   sudo yum install fuse
   
   # Fedora
   sudo dnf install fuse
   ```
4. AppImage를 실행합니다

## 🛠️ 개발 환경 설정

### 사전 요구사항
- [Flutter](https://flutter.dev) 3.16.0+
- [Git](https://git-scm.com)
- Platform-specific tools:
  - **macOS**: Xcode 14+
  - **Windows**: Visual Studio 2022 + CMake
  - **Linux**: GCC + CMake + GTK development headers

### 프로젝트 설정
```bash
# 저장소 클론
git clone https://github.com/mainbooth/desktop-drive.git
cd desktop-drive

# 의존성 설치
flutter pub get

# 개발 모드로 실행
flutter run -d macos    # macOS
flutter run -d windows  # Windows
flutter run -d linux    # Linux
```

### Firebase 설정
1. Firebase 콘솔에서 프로젝트 생성
2. `lib/config/firebase_config.dart`에 설정 추가:
```dart
static const String apiKey = 'YOUR_API_KEY';
static const String authDomain = 'YOUR_AUTH_DOMAIN';
static const String projectId = 'YOUR_PROJECT_ID';
static const String storageBucket = 'YOUR_STORAGE_BUCKET';
```

## 🏗️ 아키텍처

### 레이어 구조
```
lib/
├── core/           # 핵심 비즈니스 로직
├── services/       # 외부 서비스 연동
├── sync/           # 동기화 엔진
├── platform/       # 플랫폼별 네이티브 코드
├── ui/             # Flutter UI
├── models/         # 데이터 모델
├── config/         # 설정
└── utils/          # 유틸리티
```

### 주요 컴포넌트
- **DriveManager**: 전체 드라이브 관리
- **SyncEngine**: 파일 동기화 엔진
- **FileWatcher**: 파일 시스템 감시
- **AuthManager**: 사용자 인증
- **StatusManager**: 상태 관리
- **AutoUpdaterService**: 자동 업데이트

## 🔧 빌드 및 배포

### 로컬 빌드
```bash
# 모든 플랫폼 빌드
./scripts/build_and_deploy.sh

# 특정 플랫폼만 빌드
./scripts/build_and_deploy.sh macos
./scripts/build_and_deploy.sh windows linux
```

### CI/CD
GitHub Actions를 통한 자동 빌드 및 배포가 설정되어 있습니다.

- **트리거**: 태그 푸시 시 (`v*`)
- **플랫폼**: macOS, Windows, Linux 동시 빌드
- **배포**: GitHub Releases + 웹사이트 자동 배포

필요한 Secrets:
```
MACOS_CERTIFICATE        # macOS 코드 서명 인증서
MACOS_CERTIFICATE_PWD    # 인증서 비밀번호
MACOS_DEVELOPER_ID       # Apple Developer ID
APPLE_ID                 # Apple ID (공증용)
APPLE_PASSWORD           # App-specific password
APPLE_TEAM_ID            # Apple Team ID
WINDOWS_CERTIFICATE      # Windows 코드 서명 인증서
WINDOWS_CERTIFICATE_PWD  # 인증서 비밀번호
```

## 🧪 테스트

```bash
# 단위 테스트
flutter test

# 통합 테스트
flutter test integration_test

# 커버리지 리포트
flutter test --coverage
genhtml coverage/lcov.info -o coverage/html
```

## 📋 TODO

- [ ] 오프라인 모드 지원
- [ ] 파일 암호화 옵션
- [ ] 플러그인 시스템
- [ ] 고급 권한 관리
- [ ] 배치 동기화 설정
- [ ] 성능 모니터링 대시보드

## 🤝 기여하기

기여를 환영합니다! 다음 단계를 따라주세요:

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

### 개발 가이드라인
- [Flutter 스타일 가이드](https://docs.flutter.dev/development/tools/formatting) 준수
- 모든 새 기능에 대한 테스트 작성
- API 변경 시 문서 업데이트
- 커밋 메시지는 [Conventional Commits](https://conventionalcommits.org/) 형식 사용

## 🐛 문제 해결

### 일반적인 문제

#### macOS File Provider 이슈
1. Extension이 보이지 않는 경우:
   ```bash
   pluginkit -m | grep com.mainbooth
   ```

2. 로그 확인:
   ```bash
   log stream --predicate 'subsystem == "com.mainbooth.drive.fileprovider"'
   ```

#### Windows Cloud Files API 이슈
1. 동기화 루트 확인:
   ```powershell
   Get-CloudFilesRootInfo
   ```

2. 이벤트 로그 확인:
   - 이벤트 뷰어 > 응용 프로그램 및 서비스 로그

### 로그 파일 위치
- **macOS**: `~/Library/Application Support/com.mainbooth.drive/logs/`
- **Windows**: `%APPDATA%\com.mainbooth.drive\logs\`
- **Linux**: `~/.config/com.mainbooth.drive/logs/`

## 📄 라이선스

이 프로젝트는 MIT 라이선스 하에 배포됩니다. 자세한 내용은 [LICENSE](LICENSE) 파일을 참조하세요.

## 🔗 링크

- [공식 웹사이트](https://mainbooth.com)
- [다운로드 페이지](https://drive.mainbooth.com)
- [사용자 가이드](https://docs.mainbooth.com)
- [API 문서](https://api.mainbooth.com)
- [지원 센터](https://support.mainbooth.com)

## 📞 지원

- **이메일**: support@mainbooth.com
- **Discord**: [Main Booth Community](https://discord.gg/mainbooth)
- **GitHub Issues**: [문제 신고](https://github.com/mainbooth/desktop-drive/issues)

---

<div align="center">
  <strong>Made with ❤️ by the Main Booth Team</strong>
</div>