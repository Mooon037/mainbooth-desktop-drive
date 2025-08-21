/// 상태 관리자
/// 드라이브의 현재 상태를 관리하고 UI에 제공

import 'dart:async';
import '../utils/logger.dart';

class StatusManager {
  static StatusManager? _instance;
  static StatusManager get instance => _instance ??= StatusManager._();

  final Logger _logger = Logger('StatusManager');

  // 상태 스트림 컨트롤러
  final _driveStatusController = StreamController<DriveStatus>.broadcast();
  final _syncStatusController = StreamController<SyncStatus>.broadcast();
  final _storageStatusController = StreamController<StorageStatus>.broadcast();
  final _networkStatusController = StreamController<NetworkStatus>.broadcast();

  // 현재 상태
  DriveStatus _driveStatus = DriveStatus.stopped;
  SyncStatus _syncStatus = SyncStatus();
  StorageStatus _storageStatus = StorageStatus();
  NetworkStatus _networkStatus = NetworkStatus();

  // 통계
  final Map<String, dynamic> _statistics = {};

  StatusManager._();

  /// 초기화
  void initialize() {
    _logger.info('상태 관리자 초기화');

    // 초기 상태 발행
    _driveStatusController.add(_driveStatus);
    _syncStatusController.add(_syncStatus);
    _storageStatusController.add(_storageStatus);
    _networkStatusController.add(_networkStatus);
  }

  /// 스트림 getter
  Stream<DriveStatus> get driveStatusStream => _driveStatusController.stream;
  Stream<SyncStatus> get syncStatusStream => _syncStatusController.stream;
  Stream<StorageStatus> get storageStatusStream =>
      _storageStatusController.stream;
  Stream<NetworkStatus> get networkStatusStream =>
      _networkStatusController.stream;

  /// 현재 상태 getter
  DriveStatus get driveStatus => _driveStatus;
  SyncStatus get syncStatus => _syncStatus;
  StorageStatus get storageStatus => _storageStatus;
  NetworkStatus get networkStatus => _networkStatus;
  Map<String, dynamic> get statistics => Map.from(_statistics);

  /// 드라이브 상태 설정
  void setDriveStatus(DriveStatus status) {
    if (_driveStatus != status) {
      _driveStatus = status;
      _driveStatusController.add(status);
      _logger.debug('드라이브 상태 변경: $status');
    }
  }

  /// 동기화 상태 업데이트
  void updateSyncStatus(Map<String, dynamic> queueStatus) {
    _syncStatus = SyncStatus(
      uploadQueueSize: queueStatus['uploadQueueSize'] ?? 0,
      downloadQueueSize: queueStatus['downloadQueueSize'] ?? 0,
      activeUploads: queueStatus['activeUploads'] ?? 0,
      activeDownloads: queueStatus['activeDownloads'] ?? 0,
      activeTasks:
          List<Map<String, dynamic>>.from(queueStatus['activeTasks'] ?? []),
    );

    _syncStatusController.add(_syncStatus);
  }

  /// 저장소 상태 업데이트
  void updateStorageStatus(Map<String, dynamic> storageInfo) {
    _storageStatus = StorageStatus(
      cacheSize: storageInfo['cacheSize'] ?? 0,
      driveSize: storageInfo['driveSize'] ?? 0,
      totalSize: storageInfo['totalSize'] ?? 0,
    );

    _storageStatusController.add(_storageStatus);
  }

  /// 네트워크 상태 업데이트
  void updateNetworkStatus({
    bool? isConnected,
    double? uploadSpeed,
    double? downloadSpeed,
    int? ping,
  }) {
    _networkStatus = NetworkStatus(
      isConnected: isConnected ?? _networkStatus.isConnected,
      uploadSpeed: uploadSpeed ?? _networkStatus.uploadSpeed,
      downloadSpeed: downloadSpeed ?? _networkStatus.downloadSpeed,
      ping: ping ?? _networkStatus.ping,
    );

    _networkStatusController.add(_networkStatus);
  }

  /// 통계 업데이트
  void updateStatistics(Map<String, dynamic> stats) {
    _statistics.addAll(stats);
  }

  /// 활성 작업 추가
  void addActiveTask(String taskId, Map<String, dynamic> taskInfo) {
    final tasks = List<Map<String, dynamic>>.from(_syncStatus.activeTasks);
    tasks.add({
      'id': taskId,
      ...taskInfo,
    });

    _syncStatus = _syncStatus.copyWith(activeTasks: tasks);
    _syncStatusController.add(_syncStatus);
  }

  /// 활성 작업 제거
  void removeActiveTask(String taskId) {
    final tasks = List<Map<String, dynamic>>.from(_syncStatus.activeTasks);
    tasks.removeWhere((task) => task['id'] == taskId);

    _syncStatus = _syncStatus.copyWith(activeTasks: tasks);
    _syncStatusController.add(_syncStatus);
  }

  /// 작업 진행률 업데이트
  void updateTaskProgress(String taskId, double progress) {
    final tasks = List<Map<String, dynamic>>.from(_syncStatus.activeTasks);
    final taskIndex = tasks.indexWhere((task) => task['id'] == taskId);

    if (taskIndex != -1) {
      tasks[taskIndex]['progress'] = progress;
      _syncStatus = _syncStatus.copyWith(activeTasks: tasks);
      _syncStatusController.add(_syncStatus);
    }
  }

  /// 전체 상태 요약
  Map<String, dynamic> getStatusSummary() {
    return {
      'driveStatus': _driveStatus.toString(),
      'syncStatus': {
        'totalQueued':
            _syncStatus.uploadQueueSize + _syncStatus.downloadQueueSize,
        'totalActive': _syncStatus.activeUploads + _syncStatus.activeDownloads,
        'isActive': _syncStatus.isActive,
      },
      'storageStatus': {
        'totalSize': _storageStatus.totalSize,
        'formattedSize': _formatFileSize(_storageStatus.totalSize),
      },
      'networkStatus': {
        'isConnected': _networkStatus.isConnected,
        'ping': _networkStatus.ping,
      },
      'statistics': _statistics,
    };
  }

  /// 파일 크기 포맷
  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024)
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  /// 정리
  void dispose() {
    _driveStatusController.close();
    _syncStatusController.close();
    _storageStatusController.close();
    _networkStatusController.close();
  }
}

/// 드라이브 상태
enum DriveStatus {
  stopped,
  starting,
  running,
  stopping,
  error,
}

/// 동기화 상태
class SyncStatus {
  final int uploadQueueSize;
  final int downloadQueueSize;
  final int activeUploads;
  final int activeDownloads;
  final List<Map<String, dynamic>> activeTasks;

  SyncStatus({
    this.uploadQueueSize = 0,
    this.downloadQueueSize = 0,
    this.activeUploads = 0,
    this.activeDownloads = 0,
    this.activeTasks = const [],
  });

  bool get isActive =>
      activeUploads > 0 ||
      activeDownloads > 0 ||
      uploadQueueSize > 0 ||
      downloadQueueSize > 0;

  SyncStatus copyWith({
    int? uploadQueueSize,
    int? downloadQueueSize,
    int? activeUploads,
    int? activeDownloads,
    List<Map<String, dynamic>>? activeTasks,
  }) {
    return SyncStatus(
      uploadQueueSize: uploadQueueSize ?? this.uploadQueueSize,
      downloadQueueSize: downloadQueueSize ?? this.downloadQueueSize,
      activeUploads: activeUploads ?? this.activeUploads,
      activeDownloads: activeDownloads ?? this.activeDownloads,
      activeTasks: activeTasks ?? this.activeTasks,
    );
  }
}

/// 저장소 상태
class StorageStatus {
  final int cacheSize;
  final int driveSize;
  final int totalSize;

  StorageStatus({
    this.cacheSize = 0,
    this.driveSize = 0,
    this.totalSize = 0,
  });
}

/// 네트워크 상태
class NetworkStatus {
  final bool isConnected;
  final double uploadSpeed;
  final double downloadSpeed;
  final int ping;

  NetworkStatus({
    this.isConnected = true,
    this.uploadSpeed = 0.0,
    this.downloadSpeed = 0.0,
    this.ping = 0,
  });
}
