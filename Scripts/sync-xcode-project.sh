#!/bin/bash
set -e

# Xcode 프로젝트 파일 동기화 스크립트 (멱등성 보장)
# 파일 시스템과 project.pbxproj를 동기화

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_FILE="$PROJECT_ROOT/Soju.xcodeproj/project.pbxproj"

echo "🔧 Xcode 프로젝트 동기화 시작..."
echo "프로젝트 루트: $PROJECT_ROOT"
echo "프로젝트 파일: $PROJECT_FILE"

# 백업 생성
BACKUP_FILE="${PROJECT_FILE}.backup-$(date +%Y%m%d-%H%M%S)"
cp "$PROJECT_FILE" "$BACKUP_FILE"
echo "✅ 백업 생성: $BACKUP_FILE"

# 레거시 파일 제거 (멱등)
echo ""
echo "🗑️  레거시 파일 참조 제거 중..."

LEGACY_FILES=(
    "DesktopView.swift"
    "DesktopIconView.swift"
    "DropZoneOverlay.swift"
    "ProgramStatusView.swift"
)

for file in "${LEGACY_FILES[@]}"; do
    if grep -q "$file" "$PROJECT_FILE"; then
        echo "  - $file 제거 중..."
        # UUID 라인 제거 (멱등: 없으면 아무 일도 안함)
        sed -i '' "/$file/d" "$PROJECT_FILE"
    else
        echo "  - $file (이미 제거됨)"
    fi
done

# 새 파일 확인
echo ""
echo "📋 새 파일 확인 중..."

NEW_FILES=(
    "ShortcutsGridView.swift:Soju/Views/Workspace"
    "ShortcutView.swift:Soju/Views/Workspace"
    "AddProgramView.swift:Soju/Views/Creation"
    "WorkspaceCreationView.swift:Soju/Views/Creation"
    "LogSettingsView.swift:Soju/Views/Settings"
    "InstallationProgressView.swift:Soju/Views/Installation"
    "ProgramSelectionView.swift:Soju/Views/Installation"
)

MISSING_FILES=()
for entry in "${NEW_FILES[@]}"; do
    filename="${entry%%:*}"
    if grep -q "$filename" "$PROJECT_FILE"; then
        echo "  ✅ $filename (프로젝트에 있음)"
    else
        echo "  ⚠️  $filename (프로젝트에 없음 - Xcode에서 수동 추가 필요)"
        MISSING_FILES+=("$filename")
    fi
done

# 결과 출력
echo ""
if [ ${#MISSING_FILES[@]} -eq 0 ]; then
    echo "✅ 모든 파일이 동기화되었습니다!"
    rm "$BACKUP_FILE"
    echo "백업 삭제됨 (변경사항 없음)"
else
    echo "⚠️  다음 파일들을 Xcode에서 수동으로 추가해야 합니다:"
    for file in "${MISSING_FILES[@]}"; do
        echo "   - $file"
    done
    echo ""
    echo "백업 유지됨: $BACKUP_FILE"
fi

# 빌드 테스트
echo ""
echo "🔨 빌드 테스트 중..."
if xcodebuild -scheme Soju -configuration Debug -quiet build 2>&1 | grep -q "BUILD SUCCEEDED"; then
    echo "✅ 빌드 성공!"
    exit 0
else
    echo "❌ 빌드 실패 - 로그 확인 필요"
    echo ""
    echo "복원하려면: cp $BACKUP_FILE $PROJECT_FILE"
    exit 1
fi
