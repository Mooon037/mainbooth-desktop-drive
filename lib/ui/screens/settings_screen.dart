/// 설정 화면

import 'package:flutter/material.dart';
import '../../core/drive_manager.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final DriveManager _driveManager = DriveManager.instance;

  bool _isLoading = true;
  Map<String, dynamic> _settings = {};

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final settings = await _driveManager.loadSettings();
    setState(() {
      _settings = settings;
      _isLoading = false;
    });
  }

  Future<void> _saveSettings() async {
    setState(() {
      _isLoading = true;
    });

    try {
      await _driveManager.updateSettings(_settings);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('설정이 저장되었습니다')),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('설정 저장 실패: $e')),
        );
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('설정'),
        actions: [
          TextButton(
            onPressed: _isLoading ? null : _saveSettings,
            child: const Text('저장'),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 일반 설정
                  _buildSectionTitle('일반'),
                  Card(
                    child: Column(
                      children: [
                        SwitchListTile(
                          title: const Text('시스템 시작 시 자동 실행'),
                          subtitle: const Text(
                              '컴퓨터가 시작될 때 Main Booth Drive를 자동으로 실행합니다'),
                          value: _settings['autoStart'] ?? true,
                          onChanged: (value) {
                            setState(() {
                              _settings['autoStart'] = value;
                            });
                          },
                        ),
                        const Divider(height: 1),
                        SwitchListTile(
                          title: const Text('알림 활성화'),
                          subtitle: const Text('동기화 상태 및 오류에 대한 알림을 표시합니다'),
                          value: _settings['notifications'] ?? true,
                          onChanged: (value) {
                            setState(() {
                              _settings['notifications'] = value;
                            });
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // 동기화 설정
                  _buildSectionTitle('동기화'),
                  Card(
                    child: Column(
                      children: [
                        ListTile(
                          title: const Text('동기화 간격'),
                          subtitle: Text('${_settings['syncInterval'] ?? 30}초'),
                          trailing:
                              const Icon(Icons.arrow_forward_ios, size: 16),
                          onTap: () => _showSyncIntervalDialog(),
                        ),
                        const Divider(height: 1),
                        SwitchListTile(
                          title: const Text('선택적 동기화'),
                          subtitle: const Text('특정 프로젝트만 동기화합니다'),
                          value: _settings['selectiveSync'] ?? false,
                          onChanged: (value) {
                            setState(() {
                              _settings['selectiveSync'] = value;
                            });
                          },
                        ),
                        const Divider(height: 1),
                        ListTile(
                          title: const Text('충돌 해결 방법'),
                          subtitle: Text(_getConflictResolutionText(
                              _settings['conflictResolution'] ?? 'ask')),
                          trailing:
                              const Icon(Icons.arrow_forward_ios, size: 16),
                          onTap: () => _showConflictResolutionDialog(),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // 저장소 설정
                  _buildSectionTitle('저장소'),
                  Card(
                    child: Column(
                      children: [
                        ListTile(
                          title: const Text('최대 캐시 크기'),
                          subtitle: Text(_formatFileSize(
                              _settings['maxCacheSize'] ??
                                  5 * 1024 * 1024 * 1024)),
                          trailing:
                              const Icon(Icons.arrow_forward_ios, size: 16),
                          onTap: () => _showMaxCacheSizeDialog(),
                        ),
                        const Divider(height: 1),
                        ListTile(
                          title: const Text('드라이브 위치'),
                          subtitle: Text(_driveManager.isRunning
                              ? '변경하려면 드라이브를 정지하세요'
                              : '클릭하여 변경'),
                          enabled: !_driveManager.isRunning,
                          trailing:
                              const Icon(Icons.arrow_forward_ios, size: 16),
                          onTap: _driveManager.isRunning
                              ? null
                              : () => _showDriveLocationDialog(),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // 정보
                  _buildSectionTitle('정보'),
                  Card(
                    child: Column(
                      children: [
                        ListTile(
                          title: const Text('버전'),
                          subtitle: const Text('1.0.0'),
                        ),
                        const Divider(height: 1),
                        ListTile(
                          title: const Text('로그 보기'),
                          trailing:
                              const Icon(Icons.arrow_forward_ios, size: 16),
                          onTap: () {
                            // TODO: 로그 화면으로 이동
                          },
                        ),
                        const Divider(height: 1),
                        ListTile(
                          title: const Text('도움말'),
                          trailing: const Icon(Icons.open_in_new, size: 16),
                          onTap: () {
                            // TODO: 도움말 페이지 열기
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.primary,
            ),
      ),
    );
  }

  void _showSyncIntervalDialog() {
    final controller = TextEditingController(
      text: (_settings['syncInterval'] ?? 30).toString(),
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('동기화 간격'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: '초',
            helperText: '10 ~ 300초 사이의 값을 입력하세요',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () {
              final value = int.tryParse(controller.text);
              if (value != null && value >= 10 && value <= 300) {
                setState(() {
                  _settings['syncInterval'] = value;
                });
                Navigator.pop(context);
              }
            },
            child: const Text('확인'),
          ),
        ],
      ),
    );
  }

  void _showConflictResolutionDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('충돌 해결 방법'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RadioListTile<String>(
              title: const Text('항상 물어보기'),
              subtitle: const Text('충돌이 발생하면 어떻게 할지 묻습니다'),
              value: 'ask',
              groupValue: _settings['conflictResolution'] ?? 'ask',
              onChanged: (value) {
                setState(() {
                  _settings['conflictResolution'] = value;
                });
                Navigator.pop(context);
              },
            ),
            RadioListTile<String>(
              title: const Text('로컬 우선'),
              subtitle: const Text('로컬 파일을 유지합니다'),
              value: 'local',
              groupValue: _settings['conflictResolution'] ?? 'ask',
              onChanged: (value) {
                setState(() {
                  _settings['conflictResolution'] = value;
                });
                Navigator.pop(context);
              },
            ),
            RadioListTile<String>(
              title: const Text('원격 우선'),
              subtitle: const Text('서버 파일로 덮어씁니다'),
              value: 'remote',
              groupValue: _settings['conflictResolution'] ?? 'ask',
              onChanged: (value) {
                setState(() {
                  _settings['conflictResolution'] = value;
                });
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showMaxCacheSizeDialog() {
    final sizes = [
      1 * 1024 * 1024 * 1024, // 1GB
      2 * 1024 * 1024 * 1024, // 2GB
      5 * 1024 * 1024 * 1024, // 5GB
      10 * 1024 * 1024 * 1024, // 10GB
    ];

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('최대 캐시 크기'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: sizes.map((size) {
            return RadioListTile<int>(
              title: Text(_formatFileSize(size)),
              value: size,
              groupValue: _settings['maxCacheSize'] ?? 5 * 1024 * 1024 * 1024,
              onChanged: (value) {
                setState(() {
                  _settings['maxCacheSize'] = value;
                });
                Navigator.pop(context);
              },
            );
          }).toList(),
        ),
      ),
    );
  }

  void _showDriveLocationDialog() {
    // TODO: 폴더 선택 다이얼로그 구현
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('폴더 선택 기능은 준비 중입니다')),
    );
  }

  String _getConflictResolutionText(String value) {
    switch (value) {
      case 'ask':
        return '항상 물어보기';
      case 'local':
        return '로컬 우선';
      case 'remote':
        return '원격 우선';
      default:
        return '항상 물어보기';
    }
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(0)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(0)} GB';
  }
}
