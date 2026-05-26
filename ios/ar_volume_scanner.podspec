#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint ar_volume_scanner.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'ar_volume_scanner'
  s.version          = '0.1.0'
  s.summary          = 'Flutter AR plugin — scan objects and compute volume via ARKit/LiDAR.'
  s.description      = <<-DESC
Uses ARKit scene reconstruction (LiDAR on supported devices) and the depth API to
capture a 3-D point cloud or mesh of a real-world object, then calculates its volume
in cm³ using the signed-tetrahedra, convex-hull, or bounding-box algorithm.
                       DESC
  s.homepage         = 'https://github.com/nalugala-vc/Flutter-Augumented-Reality'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Vanessa Nalugala' => 'vanessachebukwa@gmail.com' }
  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '14.0'
  s.frameworks = 'ARKit', 'SceneKit', 'Metal'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'

  # If your plugin requires a privacy manifest, for example if it uses any
  # required reason APIs, update the PrivacyInfo.xcprivacy file to describe your
  # plugin's privacy impact, and then uncomment this line. For more information,
  # see https://developer.apple.com/documentation/bundleresources/privacy_manifest_files
  # s.resource_bundles = {'ar_volume_scanner_privacy' => ['Resources/PrivacyInfo.xcprivacy']}
end
