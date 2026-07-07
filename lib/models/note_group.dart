class NoteGroup {
  final String id;
  String name;
  List<String> noteIds;
  int colorIndex;

  NoteGroup({
    required this.id,
    this.name = '',
    required this.noteIds,
    this.colorIndex = 0,
  });
}
