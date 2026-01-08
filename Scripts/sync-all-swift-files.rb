#!/usr/bin/env ruby
# Xcode 프로젝트에 모든 Swift 파일 자동 등록 (멱등)

require 'xcodeproj'

PROJECT_PATH = File.expand_path('../../Soju.xcodeproj', __FILE__)
SOURCE_ROOT = File.expand_path('../../Soju', __FILE__)

puts "🔧 Xcode 프로젝트 동기화..."
puts "프로젝트: #{PROJECT_PATH}"
puts "소스 루트: #{SOURCE_ROOT}"

# 프로젝트 열기
project = Xcodeproj::Project.open(PROJECT_PATH)

# Soju 타겟 찾기
target = project.targets.find { |t| t.name == 'Soju' }
unless target
  puts "❌ 'Soju' 타겟을 찾을 수 없습니다"
  exit 1
end

# 모든 Swift 파일 찾기 (재귀적)
all_swift_files = Dir.glob(File.join(SOURCE_ROOT, '**', '*.swift'))
puts "\n📂 발견된 Swift 파일: #{all_swift_files.size}개"

# 기존 소스 파일 제거
target.source_build_phase.files.clear
puts "🗑️  기존 빌드 파일 제거 완료"

# 프로젝트의 메인 그룹 찾기
main_group = project.main_group['Soju'] || project.main_group.new_group('Soju')

# 기존 파일 참조 제거
main_group.clear

puts "\n➕ Swift 파일 추가 중..."

added_count = 0
all_swift_files.each do |file_path|
  # 상대 경로 계산
  relative_path = Pathname.new(file_path).relative_path_from(Pathname.new(SOURCE_ROOT))

  # 파일 참조 추가
  file_ref = main_group.new_reference(file_path)
  file_ref.source_tree = 'SOURCE_ROOT'
  file_ref.path = File.join('Soju', relative_path)

  # 빌드 단계에 추가
  target.add_file_references([file_ref])

  added_count += 1
  print "."
end

puts "\n✅ #{added_count}개 파일 추가 완료"

# 프로젝트 저장
project.save
puts "💾 프로젝트 파일 저장 완료"

puts "\n✅ 동기화 완료!"
