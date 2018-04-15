
enum ChatUser { self, other }

class ChatMessage {
  ChatMessage(this.user, this.message);

  final ChatUser user;
  final String message;
}
