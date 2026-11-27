Pod::Spec.new do |s|
  s.name             = 'TUIHomeKit'
  s.version          = '1.0.0'
  s.summary          = 'Home tab module: feed, profile and album'
  s.homepage         = 'https://cloud.tencent.com/document/product/269'
  s.license          = { :type => 'MIT' }
  s.author           = { 'Tencent Cloud' => 'im@tencent.com' }
  s.source           = { :path => './' }
  s.ios.deployment_target = '15.0'
  s.swift_version    = '5.0'
  s.static_framework = true
  s.frameworks       = 'UIKit', 'Foundation'
  s.dependency 'AtomicX'
  s.dependency 'AtomicXCore'
  s.dependency 'TUIHostBase'
  s.source_files     = 'Sources/**/*.swift'
  s.resource_bundles = {
    'TUIHomeKitBundle' => ['Resources/Localization/**/*.strings', 'Resources/Images/*.png']
  }
end
