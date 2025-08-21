/// Firebase 설정 관리
/// 데스크탑 앱에서 Firebase와 연동하기 위한 설정

class FirebaseConfig {
  // Firebase 프로젝트 설정
  static const String apiKey = 'YOUR_API_KEY';
  static const String authDomain = 'YOUR_AUTH_DOMAIN';
  static const String projectId = 'YOUR_PROJECT_ID';
  static const String storageBucket = 'YOUR_STORAGE_BUCKET';
  static const String messagingSenderId = 'YOUR_MESSAGING_SENDER_ID';
  static const String appId = 'YOUR_APP_ID';

  // Firestore 컬렉션 경로
  static const String projectsCollection = 'projects';
  static const String tracksCollection = 'tracks';
  static const String referencesCollection = 'references';
  static const String workRequestsCollection = 'workRequests';
  static const String usersCollection = 'users';

  // Storage 경로
  static const String tracksStoragePath = 'tracks';
  static const String referencesStoragePath = 'references';
  static const String imagesStoragePath = 'images';

  // 동기화 설정
  static const int maxConcurrentUploads = 3;
  static const int maxConcurrentDownloads = 5;
  static const int chunkSize = 1024 * 1024; // 1MB chunks
  static const Duration syncInterval = Duration(seconds: 30);
  static const Duration retryDelay = Duration(seconds: 5);
  static const int maxRetries = 3;

  // 캐시 설정
  static const int maxCacheSize = 5 * 1024 * 1024 * 1024; // 5GB
  static const Duration cacheExpiration = Duration(days: 30);

  // 파일 크기 제한
  static const int maxTrackFileSize = 500 * 1024 * 1024; // 500MB
  static const int maxReferenceFileSize = 100 * 1024 * 1024; // 100MB

  // 권한 설정
  static const List<String> adminActions = [
    'delete_project',
    'delete_track',
    'delete_reference',
    'manage_members',
  ];

  static const List<String> memberActions = [
    'upload_track',
    'upload_reference',
    'create_work_request',
    'comment',
  ];
}
