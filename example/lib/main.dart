import 'dart:async';

import 'package:flutter/material.dart';
import 'package:webrtc_data_channel/webrtc_data_channel.dart';

void main() => runApp(new MyApp());

class MyApp extends StatefulWidget {
  @override
  _MyAppState createState() => new _MyAppState();
}

class _MyAppState extends State<MyApp> {
  WebrtcDataChannel _dataChannel = new WebrtcDataChannel();
  StreamSubscription<String> _receivedMessages;

  List<String> _messages = [];

  int _count = 0;

  @override
  initState() {
    super.initState();

    _dataChannel.connect('<url>', '654351');

    _receivedMessages = _dataChannel.listenMessages().listen((String message) {
      _messages.add(message);
      setState(() {});
    });

    new Timer.periodic(const Duration(seconds: 5),
        (Timer timer) => _dataChannel.sendMessage('message ${_count++}'));
  }

  String _getMessages() {
    String text = '';
    for (String message in _messages) {
      text += message + '\n';
    }
    return text;
  }

  @override
  Widget build(BuildContext context) {
    return new MaterialApp(
      home: new Scaffold(
        appBar: new AppBar(
          title: new Text('Plugin example app'),
        ),
        body: new Center(
          child: new Text(_getMessages()),
        ),
      ),
    );
  }
}
