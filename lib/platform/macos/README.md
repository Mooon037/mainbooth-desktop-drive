# macOS File Provider Extension

Main Booth Drive의 macOS Finder 통합을 위한 File Provider Extension 구현 가이드

## 개요

macOS File Provider Extension은 Finder에 클라우드 드라이브를 네이티브하게 통합하는 Apple의 공식 API입니다.

## 구조

```
macos/
├── MainBoothFileProvider/
│   ├── FileProviderExtension.swift       # 메인 Extension 클래스
│   ├── FileProviderEnumerator.swift      # 파일 목록 제공
│   ├── FileProviderItem.swift            # 파일 아이템 모델
│   ├── FileProviderDomain.swift          # 도메인 설정
│   └── Info.plist                        # Extension 설정
├── MainBoothFileProviderUI/              # UI Extension (선택사항)
│   └── DocumentActionViewController.swift
└── bridge/
    ├── FileProviderBridge.h              # C 헤더
    └── FileProviderBridge.m              # Objective-C 브릿지
```

## 주요 구현 사항

### 1. FileProviderExtension.swift

```swift
import FileProvider

class FileProviderExtension: NSFileProviderExtension {
    
    override func item(for identifier: NSFileProviderItemIdentifier) throws -> NSFileProviderItem {
        // 파일 아이템 반환
    }
    
    override func urlForItem(withPersistentIdentifier identifier: NSFileProviderItemIdentifier) -> URL? {
        // 파일 URL 반환
    }
    
    override func startProvidingItem(at url: URL, completionHandler: @escaping (Error?) -> Void) {
        // 파일 다운로드 시작
    }
    
    override func stopProvidingItem(at url: URL) {
        // 파일 제공 중지
    }
}
```

### 2. FileProviderEnumerator.swift

```swift
class FileProviderEnumerator: NSObject, NSFileProviderEnumerator {
    
    func enumerateItems(for observer: NSFileProviderEnumerationObserver, startingAt page: NSFileProviderPage) {
        // 파일 목록 열거
    }
    
    func enumerateChanges(for observer: NSFileProviderChangeObserver, from anchor: NSFileProviderSyncAnchor) {
        // 변경사항 열거
    }
}
```

### 3. FileProviderItem.swift

```swift
class FileProviderItem: NSObject, NSFileProviderItem {
    
    var itemIdentifier: NSFileProviderItemIdentifier
    var parentItemIdentifier: NSFileProviderItemIdentifier
    var filename: String
    var contentType: UTType
    var documentSize: NSNumber?
    
    // 동기화 상태
    var isDownloaded: Bool
    var isDownloading: Bool
    var isUploaded: Bool
    var isUploading: Bool
}
```

## Xcode 프로젝트 설정

### 1. App Extension 추가

1. Xcode에서 File > New > Target
2. "File Provider Extension" 선택
3. Product Name: "MainBoothFileProvider"
4. Team과 Bundle Identifier 설정

### 2. Entitlements 설정

```xml
<key>com.apple.security.application-groups</key>
<array>
    <string>group.com.mainbooth.drive</string>
</array>
<key>com.apple.developer.fileprovider</key>
<true/>
```

### 3. Info.plist 설정

```xml
<key>NSExtension</key>
<dict>
    <key>NSExtensionFileProviderDocumentGroup</key>
    <string>group.com.mainbooth.drive</string>
    <key>NSExtensionPrincipalClass</key>
    <string>FileProviderExtension</string>
    <key>NSExtensionPointIdentifier</key>
    <string>com.apple.fileprovider-nonui</string>
</dict>
```

## Flutter 연동

### FFI 브릿지 구현

```c
// FileProviderBridge.h
int initialize_file_provider(void);
int register_domain(const char* identifier, const char* displayName, const char* rootPath);
int unregister_domain(const char* identifier);
void signal_enumerator(const char* itemIdentifier);
```

### 빌드 스크립트

```bash
# build_file_provider.sh
#!/bin/bash

# Swift 컴파일
swiftc -emit-library -o mainbooth_file_provider.dylib \
    -framework FileProvider \
    -framework Foundation \
    MainBoothFileProvider/*.swift \
    bridge/FileProviderBridge.m
```

## 테스트

### 1. Extension 설치 확인

```bash
# Extension 목록 확인
pluginkit -m | grep com.mainbooth
```

### 2. 로그 확인

```bash
# Console.app에서 로그 확인
log stream --predicate 'subsystem == "com.mainbooth.drive.fileprovider"'
```

## 주의사항

1. **App Sandbox**: File Provider Extension은 샌드박스 환경에서 실행
2. **App Group**: 메인 앱과 데이터 공유를 위해 App Group 필수
3. **Performance**: 파일 목록 열거는 비동기로 처리
4. **Memory**: Extension은 메모리 제한이 있음 (약 15MB)

## 디버깅

1. Xcode에서 Extension 스키마 선택
2. Run > Attach to Process by PID or Name
3. "com.mainbooth.drive.fileprovider" 입력
4. Finder에서 Main Booth Drive 접근 시 디버거 연결

## 참고 자료

- [Apple File Provider Documentation](https://developer.apple.com/documentation/fileprovider)
- [WWDC 2017 - File Provider Enhancements](https://developer.apple.com/videos/play/wwdc2017/243/)
- [Building a Document-Based App](https://developer.apple.com/documentation/uikit/view_controllers/building_a_document_browser-based_app)
