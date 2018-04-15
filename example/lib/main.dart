import 'package:flutter/material.dart';

import 'chat_room.dart';

void main() {
  runApp(new MaterialApp(
    home: new HomePage(),
  ));
}

class HomePage extends StatefulWidget {
  @override
  HomePageState createState() {
    return new HomePageState();
  }
}

class HomePageState extends State<HomePage> {
  // https://appr.tc
  final TextEditingController _roomUrlController = new TextEditingController();
  final TextEditingController _roomIdController = new TextEditingController();

  BuildContext _scaffoldContext;

  _startChat(BuildContext context) {
    if (_roomUrlController.text.isNotEmpty &&
        _roomIdController.text.isNotEmpty) {
      Navigator.push(
          context,
          new MaterialPageRoute(
              builder: (context) => new ChatRoom(
                  _roomUrlController.text, _roomIdController.text)));
    } else {
      Scaffold.of(_scaffoldContext).showSnackBar(
          new SnackBar(content: new Text('Please set room url and id')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return new Scaffold(
      appBar: new AppBar(
        title: new Text('WebRTC DataChannel Chat'),
      ),
      body: new Builder(builder: (BuildContext context) {
        _scaffoldContext = context;
        return new Column(
          children: [
            new Container(
              padding: new EdgeInsets.fromLTRB(30.0, 30.0, 30.0, 0.0),
              child: new TextField(
                autofocus: true,
                controller: _roomUrlController,
                decoration: new InputDecoration(hintText: 'Type room url'),
              ),
            ),
            new Container(
              padding: new EdgeInsets.all(30.0),
              child: new TextField(
                controller: _roomIdController,
                decoration: new InputDecoration(hintText: 'Type room id'),
              ),
            ),
            new RaisedButton(
              child: new Text('CHAT'),
              onPressed: () => _startChat(context),
            ),
          ],
        );
      }),
    );
  }
}
