import 'package:flutter/material.dart';

import 'chat_message.dart';

class ChatMessageItem extends StatelessWidget {
  ChatMessageItem(this._message);

  final ChatMessage _message;

  @override
  Widget build(BuildContext context) {
    AlignmentGeometry alignment;
    int textColor;
    String background;
    Rect centerSlice;
    EdgeInsetsGeometry padding;
    if (_message.user == ChatUser.self) {
      alignment = Alignment.centerRight;
      textColor = Colors.white.value;
      background = 'assets/bg_chat_from_self.9.png';
      centerSlice = new Rect.fromLTWH(17.0, 13.0, 12.0, 8.0);
      padding = new EdgeInsets.fromLTRB(14.5, 6.0, 18.5, 6.0);
    } else {
      alignment = Alignment.centerLeft;
      textColor = 0xFF151518;
      background = 'assets/bg_chat_from_other.9.png';
      centerSlice = new Rect.fromLTWH(21.0, 13.0, 12.0, 8.0);
      padding = new EdgeInsets.fromLTRB(18.5, 6.0, 14.5, 6.0);
    }

    return new Container(
      alignment: alignment,
      margin: new EdgeInsets.only(
        left: 20.0,
        right: 20.0,
        top: 10.0,
      ),
      child: new Container(
        decoration: new BoxDecoration(
            image: new DecorationImage(
                centerSlice: centerSlice, image: new AssetImage(background))),
        constraints: new BoxConstraints(
            minWidth: 50.0, maxWidth: 257.0, minHeight: 34.0),
        padding: padding,
        child: new Text(
          _message.message,
          style: new TextStyle(
            color: new Color(textColor),
            fontSize: 16.0,
          ),
        ),
      ),
    );
  }
}
