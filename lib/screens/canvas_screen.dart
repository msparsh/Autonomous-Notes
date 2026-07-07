import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:uuid/uuid.dart';
import '../models/note_node.dart';
import '../helpers/database_helper.dart';
import '../widgets/dotted_grid_painter.dart';
import '../widgets/draggable_resizable_note_card.dart';
import '../widgets/connections_painter.dart';
import '../widgets/app_header.dart';
import '../widgets/bridge_beam_painter.dart';

class CanvasScreen extends StatefulWidget {
  const CanvasScreen({super.key});

  @override
  State<CanvasScreen> createState() => _CanvasScreenState();
}

class _CanvasScreenState extends State<CanvasScreen>
    with TickerProviderStateMixin {
  final TransformationController _transformationController =
      TransformationController();
  final List<NoteNode> _notes = [];
  final List<ConnectionEdge> _edges = [];
  final double _canvasSize = 10000.0;
  bool _isLoading = true;
  final bool _isRebuildingEdges = false;
  String _searchQuery = '';
  bool _isSearchActive = false;
  bool _isSimulatingLayout = false;
  final Uuid _uuid = const Uuid();
  Matrix4? _previousMatrix;
  Map<String, NoteNode> _notesMap = {};
  Size? _lastViewportSize;

  // Gravity simulation state
  Ticker? _gravityTicker;
  Map<String, Offset> _nodeVelocities = {};
  int _gravityTickCount = 0;
  static const int _maxGravityTicks = 120;

  /// True while the InteractiveViewer is actively panning or zooming.
  /// Used by note cards to suppress drag gestures during viewport interaction.
  final ValueNotifier<bool> _viewportInteracting = ValueNotifier(false);

  late AnimationController _connectionAnimationController;

  // ── Bridge mode state ─────────────────────────────────────────────────────
  bool _isBridgeModeActive = false;
  NoteNode? _bridgeNodeA;
  NoteNode? _bridgeNodeB;
  bool _isBridging = false; // true during collapse + synthesis animation

  /// Canvas-space centers of selected bridge nodes (for the beam painter).
  Offset? _beamOffsetA;
  Offset? _beamOffsetB;

  double _bridgeCollapseProgress = 0.0;
  late AnimationController _bridgeBeamController;
  late AnimationController _bridgeCollapseController;

  @override
  void initState() {
    super.initState();
    _connectionAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();

    _bridgeBeamController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();

    _bridgeCollapseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _bridgeCollapseController.addListener(() {
      setState(() => _bridgeCollapseProgress = _bridgeCollapseController.value);
    });
    _bridgeCollapseController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _finalizeBridge();
      }
    });

    _loadData();
    _transformationController.addListener(_onTransformationChanged);
  }

  @override
  void dispose() {
    _gravityTicker?.dispose();
    _connectionAnimationController.dispose();
    _bridgeBeamController.dispose();
    _bridgeCollapseController.dispose();
    _viewportInteracting.dispose();
    _transformationController.removeListener(_onTransformationChanged);
    _transformationController.dispose();
    super.dispose();
  }

  void _onTransformationChanged() {
    setState(() {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final size = MediaQuery.of(context).size;
    final initialX = -(_canvasSize / 2) + (size.width / 2);
    final initialY = -(_canvasSize / 2) + (size.height / 2);
    _transformationController.value =
        Matrix4.translationValues(initialX, initialY, 1.0);
  }

  Future<void> _loadData() async {
    try {
      final loadedNotes = await DatabaseHelper.getNotes();
      final loadedEdgesData = await DatabaseHelper.getEdges();

      final loadedEdges = loadedEdgesData.map((e) {
        return ConnectionEdge(
          sourceId: e['source_id'] as String,
          targetId: e['target_id'] as String,
          similarity: e['similarity'] as double,
        );
      }).toList();

      setState(() {
        _notes.clear();
        _notes.addAll(loadedNotes);
        _edges.clear();
        _edges.addAll(loadedEdges);
        _isLoading = false;
        _notesMap = {for (var n in loadedNotes) n.id: n};
      });

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _recenter();
          _runSemanticGravityLayout();
        }
      });
    } catch (e) {
      debugPrint('Error loading data from DB: $e');
      setState(() => _isLoading = false);
    }
  }



  // Force-directed layout — driven by a vsync Ticker.
  // Physics runs every tick; setState is batched every 3 ticks to avoid
  // rebuild storms. Uses velocity + damping for smooth, organic motion.
  void _runSemanticGravityLayout() {
    if (_isSimulatingLayout || _notes.isEmpty) return;

    _notes.shuffle();
    final matrix = _transformationController.value;
    final translation = matrix.getTranslation();
    final scale = matrix.getMaxScaleOnAxis();
    final size = MediaQuery.of(context).size;

    final minX = -translation.x / scale;
    final maxX = (size.width - translation.x) / scale;
    final minY = -translation.y / scale;
    final maxY = (size.height - translation.y) / scale;

    final rand = math.Random();
    for (final note in _notes) {
      if (note.locked) continue;
      final xRange = (maxX - minX - note.width - 40.0).clamp(0.0, double.infinity);
      final yRange = (maxY - minY - note.height - 40.0).clamp(0.0, double.infinity);
      note.position = Offset(
        minX + 20.0 + (xRange > 0.0 ? rand.nextDouble() * xRange : 0.0),
        minY + 20.0 + (yRange > 0.0 ? rand.nextDouble() * yRange : 0.0),
      );
    }

    _gravityTicker?.stop();
    _gravityTicker?.dispose();

    _nodeVelocities = {for (var n in _notes) n.id: Offset.zero};
    _gravityTickCount = 0;

    setState(() => _isSimulatingLayout = true);

    // ── Physics constants ──────────────────────────────────────────────────
    const double repulsionK    = 400000.0; // node–node repulsion strength
    const double attractionK   = 0.05;     // edge spring constant
    const double restLength    = 180.0;    // edge rest distance (px)
    const double cohesionK     = 0.008;    // weak pull toward group centroid
    const double damping       = 0.72;     // velocity damping per tick (higher damping = less oscillation)
    const double maxSpeed      = 12.0;     // px/tick speed cap
    const double stopThreshold = 0.3;      // avg speed below which we stop
    const int    batchFrames   = 1;        // setState every frame for perfect smoothness

    _gravityTicker = createTicker((_) {
      _gravityTickCount++;

      final Map<String, Offset> forces = {
        for (var n in _notes) n.id: Offset.zero
      };

      // ── Repulsion between every node pair ─────────────────────────────
      for (int i = 0; i < _notes.length; i++) {
        for (int j = i + 1; j < _notes.length; j++) {
          final nodeA = _notes[i];
          final nodeB = _notes[j];
          final centerA = nodeA.position + Offset(nodeA.width / 2, nodeA.height / 2);
          final centerB = nodeB.position + Offset(nodeB.width / 2, nodeB.height / 2);

          double dx = centerA.dx - centerB.dx;
          double dy = centerA.dy - centerB.dy;
          double dist = math.sqrt(dx * dx + dy * dy);
          if (dist < 1.0) { dx = 1.0; dist = 1.0; }

          // Apply repulsion whenever nodes are closer than a comfortable margin.
          final double minDist = (nodeA.width + nodeB.width) / 2 + 120.0;
          if (dist < minDist) {
            final double mag = repulsionK / (dist * dist + 10000.0);
            final Offset dir = Offset(dx / dist * mag, dy / dist * mag);
            forces[nodeA.id] = forces[nodeA.id]! + dir;
            forces[nodeB.id] = forces[nodeB.id]! - dir;
          }
        }
      }

      // ── Edge spring attraction ─────────────────────────────────────────
      for (final edge in _edges) {
        final nodeA = _notesMap[edge.sourceId];
        final nodeB = _notesMap[edge.targetId];
        if (nodeA == null || nodeB == null) continue;

        final centerA = nodeA.position + Offset(nodeA.width / 2, nodeA.height / 2);
        final centerB = nodeB.position + Offset(nodeB.width / 2, nodeB.height / 2);
        final double dx = centerB.dx - centerA.dx;
        final double dy = centerB.dy - centerA.dy;
        final double dist = math.sqrt(dx * dx + dy * dy);
        if (dist < 1.0) continue;

        // Spring only pulls — it doesn't push (repulsion handles that).
        if (dist > restLength) {
          final double mag = attractionK * (dist - restLength) * edge.similarity;
          final Offset dir = Offset(dx / dist * mag, dy / dist * mag);
          forces[nodeA.id] = forces[nodeA.id]! + dir;
          forces[nodeB.id] = forces[nodeB.id]! - dir;
        }
      }

      // ── Weak centroid cohesion ─────────────────────────────────────────
      // Compute centroid of unlocked nodes and apply a tiny pull toward it
      // so the graph stays compact and doesn't drift apart.
      final List<NoteNode> movable = _notes.where((n) => !n.locked).toList();
      if (movable.length > 1) {
        double cx = 0, cy = 0;
        for (final n in movable) {
          cx += n.position.dx + n.width / 2;
          cy += n.position.dy + n.height / 2;
        }
        cx /= movable.length;
        cy /= movable.length;
        for (final n in movable) {
          final ncx = n.position.dx + n.width / 2;
          final ncy = n.position.dy + n.height / 2;
          forces[n.id] = forces[n.id]! +
              Offset((cx - ncx) * cohesionK, (cy - ncy) * cohesionK);
        }
      }

      // ── Integrate velocities and positions (no setState yet) ───────────
      double totalSpeed = 0.0;
      for (final note in _notes) {
        if (note.locked) continue;
        Offset vel = (_nodeVelocities[note.id] ?? Offset.zero) * damping + (forces[note.id] ?? Offset.zero);
        final double speed = math.sqrt(vel.dx * vel.dx + vel.dy * vel.dy);
        if (speed > maxSpeed) vel = vel / speed * maxSpeed;
        _nodeVelocities[note.id] = vel;
        totalSpeed += speed;
        note.position = Offset(
          (note.position.dx + vel.dx).clamp(500.0, _canvasSize - 1000.0),
          (note.position.dy + vel.dy).clamp(500.0, _canvasSize - 1000.0),
        );
      }

      // ── Batch repaints: only call setState every N ticks ───────────────
      if (_gravityTickCount % batchFrames == 0) {
        setState(() {});
      }

      // ── Convergence / timeout check ────────────────────────────────────
      final int movingCount = movable.length;
      final double avgSpeed = movingCount > 0 ? totalSpeed / movingCount : 0.0;
      final bool converged  = avgSpeed < stopThreshold;
      final bool timedOut   = _gravityTickCount >= _maxGravityTicks;

      if (converged || timedOut) {
        _gravityTicker?.stop();
        // One final setState so the UI shows the settled positions.
        setState(() {
          _notesMap = {for (var n in _notes) n.id: n};
          _isSimulatingLayout = false;
        });
        for (final note in _notes) {
          DatabaseHelper.updateNotePositionAndSize(note);
        }
      }
    });

    _gravityTicker!.start();
  }

  void _addNewNoteAt(Offset localPosition) async {
    for (final note in _notes) {
      final rect = Rect.fromLTWH(
        note.position.dx,
        note.position.dy,
        note.width,
        note.height,
      );
      if (rect.contains(localPosition)) {
        return;
      }
    }
    final newNote = NoteNode(id: _uuid.v4(), position: localPosition);
    setState(() {
      _notes.add(newNote);
      _notesMap[newNote.id] = newNote;
    });
    await DatabaseHelper.insertNote(newNote);
    await _reloadEdgesOnly();
    final freshNotes = await DatabaseHelper.getNotes();
    setState(() {
      _notes.clear();
      _notes.addAll(freshNotes);
      _notesMap = {for (var n in freshNotes) n.id: n};
    });
    _runSemanticGravityLayout();
  }

  void _addNewNoteAtCenter() {
    final size = MediaQuery.of(context).size;
    final translation = _transformationController.value.getTranslation();
    final scale = _transformationController.value.getMaxScaleOnAxis();
    final localX = (-translation.x + size.width / 2 - 160) / scale;
    final localY = (-translation.y + size.height / 2 - 90) / scale;
    _addNewNoteAt(Offset(localX, localY));
  }

  void _deleteNote(NoteNode note) async {
    setState(() {
      _notes.removeWhere((n) => n.id == note.id);
      _edges.removeWhere(
          (e) => e.sourceId == note.id || e.targetId == note.id);
      _notesMap.remove(note.id);
    });
    await DatabaseHelper.deleteNote(note.id);
  }

  Future<void> _reloadEdgesOnly() async {
    final loadedEdgesData = await DatabaseHelper.getEdges();
    final loadedEdges = loadedEdgesData.map((e) {
      return ConnectionEdge(
        sourceId: e['source_id'] as String,
        targetId: e['target_id'] as String,
        similarity: e['similarity'] as double,
      );
    }).toList();
    setState(() {
      _edges.clear();
      _edges.addAll(loadedEdges);
    });
  }

  void _recenter({List<NoteNode>? targetNotesList}) {
    final size = MediaQuery.of(context).size;

    final targetNotes = targetNotesList ??
        (_isSearchActive && _searchQuery.isNotEmpty
            ? _notes
                .where((note) => note.content
                    .toLowerCase()
                    .contains(_searchQuery.toLowerCase()))
                .toList()
            : _notes);

    if (targetNotes.isEmpty) {
      final initialX = -(_canvasSize / 2) + (size.width / 2);
      final initialY = -(_canvasSize / 2) + (size.height / 2);
      setState(() {
        _transformationController.value =
            Matrix4.translationValues(initialX, initialY, 1.0);
      });
      return;
    }

    double minX = targetNotes.first.position.dx;
    double minY = targetNotes.first.position.dy;
    double maxX = targetNotes.first.position.dx + targetNotes.first.width;
    double maxY = targetNotes.first.position.dy + targetNotes.first.height;

    for (final note in targetNotes) {
      if (note.position.dx < minX) minX = note.position.dx;
      if (note.position.dy < minY) minY = note.position.dy;
      if (note.position.dx + note.width > maxX) {
        maxX = note.position.dx + note.width;
      }
      if (note.position.dy + note.height > maxY) {
        maxY = note.position.dy + note.height;
      }
    }

    setState(() {
      _transformationController.value = Matrix4.translationValues(
        (size.width / 2) - (minX + maxX) / 2,
        (size.height / 2) - (minY + maxY) / 2,
        1.0,
      );
    });
  }

  // ─── Bridge Mode ────────────────────────────────────────────────────────────

  void _toggleBridgeMode() {
    if (_isBridging) return; // Can't toggle during active synthesis
    setState(() {
      _isBridgeModeActive = !_isBridgeModeActive;
      if (!_isBridgeModeActive) {
        _bridgeNodeA = null;
        _bridgeNodeB = null;
        _beamOffsetA = null;
        _beamOffsetB = null;
        _bridgeCollapseProgress = 0.0;
        _bridgeCollapseController.reset();
      }
    });
  }

  /// Called when a note card is tapped during bridge selection mode.
  void _onBridgeNodeSelected(NoteNode node) {
    if (_isBridging) return;
    if (_bridgeNodeA == null) {
      setState(() {
        _bridgeNodeA = node;
        _beamOffsetA = _noteCanvasCenter(node);
      });
    } else if (_bridgeNodeA!.id != node.id && _bridgeNodeB == null) {
      setState(() {
        _bridgeNodeB = node;
        _beamOffsetB = _noteCanvasCenter(node);
      });
      // Both nodes selected → fire the collapse animation
      Future.delayed(const Duration(milliseconds: 200), () {
        if (mounted) _startBridgeCollapse();
      });
    }
  }

  /// Computes the canvas-local center Offset of a note (for beam drawing).
  Offset _noteCanvasCenter(NoteNode note) {
    return Offset(
      note.position.dx + note.width / 2,
      note.position.dy + note.height / 2,
    );
  }

  void _startBridgeCollapse() {
    setState(() => _isBridging = true);
    _bridgeCollapseController.forward(from: 0.0);
  }

  /// Called when the collapse animation completes — generates the bridge note.
  Future<void> _finalizeBridge() async {
    final nodeA = _bridgeNodeA;
    final nodeB = _bridgeNodeB;
    if (nodeA == null || nodeB == null) return;

    // ── 1. Compute geometric midpoint position ──────────────────────────────
    final midPos = Offset(
      (nodeA.position.dx + nodeB.position.dx) / 2,
      (nodeA.position.dy + nodeB.position.dy) / 2,
    );



    // ── 4. Create the bridge note ───────────────────────────────────────────
    final bridgeNote = NoteNode(
      id: _uuid.v4(),
      title: "",
      content: "",
      position: midPos,
      width: 280.0,
      height: 160.0,
      paperType: 'blank',
      isBridge: true,
    );

    // ── 5. Persist and reload ───────────────────────────────────────────────
    await DatabaseHelper.insertNote(bridgeNote);
    await _reloadEdgesOnly();
    final freshNotes = await DatabaseHelper.getNotes();

    if (mounted) {
      setState(() {
        _notes.clear();
        _notes.addAll(freshNotes);
        _notesMap = {for (var n in freshNotes) n.id: n};
        // Reset bridge mode
        _isBridgeModeActive = false;
        _isBridging = false;
        _bridgeNodeA = null;
        _bridgeNodeB = null;
        _beamOffsetA = null;
        _beamOffsetB = null;
        _bridgeCollapseProgress = 0.0;
      });
      _bridgeCollapseController.reset();
      _runSemanticGravityLayout();
    }
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final viewportSize = MediaQuery.of(context).size;

    if (_lastViewportSize != null && _lastViewportSize != viewportSize) {
      final matrix = _transformationController.value;
      final translation = matrix.getTranslation();
      final scale = matrix.getMaxScaleOnAxis();

      final oldCenter = Offset(_lastViewportSize!.width / 2, _lastViewportSize!.height / 2);
      final newCenter = Offset(viewportSize.width / 2, viewportSize.height / 2);

      final newTx = translation.x + (newCenter.dx - oldCenter.dx);
      final newTy = translation.y + (newCenter.dy - oldCenter.dy);

      // ignore: deprecated_member_use
      _transformationController.value = Matrix4.identity()
        // ignore: deprecated_member_use
        ..translate(newTx, newTy)
        // ignore: deprecated_member_use
        ..scale(scale);
    }
    _lastViewportSize = viewportSize;

    // Compute viewport-space beam offsets for the overlay painter.
    // Canvas-local coords → screen coords: screen = (canvas * scale) + translation
    Offset? screenBeamA;
    Offset? screenBeamB;
    if (_isBridgeModeActive || _isBridging) {
      final matrix = _transformationController.value;
      final scale = matrix.storage[0];
      final tx = matrix.storage[12];
      final ty = matrix.storage[13];

      if (_beamOffsetA != null) {
        screenBeamA = Offset(
          _beamOffsetA!.dx * scale + tx,
          _beamOffsetA!.dy * scale + ty,
        );
      }
      if (_beamOffsetB != null) {
        screenBeamB = Offset(
          _beamOffsetB!.dx * scale + tx,
          _beamOffsetB!.dy * scale + ty,
        );
      }
    }

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      extendBodyBehindAppBar: true,
      appBar: const AppHeader(),
      body: Stack(
        children: [
          // ── Canvas ────────────────────────────────────────────────────────
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : InteractiveViewer(
                  transformationController: _transformationController,
                  constrained: false,
                  boundaryMargin: const EdgeInsets.all(3000.0),
                  minScale: 0.2,
                  maxScale: 4.0,
                  onInteractionStart: (details) {
                    _viewportInteracting.value = true;
                    _previousMatrix =
                        _transformationController.value.clone();
                  },
                  onInteractionEnd: (details) {
                    _viewportInteracting.value = false;
                  },
                  onInteractionUpdate: (details) {
                    final currentMatrix = _transformationController.value;
                    final scale = currentMatrix.storage[0];
                    if (details.pointerCount > 1 &&
                        (scale <= 0.2 || scale >= 4.0)) {
                      if (_previousMatrix != null) {
                        final newMatrix = currentMatrix.clone();
                        newMatrix.setEntry(
                            0, 3, _previousMatrix!.entry(0, 3));
                        newMatrix.setEntry(
                            1, 3, _previousMatrix!.entry(1, 3));
                        newMatrix.setEntry(
                            2, 3, _previousMatrix!.entry(2, 3));
                        _transformationController.value = newMatrix;
                      }
                    }
                    _previousMatrix =
                        _transformationController.value.clone();
                  },
                  child: GestureDetector(
                    onDoubleTapDown: _isBridgeModeActive
                        ? null
                        : (details) => _addNewNoteAt(details.localPosition),
                    child: SizedBox(
                      width: _canvasSize,
                      height: _canvasSize,
                      child: CustomPaint(
                        painter: DottedGridPainter(
                          transform: _transformationController.value,
                          viewportSize: viewportSize,
                        ),
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            // Connections layer
                            Positioned.fill(
                              child: RepaintBoundary(
                                child: AnimatedBuilder(
                                  animation: _connectionAnimationController,
                                  builder: (context, _) => CustomPaint(
                                    painter: ConnectionsPainter(
                                      notes: _notes,
                                      edges: _edges,
                                      animationValue:
                                          _connectionAnimationController
                                              .value,
                                      noteMap: _notesMap,
                                      searchQuery: _searchQuery,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            // Note cards layer
                            Positioned.fill(
                              child: RepaintBoundary(
                                child: Stack(
                                  clipBehavior: Clip.none,
                                  children: _notes.map((note) {
                                    final bool matches =
                                        _searchQuery.isEmpty ||
                                            note.content.toLowerCase().contains(
                                                _searchQuery.toLowerCase());
                                    final bool isBridgeSelected =
                                        _isBridgeModeActive &&
                                            (_bridgeNodeA?.id == note.id ||
                                                _bridgeNodeB?.id == note.id);
                                    return DraggableResizableNoteCard(
                                      key: ValueKey(note.id),
                                      note: note,
                                      matches: matches,
                                      viewportInteracting: _viewportInteracting,
                                      isBridgeSelected: isBridgeSelected,
                                      onBridgeTap: _isBridgeModeActive && !_isBridging
                                          ? () => _onBridgeNodeSelected(note)
                                          : null,
                                      onDelete: () => _deleteNote(note),
                                      onSave: (updatedNote) async {
                                        await DatabaseHelper
                                            .updateNote(updatedNote);
                                        await _reloadEdgesOnly();
                                        final freshNotes = await DatabaseHelper
                                            .getNotes();
                                        setState(() {
                                          _notes.clear();
                                          _notes.addAll(freshNotes);
                                          _notesMap = {
                                            for (var n in freshNotes) n.id: n
                                          };
                                        });
                                      },
                                      onLayoutChanged:
                                          (updatedNote) async {
                                        await DatabaseHelper
                                            .updateNotePositionAndSize(
                                                updatedNote);
                                        setState(() {});
                                      },
                                      onDragUpdate: (updatedNote) =>
                                          setState(() {}),
                                    );
                                  }).toList(),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

          // ── Bridge Beam Overlay (screen-space, drawn above canvas) ─────────
          if ((_isBridgeModeActive || _isBridging) && screenBeamA != null)
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedBuilder(
                  animation: _bridgeBeamController,
                  builder: (context, _) => CustomPaint(
                    painter: BridgeBeamPainter(
                      nodeA: screenBeamA,
                      nodeB: screenBeamB,
                      animationValue: _bridgeBeamController.value,
                      collapseProgress: _bridgeCollapseProgress,
                    ),
                  ),
                ),
              ),
            ),

          if (!_isLoading) ...[
            // ── Bridge Mode Top Banner ─────────────────────────────────────
            if (_isBridgeModeActive || _isBridging)
              Positioned(
                top: 52,
                left: 0,
                right: 0,
                child: Center(
                  child: _buildBridgeBanner(),
                ),
              ),

            // ── Bottom Command Dock ────────────────────────────────────────
            if (!_isBridgeModeActive && !_isBridging)
              Positioned(
                bottom: 24,
                left: 0,
                right: 0,
                child: Center(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    transitionBuilder: (child, anim) =>
                        FadeTransition(opacity: anim, child: child),
                    child: _isSearchActive
                        ? _buildSearchBar()
                        : _buildCommandDock(),
                  ),
                ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.3, end: 0.0),
              ),



            // ── Status Toast ───────────────────────────────────────────────
            if (_isRebuildingEdges || _isSimulatingLayout)
              Positioned(
                top: 52,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 9),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1C1C2E)
                          .withValues(alpha: 0.93),
                      borderRadius: BorderRadius.circular(22),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.25),
                          blurRadius: 16,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(
                          width: 13,
                          height: 13,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.8,
                            color: Color(0xFF818CF8),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          _isRebuildingEdges
                              ? 'Running semantic indexing…'
                              : 'Simulating gravity…',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color:
                                Colors.white.withValues(alpha: 0.88),
                            fontWeight: FontWeight.w500,
                            letterSpacing: 0.1,
                          ),
                        ),
                      ],
                    ),
                  ).animate().fadeIn(duration: 180.ms),
                ),
              ),
          ],
        ],
      ),
    );
  }

  // ─── Bridge mode banner ───────────────────────────────────────────────────

  Widget _buildBridgeBanner() {
    final String label;
    final String sublabel;
    final Color glowColor;

    if (_isBridging) {
      label = 'Synthesizing Bridge…';
      sublabel = 'Computing semantic midpoint';
      glowColor = const Color(0xFF6366F1);
    } else if (_bridgeNodeA == null) {
      label = 'Bridge Mode';
      sublabel = 'Select the first note';
      glowColor = const Color(0xFFF59E0B);
    } else {
      label = 'Bridge Mode';
      sublabel = 'Select the second note to synthesize';
      glowColor = const Color(0xFFF59E0B);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF18181B).withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: glowColor.withValues(alpha: 0.45),
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: glowColor.withValues(alpha: 0.25),
            blurRadius: 24,
            offset: const Offset(0, 4),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Animated icon
          if (_isBridging)
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2.0,
                color: Color(0xFF818CF8),
              ),
            )
          else
            ShaderMask(
              shaderCallback: (bounds) => const LinearGradient(
                colors: [Color(0xFFF59E0B), Color(0xFF818CF8)],
              ).createShader(bounds),
              child: const Icon(
                Icons.merge_type_rounded,
                size: 18,
                color: Colors.white,
              ),
            ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: GoogleFonts.outfit(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  letterSpacing: -0.2,
                ),
              ),
              Text(
                sublabel,
                style: GoogleFonts.inter(
                  fontSize: 10.5,
                  color: Colors.white.withValues(alpha: 0.45),
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ),

          // Node A indicator
          if (_bridgeNodeA != null && !_isBridging) ...[
            const SizedBox(width: 14),
            Container(
              width: 1,
              height: 24,
              color: Colors.white.withValues(alpha: 0.1),
            ),
            const SizedBox(width: 14),
            _BridgeNodeIndicator(
              label: _truncateNodeLabel(_bridgeNodeA!),
              color: const Color(0xFFF59E0B),
              index: 'A',
            ),
          ],
          if (_bridgeNodeA != null && _bridgeNodeB != null && !_isBridging) ...[
            const SizedBox(width: 8),
            const Icon(Icons.arrow_forward_rounded,
                size: 14, color: Color(0xFF6B7280)),
            const SizedBox(width: 8),
            _BridgeNodeIndicator(
              label: _truncateNodeLabel(_bridgeNodeB!),
              color: const Color(0xFF818CF8),
              index: 'B',
            ),
          ],

          // Cancel button
          if (!_isBridging) ...[
            const SizedBox(width: 14),
            Container(
              width: 1,
              height: 24,
              color: Colors.white.withValues(alpha: 0.1),
            ),
            const SizedBox(width: 10),
            _BridgeCancelBtn(onTap: _toggleBridgeMode),
          ],
        ],
      ),
    ).animate().fadeIn(duration: 250.ms).slideY(begin: -0.2, end: 0.0);
  }

  String _truncateNodeLabel(NoteNode node) {
    final raw = node.content.startsWith('[') ? 'Note' : node.content;
    final cleaned = raw.replaceAll('\n', ' ').trim();
    return cleaned.length > 18 ? '${cleaned.substring(0, 18)}…' : cleaned;
  }

  // ─── Dark command dock ────────────────────────────────────────────────────

  Widget _buildCommandDock() {
    return Container(
      key: const ValueKey('dock'),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFF18181B),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.40),
            blurRadius: 32,
            offset: const Offset(0, 10),
          ),
          BoxShadow(
            color: Colors.white.withValues(alpha: 0.04),
            blurRadius: 0,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _DockBtn(
            icon: Icons.search_rounded,
            tooltip: 'Search notes',
            onTap: () => setState(() => _isSearchActive = true),
          ),
          _DockBtn(
            icon: Icons.my_location_rounded,
            tooltip: 'Focus view',
            onTap: _recenter,
          ),
          // ── Bridge button ─────────────────────────────────────────────
          _DockBtn(
            icon: Icons.merge_type_rounded,
            tooltip: 'Thought Bridge — select two notes to synthesize a connection',
            active: _isBridgeModeActive,
            activeColor: const Color(0xFFF59E0B),
            onTap: _isBridging ? null : _toggleBridgeMode,
          ),
          _DockBtn(
            icon: Icons.hub_rounded,
            tooltip: 'Run semantic gravity',
            loading: _isSimulatingLayout,
            onTap:
                _isSimulatingLayout ? null : _runSemanticGravityLayout,
          ),
          Container(
            width: 1,
            height: 26,
            color: const Color(0xFF3F3F46),
            margin: const EdgeInsets.symmetric(horizontal: 6),
          ),
          GestureDetector(
            onTap: _addNewNoteAtCenter,
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 9),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF6366F1)
                        .withValues(alpha: 0.45),
                    blurRadius: 14,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.add_rounded,
                      size: 16, color: Colors.white),
                  const SizedBox(width: 6),
                  Text(
                    'New Note',
                    style: GoogleFonts.outfit(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Dark search bar ──────────────────────────────────────────────────────

  Widget _buildSearchBar() {
    return Container(
      key: const ValueKey('search'),
      width: 380,
      padding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF18181B),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.40),
            blurRadius: 32,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.search_rounded,
              size: 18, color: Color(0xFF6B7280)),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              autofocus: true,
              onChanged: (value) =>
                  setState(() => _searchQuery = value),
              style: GoogleFonts.inter(
                fontSize: 14,
                color: Colors.white,
                fontWeight: FontWeight.w400,
              ),
              decoration: InputDecoration(
                hintText: 'Search notes…',
                hintStyle: GoogleFonts.inter(
                  color: const Color(0xFF6B7280),
                  fontSize: 14,
                ),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: () => setState(() {
              _isSearchActive = false;
              _searchQuery = '';
            }),
            child: Container(
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.close_rounded,
                  size: 14, color: Color(0xFF9CA3AF)),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// _BridgeNodeIndicator — small pill showing a selected bridge node label
// ═══════════════════════════════════════════════════════════════════════════════

class _BridgeNodeIndicator extends StatelessWidget {
  final String label;
  final Color color;
  final String index;

  const _BridgeNodeIndicator({
    required this.label,
    required this.color,
    required this.index,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 14,
            height: 14,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              index,
              style: GoogleFonts.outfit(
                fontSize: 8,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 10.5,
              fontWeight: FontWeight.w500,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// _BridgeCancelBtn
// ═══════════════════════════════════════════════════════════════════════════════

class _BridgeCancelBtn extends StatefulWidget {
  final VoidCallback onTap;
  const _BridgeCancelBtn({required this.onTap});

  @override
  State<_BridgeCancelBtn> createState() => _BridgeCancelBtnState();
}

class _BridgeCancelBtnState extends State<_BridgeCancelBtn> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 130),
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: _hovered
                ? Colors.white.withValues(alpha: 0.08)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            Icons.close_rounded,
            size: 15,
            color: Colors.white.withValues(alpha: _hovered ? 0.7 : 0.3),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// _DockBtn — icon-only button in the command dock
// ═══════════════════════════════════════════════════════════════════════════════

class _DockBtn extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final bool active;
  final bool loading;
  final Color? activeColor;
  final VoidCallback? onTap;

  const _DockBtn({
    required this.icon,
    required this.tooltip,
    this.active = false,
    this.loading = false,
    this.activeColor,
    this.onTap,
  });

  @override
  State<_DockBtn> createState() => _DockBtnState();
}

class _DockBtnState extends State<_DockBtn> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final bool enabled = widget.onTap != null && !widget.loading;
    final Color resolvedActiveColor = widget.activeColor ?? const Color(0xFF818CF8);
    final Color iconColor = widget.active
        ? resolvedActiveColor
        : _hovered
            ? Colors.white
            : const Color(0xFF9CA3AF);

    return Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 500),
      preferBelow: false,
      child: MouseRegion(
        cursor: enabled
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: enabled ? widget.onTap : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            padding: const EdgeInsets.symmetric(
                horizontal: 13, vertical: 8),
            decoration: BoxDecoration(
              color: _hovered
                  ? Colors.white.withValues(alpha: 0.09)
                  : widget.active
                      ? resolvedActiveColor.withValues(alpha: 0.18)
                      : Colors.transparent,
              borderRadius: BorderRadius.circular(16),
            ),
            child: widget.loading
                ? const SizedBox(
                    width: 19,
                    height: 19,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.8,
                      color: Color(0xFF818CF8),
                    ),
                  )
                : Icon(widget.icon, size: 19, color: iconColor),
          ),
        ),
      ),
    );
  }
}
