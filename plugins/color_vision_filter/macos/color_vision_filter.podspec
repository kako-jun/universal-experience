Pod::Spec.new do |s|
  s.name             = 'color_vision_filter'
  s.version          = '0.1.0'
  s.summary          = 'macOS implementation of color_vision_filter plugin'
  s.description      = 'Platform plugin for applying color vision deficiency filters'
  s.homepage         = 'https://github.com/kako-jun/universal-experience'
  s.license          = { :type => 'MIT', :file => '../LICENSE' }
  s.author           = { 'kako-jun' => 'kako-jun@users.noreply.github.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'FlutterMacOS'
  s.platform = :osx, '10.14'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '5.0'
end
