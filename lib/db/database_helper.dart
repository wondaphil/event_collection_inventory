// lib/db/database_helper.dart
import 'dart:typed_data';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'database_migration.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  static const int _dbVersion = 11; // bump after adding photoHash

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB("inventory.db");
    return _database!;
  }

  Future<Database> _initDB(String dbName) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, dbName);

    return openDatabase(
      path,
      version: _dbVersion,
      onCreate: _createDB,
      onUpgrade: (db, oldVersion, newVersion) async {
        await DatabaseMigration.runMigrations(db);
      },
      onOpen: (db) async {
        await DatabaseMigration.runMigrations(db);
      },
    );
  }

  // SHA-1 helper
  String _hash(Uint8List? bytes) {
    if (bytes == null || bytes.isEmpty) return "";
    return sha1.convert(bytes).toString();
  }

  Future<void> _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE categories (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT UNIQUE NOT NULL,
        description TEXT,
        createdAt TEXT NOT NULL,
        updated_at TEXT,
        uuid TEXT,
        deleted INTEGER DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        categoryId INTEGER,
        code TEXT UNIQUE NOT NULL,
        name TEXT NOT NULL,
        description TEXT,
        photo BLOB,
        photoHash TEXT,
        createdAt TEXT NOT NULL,
        updatedAt TEXT NOT NULL,
        uuid TEXT,
        category_uuid TEXT,
        deleted INTEGER DEFAULT 0,
        FOREIGN KEY (categoryId) REFERENCES categories(id) ON DELETE SET NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE stock_transactions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        itemId INTEGER,
        quantity INTEGER NOT NULL,
        type TEXT CHECK(type IN ('IN','OUT')),
        date TEXT NOT NULL,
        notes TEXT,
        uuid TEXT,
        item_uuid TEXT,
        updated_at TEXT,
        deleted INTEGER DEFAULT 0,
        FOREIGN KEY (itemId) REFERENCES items(id) ON DELETE SET NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS device_info (
        device_id TEXT PRIMARY KEY
      )
    ''');

    await _createIndexes(db);
  }

  Future<void> _createIndexes(Database db) async {
    await db.execute("CREATE INDEX IF NOT EXISTS idx_categories_uuid ON categories(uuid)");
    await db.execute("CREATE INDEX IF NOT EXISTS idx_items_uuid ON items(uuid)");
    await db.execute("CREATE INDEX IF NOT EXISTS idx_items_category_uuid ON items(category_uuid)");
    await db.execute("CREATE INDEX IF NOT EXISTS idx_tx_uuid ON stock_transactions(uuid)");
    await db.execute("CREATE INDEX IF NOT EXISTS idx_tx_item_uuid ON stock_transactions(item_uuid)");
    await db.execute("CREATE INDEX IF NOT EXISTS idx_tx_itemId ON stock_transactions(itemId)");
  }

  // ---------------------------------------------------------------------------
  // ITEMS
  // ---------------------------------------------------------------------------
  Future<int> insertItem(Map<String, dynamic> row) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch.toString();
    final photo = row["photo"] as Uint8List?;
    row["createdAt"] = now;
    row["updatedAt"] = now;
    row["photoHash"] = _hash(photo);
    return db.insert("items", row);
  }

  Future<int> updateItem(Map<String, dynamic> row) async {
    final db = await database;
    final id = row["id"];
    final now = DateTime.now().millisecondsSinceEpoch.toString();
    final photo = row["photo"] as Uint8List?;

    row["updatedAt"] = now;
    row["photoHash"] = _hash(photo);

    return db.update("items", row, where: "id = ?", whereArgs: [id]);
  }

  Future<int> softDeleteItem(int id) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch.toString();

    return db.update(
      "items",
      {"deleted": 1, "updatedAt": now},
      where: "id = ?",
      whereArgs: [id],
    );
  }

  Future<List<Map<String, dynamic>>> getAllItemsRaw() async {
    final db = await database;
    return db.query("items");
  }

  Future<List<Map<String, dynamic>>> getAllItems() async {
    final db = await database;
    return db.query(
      "items",
      where: "deleted = 0",
      orderBy: "name COLLATE NOCASE ASC",
    );
  }

  // ---------------------------------------------------------------------------
  // CATEGORIES
  // ---------------------------------------------------------------------------
  Future<int> insertCategory(Map<String, dynamic> row) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch.toString();

    row["createdAt"] = now;
    row["updated_at"] = now;
    row["deleted"] = 0;

    return db.insert("categories", row);
  }

  Future<int> softDeleteCategory(int id) async {
    final db = await database;
    return db.update(
      "categories",
      {
        "deleted": 1,
        "updated_at": DateTime.now().millisecondsSinceEpoch.toString(),
      },
      where: "id = ?",
      whereArgs: [id],
    );
  }

  Future<List<Map<String, dynamic>>> getAllCategoriesRaw() async {
    final db = await database;
    return db.query("categories");
  }

  Future<List<Map<String, dynamic>>> getAllCategories() async {
    final db = await database;
    return db.query(
      "categories",
      where: "deleted = 0",
      orderBy: "name ASC",
    );
  }

  // ---------------------------------------------------------------------------
  // TRANSACTIONS
  // ---------------------------------------------------------------------------
  Future<int> addStockTransaction(Map<String, dynamic> row) async {
    final db = await database;
    row["updated_at"] = DateTime.now().millisecondsSinceEpoch.toString();
    return db.insert("stock_transactions", row);
  }

  Future<int> softDeleteTransaction(int id) async {
    final db = await database;
    return db.update(
      "stock_transactions",
      {
        "deleted": 1,
        "updated_at": DateTime.now().millisecondsSinceEpoch.toString(),
      },
      where: "id = ?",
      whereArgs: [id],
    );
  }
  
  Future<int> getCurrentStock(int itemId) async {
	  final db = await database;
	  final result = await db.rawQuery('''
		SELECT IFNULL(SUM(
		  CASE WHEN type='IN' THEN quantity
			   WHEN type='OUT' THEN -quantity
			   ELSE 0 END
		),0) AS currentStock
		FROM stock_transactions
		WHERE itemId = ? AND deleted = 0
	  ''', [itemId]);

	  return result.first["currentStock"] as int;
	}

  // ---------------------------------------------------------------------------
  Future<void> reloadDatabase() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
    }
    await database;
  }

  Future close() async {
    final db = await database;
    db.close();
  }
}