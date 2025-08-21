/// Main Booth Drive 트랙 모델
/// 프로젝트 내의 트랙을 관리하는 모델

class DriveTrack {
  final String id;
  final String projectId;
  final String name;
  final String audioUrl;
  final String? imageUrl;
  final String uploaderId;
  final String uploaderName;
  final int duration;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String localPath;
  final SyncStatus syncStatus;
  final int? fileSize;
  final String? fileHash;

  DriveTrack({
    required this.id,
    required this.projectId,
    required this.name,
    required this.audioUrl,
    this.imageUrl,
    required this.uploaderId,
    required this.uploaderName,
    required this.duration,
    required this.createdAt,
    required this.updatedAt,
    required this.localPath,
    this.syncStatus = SyncStatus.pending,
    this.fileSize,
    this.fileHash,
  });

  /// Firestore 데이터로부터 생성
  factory DriveTrack.fromFirestore(
    Map<String, dynamic> data,
    String id,
    String projectId,
    String projectLocalPath,
  ) {
    return DriveTrack(
      id: id,
      projectId: projectId,
      name: data['name'] ?? '',
      audioUrl: data['audioUrl'] ?? '',
      imageUrl: data['imageUrl'],
      uploaderId: data['uploaderId'] ?? '',
      uploaderName: data['uploaderName'] ?? '',
      duration: data['duration'] ?? 0,
      createdAt: (data['createdAt'] as dynamic).toDate(),
      updatedAt: (data['updatedAt'] as dynamic).toDate(),
      localPath: '$projectLocalPath/Tracks/${data['name']}.wav',
      fileSize: data['fileSize'],
      fileHash: data['fileHash'],
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'projectId': projectId,
        'name': name,
        'audioUrl': audioUrl,
        'imageUrl': imageUrl,
        'uploaderId': uploaderId,
        'uploaderName': uploaderName,
        'duration': duration,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'localPath': localPath,
        'syncStatus': syncStatus.toString(),
        'fileSize': fileSize,
        'fileHash': fileHash,
      };
}

/// 파일 동기화 상태
enum SyncStatus {
  pending, // ☁️ 클라우드만 있음
  synced, // ✅ 동기화 완료
  syncing, // 🔄 동기화 중
  error, // ⚠️ 오류
  conflict, // ⚠️ 충돌
  uploading, // ⬆️ 업로드 중
  downloading, // ⬇️ 다운로드 중
}
