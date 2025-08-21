/// Main Booth Drive 작업 요청 모델
/// 프로젝트의 작업 요청 및 피드백을 관리하는 모델

class DriveWorkRequest {
  final String id;
  final String projectId;
  final String title;
  final String content;
  final String requesterId;
  final String requesterName;
  final List<String> attachmentUrls;
  final RequestStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String localPath;
  final List<WorkRequestComment> comments;

  DriveWorkRequest({
    required this.id,
    required this.projectId,
    required this.title,
    required this.content,
    required this.requesterId,
    required this.requesterName,
    this.attachmentUrls = const [],
    this.status = RequestStatus.pending,
    required this.createdAt,
    required this.updatedAt,
    required this.localPath,
    this.comments = const [],
  });

  /// Firestore 데이터로부터 생성
  factory DriveWorkRequest.fromFirestore(
    Map<String, dynamic> data,
    String id,
    String projectId,
    String projectLocalPath,
  ) {
    return DriveWorkRequest(
      id: id,
      projectId: projectId,
      title: data['title'] ?? '',
      content: data['content'] ?? '',
      requesterId: data['requesterId'] ?? '',
      requesterName: data['requesterName'] ?? '',
      attachmentUrls: List<String>.from(data['attachmentUrls'] ?? []),
      status: _parseStatus(data['status']),
      createdAt: (data['createdAt'] as dynamic).toDate(),
      updatedAt: (data['updatedAt'] as dynamic).toDate(),
      localPath: '$projectLocalPath/WorkRequests/${data['title']}.md',
      comments: (data['comments'] as List<dynamic>? ?? [])
          .map((c) => WorkRequestComment.fromMap(c))
          .toList(),
    );
  }

  static RequestStatus _parseStatus(String? status) {
    switch (status) {
      case 'pending':
        return RequestStatus.pending;
      case 'in_progress':
        return RequestStatus.inProgress;
      case 'completed':
        return RequestStatus.completed;
      case 'cancelled':
        return RequestStatus.cancelled;
      default:
        return RequestStatus.pending;
    }
  }

  /// 로컬 마크다운 파일로 변환
  String toMarkdown() {
    final buffer = StringBuffer();
    buffer.writeln('# $title');
    buffer.writeln();
    buffer.writeln('**요청자:** $requesterName');
    buffer.writeln('**생성일:** ${createdAt.toLocal()}');
    buffer.writeln('**상태:** ${_statusToKorean(status)}');
    buffer.writeln();
    buffer.writeln('## 내용');
    buffer.writeln(content);

    if (attachmentUrls.isNotEmpty) {
      buffer.writeln();
      buffer.writeln('## 첨부파일');
      for (var url in attachmentUrls) {
        buffer.writeln('- $url');
      }
    }

    if (comments.isNotEmpty) {
      buffer.writeln();
      buffer.writeln('## 댓글');
      for (var comment in comments) {
        buffer.writeln();
        buffer.writeln(
            '### ${comment.authorName} - ${comment.createdAt.toLocal()}');
        buffer.writeln(comment.content);
      }
    }

    return buffer.toString();
  }

  String _statusToKorean(RequestStatus status) {
    switch (status) {
      case RequestStatus.pending:
        return '대기 중';
      case RequestStatus.inProgress:
        return '진행 중';
      case RequestStatus.completed:
        return '완료';
      case RequestStatus.cancelled:
        return '취소됨';
    }
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'projectId': projectId,
        'title': title,
        'content': content,
        'requesterId': requesterId,
        'requesterName': requesterName,
        'attachmentUrls': attachmentUrls,
        'status': status.toString().split('.').last,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'localPath': localPath,
        'comments': comments.map((c) => c.toMap()).toList(),
      };
}

/// 작업 요청 상태
enum RequestStatus {
  pending,
  inProgress,
  completed,
  cancelled,
}

/// 작업 요청 댓글
class WorkRequestComment {
  final String id;
  final String authorId;
  final String authorName;
  final String content;
  final DateTime createdAt;

  WorkRequestComment({
    required this.id,
    required this.authorId,
    required this.authorName,
    required this.content,
    required this.createdAt,
  });

  factory WorkRequestComment.fromMap(Map<String, dynamic> map) {
    return WorkRequestComment(
      id: map['id'] ?? '',
      authorId: map['authorId'] ?? '',
      authorName: map['authorName'] ?? '',
      content: map['content'] ?? '',
      createdAt: (map['createdAt'] as dynamic).toDate(),
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'authorId': authorId,
        'authorName': authorName,
        'content': content,
        'createdAt': createdAt.toIso8601String(),
      };
}
