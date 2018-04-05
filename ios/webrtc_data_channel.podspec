#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html
#
Pod::Spec.new do |s|
  s.name             = 'webrtc_data_channel'
  s.version          = '0.0.1'
  s.summary          = 'Flutter plugin for WebRTC data channel.'
  s.description      = <<-DESC
Flutter plugin for WebRTC data channel.
                       DESC
  s.homepage         = 'https://github.com/Piasy/FlutterWebRTCDataChannel'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Piasy' => 'xz4215@gmail.com' }
  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.public_header_files = 'Classes/**/*.h'
  s.libraries = 'icucore'
  s.dependency 'Flutter'
  s.dependency 'GoogleWebRTC', '>= 1.1.22642'

  s.ios.deployment_target = '8.0'
end
