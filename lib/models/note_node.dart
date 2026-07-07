import 'dart:ui';

class NoteNode {
  final String id;
  String title;
  String content;
  Offset position;
  double width;
  double height;
  String paperType;
  bool locked;
  int colorIndex;
  /// True if this note was synthesized by the Thought Bridge engine.
  bool isBridge;

  NoteNode({
    required this.id,
    this.title = '',
    this.content = '',
    required this.position,
    this.width = 240.0,
    this.height = 130.0,
    this.paperType = 'blank',
    this.locked = false,
    this.colorIndex = 0,
    this.isBridge = false,
  });
}
