import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../models/note_node.dart';
import '../config/colors.dart';
import 'card_paper_painter.dart';

class DraggableResizableNoteCard extends StatefulWidget {
  final NoteNode note;
  final bool matches;
  final VoidCallback onDelete;
  final Function(NoteNode) onSave;
  final Function(NoteNode)? onDragUpdate;
  final Function(NoteNode)? onLayoutChanged;
  /// Notifies when the InteractiveViewer is actively panning/zooming so
  /// node drag gestures can be suppressed during viewport interactions.
  final ValueNotifier<bool> viewportInteracting;

  // ── Bridge selection props ─────────────────────────────────────────────────
  /// Whether this card is currently selected as a bridge endpoint.
  final bool isBridgeSelected;
  /// Non-null when bridge mode is active. Replaces drag behaviour with selection.
  final VoidCallback? onBridgeTap;

  const DraggableResizableNoteCard({
    super.key,
    required this.note,
    required this.matches,
    required this.onDelete,
    required this.onSave,
    required this.viewportInteracting,
    this.onDragUpdate,
    this.onLayoutChanged,
    this.isBridgeSelected = false,
    this.onBridgeTap,
  });

  @override
  State<DraggableResizableNoteCard> createState() =>
      _DraggableResizableNoteCardState();
}

class _DraggableResizableNoteCardState
    extends State<DraggableResizableNoteCard>
    with SingleTickerProviderStateMixin {
  late Offset _position;
  late double _width;
  late double _height;
  late TextEditingController _contentController;
  late FocusNode _focusNode;
  bool _isEditing = false;

  /// True while the user is actively panning the card.
  bool _isDragging = false;

  /// True when the right mouse button initiated the current pointer gesture.
  bool _isRightButtonDown = false;

  /// True while the mouse is anywhere on the card header area.
  bool _headerHovered = false;

  /// Bridge selection pulse animation controller
  late AnimationController _bridgePulseController;

  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    _position = widget.note.position;
    _width = widget.note.width;
    _height = widget.note.height;
    _contentController =
        TextEditingController(text: _cleanContent(widget.note.content));
    _focusNode = FocusNode();
    _focusNode.addListener(() {
      if (!_focusNode.hasFocus) {
        if (mounted && _isEditing) {
          setState(() {
            _isEditing = false;
          });
          _saveData(immediate: true);
        }
      }
    });

    _bridgePulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    if (widget.isBridgeSelected) {
      _bridgePulseController.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _contentController.dispose();
    _focusNode.dispose();
    _bridgePulseController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant DraggableResizableNoteCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Sync local layout WITHOUT a nested setState — the parent's setState
    // already scheduled this rebuild. A second setState here causes a
    // double-rebuild cascade (the main cause of gravity jitter).
    if (!_isDragging) {
      _position = widget.note.position;
      _width = widget.note.width;
      _height = widget.note.height;
    }
    final cleaned = _cleanContent(widget.note.content);
    if (cleaned != _contentController.text) {
      _contentController.text = cleaned;
    }

    // Manage bridge pulse animation
    if (widget.isBridgeSelected && !oldWidget.isBridgeSelected) {
      _bridgePulseController.repeat(reverse: true);
    } else if (!widget.isBridgeSelected && oldWidget.isBridgeSelected) {
      _bridgePulseController.stop();
      _bridgePulseController.reset();
    }
  }

  static String _cleanContent(String content) {
    if (!content.startsWith('[')) return content;
    try {
      final cleanBuffer = StringBuffer();
      int index = 0;
      while (true) {
        index = content.indexOf('"insert":', index);
        if (index == -1) break;
        index += 9;
        while (index < content.length &&
            (content[index] == ' ' || content[index] == '\t')) {
          index++;
        }
        if (index < content.length && content[index] == '"') {
          index++;
          final start = index;
          while (index < content.length && content[index] != '"') {
            if (content[index] == '\\' && index + 1 < content.length) {
              index += 2;
            } else {
              index++;
            }
          }
          if (index < content.length) {
            cleanBuffer.write(content.substring(start, index));
          }
        }
      }
      return cleanBuffer.toString().replaceAll('\\n', '\n');
    } catch (_) {
      return content;
    }
  }

  void _saveData({bool immediate = false}) {
    widget.note.content = _contentController.text;
    widget.note.title = '';
    if (immediate) {
      _debounceTimer?.cancel();
      widget.onSave(widget.note);
    } else {
      if (_debounceTimer?.isActive ?? false) _debounceTimer!.cancel();
      _debounceTimer = Timer(const Duration(milliseconds: 1000), () {
        widget.onSave(widget.note);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final int colorIdx =
        (widget.note.colorIndex >= 0 && widget.note.colorIndex < cardBgColors.length)
            ? widget.note.colorIndex
            : 0;
    final bgColor = cardBgColors[colorIdx];
    final borderColor = cardBorderColors[colorIdx];

    return Positioned(
      left: _position.dx,
      top: _position.dy,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: widget.matches ? 1.0 : 0.12,
        child: IgnorePointer(
          ignoring: !widget.matches,
          child: Hero(
            tag: 'note-${widget.note.id}',
            child: Material(
              color: Colors.transparent,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onDoubleTap: () {
                  if (!widget.note.locked && widget.onBridgeTap == null) {
                    setState(() {
                      _isEditing = true;
                    });
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (_focusNode.canRequestFocus) {
                        _focusNode.requestFocus();
                      }
                    });
                  }
                },
                onDoubleTapDown: (_) {},
                child: Stack(
                  clipBehavior: Clip.none,
                children: [
                  // ── Bridge selection pulse ring ───────────────────────────
                  if (widget.isBridgeSelected)
                    Positioned.fill(
                      child: AnimatedBuilder(
                        animation: _bridgePulseController,
                        builder: (context, _) {
                          final t = _bridgePulseController.value;
                          return CustomPaint(
                            painter: _BridgeSelectionRingPainter(
                              pulseValue: t,
                              width: _width,
                              height: _height,
                            ),
                          );
                        },
                      ),
                    ),

                  // ── Bridge note gradient border ───────────────────────────
                  if (widget.note.isBridge)
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _BridgeGradientBorderPainter(
                          width: _width,
                          height: _height,
                        ),
                      ),
                    ),

                  // ── Card body ────────────────────────────────────────────
                  Container(
                      width: _width,
                      height: _height,
                      decoration: BoxDecoration(
                        color: bgColor,
                        borderRadius: BorderRadius.circular(14),
                        border: widget.isBridgeSelected
                            ? Border.all(
                                color: const Color(0xFFF59E0B),
                                width: 2.0,
                              )
                            : Border.all(color: borderColor, width: 1.5),
                        boxShadow: [
                          if (widget.isBridgeSelected) ...[
                            BoxShadow(
                              color: const Color(0xFFF59E0B).withValues(alpha: 0.45),
                              blurRadius: 24,
                              spreadRadius: 2,
                            ),
                          ] else ...[
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.05),
                              blurRadius: 20,
                              offset: const Offset(0, 6),
                            ),
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.02),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                          if (widget.note.isBridge) ...[
                            BoxShadow(
                              color: const Color(0xFFF59E0B).withValues(alpha: 0.20),
                              blurRadius: 18,
                              spreadRadius: 1,
                            ),
                            BoxShadow(
                              color: const Color(0xFF6366F1).withValues(alpha: 0.15),
                              blurRadius: 12,
                            ),
                          ],
                        ],
                      ),
                      child: CustomPaint(
                        painter: CardPaperPainter(paperType: widget.note.paperType),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // ── Drag header ─────────────────────────────────
                            _buildDragHeader(borderColor),

                            // ── Bridge badge ────────────────────────────────
                            if (widget.note.isBridge)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(10, 4, 10, 0),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        gradient: const LinearGradient(
                                          colors: [
                                            Color(0xFFF59E0B),
                                            Color(0xFF6366F1),
                                          ],
                                        ),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(
                                            Icons.merge_type_rounded,
                                            size: 9,
                                            color: Colors.white,
                                          ),
                                          const SizedBox(width: 3),
                                          Text(
                                            'BRIDGE',
                                            style: GoogleFonts.outfit(
                                              fontSize: 7.5,
                                              fontWeight: FontWeight.w700,
                                              color: Colors.white,
                                              letterSpacing: 0.8,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                            // ── Text content ─────────────────────────────────
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
                                child: TextField(
                                  controller: _contentController,
                                  focusNode: _focusNode,
                                  maxLines: null,
                                  expands: true,
                                  enabled: _isEditing && !widget.note.locked && widget.onBridgeTap == null,
                                  keyboardType: TextInputType.multiline,
                                  style: GoogleFonts.inter(
                                    fontSize: 12.5,
                                    color: Colors.grey.shade800,
                                    height: 1.55,
                                  ),
                                  onChanged: (_) => _saveData(),
                                  decoration: InputDecoration(
                                    hintText: widget.note.isBridge
                                        ? 'Synthesized bridge…'
                                        : 'Write a note…',
                                    hintStyle: GoogleFonts.inter(
                                      color: Colors.grey.shade400,
                                      fontSize: 12.5,
                                      fontStyle: FontStyle.italic,
                                    ),
                                    border: InputBorder.none,
                                    isDense: true,
                                    contentPadding: EdgeInsets.zero,
                                  ),
                                ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // ── Bridge tap overlay ────────────────────────────────────
                  // When bridge mode is active, the whole card becomes tappable.
                  if (widget.onBridgeTap != null)
                    Positioned.fill(
                      child: MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: widget.onBridgeTap,
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.transparent,
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                      ),
                    ),

                  // ── Resize handle (bottom-right) ─────────────────────────
                  if (!widget.note.locked && widget.onBridgeTap == null)
                    Positioned(
                      right: 0,
                      bottom: 0,
                      width: 22,
                      height: 22,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onPanUpdate: (details) {
                          setState(() {
                            _width = (_width + details.delta.dx).clamp(150.0, 1000.0);
                            _height = (_height + details.delta.dy).clamp(100.0, 1000.0);
                          });
                          widget.note.width = _width;
                          widget.note.height = _height;
                          widget.onDragUpdate?.call(widget.note);
                        },
                        onPanEnd: (details) {
                          const double grid = 30.0;
                          final snappedWidth = (_width / grid).round() * grid;
                          final snappedHeight = (_height / grid).round() * grid;
                          setState(() {
                            _width = snappedWidth.clamp(150.0, 1000.0);
                            _height = snappedHeight.clamp(100.0, 1000.0);
                          });
                          widget.note.width = _width;
                          widget.note.height = _height;
                          if (widget.onLayoutChanged != null) {
                            widget.onLayoutChanged!(widget.note);
                          } else {
                            widget.onSave(widget.note);
                          }
                        },
                        child: MouseRegion(
                          cursor: SystemMouseCursors.resizeUpLeftDownRight,
                          child: Padding(
                            padding: const EdgeInsets.all(4),
                            child: CustomPaint(
                              size: const Size(10, 10),
                              painter: _ResizeHandlePainter(borderColor),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            ),
          ),
        ),
      ),
    )
        .animate()
        .fadeIn(duration: 180.ms)
        .scale(
          begin: const Offset(0.96, 0.96),
          end: const Offset(1.0, 1.0),
          curve: Curves.easeOut,
        );
  }

  Widget _buildDragHeader(Color borderColor) {
    return MouseRegion(
      // KEY FIX: track hover so we show/hide action buttons
      onEnter: (_) => setState(() => _headerHovered = true),
      onExit: (_) => setState(() => _headerHovered = false),
      cursor: widget.onBridgeTap != null
          ? SystemMouseCursors.click
          : widget.note.locked
              ? SystemMouseCursors.basic
              : (_isDragging ? SystemMouseCursors.grabbing : SystemMouseCursors.grab),
      child: Listener(
        // Track which mouse button started the gesture so we can ignore
        // right-button presses (button == 2) for node dragging.
        onPointerDown: (e) => _isRightButtonDown = e.buttons == 2,
        onPointerUp: (_) => _isRightButtonDown = false,
        onPointerCancel: (_) => _isRightButtonDown = false,
        child: GestureDetector(
        // translucent = scroll / pinch events fall through to InteractiveViewer
        // when the user isn't performing a drag gesture.
        behavior: HitTestBehavior.translucent,
        onPanStart: (widget.note.locked || widget.onBridgeTap != null)
            ? null
            : (_) {
                if (_isRightButtonDown) return;
                if (widget.viewportInteracting.value) return;
                setState(() => _isDragging = true);
              },
        onPanUpdate: (widget.note.locked || widget.onBridgeTap != null)
            ? null
            : (details) {
                if (_isRightButtonDown) return;
                if (widget.viewportInteracting.value) return;
                if (!_isDragging) return; // guard: don't move if start was skipped
                setState(() => _position += details.delta);
                widget.note.position = _position;
                widget.onDragUpdate?.call(widget.note);
              },
        onPanEnd: (widget.note.locked || widget.onBridgeTap != null)
            ? null
            : (_) {
                if (_isRightButtonDown) return;
                if (!_isDragging) return; // guard: nothing to finish
                setState(() => _isDragging = false);
                const double grid = 30.0;
                final snappedX = (_position.dx / grid).round() * grid;
                final snappedY = (_position.dy / grid).round() * grid;
                setState(() => _position = Offset(snappedX, snappedY));
                widget.note.position = _position;
                if (widget.onLayoutChanged != null) {
                  widget.onLayoutChanged!(widget.note);
                } else {
                  widget.onSave(widget.note);
                }
              },
        child: Container(
          height: 20,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: borderColor.withValues(alpha: 0.6), width: 1),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (widget.onBridgeTap == null)
                AnimatedOpacity(
                  duration: const Duration(milliseconds: 150),
                  opacity: _headerHovered ? 1.0 : 0.0,
                  child: _MicroButton(
                    icon: Icons.close_rounded,
                    color: Colors.grey.shade400,
                    hoverColor: Colors.red.shade400,
                    tooltip: 'Delete',
                    onTap: widget.onDelete,
                  ),
                ),
            ],
          ),
        ),
      ),   // GestureDetector
    ),     // Listener
    );     // MouseRegion

  }
}

// ─── Bridge selection ring painter ───────────────────────────────────────────

class _BridgeSelectionRingPainter extends CustomPainter {
  final double pulseValue; // 0.0 to 1.0
  final double width;
  final double height;

  _BridgeSelectionRingPainter({
    required this.pulseValue,
    required this.width,
    required this.height,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const double padding = 8.0;
    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(-padding, -padding, width + padding * 2, height + padding * 2),
      const Radius.circular(20),
    );

    // Outer expanding ring
    final outerExpand = pulseValue * 6.0;
    final outerRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        -padding - outerExpand,
        -padding - outerExpand,
        width + (padding + outerExpand) * 2,
        height + (padding + outerExpand) * 2,
      ),
      Radius.circular(22 + outerExpand),
    );

    final outerPaint = Paint()
      ..color = const Color(0xFFF59E0B).withValues(alpha: 0.25 * (1.0 - pulseValue))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    canvas.drawRRect(outerRect, outerPaint);

    // Inner glowing border
    final innerPaint = Paint()
      ..shader = LinearGradient(
        colors: const [Color(0xFFF59E0B), Color(0xFF818CF8), Color(0xFFF59E0B)],
        stops: const [0.0, 0.5, 1.0],
      ).createShader(Rect.fromLTWH(0, 0, width, height))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0 + pulseValue * 1.0;
    canvas.drawRRect(rect, innerPaint);
  }

  @override
  bool shouldRepaint(covariant _BridgeSelectionRingPainter old) =>
      old.pulseValue != pulseValue;
}

// ─── Bridge gradient border painter (permanent on bridge notes) ───────────────

class _BridgeGradientBorderPainter extends CustomPainter {
  final double width;
  final double height;

  _BridgeGradientBorderPainter({required this.width, required this.height});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, width, height),
      const Radius.circular(14),
    );
    final paint = Paint()
      ..shader = LinearGradient(
        colors: [
          const Color(0xFFF59E0B).withValues(alpha: 0.7),
          const Color(0xFF6366F1).withValues(alpha: 0.7),
          const Color(0xFFF59E0B).withValues(alpha: 0.4),
        ],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(Rect.fromLTWH(0, 0, width, height))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;
    canvas.drawRRect(rect, paint);
  }

  @override
  bool shouldRepaint(covariant _BridgeGradientBorderPainter old) => false;
}

// ─── Micro icon button used in the card header ────────────────────────────────

class _MicroButton extends StatefulWidget {
  final IconData icon;
  final Color color;
  final Color? hoverColor;
  final VoidCallback onTap;
  final String tooltip;

  const _MicroButton({
    required this.icon,
    required this.color,
    this.hoverColor,
    required this.onTap,
    required this.tooltip,
  });

  @override
  State<_MicroButton> createState() => _MicroButtonState();
}

class _MicroButtonState extends State<_MicroButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final effectiveColor =
        _hovered && widget.hoverColor != null ? widget.hoverColor! : widget.color;
    return Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 500),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: _hovered
                  ? (widget.hoverColor ?? widget.color).withValues(alpha: 0.12)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(5),
            ),
            child: Icon(widget.icon, size: 13, color: effectiveColor),
          ),
        ),
      ),
    );
  }
}

// ─── Resize handle painter ────────────────────────────────────────────────────

class _ResizeHandlePainter extends CustomPainter {
  final Color color;
  _ResizeHandlePainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: 0.6)
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 1.4;
    final w = size.width;
    final h = size.height;
    canvas.drawLine(Offset(w * 0.4, h), Offset(w, h * 0.4), paint);
    canvas.drawLine(Offset(w * 0.7, h), Offset(w, h * 0.7), paint);
    canvas.drawLine(Offset(w, h), Offset(w, h), paint);
  }

  @override
  bool shouldRepaint(covariant _ResizeHandlePainter old) => old.color != color;
}
