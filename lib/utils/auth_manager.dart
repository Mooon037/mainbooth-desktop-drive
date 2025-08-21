/// 인증 관리자
/// Firebase 인증 및 사용자 정보 관리

import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../config/drive_config.dart';
import 'file_utils.dart';
import 'logger.dart';

class AuthManager {
  static AuthManager? _instance;
  static AuthManager get instance => _instance ??= AuthManager._();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final Logger _logger = Logger('AuthManager');

  User? _currentUser;
  Map<String, dynamic>? _userProfile;

  AuthManager._();

  /// 현재 사용자
  User? get currentUser => _currentUser;

  /// 사용자 프로필
  Map<String, dynamic>? get userProfile => _userProfile;

  /// 사용자 ID
  String? get userId => _currentUser?.uid;

  /// 사용자 이름
  String get userName =>
      _userProfile?['name'] ?? _currentUser?.displayName ?? 'Unknown User';

  /// 로그인 상태
  bool get isAuthenticated => _currentUser != null;

  /// 초기화
  Future<void> initialize() async {
    try {
      // 저장된 인증 정보 로드
      await _loadStoredAuth();

      // 인증 상태 리스너
      _auth.authStateChanges().listen((user) {
        _handleAuthStateChange(user);
      });

      // 현재 사용자 확인
      _currentUser = _auth.currentUser;
      if (_currentUser != null) {
        await _loadUserProfile();
      }
    } catch (e) {
      _logger.error('인증 초기화 실패', e);
    }
  }

  /// 이메일 로그인
  Future<bool> signInWithEmail(String email, String password) async {
    try {
      _logger.info('이메일 로그인 시도: $email');

      final credential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      if (credential.user != null) {
        _currentUser = credential.user;
        await _loadUserProfile();
        await _saveAuthInfo();

        _logger.info('로그인 성공: ${_currentUser!.uid}');
        return true;
      }

      return false;
    } on FirebaseAuthException catch (e) {
      _logger.error('로그인 실패: ${e.code}', e);
      throw _handleAuthException(e);
    } catch (e) {
      _logger.error('로그인 실패', e);
      rethrow;
    }
  }

  /// 로그아웃
  Future<void> signOut() async {
    try {
      await _auth.signOut();
      _currentUser = null;
      _userProfile = null;
      await _clearAuthInfo();

      _logger.info('로그아웃 완료');
    } catch (e) {
      _logger.error('로그아웃 실패', e);
      rethrow;
    }
  }

  /// 토큰 갱신
  Future<String?> getIdToken({bool forceRefresh = false}) async {
    try {
      if (_currentUser == null) return null;

      return await _currentUser!.getIdToken(forceRefresh);
    } catch (e) {
      _logger.error('토큰 갱신 실패', e);
      return null;
    }
  }

  /// 사용자 프로필 로드
  Future<void> _loadUserProfile() async {
    if (_currentUser == null) return;

    try {
      final doc =
          await _firestore.collection('users').doc(_currentUser!.uid).get();

      if (doc.exists) {
        _userProfile = doc.data();
        _logger.info('사용자 프로필 로드 완료: ${_userProfile?['name']}');
      }
    } catch (e) {
      _logger.error('사용자 프로필 로드 실패', e);
    }
  }

  /// 인증 상태 변경 처리
  void _handleAuthStateChange(User? user) {
    _currentUser = user;

    if (user != null) {
      _logger.info('인증 상태 변경: 로그인 - ${user.uid}');
      _loadUserProfile();
    } else {
      _logger.info('인증 상태 변경: 로그아웃');
      _userProfile = null;
    }
  }

  /// 인증 정보 저장 (로컬)
  Future<void> _saveAuthInfo() async {
    if (_currentUser == null) return;

    try {
      final authData = {
        'uid': _currentUser!.uid,
        'email': _currentUser!.email,
        'lastSignIn': DateTime.now().toIso8601String(),
      };

      final authPath = '${DriveConfig.configPath}/auth.json';
      await FileUtils.writeJsonFile(authPath, authData);
    } catch (e) {
      _logger.error('인증 정보 저장 실패', e);
    }
  }

  /// 저장된 인증 정보 로드
  Future<void> _loadStoredAuth() async {
    try {
      final authPath = '${DriveConfig.configPath}/auth.json';
      final authData = await FileUtils.readJsonFile(authPath);

      if (authData != null) {
        _logger.info('저장된 인증 정보 발견: ${authData['email']}');
      }
    } catch (e) {
      _logger.error('인증 정보 로드 실패', e);
    }
  }

  /// 인증 정보 삭제
  Future<void> _clearAuthInfo() async {
    try {
      final authPath = '${DriveConfig.configPath}/auth.json';
      final authFile = File(authPath);

      if (await authFile.exists()) {
        await authFile.delete();
      }
    } catch (e) {
      _logger.error('인증 정보 삭제 실패', e);
    }
  }

  /// Firebase 인증 예외 처리
  String _handleAuthException(FirebaseAuthException e) {
    switch (e.code) {
      case 'user-not-found':
        return '사용자를 찾을 수 없습니다.';
      case 'wrong-password':
        return '비밀번호가 올바르지 않습니다.';
      case 'email-already-in-use':
        return '이미 사용 중인 이메일입니다.';
      case 'invalid-email':
        return '올바른 이메일 형식이 아닙니다.';
      case 'weak-password':
        return '비밀번호가 너무 약합니다.';
      case 'network-request-failed':
        return '네트워크 연결을 확인해주세요.';
      case 'too-many-requests':
        return '너무 많은 시도가 있었습니다. 잠시 후 다시 시도해주세요.';
      default:
        return '인증 오류가 발생했습니다: ${e.message}';
    }
  }

  /// 비밀번호 재설정 이메일 전송
  Future<void> sendPasswordResetEmail(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
      _logger.info('비밀번호 재설정 이메일 전송: $email');
    } on FirebaseAuthException catch (e) {
      _logger.error('비밀번호 재설정 실패: ${e.code}', e);
      throw _handleAuthException(e);
    }
  }

  /// 이메일 인증 여부
  bool get isEmailVerified => _currentUser?.emailVerified ?? false;

  /// 이메일 인증 메일 재전송
  Future<void> sendEmailVerification() async {
    try {
      if (_currentUser != null && !isEmailVerified) {
        await _currentUser!.sendEmailVerification();
        _logger.info('이메일 인증 메일 전송');
      }
    } catch (e) {
      _logger.error('이메일 인증 메일 전송 실패', e);
      rethrow;
    }
  }

  /// 사용자 권한 확인
  Future<bool> hasPermission(String projectId, String action) async {
    if (_currentUser == null) return false;

    try {
      // 프로젝트 문서 확인
      final projectDoc =
          await _firestore.collection('projects').doc(projectId).get();

      if (!projectDoc.exists) return false;

      final projectData = projectDoc.data()!;
      final isOwner = projectData['ownerId'] == _currentUser!.uid;

      // 소유자는 모든 권한
      if (isOwner) return true;

      // 협업자 권한 확인
      final collaborators =
          List<Map<String, dynamic>>.from(projectData['collaborators'] ?? []);
      final collaborator = collaborators.firstWhere(
        (c) => c['userId'] == _currentUser!.uid,
        orElse: () => {},
      );

      if (collaborator.isEmpty) return false;

      // 액션별 권한 확인
      final role = collaborator['role'] ?? 'member';
      return _checkRolePermission(role, action);
    } catch (e) {
      _logger.error('권한 확인 실패', e);
      return false;
    }
  }

  bool _checkRolePermission(String role, String action) {
    switch (role) {
      case 'admin':
        return true; // 관리자는 모든 권한
      case 'member':
        return !['delete_project', 'delete_track', 'manage_members']
            .contains(action);
      default:
        return false;
    }
  }
}
