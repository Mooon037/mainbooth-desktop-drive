/// Main Booth Drive 프로젝트 모델
/// 모바일 앱의 프로젝트 구조와 동기화되는 데스크탑 드라이브용 모델

class DriveProject {
  final String id;
  final String name;
  final String? description;
  final String? imageUrl;
  final String ownerId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isOwner;
  final String localPath;
  final SyncStatus syncStatus;

  DriveProject({
    required this.id,
    required this.name,
    this.description,
    this.imageUrl,
    required this.ownerId,
    required this.createdAt,
    required this.updatedAt,
    required this.isOwner,
    required this.localPath,
    this.syncStatus = SyncStatus.pending,
  });

  /// Firestore 데이터로부터 생성
  factory DriveProject.fromFirestore(
      Map<String, dynamic> data, String id, String localBasePath) {
    return DriveProject(
      id: id,
      name: data['name'] ?? '',
      description: data['description'],
      imageUrl: data['imageUrl'],
      ownerId: data['ownerId'] ?? '',
      createdAt: (data['createdAt'] as dynamic).toDate(),
      updatedAt: (data['updatedAt'] as dynamic).toDate(),
      isOwner: data['isOwner'] ?? false,
      localPath: '$localBasePath/Projects/$id',
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'imageUrl': imageUrl,
        'ownerId': ownerId,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'isOwner': isOwner,
        'localPath': localPath,
        'syncStatus': syncStatus.toString(),
      };
}

enum SyncStatus {
  pending, // ☁️ 클라우드만 있음
  synced, // ✅ 동기화 완료
  syncing, // 🔄 동기화 중
  error, // ⚠️ 오류
  conflict, // ⚠️ 충돌
}
