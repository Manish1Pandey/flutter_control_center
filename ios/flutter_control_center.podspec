#
# CocoaPods spec for the flutter_control_center Flutter plugin (app side).
# The Widget Extension side is copied into your extension target by
# `dart run flutter_control_center:setup` (see README).
#
Pod::Spec.new do |s|
  s.name             = 'flutter_control_center'
  s.version          = '0.1.0'
  s.summary          = 'iOS 18 Control Center / Lock Screen / Action button controls for Flutter.'
  s.description      = <<-DESC
Stores control state in an App Group, reloads WidgetKit controls and delivers control
actions (button presses, toggle changes) to Dart.
                       DESC
  s.homepage         = 'https://github.com/Manish1Pandey/flutter_control_center'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Manish Kumar Panday' => 'https://github.com/Manish1Pandey' }
  s.source           = { :path => '.' }
  s.source_files     = 'flutter_control_center/Sources/flutter_control_center/**/*.swift'
  s.dependency 'Flutter'
  s.platform = :ios, '13.0'
  s.weak_frameworks = 'WidgetKit'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'
  s.resource_bundles = {
    'flutter_control_center_privacy' => ['flutter_control_center/Sources/flutter_control_center/PrivacyInfo.xcprivacy']
  }
end
