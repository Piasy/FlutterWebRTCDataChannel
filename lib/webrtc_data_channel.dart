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

class WebRTCDataChannel {
  /// disconnected from room server and signal server
  static const int SIGNALING_STATE_DISCONNECTED = 0;
  /// connected to room server and signal server
  static const int SIGNALING_STATE_CONNECTED = 2;

  /// ICE connection disconnected
  static const int ICE_STATE_DISCONNECTED = 5;
  /// ICE connection connected
  static const int ICE_STATE_CONNECTED = 2;

  Stream<dynamic> _receivedEvents;

  /// connect to room with [roomUrl] and [roomId]
  Future<int> connect(String roomUrl, String roomId) =>
      _methodChannel.invokeMethod(METHOD_CONNECT_TO_ROOM, {
        'roomUrl': roomUrl,
        'roomId': roomId
      }).then<int>((dynamic result) => result);

  /// listening for signaling state
  Stream<int> listenSignalingState() {
    if (_receivedEvents == null) {
      _receivedEvents = _eventChannel.receiveBroadcastStream();
    }

    return _receivedEvents
        .map<Map>((dynamic event) => event)
        .where((Map event) => event['type'] == EVENT_TYPE_SIGNALING_STATE)
        .map<int>((Map event) => event['state']);
  }

  /// listening for ICE connection state
  Stream<int> listenIceState() {
    if (_receivedEvents == null) {
      _receivedEvents = _eventChannel.receiveBroadcastStream();
    }

    return _receivedEvents
        .map<Map>((dynamic event) => event)
        .where((Map event) => event['type'] == EVENT_TYPE_ICE_STATE)
        .map<int>((Map event) => event['state']);
  }

  /// listening for received messages
  Stream<String> listenMessages() {
    if (_receivedEvents == null) {
      _receivedEvents = _eventChannel.receiveBroadcastStream();
    }

    return _receivedEvents
        .map<Map>((dynamic event) => event)
        .where((Map event) => event['type'] == EVENT_TYPE_MESSAGE)
        .map<String>((Map event) => event['message']);
  }

  /// send message
  Future<int> sendMessage(String message) => _methodChannel.invokeMethod(
      METHOD_SEND_MESSAGE,
      {'message': message}).then<int>((dynamic result) => result);

  /// disconnect from room
  Future<int> disconnect() => _methodChannel
      .invokeMethod(METHOD_DISCONNECT)
      .then<int>((dynamic result) => result);
}
