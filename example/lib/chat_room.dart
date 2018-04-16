import 'dart:async';

import 'package:flutter/material.dart';
import 'package:webrtc_data_channel/webrtc_data_channel.dart';

import 'chat_message.dart';
import 'chat_message_item.dart';

class ChatRoom extends StatefulWidget {
  ChatRoom(this._roomUrl, this._roomId);

  final String _roomUrl, _roomId;

  @override
  _ChatRoomState createState() => new _ChatRoomState(_roomUrl, _roomId);
}

class _ChatRoomState extends State<ChatRoom> {
  _ChatRoomState(this._roomUrl, this._roomId);

  final String _roomUrl, _roomId;
  final TextEditingController _messageController = new TextEditingController();

  BuildContext _context;

  // active: dispose -> SignalingState
  // passive: SignalingState -> dispose
  bool _activeClosing = false;
  bool _errorHappened = false;

  bool _iceConnected = false;
  List<ChatMessage> _messages = [];

  WebRTCDataChannel _dataChannel = new WebRTCDataChannel();
  StreamSubscription<String> _receivedMessages;
  StreamSubscription<int> _signalingState;
  StreamSubscription<int> _iceState;

  @override
  initState() {
    super.initState();

    _dataChannel.connect(_roomUrl, _roomId);

    _receivedMessages = _dataChannel.listenMessages().listen(
        (String message) => setState(
            () => _messages.add(new ChatMessage(ChatUser.other, message))),
        onError: _onError);

    _signalingState = _dataChannel.listenSignalingState().listen((int state) {
      if (state == WebRTCDataChannel.SIGNALING_STATE_DISCONNECTED) {
        if (!_activeClosing) {
          _disconnect();
          Navigator.pop(_context);
        }
      }
    }, onError: _onError);

    _iceState = _dataChannel.listenIceState().listen((int state) {
      switch (state) {
        case WebRTCDataChannel.ICE_STATE_CONNECTED:
          setState(() {
            _iceConnected = true;
          });
          break;
        case WebRTCDataChannel.ICE_STATE_DISCONNECTED:
          setState(() {
            _iceConnected = false;
          });
          break;
        default:
          break;
      }
    }, onError: _onError);
  }

  @override
  void dispose() {
    super.dispose();

    _activeClosing = true;
    _disconnect();
  }

  _onError(dynamic error) {
    if (_errorHappened) {
      return;
    }
    _errorHappened = true;

    showDialog<Null>(
        context: _context,
        barrierDismissible: false,
        builder: (BuildContext context) => new AlertDialog(
              title: new Text('Error: ${error.message}'),
              actions: [
                new FlatButton(
                    onPressed: () {
                      Navigator.pop(context);
                    },
                    child: new Text('OK'))
              ],
            )).then((dynamic result) {
      _disconnect();
      Navigator.pop(_context);
    });
  }

  _disconnect() {
    _receivedMessages.cancel();
    _signalingState.cancel();
    _iceState.cancel();
    _dataChannel.disconnect();
  }

  _sendMessage() {
    String message = _messageController.text;
    _dataChannel.sendMessage(_messageController.text);
    _messageController.clear();
    setState(() => _messages.add(new ChatMessage(ChatUser.self, message)));
  }

  @override
  Widget build(BuildContext context) {
    _context = context;

    return new Scaffold(
      appBar: new AppBar(
        title: new Text(_roomId),
      ),
      body: new Container(
        color: new Color(0xFF232329),
        child: new Column(
          children: [
            new Expanded(
                child: new ListView.builder(
                    itemCount: _messages.length,
                    itemBuilder: (BuildContext context, int index) =>
                        new ChatMessageItem(_messages[index]))),
            new Container(
              margin:
                  new EdgeInsets.only(left: 20.0, right: 20.0, bottom: 10.0),
              child: new Row(
                children: [
                  new Expanded(
                      child: new TextField(
                    style: new TextStyle(color: Colors.white),
                    controller: _messageController,
                    decoration: new InputDecoration(
                        hintText: 'Say something...',
                        hintStyle: new TextStyle(color: new Color(0xFF999999))),
                  )),
                  new RaisedButton(
                    disabledColor: new Color(0xFF555555),
                    onPressed: _iceConnected ? _sendMessage : null,
                    child: new Text('SEND'),
                  )
                ],
              ),
            )
          ],
        ),
      ),
    );
  }
}
