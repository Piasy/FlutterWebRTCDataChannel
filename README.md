# Flutter WebRTC DataChannel plugin

This plugin allows Flutter apps to use WebRTC DataChannel to establish P2P connection and exchange
text messages.

![](/art/art.png)

## Install

Plugin dependency:

``` yaml
webrtc_data_channel: "^0.1.0"
```

WebRTC Android dependency:

``` gradle
rootProject.allprojects {
    repositories {
        maven {
            url  "https://google.bintray.com/webrtc"
        }
    }
}

dependencies {
    api 'org.webrtc:google-webrtc:1.0.22672'
}
```

WebRTC iOS dependency:

``` ruby
pod 'GoogleWebRTC', '1.1.22642'
```

## Usage

``` dart
import 'package:webrtc_data_channel/webrtc_data_channel.dart';

// create DataChannel and connect to room
WebRTCDataChannel _dataChannel = new WebRTCDataChannel();
_dataChannel.connect(_roomUrl, _roomId);

// listen for messages
_receivedMessages = _dataChannel.listenMessages()
        .listen((String message) {
            // handle message
        });

// send message
_dataChannel.sendMessage(message);

// disconnect from room
_dataChannel.disconnect();
```

## Server setup

This plugin use [webrtc/apprtc](https://github.com/webrtc/apprtc) as room server and signal server,
you can use `https://appr.tc/` or deploy it yourself, I've a Docker image for it,
[piasy/apprtc-server](https://hub.docker.com/r/piasy/apprtc-server/).

## Development setup

+ `git clone https://github.com/Piasy/webrtc_data_channel`
+ `flutter create -t plugin webrtc_data_channel`
+ `cd webrtc_data_channel/example/ios && pod install`
