/// 알림 관리자
/// 시스템 알림 및 사용자 알림 처리

import 'dart:io';
import '../utils/logger.dart';

class NotificationManager {
  static NotificationManager? _instance;
  static NotificationManager get instance =>
      _instance ??= NotificationManager._();

  final Logger _logger = Logger('NotificationManager');
  bool _isInitialized = false;
  bool _notificationsEnabled = true;

  NotificationManager._();

  /// 초기화
  Future<void> initialize() async {
    try {
      _logger.info('알림 관리자 초기화');

      // 플랫폼별 알림 초기화
      if (Platform.isMacOS) {
        await _initializeMacOS();
      } else if (Platform.isWindows) {
        await _initializeWindows();
      } else if (Platform.isLinux) {
        await _initializeLinux();
      }

      _isInitialized = true;
    } catch (e) {
      _logger.error('알림 초기화 실패', e);
    }
  }

  /// macOS 알림 초기화
  Future<void> _initializeMacOS() async {
    // macOS 알림 센터 권한 확인
    // 실제 구현 시 native 코드 필요
  }

  /// Windows 알림 초기화
  Future<void> _initializeWindows() async {
    // Windows 토스트 알림 초기화
    // 실제 구현 시 win32 API 필요
  }

  /// Linux 알림 초기화
  Future<void> _initializeLinux() async {
    // libnotify 초기화
    // 실제 구현 시 DBus 연동 필요
  }

  /// 알림 표시
  Future<void> showNotification({
    required String title,
    required String message,
    NotificationType type = NotificationType.info,
    String? actionId,
    Map<String, dynamic>? data,
  }) async {
    if (!_isInitialized || !_notificationsEnabled) return;

    _logger.debug('알림 표시: $title - $message');

    try {
      if (Platform.isMacOS) {
        await _showMacOSNotification(title, message, type);
      } else if (Platform.isWindows) {
        await _showWindowsNotification(title, message, type);
      } else if (Platform.isLinux) {
        await _showLinuxNotification(title, message, type);
      }
    } catch (e) {
      _logger.error('알림 표시 실패', e);
    }
  }

  /// macOS 알림 표시
  Future<void> _showMacOSNotification(
    String title,
    String message,
    NotificationType type,
  ) async {
    // AppleScript를 통한 알림 표시
    final script = '''
      display notification "$message" with title "$title" sound name "${_getSoundName(type)}"
    ''';

    await Process.run('osascript', ['-e', script]);
  }

  /// Windows 알림 표시
  Future<void> _showWindowsNotification(
    String title,
    String message,
    NotificationType type,
  ) async {
    // PowerShell을 통한 토스트 알림
    final script = '''
      [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
      [Windows.UI.Notifications.ToastNotification, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
      
      \$template = @"
      <toast>
        <visual>
          <binding template="ToastGeneric">
            <text>$title</text>
            <text>$message</text>
          </binding>
        </visual>
      </toast>
      "@
      
      \$xml = New-Object Windows.Data.Xml.Dom.XmlDocument
      \$xml.LoadXml(\$template)
      \$toast = New-Object Windows.UI.Notifications.ToastNotification \$xml
      [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier("Main Booth Drive").Show(\$toast)
    ''';

    await Process.run('powershell', ['-Command', script]);
  }

  /// Linux 알림 표시
  Future<void> _showLinuxNotification(
    String title,
    String message,
    NotificationType type,
  ) async {
    // notify-send 명령 사용
    final urgency = _getUrgencyLevel(type);

    await Process.run('notify-send', [
      '-a',
      'Main Booth Drive',
      '-u',
      urgency,
      '-i',
      _getIconName(type),
      title,
      message,
    ]);
  }

  /// 진행률 알림 표시
  Future<void> showProgressNotification({
    required String id,
    required String title,
    required String message,
    required double progress,
  }) async {
    if (!_isInitialized || !_notificationsEnabled) return;

    // 플랫폼별 진행률 알림 구현
    _logger.debug('진행률 알림: $title - ${(progress * 100).toStringAsFixed(1)}%');
  }

  /// 알림 제거
  Future<void> removeNotification(String id) async {
    if (!_isInitialized) return;

    // 플랫폼별 알림 제거 구현
    _logger.debug('알림 제거: $id');
  }

  /// 동기화 관련 알림
  Future<void> showSyncNotification(SyncEvent event) async {
    switch (event.type) {
      case SyncEventType.started:
        await showNotification(
          title: '동기화 시작',
          message: '${event.projectName} 프로젝트 동기화를 시작합니다',
          type: NotificationType.info,
        );
        break;

      case SyncEventType.completed:
        await showNotification(
          title: '동기화 완료',
          message: '${event.projectName} 프로젝트 동기화가 완료되었습니다',
          type: NotificationType.success,
        );
        break;

      case SyncEventType.failed:
        await showNotification(
          title: '동기화 실패',
          message: '${event.projectName}: ${event.error}',
          type: NotificationType.error,
        );
        break;

      case SyncEventType.conflict:
        await showNotification(
          title: '동기화 충돌',
          message: '${event.fileName}에서 충돌이 발생했습니다',
          type: NotificationType.warning,
          actionId: 'resolve_conflict',
          data: {'filePath': event.filePath},
        );
        break;
    }
  }

  /// 알림 설정
  void setNotificationsEnabled(bool enabled) {
    _notificationsEnabled = enabled;
    _logger.info('알림 설정: ${enabled ? '활성화' : '비활성화'}');
  }

  /// 사운드 이름 가져오기 (macOS)
  String _getSoundName(NotificationType type) {
    switch (type) {
      case NotificationType.success:
        return 'Glass';
      case NotificationType.error:
        return 'Basso';
      case NotificationType.warning:
        return 'Hero';
      default:
        return 'Pop';
    }
  }

  /// 긴급도 레벨 가져오기 (Linux)
  String _getUrgencyLevel(NotificationType type) {
    switch (type) {
      case NotificationType.error:
        return 'critical';
      case NotificationType.warning:
        return 'normal';
      default:
        return 'low';
    }
  }

  /// 아이콘 이름 가져오기 (Linux)
  String _getIconName(NotificationType type) {
    switch (type) {
      case NotificationType.success:
        return 'dialog-information';
      case NotificationType.error:
        return 'dialog-error';
      case NotificationType.warning:
        return 'dialog-warning';
      default:
        return 'dialog-information';
    }
  }
}

/// 알림 타입
enum NotificationType {
  info,
  success,
  warning,
  error,
}

/// 동기화 이벤트
class SyncEvent {
  final SyncEventType type;
  final String projectName;
  final String? fileName;
  final String? filePath;
  final String? error;

  SyncEvent({
    required this.type,
    required this.projectName,
    this.fileName,
    this.filePath,
    this.error,
  });
}

/// 동기화 이벤트 타입
enum SyncEventType {
  started,
  completed,
  failed,
  conflict,
}
