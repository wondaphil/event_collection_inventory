// lib/db/database_migration.dart
import 'dart:typed_data';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

class DatabaseMigration {
  static final Uuid _uuid = const Uuid();

  static Future<void> runMigrations(Database db) async {
    await _ensureDeviceInfo(db);
    await _upgradeCategories(db);
    await _upgradeItems(db);
    await _upgradeTransactions(db);
    await _createIndexes(db);
  }

  // ---------------------------------------------------------------------------
  // DEVICE INFO
  // ---------------------------------------------------------------------------
  static Future<void> _ensureDeviceInfo(Database db) async {
    await db.execute("""
      CREATE TABLE IF NOT EXISTS device_info (
        device_id TEXT PRIMARY KEY
      )
    """);
  }

  // ---------------------------------------------------------------------------
  // SMALL UTIL
  // ---------------------------------------------------------------------------
  static Future<List<String>> _cols(Database db, String table) async {
    final rows = await db.rawQuery("PRAGMA table_info($table)");
    return rows.map((e) => e["name"] as String).toList();
  }

  static String _hash(Uint8List? bytes) {
    if (bytes == null || bytes.isEmpty) return "";
    return sha1.convert(bytes).toString();
  }

  // ---------------------------------------------------------------------------
  // CATEGORIES
  // ---------------------------------------------------------------------------
  static Future<void> _upgradeCategories(Database db) async {
    final c = await _cols(db, "categories");

    if (!c.contains("uuid")) {
      await db.execute("ALTER TABLE categories ADD COLUMN uuid TEXT");
      final rows = await db.query("categories");
      for (final r in rows) {
        await db.update("categories", {"uuid": _uuid.v4()},
            where: "id=?", whereArgs: [r["id"]]);
      }
    }

    if (!c.contains("updated_at")) {
      await db.execute("ALTER TABLE categories ADD COLUMN updated_at TEXT");
      await db.execute("UPDATE categories SET updated_at = createdAt");
    }

    if (!c.contains("deleted")) {
      await db.execute(
          "ALTER TABLE categories ADD COLUMN deleted INTEGER DEFAULT 0");
      await db.execute("UPDATE categories SET deleted = 0");
    }
  }

  // ---------------------------------------------------------------------------
  // ITEMS (includes photoHash generation)
  // ---------------------------------------------------------------------------
  static Future<void> _upgradeItems(Database db) async {
    final c = await _cols(db, "items");

    if (!c.contains("uuid")) {
      await db.execute("ALTER TABLE items ADD COLUMN uuid TEXT");
      final rows = await db.query("items");
      for (final r in rows) {
        await db.update("items", {"uuid": _uuid.v4()},
            where: "id=?", whereArgs: [r["id"]]);
      }
    }

    if (!c.contains("category_uuid")) {
      await db.execute("ALTER TABLE items ADD COLUMN category_uuid TEXT");
      final rows = await db.rawQuery("""
        SELECT items.id AS iid, categories.uuid AS cuuid
        FROM items LEFT JOIN categories ON items.categoryId = categories.id
      """);
      for (final r in rows) {
        await db.update("items", {"category_uuid": r["cuuid"]},
            where: "id=?", whereArgs: [r["iid"]]);
      }
    }

    if (!c.contains("deleted")) {
      await db.execute("ALTER TABLE items ADD COLUMN deleted INTEGER DEFAULT 0");
      await db.execute("UPDATE items SET deleted = 0");
    }

    // ⭐ NEW — ADD photoHash
    // ⭐ Ensure photoHash column exists
	if (!c.contains("photoHash")) {
	  await db.execute("ALTER TABLE items ADD COLUMN photoHash TEXT");
	}

	// ⭐ Always recompute hash for ALL items
	final rows = await db.query("items", columns: ["id", "photo"]);
	for (final r in rows) {
	  Uint8List? bytes;
	  final raw = r["photo"];

	  if (raw != null) {
		if (raw is Uint8List) bytes = raw;
		else if (raw is List<int>) bytes = Uint8List.fromList(raw);
	  }

	  final hash = _hash(bytes);

	  await db.update(
		"items",
		{"photoHash": hash},
		where: "id = ?",
		whereArgs: [r["id"]],
	  );
	}
  }

  // ---------------------------------------------------------------------------
  // TRANSACTIONS
  // ---------------------------------------------------------------------------
  static Future<void> _upgradeTransactions(Database db) async {
    final c = await _cols(db, "stock_transactions");

    if (!c.contains("uuid")) {
      await db.execute("ALTER TABLE stock_transactions ADD COLUMN uuid TEXT");
      final rows = await db.query("stock_transactions");
      for (final r in rows) {
        await db.update("stock_transactions", {"uuid": _uuid.v4()},
            where: "id=?", whereArgs: [r["id"]]);
      }
    }

    if (!c.contains("item_uuid")) {
      await db.execute(
          "ALTER TABLE stock_transactions ADD COLUMN item_uuid TEXT");

      final rows = await db.rawQuery("""
        SELECT stock_transactions.id AS tid, items.uuid AS iuuid
        FROM stock_transactions
        LEFT JOIN items ON stock_transactions.itemId = items.id
      """);

      for (final r in rows) {
        await db.update("stock_transactions", {"item_uuid": r["iuuid"]},
            where: "id=?", whereArgs: [r["tid"]]);
      }
    }

    if (!c.contains("updated_at")) {
      await db.execute("ALTER TABLE stock_transactions ADD COLUMN updated_at TEXT");
      await db.execute("UPDATE stock_transactions SET updated_at = date");
    }

    if (!c.contains("deleted")) {
      await db.execute(
          "ALTER TABLE stock_transactions ADD COLUMN deleted INTEGER DEFAULT 0");
      await db.execute("UPDATE stock_transactions SET deleted = 0");
    }
  }

  // ---------------------------------------------------------------------------
  // INDEXES
  // ---------------------------------------------------------------------------
  static Future<void> _createIndexes(Database db) async {
    await db.execute(
        "CREATE INDEX IF NOT EXISTS idx_cat_uuid ON categories(uuid)");
    await db.execute(
        "CREATE INDEX IF NOT EXISTS idx_item_uuid ON items(uuid)");
    await db.execute(
        "CREATE INDEX IF NOT EXISTS idx_item_cat_uuid ON items(category_uuid)");
    await db.execute(
        "CREATE INDEX IF NOT EXISTS idx_tx_uuid ON stock_transactions(uuid)");
    await db.execute(
        "CREATE INDEX IF NOT EXISTS idx_tx_item_uuid ON stock_transactions(item_uuid)");
  }
}