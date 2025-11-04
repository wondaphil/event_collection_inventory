import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart';
import 'screens/home_screen.dart';
import 'db/database_helper.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // final dbPath = await getDatabasesPath();
  // print("Database path: $dbPath/inventory.db");
  // await DatabaseHelper.instance.database; // initializes DB
  await testDatabase();
  runApp(const MyApp());
}

Future<void> testDatabase() async {
  final db = DatabaseHelper.instance;

  // 1. Insert a new item
  int itemId = await db.insertItem({
    'code': 'PEN001',
    'name': 'Ballpoint Pen',
    'description': 'Blue ink pen',
    'createdAt': DateTime.now().toIso8601String(),
    'updatedAt': DateTime.now().toIso8601String(),
  });
  print('Inserted item ID: $itemId');

  // 2. Add stock transactions
  await db.addStockTransaction({
    'itemId': itemId,
    'quantity': 50,
    'type': 'IN',
    'date': DateTime.now().toIso8601String(),
    'notes': 'Initial stock',
  });

  await db.addStockTransaction({
    'itemId': itemId,
    'quantity': 10,
    'type': 'OUT',
    'date': DateTime.now().toIso8601String(),
    'notes': 'Used 10 pens',
  });

  // 3. Get current stock
  final stock = await db.getCurrentStock(itemId);
  print('Current stock for item $itemId: $stock');

  // 4. List all items
  final items = await db.getAllItems();
  print('All items: $items');
  
  await testCategories();
}

Future<void> testCategories() async {
  final db = DatabaseHelper.instance;

  // Insert category
  int catId = await db.insertCategory({
    'name': 'Stationery',
    'description': 'Pens, notebooks, office items',
    'createdAt': DateTime.now().toIso8601String(),
  });
  print('Inserted category ID: $catId');

  // Insert item linked to category
  int itemId = await db.insertItem({
    'categoryId': catId,
    'code': 'NOTE001',
    'name': 'Notebook',
    'description': 'A5 size notebook',
    'createdAt': DateTime.now().toIso8601String(),
    'updatedAt': DateTime.now().toIso8601String(),
  });
  print('Inserted item ID: $itemId');

  // Check join query
  final result = await (await db.database).rawQuery('''
    SELECT i.name AS item, c.name AS category
    FROM items i
    LEFT JOIN categories c ON i.categoryId = c.id
  ''');

  print('Item with category: $result');
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Event Collection',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}