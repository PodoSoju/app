#!/usr/bin/env python3
"""
Xcode 프로젝트에 파일 자동 추가 (멱등성 보장)
"""
import sys
import re
import uuid
from pathlib import Path

def generate_uuid():
    """24자 Xcode UUID 생성"""
    return uuid.uuid4().hex[:24].upper()

def find_group_uuid(content, group_name):
    """PBXGroup에서 특정 그룹의 UUID 찾기"""
    # /* Views */ = { 패턴 찾기
    pattern = rf'([A-F0-9]{{24}}) /\* {re.escape(group_name)} \*/ = \{{'
    match = re.search(pattern, content)
    return match.group(1) if match else None

def file_exists_in_project(content, filename):
    """파일이 이미 프로젝트에 있는지 확인"""
    return filename in content

def add_file_reference(content, filename, filepath):
    """PBXFileReference 섹션에 파일 추가"""
    file_uuid = generate_uuid()

    # PBXFileReference 섹션 찾기
    section_start = content.find('/* Begin PBXFileReference section */')
    section_end = content.find('/* End PBXFileReference section */', section_start)

    if section_start == -1:
        return content, None

    # 새 파일 참조 생성
    file_ref = f'\t\t{file_uuid} /* {filename} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {filename}; sourceTree = "<group>"; }};\n'

    # 섹션 끝에 추가
    insert_pos = section_end
    content = content[:insert_pos] + file_ref + content[insert_pos:]

    return content, file_uuid

def add_build_file(content, filename, file_uuid):
    """PBXBuildFile 섹션에 빌드 파일 추가"""
    build_uuid = generate_uuid()

    section_start = content.find('/* Begin PBXBuildFile section */')
    section_end = content.find('/* End PBXBuildFile section */', section_start)

    if section_start == -1:
        return content, None

    # 새 빌드 파일 생성
    build_file = f'\t\t{build_uuid} /* {filename} in Sources */ = {{isa = PBXBuildFile; fileRef = {file_uuid} /* {filename} */; }};\n'

    insert_pos = section_end
    content = content[:insert_pos] + build_file + content[insert_pos:]

    return content, build_uuid

def add_to_group(content, group_name, filename, file_uuid):
    """PBXGroup에 파일 추가"""
    group_uuid = find_group_uuid(content, group_name)
    if not group_uuid:
        print(f"⚠️  그룹 '{group_name}' 찾을 수 없음")
        return content

    # 그룹 찾기
    group_pattern = rf'{group_uuid} /\* {re.escape(group_name)} \*/ = \{{[^}}]+children = \([^)]+\);'
    match = re.search(group_pattern, content, re.DOTALL)

    if not match:
        print(f"⚠️  그룹 '{group_name}' children 찾을 수 없음")
        return content

    # children 배열에 추가
    group_text = match.group(0)
    children_end = group_text.rfind(');')

    if children_end == -1:
        return content

    # 새 파일 참조 추가
    file_entry = f'\t\t\t\t{file_uuid} /* {filename} */,\n'
    new_group_text = group_text[:children_end] + file_entry + group_text[children_end:]

    content = content.replace(group_text, new_group_text)
    return content

def add_to_sources_build_phase(content, filename, build_uuid):
    """PBXSourcesBuildPhase에 파일 추가"""
    # Soju 타겟의 Sources 섹션 찾기
    pattern = r'([A-F0-9]{24}) /\* Sources \*/ = \{[^}]+isa = PBXSourcesBuildPhase;[^}]+files = \([^)]+\);'
    match = re.search(pattern, content, re.DOTALL)

    if not match:
        print("⚠️  PBXSourcesBuildPhase 찾을 수 없음")
        return content

    phase_text = match.group(0)
    files_end = phase_text.rfind(');')

    if files_end == -1:
        return content

    # files 배열에 추가
    file_entry = f'\t\t\t\t{build_uuid} /* {filename} in Sources */,\n'
    new_phase_text = phase_text[:files_end] + file_entry + phase_text[files_end:]

    content = content.replace(phase_text, new_phase_text)
    return content

def add_file_to_project(content, filename, group_name):
    """파일을 프로젝트에 추가 (멱등)"""
    # 이미 있으면 스킵
    if file_exists_in_project(content, filename):
        print(f"  ✅ {filename} (이미 프로젝트에 있음)")
        return content, True

    print(f"  ➕ {filename} 추가 중...")

    # 1. PBXFileReference 추가
    content, file_uuid = add_file_reference(content, filename, f"{group_name}/{filename}")
    if not file_uuid:
        print(f"  ❌ {filename} - FileReference 추가 실패")
        return content, False

    # 2. PBXBuildFile 추가
    content, build_uuid = add_build_file(content, filename, file_uuid)
    if not build_uuid:
        print(f"  ❌ {filename} - BuildFile 추가 실패")
        return content, False

    # 3. PBXGroup에 추가
    content = add_to_group(content, group_name, filename, file_uuid)

    # 4. PBXSourcesBuildPhase에 추가
    content = add_to_sources_build_phase(content, filename, build_uuid)

    print(f"  ✅ {filename} 추가 완료")
    return content, True

def main():
    project_file = Path(__file__).parent.parent / "Soju.xcodeproj" / "project.pbxproj"

    if not project_file.exists():
        print(f"❌ 프로젝트 파일 없음: {project_file}")
        sys.exit(1)

    print(f"📂 프로젝트 파일: {project_file}")

    # 프로젝트 파일 읽기
    content = project_file.read_text(encoding='utf-8')
    original_content = content

    # 추가할 파일들
    files_to_add = [
        ("ShortcutsGridView.swift", "Workspace"),
        ("ShortcutView.swift", "Workspace"),
        ("AddProgramView.swift", "Creation"),
        ("WorkspaceCreationView.swift", "Creation"),
        ("LogSettingsView.swift", "Settings"),
    ]

    print("\n📋 파일 추가 중...")
    all_success = True

    for filename, group in files_to_add:
        content, success = add_file_to_project(content, filename, group)
        if not success:
            all_success = False

    # 변경사항이 있으면 저장
    if content != original_content:
        project_file.write_text(content, encoding='utf-8')
        print("\n✅ 프로젝트 파일 업데이트 완료")
    else:
        print("\n✅ 변경사항 없음 (모든 파일이 이미 추가됨)")

    sys.exit(0 if all_success else 1)

if __name__ == "__main__":
    main()
