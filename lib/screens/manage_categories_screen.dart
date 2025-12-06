// lib/screens/manage_categories_screen.dart
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../db/database_helper.dart';

class ManageCategoriesScreen extends StatefulWidget {
  const ManageCategoriesScreen({super.key});

  @override
  State<ManageCategoriesScreen> createState() =>
      _ManageCategoriesScreenState();
}

class _ManageCategoriesScreenState extends State<ManageCategoriesScreen> {
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();

  List<Map<String, dynamic>> categories = [];

  @override
  void initState() {
    super.initState();
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    final result = await DatabaseHelper.instance.getAllCategories();
    setState(() => categories = result);
  }

  // ===========================================================================
  // ADD CATEGORY (with uuid + sync fields)
  // ===========================================================================
  Future<void> _addCategory() async {
    if (_nameCtrl.text.isEmpty) return;

    final now = DateTime.now().toIso8601String();
    final db = DatabaseHelper.instance;

    await db.insertCategory({
      'name': _nameCtrl.text,
      'description': _descCtrl.text,
      'createdAt': now,
      'updated_at': now,
      'uuid': const Uuid().v4(),
      'deleted': 0,
    });

    _nameCtrl.clear();
    _descCtrl.clear();
    _loadCategories();
  }

  // ===========================================================================
  // EDIT CATEGORY (sync-friendly)
  // ===========================================================================
  Future<void> _editCategory(Map<String, dynamic> category) async {
    final nameCtrl = TextEditingController(text: category['name']);
    final descCtrl = TextEditingController(text: category['description']);

    final updated = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Edit Category'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Name')),
            TextField(
                controller: descCtrl,
                decoration: const InputDecoration(labelText: 'Description')),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              if (nameCtrl.text.isEmpty) return;

              final db = DatabaseHelper.instance;

              await db.database.then((dbConn) => dbConn.update(
                    'categories',
                    {
                      'name': nameCtrl.text,
                      'description': descCtrl.text,
                      'updated_at':
                          DateTime.now().toIso8601String(), // sync field
                    },
                    where: 'id = ?',
                    whereArgs: [category['id']],
                  ));

              Navigator.pop(context, true);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (updated == true) _loadCategories();
  }

  // ===========================================================================
  // SOFT DELETE CATEGORY (sync-friendly)
  // ===========================================================================
  Future<void> _deleteCategory(int id) async {
    final db = DatabaseHelper.instance;

    // Count items under this category
    final countResult = await (await db.database).rawQuery(
      'SELECT COUNT(*) AS cnt FROM items WHERE categoryId = ?',
      [id],
    );

    final itemCount = (countResult.first['cnt'] as num).toInt();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Category'),
        content: Text(
          itemCount > 0
              ? 'This category currently has $itemCount items.\n\n'
                  'If you delete it, those items will lose their category assignment.\n\n'
                  'Are you sure you want to continue?'
              : 'Are you sure you want to delete this empty category?',
          style: const TextStyle(height: 1.3),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // SOFT DELETE
    await db.database.then((dbConn) => dbConn.update(
          "categories",
          {
            "deleted": 1,
            "updated_at": DateTime.now().toIso8601String(),
          },
          where: "id = ?",
          whereArgs: [id],
        ));

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Category deleted')),
    );

    _loadCategories();
  }

  // ===========================================================================
  // UI — 100% your original UI preserved
  // ===========================================================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Manage Categories')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
                controller: _nameCtrl,
                decoration: const InputDecoration(labelText: 'Category Name')),
            TextField(
                controller: _descCtrl,
                decoration: const InputDecoration(labelText: 'Description')),
            const SizedBox(height: 12),

            // Add button
            FilledButton.icon(
              onPressed: _addCategory,
              icon: const Icon(Icons.add),
              label: const Text('Add Category'),
            ),

            const Divider(height: 32),

            Expanded(
              child: ListView.builder(
                itemCount: categories.length,
                itemBuilder: (_, i) {
                  final cat = categories[i];
                  return Card(
                    margin: const EdgeInsets.symmetric(vertical: 6),
                    child: ListTile(
                      title: Text(cat['name']),
                      subtitle: Text(cat['description'] ?? ''),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit_outlined,
                                color: Colors.teal),
                            onPressed: () => _editCategory(cat),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline,
                                color: Colors.redAccent),
                            onPressed: () => _deleteCategory(cat['id']),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            )
          ],
        ),
      ),
    );
  }
}