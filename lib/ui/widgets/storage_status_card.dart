/// 저장소 상태 카드 위젯

import 'package:flutter/material.dart';
import '../../core/status_manager.dart';

class StorageStatusCard extends StatelessWidget {
  final StorageStatus storageStatus;

  const StorageStatusCard({
    Key? key,
    required this.storageStatus,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.storage,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  '저장소 사용량',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // 전체 사용량
            Row(
              children: [
                Text(
                  _formatFileSize(storageStatus.totalSize),
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '사용 중',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // 사용량 막대
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: storageStatus.totalSize /
                    (5 * 1024 * 1024 * 1024), // 5GB 기준
                minHeight: 8,
                backgroundColor: theme.colorScheme.surfaceVariant,
              ),
            ),
            const SizedBox(height: 16),

            // 세부 사용량
            Row(
              children: [
                Expanded(
                  child: _buildStorageDetail(
                    context,
                    icon: Icons.folder_open,
                    label: '드라이브',
                    size: storageStatus.driveSize,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildStorageDetail(
                    context,
                    icon: Icons.cached,
                    label: '캐시',
                    size: storageStatus.cacheSize,
                    color: theme.colorScheme.secondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // 캐시 정리 버튼
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  _showClearCacheDialog(context);
                },
                icon: const Icon(Icons.cleaning_services, size: 20),
                label: const Text('캐시 정리'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStorageDetail(
    BuildContext context, {
    required IconData icon,
    required String label,
    required int size,
    required Color color,
  }) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 4),
              Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            _formatFileSize(size),
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  void _showClearCacheDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('캐시 정리'),
        content: Text(
          '캐시를 정리하면 ${_formatFileSize(storageStatus.cacheSize)}의 공간을 확보할 수 있습니다.\n\n'
          '캐시된 파일은 필요할 때 다시 다운로드됩니다.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              // TODO: 캐시 정리 실행
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('캐시를 정리했습니다'),
                ),
              );
            },
            child: const Text('정리'),
          ),
        ],
      ),
    );
  }
}
