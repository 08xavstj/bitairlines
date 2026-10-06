#!/usr/bin/env ruby
# Generates BitAirlines.xcodeproj from the folders on disk (like XcodeGen). The project file is a build artifact:
# re-run this script after adding or removing source files, and do not hand-edit the project.
#
#   ruby tools/generate_xcodeproj.rb
#
# Requires the `xcodeproj` gem (installed with CocoaPods, or: gem install xcodeproj).
require 'xcodeproj'
require 'fileutils'

ROOT = File.expand_path('..', __dir__)
PROJECT_PATH = File.join(ROOT, 'BitAirlines.xcodeproj')

APP_NAME = 'BitAirlines'
TEST_NAME = 'BitAirlinesTests'
DISPLAY_NAME = 'Pixel Props'                       # the name under the icon
BUNDLE_ID = 'ca.amaruq.bitairlines'                # change freely until the first App Store upload; permanent after that
DEVELOPMENT_TEAM = 'AKLDHPSZ33'                    # personal team (Apple Development certificate); not a secret
DEPLOYMENT_TARGET = '17.0'
# iCloud saves and Game Center need a paid Apple Developer Program membership: a free personal team cannot sign them and the
# build would fail to install. Turn this on once the team above is a paid one (or run with BIT_CLOUD=1).
CLOUD_FEATURES = ENV['BIT_CLOUD'] == '1' || false
ENTITLEMENTS = 'Support/BitAirlines.entitlements'
CORE_PACKAGE = 'AirlineCore'

FileUtils.rm_rf(PROJECT_PATH)
project = Xcodeproj::Project.new(PROJECT_PATH)

app = project.new_target(:application, APP_NAME, :ios, DEPLOYMENT_TARGET)
tests = project.new_target(:unit_test_bundle, TEST_NAME, :ios, DEPLOYMENT_TARGET)
tests.add_dependency(app)

# ---- Files ---------------------------------------------------------------------------------------
def add_tree(project, group, dir, target, resource_exts: %w[.xcassets .xcprivacy .ttf], skip: [])
  Dir.children(dir).sort.each do |name|
    path = File.join(dir, name)
    next if name.start_with?('.') || skip.include?(name)
    if File.directory?(path) && File.extname(name) != '.xcassets'
      add_tree(project, group.new_group(name, name), path, target, resource_exts: resource_exts, skip: skip)
    elsif name.end_with?('.swift')
      target.add_file_references([group.new_reference(name)])
    elsif resource_exts.include?(File.extname(name))
      ref = group.new_reference(name)
      target.resources_build_phase.add_file_reference(ref)
    end
  end
end

app_group = project.main_group.new_group(APP_NAME, APP_NAME)
add_tree(project, app_group, File.join(ROOT, APP_NAME), app)
test_group = project.main_group.new_group(TEST_NAME, TEST_NAME)
add_tree(project, test_group, File.join(ROOT, TEST_NAME), tests)

# ---- Local Swift package: AirlineCore ------------------------------------------------------------
package_ref = project.new(Xcodeproj::Project::Object::XCLocalSwiftPackageReference)
package_ref.relative_path = CORE_PACKAGE
project.root_object.package_references << package_ref
[app, tests].each do |target|
  dependency = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
  dependency.product_name = CORE_PACKAGE
  target.package_product_dependencies << dependency
  build_file = project.new(Xcodeproj::Project::Object::PBXBuildFile)
  build_file.product_ref = dependency
  target.frameworks_build_phase.files << build_file
end

# ---- Build settings ------------------------------------------------------------------------------
# The app is Swift 5 language mode on purpose: the local 9B agent edits the views, and strict-concurrency errors are noise for it.
# AirlineCore itself is Swift 6 strict (see AirlineCore/Package.swift).
common = {
  'SWIFT_VERSION' => '5.0',
  'IPHONEOS_DEPLOYMENT_TARGET' => DEPLOYMENT_TARGET,
  'TARGETED_DEVICE_FAMILY' => '1',                  # iPhone only
  'MARKETING_VERSION' => '0.1.0',
  'CURRENT_PROJECT_VERSION' => '1',
  'GENERATE_INFOPLIST_FILE' => 'YES',
  'CODE_SIGN_STYLE' => 'Automatic',
  'ENABLE_USER_SCRIPT_SANDBOXING' => 'YES',
  'SWIFT_EMIT_LOC_STRINGS' => 'YES',
}
app.build_configurations.each do |config|
  s = config.build_settings
  s.merge!(common)
  s['PRODUCT_BUNDLE_IDENTIFIER'] = BUNDLE_ID
  s['PRODUCT_NAME'] = '$(TARGET_NAME)'
  s['DEVELOPMENT_TEAM'] = DEVELOPMENT_TEAM
  s['ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME'] = 'AccentColor'
  s['INFOPLIST_KEY_CFBundleDisplayName'] = DISPLAY_NAME
  s['INFOPLIST_KEY_UIApplicationSceneManifest_Generation'] = 'YES'
  s['INFOPLIST_KEY_UILaunchScreen_Generation'] = 'YES'
  s['INFOPLIST_KEY_UIUserInterfaceStyle'] = 'Dark'
  s['INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone'] = 'UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight'
  s['INFOPLIST_KEY_UIRequiresFullScreen'] = 'YES'
  s['INFOPLIST_KEY_ITSAppUsesNonExemptEncryption'] = 'NO'
  s['LD_RUNPATH_SEARCH_PATHS'] = ['$(inherited)', '@executable_path/Frameworks']
  s['SDKROOT'] = 'iphoneos'
  s['SUPPORTED_PLATFORMS'] = 'iphoneos iphonesimulator'
  s['SWIFT_ACTIVE_COMPILATION_CONDITIONS'] = '$(inherited) DEBUG' if config.name == 'Debug'
  s['CODE_SIGN_ENTITLEMENTS'] = ENTITLEMENTS if CLOUD_FEATURES
end
tests.build_configurations.each do |config|
  s = config.build_settings
  s.merge!(common)
  s['PRODUCT_BUNDLE_IDENTIFIER'] = "#{BUNDLE_ID}.tests"
  s['DEVELOPMENT_TEAM'] = DEVELOPMENT_TEAM
  s['PRODUCT_NAME'] = '$(TARGET_NAME)'
  s['TEST_HOST'] = "$(BUILT_PRODUCTS_DIR)/#{APP_NAME}.app/#{APP_NAME}"
  s['BUNDLE_LOADER'] = '$(TEST_HOST)'
  s['ENABLE_TESTING_SEARCH_PATHS'] = 'YES'
  s['SDKROOT'] = 'iphoneos'
  s['SUPPORTED_PLATFORMS'] = 'iphoneos iphonesimulator'
end

# Project-level defaults (the xcodeproj gem starts at Swift 5 / older targets).
project.build_configurations.each do |config|
  config.build_settings['SWIFT_VERSION'] = '5.0'
  config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = DEPLOYMENT_TARGET
end

project.save

# ---- Shared scheme -------------------------------------------------------------------------------
scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(app)
scheme.add_test_target(tests)
scheme.set_launch_target(app)
scheme.save_as(PROJECT_PATH, APP_NAME, true)

puts "Generated #{PROJECT_PATH}"
