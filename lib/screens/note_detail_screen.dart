import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/note_node.dart';
import '../config/colors.dart';
import '../widgets/card_paper_painter.dart';
import '../widgets/app_header.dart';

class NoteDetailScreen extends StatefulWidget {
  final NoteNode note;
  final VoidCallback onUpdate;

  const NoteDetailScreen({
    super.key,
    required this.note,
    required this.onUpdate,
  });

  @override
  State<NoteDetailScreen> createState() => _NoteDetailScreenState();
}

class _NoteDetailScreenState extends State<NoteDetailScreen> {
  late TextEditingController _titleController;
  late QuillController _quillController;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.note.title);

    Document doc;
    if (widget.note.content.startsWith('[')) {
      try {
        doc = Document.fromJson(jsonDecode(widget.note.content));
      } catch (e) {
        doc = Document()..insert(0, widget.note.content);
      }
    } else {
      doc = Document()..insert(0, widget.note.content);
    }

    _quillController = QuillController(
      document: doc,
      selection: const TextSelection.collapsed(offset: 0),
    );

    _quillController.addListener(_saveData);
  }

  @override
  void dispose() {
    _quillController.removeListener(_saveData);
    _titleController.dispose();
    _quillController.dispose();
    super.dispose();
  }

  void _saveData() {
    widget.note.title = _titleController.text;
    widget.note.content = jsonEncode(_quillController.document.toDelta().toJson());
    widget.onUpdate();
  }

  @override
  Widget build(BuildContext context) {
    final bgColor = cardBgColors[widget.note.colorIndex];
    final borderColor = cardBorderColors[widget.note.colorIndex];

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppHeader(
        showBackButton: true,
        onBack: () {
          _saveData();
          Navigator.pop(context);
        },
        backgroundColor: bgColor,
      ),
      body: CustomPaint(
        painter: CardPaperPainter(
          paperType: widget.note.paperType,
          lineColor: borderColor.withValues(alpha: 0.5),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: 32.0,
            vertical: 16.0,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _titleController,
                style: GoogleFonts.outfit(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: Colors.black87,
                  letterSpacing: -0.6,
                ),
                decoration: InputDecoration(
                  hintText: 'Untitled Note',
                  hintStyle: GoogleFonts.outfit(color: Colors.grey.shade400, fontWeight: FontWeight.w700),
                  border: InputBorder.none,
                ),
                onChanged: (_) => _saveData(),
              ),
              const SizedBox(height: 8),
              Container(
                height: 1.5,
                color: borderColor,
                width: double.infinity,
              ),
              const SizedBox(height: 12),
              QuillSimpleToolbar(
                controller: _quillController,
                config: const QuillSimpleToolbarConfig(
                  showFontFamily: false,
                  showSearchButton: false,
                  showInlineCode: false,
                  showCodeBlock: false,
                  showSmallButton: false,
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: QuillEditor.basic(
                  controller: _quillController,
                  config: const QuillEditorConfig(
                    autoFocus: true,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
