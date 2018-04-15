import 'dart:async';

import 'package:flutter/services.dart';

const String METHOD_CHANNEL_NAME =
    "com.github.piasy/webrtc_data_channel.method";
const String EVENT_CHANNEL_NAME = "com.github.piasy/webrtc_data_channel.event";

const String METHOD_CONNECT_TO_ROOM = "connectToRoom";
const String METHOD_SEND_MESSAGE = "sendMessage";
const String METHOD_DISCONNECT = "disconnect";

const int EVENT_TYPE_SIGNALING_STATE = 1;
const int EVENT_TYPE_ICE_STATE = 2;
const int EVENT_TYPE_MESSAGE = 3;

const MethodChannel _methodChannel = const MethodChannel(METHOD_CHANNEL_NAME);
const EventChannel _eventChannel = const EventChannel(EVENT_CHANNEL_NAME);

class WebrtcDataChannel {
  static const int SIGNALING_STATE_DISCONNECTED = 0;
  static const int SIGNALING_STATE_CONNECTED = 2;

  static const int ICE_STATE_DISCONNECTED = 5;
  static const int ICE_STATE_CONNECTED = 2;

  Stream<dynamic> _receivedEvents;

  Future<int> connect(String roomUrl, String roomId) =>
      _methodChannel.invokeMethod(METHOD_CONNECT_TO_ROOM, {
        'roomUrl': roomUrl,
        'roomId': roomId
      }).then<int>((dynamic result) => result);

  Stream<int> listenSignalingState() {
    if (_receivedEvents == null) {
      _receivedEvents = _eventChannel.receiveBroadcastStream();
    }

    return _receivedEvents
        .map<Map>((dynamic event) => event)
        .where((Map event) => event['type'] == EVENT_TYPE_SIGNALING_STATE)
        .map<int>((Map event) => event['state']);
  }

  Stream<int> listenIceState() {
    if (_receivedEvents == null) {
      _receivedEvents = _eventChannel.receiveBroadcastStream();
    }

    return _receivedEvents
        .map<Map>((dynamic event) => event)
        .where((Map event) => event['type'] == EVENT_TYPE_ICE_STATE)
        .map<int>((Map event) => event['state']);
  }

  Stream<String> listenMessages() {
    if (_receivedEvents == null) {
      _receivedEvents = _eventChannel.receiveBroadcastStream();
    }

    return _receivedEvents
        .map<Map>((dynamic event) => event)
        .where((Map event) => event['type'] == EVENT_TYPE_MESSAGE)
        .map<String>((Map event) => event['message']);
  }

  Future<int> sendMessage(String message) => _methodChannel.invokeMethod(
      METHOD_SEND_MESSAGE,
      {'message': message}).then<int>((dynamic result) => result);

  Future<int> disconnect() => _methodChannel
      .invokeMethod(METHOD_DISCONNECT)
      .then<int>((dynamic result) => result);
}
