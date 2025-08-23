# 릴리스 생성 가이드

## 1. 태그 생성 및 릴리스 트리거

```bash
# 1. 변경사항 커밋
git add .
git commit -m "Release v1.0.0 준비"

# 2. 태그 생성
git tag v1.0.0

# 3. 태그 푸시 (이것이 GitHub Actions 워크플로우를 트리거함)
git push origin v1.0.0
```

## 2. 수동 릴리스 생성 (GitHub 웹 인터페이스)

1. GitHub 저장소 페이지로 이동
2. "Releases" 탭 클릭
3. "Create a new release" 버튼 클릭
4. 태그 버전: `v1.0.0` 입력
5. 릴리스 제목: `Main Booth Drive v1.0.0` 입력
6. 설명 작성
7. 파일 업로드:
   - `MainBoothDrive-v1.0.0-mac.dmg`
   - `MainBoothDrive-v1.0.0-windows.exe`
   - `MainBoothDrive-v1.0.0-linux.AppImage`

## 3. 워크플로우 수동 실행

1. GitHub 저장소의 "Actions" 탭으로 이동
2. "Build and Release" 워크플로우 선택
3. "Run workflow" 버튼 클릭
4. 버전 입력 (예: 1.0.0)
5. "Run workflow" 실행

## 4. 릴리스 확인

릴리스가 성공적으로 생성되면:
- https://github.com/Mooon037/mainbooth-desktop-drive/releases 에서 확인 가능
- 웹사이트의 다운로드 링크가 자동으로 업데이트됨

## 5. 문제 해결

### 404 오류가 계속 발생하는 경우:
1. 릴리스가 실제로 생성되었는지 확인
2. 파일이 올바르게 업로드되었는지 확인
3. 저장소가 public인지 확인 (private인 경우 인증 필요)

### 빌드 실패 시:
1. GitHub Actions 로그 확인
2. 필요한 시크릿 변수들이 설정되어 있는지 확인:
   - `GITHUB_TOKEN` (자동 제공)
   - `MACOS_CERTIFICATE` (선택사항)
   - `WINDOWS_CERTIFICATE` (선택사항)
