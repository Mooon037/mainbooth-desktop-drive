/// 프로젝트 목록 아이템 위젯

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class ProjectListItem extends StatelessWidget {
  final Map<String, dynamic> project;
  final VoidCallback? onTap;

  const ProjectListItem({
    Key? key,
    required this.project,
    this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lastActivity = project['lastActivity'] as DateTime;
    final syncStatus = project['syncStatus'] as String;

    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // 프로젝트 아이콘
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.folder_special,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 16),

              // 프로젝트 정보
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            project['name'],
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        _buildSyncStatusIcon(syncStatus, theme),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          Icons.audiotrack,
                          size: 16,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${project['trackCount']}개 트랙',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Icon(
                          Icons.people,
                          size: 16,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${project['memberCount']}명',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '마지막 활동: ${_formatLastActivity(lastActivity)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color:
                            theme.colorScheme.onSurfaceVariant.withOpacity(0.7),
                      ),
                    ),
                  ],
                ),
              ),

              // 열기 버튼
              IconButton(
                icon: const Icon(Icons.arrow_forward_ios, size: 16),
                onPressed: onTap,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSyncStatusIcon(String status, ThemeData theme) {
    switch (status) {
      case 'synced':
        return Icon(
          Icons.cloud_done,
          size: 20,
          color: Colors.green,
        );
      case 'syncing':
        return SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(
              theme.colorScheme.primary,
            ),
          ),
        );
      case 'error':
        return Icon(
          Icons.cloud_off,
          size: 20,
          color: Colors.red,
        );
      default:
        return Icon(
          Icons.cloud_queue,
          size: 20,
          color: theme.colorScheme.onSurfaceVariant,
        );
    }
  }

  String _formatLastActivity(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inMinutes < 1) {
      return '방금 전';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}분 전';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}시간 전';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}일 전';
    } else {
      return DateFormat('yyyy.MM.dd').format(dateTime);
    }
  }
}
