/// 메인 화면
/// 드라이브 상태와 프로젝트 목록을 표시

import 'package:flutter/material.dart';
import 'dart:async';
import '../../core/drive_manager.dart';
import '../../core/status_manager.dart';
import '../../utils/file_utils.dart';
import '../widgets/project_list_item.dart';
import '../widgets/sync_status_card.dart';
import '../widgets/storage_status_card.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({Key? key}) : super(key: key);

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  final DriveManager _driveManager = DriveManager.instance;
  final StatusManager _statusManager = StatusManager.instance;

  StreamSubscription<DriveStatus>? _driveStatusSub;
  StreamSubscription<SyncStatus>? _syncStatusSub;
  StreamSubscription<StorageStatus>? _storageStatusSub;

  DriveStatus _driveStatus = DriveStatus.stopped;
  SyncStatus _syncStatus = SyncStatus();
  StorageStatus _storageStatus = StorageStatus();
  List<Map<String, dynamic>> _projects = [];

  @override
  void initState() {
    super.initState();
    _setupListeners();
    _loadProjects();
  }

  @override
  void dispose() {
    _driveStatusSub?.cancel();
    _syncStatusSub?.cancel();
    _storageStatusSub?.cancel();
    super.dispose();
  }

  void _setupListeners() {
    _driveStatusSub = _statusManager.driveStatusStream.listen((status) {
      setState(() {
        _driveStatus = status;
      });
    });

    _syncStatusSub = _statusManager.syncStatusStream.listen((status) {
      setState(() {
        _syncStatus = status;
      });
    });

    _storageStatusSub = _statusManager.storageStatusStream.listen((status) {
      setState(() {
        _storageStatus = status;
      });
    });
  }

  Future<void> _loadProjects() async {
    // TODO: 실제 프로젝트 목록 로드
    setState(() {
      _projects = [
        {
          'id': '1',
          'name': 'Summer Album 2024',
          'trackCount': 12,
          'memberCount': 4,
          'lastActivity': DateTime.now().subtract(Duration(minutes: 30)),
          'syncStatus': 'synced',
        },
        {
          'id': '2',
          'name': 'Collaboration with Artist X',
          'trackCount': 5,
          'memberCount': 2,
          'lastActivity': DateTime.now().subtract(Duration(hours: 2)),
          'syncStatus': 'syncing',
        },
      ];
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: Column(
        children: [
          // 커스텀 타이틀바
          _buildTitleBar(theme),

          // 콘텐츠
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 사용자 정보
                  _buildUserInfo(theme),
                  const SizedBox(height: 24),

                  // 드라이브 상태
                  _buildDriveStatus(theme),
                  const SizedBox(height: 16),

                  // 동기화 상태
                  if (_driveStatus == DriveStatus.running) ...[
                    SyncStatusCard(syncStatus: _syncStatus),
                    const SizedBox(height: 16),
                  ],

                  // 저장소 상태
                  StorageStatusCard(storageStatus: _storageStatus),
                  const SizedBox(height: 24),

                  // 프로젝트 목록
                  _buildProjectList(theme),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTitleBar(ThemeData theme) {
    return Container(
      height: 52,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: theme.colorScheme.outlineVariant.withOpacity(0.5),
          ),
        ),
      ),
      child: Row(
        children: [
          const SizedBox(width: 16),
          Icon(
            Icons.cloud_queue,
            color: theme.colorScheme.primary,
            size: 24,
          ),
          const SizedBox(width: 8),
          Text(
            'Main Booth Drive',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const Spacer(),
          // 창 컨트롤 버튼
          IconButton(
            icon: const Icon(Icons.minimize, size: 20),
            onPressed: () {
              // 최소화
            },
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 20),
            onPressed: () {
              // 닫기 (숨기기)
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }

  Widget _buildUserInfo(ThemeData theme) {
    return Row(
      children: [
        CircleAvatar(
          radius: 24,
          backgroundColor: theme.colorScheme.primaryContainer,
          child: Text(
            _driveManager.userName.substring(0, 1).toUpperCase(),
            style: TextStyle(
              color: theme.colorScheme.onPrimaryContainer,
              fontWeight: FontWeight.bold,
              fontSize: 20,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _driveManager.userName,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              '${_projects.length}개 프로젝트',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const Spacer(),
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert),
          onSelected: (value) {
            switch (value) {
              case 'settings':
                Navigator.pushNamed(context, '/settings');
                break;
              case 'logout':
                _driveManager.signOut();
                break;
            }
          },
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'settings',
              child: Row(
                children: [
                  Icon(Icons.settings_outlined, size: 20),
                  SizedBox(width: 12),
                  Text('설정'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'logout',
              child: Row(
                children: [
                  Icon(Icons.logout, size: 20),
                  SizedBox(width: 12),
                  Text('로그아웃'),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDriveStatus(ThemeData theme) {
    IconData icon;
    String status;
    Color color;

    switch (_driveStatus) {
      case DriveStatus.running:
        icon = Icons.check_circle;
        status = '실행 중';
        color = Colors.green;
        break;
      case DriveStatus.stopped:
        icon = Icons.pause_circle;
        status = '정지됨';
        color = Colors.orange;
        break;
      case DriveStatus.error:
        icon = Icons.error;
        status = '오류';
        color = Colors.red;
        break;
      default:
        icon = Icons.sync;
        status = '준비 중';
        color = theme.colorScheme.primary;
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(icon, color: color, size: 32),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '드라이브 상태',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                Text(
                  status,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ],
            ),
            const Spacer(),
            FilledButton.tonal(
              onPressed: () async {
                if (_driveStatus == DriveStatus.running) {
                  await _driveManager.stop();
                } else {
                  await _driveManager.start();
                }
              },
              child: Text(
                _driveStatus == DriveStatus.running ? '정지' : '시작',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProjectList(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              '프로젝트',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: _loadProjects,
              icon: const Icon(Icons.refresh, size: 20),
              label: const Text('새로고침'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_projects.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Center(
                child: Column(
                  children: [
                    Icon(
                      Icons.folder_off_outlined,
                      size: 64,
                      color:
                          theme.colorScheme.onSurfaceVariant.withOpacity(0.5),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '프로젝트가 없습니다',
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '모바일 앱에서 프로젝트를 생성하거나\n초대를 받아보세요',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color:
                            theme.colorScheme.onSurfaceVariant.withOpacity(0.7),
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          )
        else
          ...List.generate(
            _projects.length,
            (index) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: ProjectListItem(
                project: _projects[index],
                onTap: () {
                  _driveManager.openProject(_projects[index]['id']);
                },
              ),
            ),
          ),
      ],
    );
  }
}
