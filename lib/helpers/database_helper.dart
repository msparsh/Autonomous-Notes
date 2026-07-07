import 'dart:io';
import 'dart:ui';
import 'dart:convert';
import 'dart:math' as math;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../models/note_node.dart';
import '../models/note_group.dart';
import '../utils/vector_engine.dart';

class DatabaseHelper {
  static Database? databaseInstance;

  static Future<Database> get database async {
    if (databaseInstance != null) return databaseInstance!;
    databaseInstance = await _initDatabase();
    return databaseInstance!;
  }

  static Future<Database> _initDatabase() async {
    final docDir = await getApplicationDocumentsDirectory();
    final notesDir = Directory(p.join(docDir.path, 'Notes'));
    if (!await notesDir.exists()) {
      await notesDir.create(recursive: true);
    }
    final dbPath = p.join(notesDir.path, 'notes.db');

    return await openDatabase(
      dbPath,
      version: 7,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE notes(
            id TEXT PRIMARY KEY,
            title TEXT,
            content TEXT,
            position_x REAL,
            position_y REAL,
            width REAL,
            height REAL,
            paper_type TEXT DEFAULT 'blank',
            locked INTEGER DEFAULT 0,
            color_index INTEGER DEFAULT 0,
            is_bridge INTEGER DEFAULT 0
          )
        ''');
        await db.execute('''
          CREATE TABLE note_vectors(
            note_id TEXT PRIMARY KEY,
            vector TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE edges(
            id TEXT PRIMARY KEY,
            source_id TEXT,
            target_id TEXT,
            similarity REAL
          )
        ''');
        await db.execute('''
          CREATE TABLE vocab(
            id INTEGER PRIMARY KEY,
            word_list TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE note_groups(
            id TEXT PRIMARY KEY,
            name TEXT,
            color_index INTEGER
          )
        ''');
        await db.execute('''
          CREATE TABLE group_notes(
            group_id TEXT,
            note_id TEXT,
            PRIMARY KEY (group_id, note_id)
          )
        ''');
        await _insertMockNotes(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          try {
            await db.execute("ALTER TABLE notes ADD COLUMN paper_type TEXT DEFAULT 'blank'");
          } catch (_) {}
          try {
            await db.execute("ALTER TABLE notes ADD COLUMN locked INTEGER DEFAULT 0");
          } catch (_) {}
        }
        if (oldVersion < 3) {
          try {
            await db.execute("ALTER TABLE notes ADD COLUMN color_index INTEGER DEFAULT 0");
          } catch (_) {}
        }
        if (oldVersion < 4) {
          try {
            await db.execute('''
              CREATE TABLE IF NOT EXISTS note_vectors(
                note_id TEXT PRIMARY KEY,
                vector TEXT
              )
            ''');
          } catch (_) {}
          try {
            await db.execute('''
              CREATE TABLE IF NOT EXISTS edges(
                id TEXT PRIMARY KEY,
                source_id TEXT,
                target_id TEXT,
                similarity REAL
              )
            ''');
          } catch (_) {}
          final countMap = await db.rawQuery("SELECT COUNT(*) as count FROM notes");
          final count = countMap.first['count'] as int? ?? 0;
          if (count == 0) {
            await _insertMockNotes(db);
          }
        }
        if (oldVersion < 5) {
          // Delete old mocks to make room for the new set
          final oldMockIds = ['mock-note-cpp', 'mock-note-rust', 'mock-note-pasta', 'mock-note-bread'];
          for (final id in oldMockIds) {
            await db.delete('notes', where: 'id = ?', whereArgs: [id]);
          }
          await _insertMockNotes(db);
        }
        if (oldVersion < 6) {
          // Add the vocab table for bridge synthesis
          try {
            await db.execute('''
              CREATE TABLE IF NOT EXISTS vocab(
                id INTEGER PRIMARY KEY,
                word_list TEXT
              )
            ''');
          } catch (_) {}
          // Add is_bridge flag to existing notes table
          try {
            await db.execute("ALTER TABLE notes ADD COLUMN is_bridge INTEGER DEFAULT 0");
          } catch (_) {}
          // Re-run recalculation to populate vocab table
          await _recalculateAllEdgesWithDb(db);
        }
        if (oldVersion < 7) {
          try {
            await db.execute('''
              CREATE TABLE IF NOT EXISTS note_groups(
                id TEXT PRIMARY KEY,
                name TEXT,
                color_index INTEGER
              )
            ''');
          } catch (_) {}
          try {
            await db.execute('''
              CREATE TABLE IF NOT EXISTS group_notes(
                group_id TEXT,
                note_id TEXT,
                PRIMARY KEY (group_id, note_id)
              )
            ''');
          } catch (_) {}
        }
      },
    );
  }

  static Future<void> _insertMockNotes(Database db) async {
     // removed mocks

    // Generate vectors and edges for mocks
    await _recalculateAllEdgesWithDb(db);
  }

  static Future<List<NoteNode>> getNotes() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query('notes');
    return List.generate(maps.length, (i) {
      return NoteNode(
        id: maps[i]['id'] as String,
        title: maps[i]['title'] as String? ?? '',
        content: maps[i]['content'] as String? ?? '',
        position: Offset(
          maps[i]['position_x'] as double? ?? 0.0,
          maps[i]['position_y'] as double? ?? 0.0,
        ),
        width: maps[i]['width'] as double? ?? 320.0,
        height: maps[i]['height'] as double? ?? 160.0,
        paperType: maps[i]['paper_type'] as String? ?? 'blank',
        locked: (maps[i]['locked'] as int? ?? 0) == 1,
        colorIndex: maps[i]['color_index'] as int? ?? 0,
        isBridge: (maps[i]['is_bridge'] as int? ?? 0) == 1,
      );
    });
  }

  static Future<void> insertNote(NoteNode note) async {
    final db = await database;
    await db.insert(
      'notes',
      {
        'id': note.id,
        'title': note.title,
        'content': note.content,
        'position_x': note.position.dx,
        'position_y': note.position.dy,
        'width': note.width,
        'height': note.height,
        'paper_type': note.paperType,
        'locked': note.locked ? 1 : 0,
        'color_index': note.colorIndex,
        'is_bridge': note.isBridge ? 1 : 0,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await _updateNoteVectorAndEdges(db, note.id, note.title, note.content);
  }

  static Future<void> updateNote(NoteNode note) async {
    final db = await database;
    await db.update(
      'notes',
      {
        'title': note.title,
        'content': note.content,
        'position_x': note.position.dx,
        'position_y': note.position.dy,
        'width': note.width,
        'height': note.height,
        'paper_type': note.paperType,
        'locked': note.locked ? 1 : 0,
        'color_index': note.colorIndex,
        'is_bridge': note.isBridge ? 1 : 0,
      },
      where: 'id = ?',
      whereArgs: [note.id],
    );
    await _updateNoteVectorAndEdges(db, note.id, note.title, note.content);
  }

  static Future<void> updateNotePositionAndSize(NoteNode note) async {
    final db = await database;
    await db.update(
      'notes',
      {
        'position_x': note.position.dx,
        'position_y': note.position.dy,
        'width': note.width,
        'height': note.height,
      },
      where: 'id = ?',
      whereArgs: [note.id],
    );
  }

  static Future<void> deleteNote(String id) async {
    final db = await database;
    await db.delete(
      'notes',
      where: 'id = ?',
      whereArgs: [id],
    );
    await db.delete(
      'note_vectors',
      where: 'note_id = ?',
      whereArgs: [id],
    );
    await db.delete(
      'edges',
      where: 'source_id = ? OR target_id = ?',
      whereArgs: [id, id],
    );
    // Remove node from any group associations
    await db.delete(
      'group_notes',
      where: 'note_id = ?',
      whereArgs: [id],
    );
  }

  // --- Group Queries ---

  static Future<List<NoteGroup>> getGroups() async {
    final db = await database;
    final List<Map<String, dynamic>> groupMaps = await db.query('note_groups');
    final List<NoteGroup> groups = [];
    for (final map in groupMaps) {
      final String groupId = map['id'] as String;
      final List<Map<String, dynamic>> noteMaps = await db.query(
        'group_notes',
        columns: ['note_id'],
        where: 'group_id = ?',
        whereArgs: [groupId],
      );
      final List<String> noteIds = noteMaps.map((e) => e['note_id'] as String).toList();
      groups.add(NoteGroup(
        id: groupId,
        name: map['name'] as String? ?? '',
        noteIds: noteIds,
        colorIndex: map['color_index'] as int? ?? 0,
      ));
    }
    return groups;
  }

  static Future<void> insertGroup(NoteGroup group) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.insert(
        'note_groups',
        {
          'id': group.id,
          'name': group.name,
          'color_index': group.colorIndex,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      // Clean old note assignments
      await txn.delete(
        'group_notes',
        where: 'group_id = ?',
        whereArgs: [group.id],
      );
      // Insert new note assignments
      for (final noteId in group.noteIds) {
        await txn.insert(
          'group_notes',
          {
            'group_id': group.id,
            'note_id': noteId,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  static Future<void> updateGroup(NoteGroup group) async {
    await insertGroup(group); // insert with replace handles transaction/updates perfectly
  }

  static Future<void> deleteGroup(String groupId) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete(
        'note_groups',
        where: 'id = ?',
        whereArgs: [groupId],
      );
      await txn.delete(
        'group_notes',
        where: 'group_id = ?',
        whereArgs: [groupId],
      );
    });
  }

  // Vector & Edges calculations helper

  static Future<void> _updateNoteVectorAndEdges(
      Database db, String noteId, String title, String content) async {
    // Simply delegate single updates to full recalculation, ensuring
    // that the dynamic vocabulary is kept synchronized across all notes.
    await _recalculateAllEdgesWithDb(db);
  }

  /// Reset all vectors and recalculate all connections from scratch
  static Future<void> recalculateAllEdges() async {
    final db = await database;
    await _recalculateAllEdgesWithDb(db);
  }

  // ─── Bridge Synthesis Helpers ──────────────────────────────────────────────

  /// Retrieve the stored vector for a single note (decoded from JSON).
  static Future<List<double>?> getVectorForNote(String noteId) async {
    final db = await database;
    final rows = await db.query(
      'note_vectors',
      where: 'note_id = ?',
      whereArgs: [noteId],
    );
    if (rows.isEmpty) return null;
    final encoded = rows.first['vector'] as String?;
    if (encoded == null) return null;
    try {
      final decoded = jsonDecode(encoded) as List<dynamic>;
      return decoded.map((v) => (v as num).toDouble()).toList();
    } catch (_) {
      return null;
    }
  }

  /// Retrieve the stored vocabulary list from the last recalculation.
  /// Returns an empty list if not yet populated.
  static Future<List<String>> getVocabulary() async {
    final db = await database;
    try {
      final rows = await db.query('vocab', limit: 1);
      if (rows.isEmpty) return [];
      final encoded = rows.first['word_list'] as String?;
      if (encoded == null) return [];
      final decoded = jsonDecode(encoded) as List<dynamic>;
      return decoded.map((v) => v as String).toList();
    } catch (_) {
      return [];
    }
  }

  // ─────────────────────────────────────────────────────────────────────────

  static Future<void> _recalculateAllEdgesWithDb(Database db) async {
    // Clear current vectors and edges
    await db.delete('note_vectors');
    await db.delete('edges');

    final List<Map<String, dynamic>> notes = await db.query('notes');
    if (notes.isEmpty) return;

    // 1. Build a dynamic vocabulary from all notes
    final Set<String> vocabularySet = {};
    final Map<String, List<String>> noteTokenized = {};

    for (final note in notes) {
      final id = note['id'] as String;
      final content = note['content'] as String? ?? '';

      // Tokenize content (supports fallback if it was saved in Quill Delta)
      final tokens = VectorEngine.tokenize(VectorEngine.tokenizeQuillJson(content));
      noteTokenized[id] = tokens;
      vocabularySet.addAll(tokens);
    }

    final List<String> vocabList = vocabularySet.toList();
    if (vocabList.isEmpty) return;

    // Persist the vocabulary for bridge synthesis use
    await db.delete('vocab');
    await db.insert('vocab', {
      'id': 1,
      'word_list': jsonEncode(vocabList),
    }, conflictAlgorithm: ConflictAlgorithm.replace);

    // 2. Generate term-frequency vectors for each note based on exact dynamic vocabulary
    final Map<String, List<double>> generatedVectors = {};

    for (final note in notes) {
      final id = note['id'] as String;
      final tokens = noteTokenized[id]!;

      final Map<String, double> termCounts = {};
      for (final tok in tokens) {
        termCounts[tok] = (termCounts[tok] ?? 0.0) + 1.0;
      }

      final List<double> vector = List.filled(vocabList.length, 0.0);
      for (int i = 0; i < vocabList.length; i++) {
        final term = vocabList[i];
        if (termCounts.containsKey(term)) {
          vector[i] = termCounts[term]!;
        }
      }

      // Normalize the vector
      double sumSq = 0.0;
      for (final val in vector) {
        sumSq += val * val;
      }
      if (sumSq > 0.0) {
        final double magnitude = math.sqrt(sumSq);
        for (int i = 0; i < vector.length; i++) {
          vector[i] /= magnitude;
        }
      }

      generatedVectors[id] = vector;

      await db.insert(
        'note_vectors',
        {
          'note_id': id,
          'vector': jsonEncode(vector),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    // Fetch group notes mapping to enforce group exclusivity
    final List<Map<String, dynamic>> groupNotesRows = await db.query('group_notes');
    final Map<String, Set<String>> noteToGroups = {};
    for (final row in groupNotesRows) {
      final noteId = row['note_id'] as String;
      final groupId = row['group_id'] as String;
      noteToGroups.putIfAbsent(noteId, () => {}).add(groupId);
    }

    // 3. Double loop for similarity calculation & edge generation
    final ids = generatedVectors.keys.toList();
    for (int i = 0; i < ids.length; i++) {
      for (int j = i + 1; j < ids.length; j++) {
        final idA = ids[i];
        final idB = ids[j];

        final groupsA = noteToGroups[idA] ?? {};
        final groupsB = noteToGroups[idB] ?? {};
        final bool canRelate = (groupsA.isEmpty && groupsB.isEmpty) ||
            groupsA.intersection(groupsB).isNotEmpty;
        if (!canRelate) continue;

        final vecA = generatedVectors[idA]!;
        final vecB = generatedVectors[idB]!;

        final similarity = VectorEngine.computeSimilarity(vecA, vecB);
        // Clean overlap metric: 0.15 threshold is high enough for keyword overlap
        if (similarity >= 0.15) {
          final edgeId = '${idA}_$idB';
          await db.insert(
            'edges',
            {
              'id': edgeId,
              'source_id': idA,
              'target_id': idB,
              'similarity': similarity,
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      }
    }

    // Auto-assign matching colors to similar notes (clusters)
    await _assignClusterColors(db);
  }

  /// Runs Union-Find (DSU) on active edges and updates note card colorIndex automatically
  static Future<void> _assignClusterColors(Database db) async {
    final List<Map<String, dynamic>> notes = await db.query('notes');
    if (notes.isEmpty) return;

    final List<Map<String, dynamic>> edges = await db.query('edges');

    // DSU Initialization
    final Map<String, String> parent = {for (var n in notes) n['id'] as String: n['id'] as String};

    String find(String i) {
      if (parent[i] == i) return i;
      parent[i] = find(parent[i]!); // path compression
      return parent[i]!;
    }

    void union(String i, String j) {
      final rootI = find(i);
      final rootJ = find(j);
      if (rootI != rootJ) {
        parent[rootI] = rootJ;
      }
    }

    // Connect nodes with edges
    for (final edge in edges) {
      final s = edge['source_id'] as String;
      final t = edge['target_id'] as String;
      if (parent.containsKey(s) && parent.containsKey(t)) {
        union(s, t);
      }
    }

    // Group note IDs by root parent
    final Map<String, List<String>> groups = {};
    for (final note in notes) {
      final id = note['id'] as String;
      final root = find(id);
      groups.putIfAbsent(root, () => []).add(id);
    }

    // Assign colors based on clusters
    // Index 0: Classic White (for isolated nodes)
    // Indices 1..6: Curated colors (for cluster members, cycled)
    int colorCounter = 1;
    for (final entry in groups.entries) {
      final members = entry.value;
      if (members.length < 2) {
        // Isolated node gets classic white
        for (final id in members) {
          await db.update('notes', {'color_index': 0}, where: 'id = ?', whereArgs: [id]);
        }
      } else {
        // Group of connected nodes gets a matching color
        final clusterColor = colorCounter;
        colorCounter = (colorCounter % 6) + 1; // cycle 1 to 6
        for (final id in members) {
          await db.update('notes', {'color_index': clusterColor}, where: 'id = ?', whereArgs: [id]);
        }
      }
    }
  }

  /// Retrieve all generated edges
  static Future<List<Map<String, dynamic>>> getEdges() async {
    final db = await database;
    return await db.query('edges');
  }
}
