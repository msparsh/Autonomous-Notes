import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes/main.dart';
import 'package:notes/helpers/database_helper.dart';
import 'package:sqflite/sqflite.dart';

class MockDatabase extends Fake implements Database {
  @override
  Future<List<Map<String, Object?>>> query(
    String table, {
    bool? distinct,
    List<String>? columns,
    String? where,
    List<Object?>? whereArgs,
    String? groupBy,
    String? having,
    String? orderBy,
    int? limit,
    int? offset,
  }) async {
    return []; // Return an empty list of notes for the test
  }
}

void main() {
  testWidgets('Canvas Note App smoke test', (WidgetTester tester) async {
    // Inject MockDatabase
    DatabaseHelper.databaseInstance = MockDatabase();

    // Build our app and trigger a frame.
    await tester.pumpWidget(const CanvasNoteApp());

    // Allow database loading to complete
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // Verify that the search input is present.
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Search notes...'), findsOneWidget);
  });
}

