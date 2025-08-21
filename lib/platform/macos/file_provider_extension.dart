/// macOS File Provider Extension 래퍼
/// Finder와 Main Booth Drive를 연결하는 네이티브 확장

import 'dart:ffi';
import 'package:ffi/ffi.dart';
import '../../utils/logger.dart';

/// macOS File Provider Extension을 Dart에서 사용하기 위한 래퍼
/// 실제 구현은 Swift로 작성되며, 이 클래스는 FFI를 통해 통신
class MacOSFileProviderExtension {
  static MacOSFileProviderExtension? _instance;
  static MacOSFileProviderExtension get instance =>
      _instance ??= MacOSFileProviderExtension._();

  final Logger _logger = Logger('MacOSFileProvider');
  late DynamicLibrary _nativeLib;
  bool _isInitialized = false;

  MacOSFileProviderExtension._();

  /// 초기화
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      _logger.info('macOS File Provider Extension 초기화');

      // 네이티브 라이브러리 로드
      _nativeLib = DynamicLibrary.open('mainbooth_file_provider.dylib');

      // 함수 포인터 가져오기
      _initializeNative = _nativeLib
          .lookup<NativeFunction<InitializeFunc>>('initialize_file_provider')
          .asFunction();

      _registerDomain = _nativeLib
          .lookup<NativeFunction<RegisterDomainFunc>>('register_domain')
          .asFunction();

      _unregisterDomain = _nativeLib
          .lookup<NativeFunction<UnregisterDomainFunc>>('unregister_domain')
          .asFunction();

      _signalEnumerator = _nativeLib
          .lookup<NativeFunction<SignalEnumeratorFunc>>('signal_enumerator')
          .asFunction();

      // 네이티브 초기화
      final result = _initializeNative();
      if (result != 0) {
        throw Exception('File Provider 초기화 실패: $result');
      }

      _isInitialized = true;
      _logger.info('macOS File Provider Extension 초기화 완료');
    } catch (e) {
      _logger.error('File Provider 초기화 실패', e);
      rethrow;
    }
  }

  /// 도메인 등록 (Finder에 표시)
  Future<void> registerDomain({
    required String identifier,
    required String displayName,
    required String rootPath,
  }) async {
    if (!_isInitialized) {
      throw Exception('File Provider가 초기화되지 않았습니다');
    }

    try {
      _logger.info('도메인 등록: $displayName');

      final identifierPtr = identifier.toNativeUtf8();
      final displayNamePtr = displayName.toNativeUtf8();
      final rootPathPtr = rootPath.toNativeUtf8();

      final result = _registerDomain(
        identifierPtr.cast<Int8>(),
        displayNamePtr.cast<Int8>(),
        rootPathPtr.cast<Int8>(),
      );

      calloc.free(identifierPtr);
      calloc.free(displayNamePtr);
      calloc.free(rootPathPtr);

      if (result != 0) {
        throw Exception('도메인 등록 실패: $result');
      }

      _logger.info('도메인 등록 완료');
    } catch (e) {
      _logger.error('도메인 등록 실패', e);
      rethrow;
    }
  }

  /// 도메인 해제
  Future<void> unregisterDomain(String identifier) async {
    if (!_isInitialized) return;

    try {
      _logger.info('도메인 해제: $identifier');

      final identifierPtr = identifier.toNativeUtf8();

      final result = _unregisterDomain(identifierPtr.cast<Int8>());

      calloc.free(identifierPtr);

      if (result != 0) {
        _logger.warning('도메인 해제 실패: $result');
      }
    } catch (e) {
      _logger.error('도메인 해제 실패', e);
    }
  }

  /// 파일 변경 알림
  Future<void> signalEnumeratorForItem(String itemIdentifier) async {
    if (!_isInitialized) return;

    try {
      final identifierPtr = itemIdentifier.toNativeUtf8();

      _signalEnumerator(identifierPtr.cast<Int8>());

      calloc.free(identifierPtr);
    } catch (e) {
      _logger.error('Enumerator 신호 실패', e);
    }
  }

  /// 파일 속성 설정
  Future<void> setItemAttributes({
    required String itemIdentifier,
    required Map<String, dynamic> attributes,
  }) async {
    // 네이티브 코드로 속성 전달
    // 실제 구현은 Swift에서 처리
  }

  /// 썸네일 제공
  Future<void> provideThumbnail({
    required String itemIdentifier,
    required String thumbnailPath,
  }) async {
    // 네이티브 코드로 썸네일 전달
  }

  /// 퀵룩 미리보기 제공
  Future<void> provideQuickLook({
    required String itemIdentifier,
    required String previewPath,
  }) async {
    // 네이티브 코드로 미리보기 전달
  }

  // 네이티브 함수 타입 정의
  late final int Function() _initializeNative;
  late final int Function(Pointer<Int8>, Pointer<Int8>, Pointer<Int8>)
      _registerDomain;
  late final int Function(Pointer<Int8>) _unregisterDomain;
  late final void Function(Pointer<Int8>) _signalEnumerator;
}

// FFI 함수 시그니처
typedef InitializeFunc = Int32 Function();
typedef RegisterDomainFunc = Int32 Function(
  Pointer<Int8> identifier,
  Pointer<Int8> displayName,
  Pointer<Int8> rootPath,
);
typedef UnregisterDomainFunc = Int32 Function(Pointer<Int8> identifier);
typedef SignalEnumeratorFunc = Void Function(Pointer<Int8> itemIdentifier);

/// File Provider Extension 설정
class FileProviderConfiguration {
  /// Main Booth Drive 도메인 식별자
  static const String domainIdentifier = 'com.mainbooth.drive.fileprovider';

  /// Finder에 표시될 이름
  static const String displayName = 'Main Booth Drive';

  /// 지원하는 파일 타입
  static const List<String> supportedFileTypes = [
    'public.audio',
    'public.movie',
    'public.image',
    'public.text',
    'public.data',
  ];

  /// 파일 속성 키
  static const Map<String, String> attributeKeys = {
    'contentType': 'NSFileProviderContentType',
    'filename': 'NSFileProviderFilename',
    'size': 'NSFileProviderFileSize',
    'creationDate': 'NSFileProviderCreationDate',
    'contentModificationDate': 'NSFileProviderContentModificationDate',
    'isMostRecentVersionDownloaded':
        'NSFileProviderIsMostRecentVersionDownloaded',
    'isUploaded': 'NSFileProviderIsUploaded',
    'isDownloading': 'NSFileProviderIsDownloading',
    'isUploading': 'NSFileProviderIsUploading',
    'downloadingError': 'NSFileProviderDownloadingError',
    'uploadingError': 'NSFileProviderUploadingError',
  };

  /// 동기화 상태 아이콘
  static const Map<String, String> statusIcons = {
    'pending': 'icloud',
    'synced': 'checkmark.icloud',
    'syncing': 'arrow.triangle.2.circlepath.icloud',
    'error': 'exclamationmark.icloud',
    'uploading': 'arrow.up.circle',
    'downloading': 'arrow.down.circle',
  };
}
