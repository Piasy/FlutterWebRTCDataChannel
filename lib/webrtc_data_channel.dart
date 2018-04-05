import 'dart:async';

import 'package:flutter/services.dart';

class WebrtcDataChannel {
  static const String METHOD_CHANNEL_NAME =
      "com.github.piasy/webrtc_data_channel.method";
  static const String EVENT_CHANNEL_NAME =
      "com.github.piasy/webrtc_data_channel.event";

  static const String METHOD_CONNECT_TO_ROOM = "connectToRoom";
  static const String METHOD_SEND_MESSAGE = "sendMessage";

  final MethodChannel _methodChannel = const MethodChannel(METHOD_CHANNEL_NAME);
  final EventChannel _eventChannel = const EventChannel(EVENT_CHANNEL_NAME);

  Stream<String> _receivedMessages;

  Future<bool> connect(String roomUrl, String roomId) =>
      _methodChannel.invokeMethod(METHOD_CONNECT_TO_ROOM, {
        'roomUrl': roomUrl,
        'roomId': roomId
      }).then<bool>((dynamic result) => result);

  Future<bool> sendMessage(String message) => _methodChannel.invokeMethod(
      METHOD_SEND_MESSAGE,
      {'message': message}).then<bool>((dynamic result) => result);

  Stream<String> listenMessages() {
    if (_receivedMessages == null) {
      _receivedMessages = _eventChannel.receiveBroadcastStream();
    }

    return _receivedMessages;
  }
}
