import 'package:flutter/material.dart';
import '../db/database_helper.dart';
import 'add_item_screen.dart';
import 'item_detail_screen.dart';
import 'manage_categories_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Map<String, dynamic>> allItems = [];
  List<Map<String, dynamic>> filteredItems = [];
  List<Map<String, dynamic>> categories = [];
  int? selectedCategoryId;
  String searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadCategories();
    _loadItems();
  }

  Future<void> _loadCategories() async {
    final db = DatabaseHelper.instance;
    final result = await db.getAllCategories();
    setState(() => categories = result);
  }

  Future<void> _loadItems() async {
    final db = DatabaseHelper.instance;
    final result = await db.database.then((dbConn) => dbConn.rawQuery('''
      SELECT i.id, i.code, i.name, i.description, i.categoryId,
             c.name AS category,
             IFNULL(SUM(CASE WHEN t.type='IN' THEN t.quantity
                             WHEN t.type='OUT' THEN -t.quantity ELSE 0 END), 0)
             AS stock
      FROM items i
      LEFT JOIN categories c ON i.categoryId = c.id
      LEFT JOIN stock_transactions t ON i.id = t.itemId
      GROUP BY i.id
      ORDER BY i.name COLLATE NOCASE ASC
    '''));

    setState(() {
      allItems = result;
      _applyFilters();
    });
  }
  
  Future<void> _editItem(Map<String, dynamic> item) async {
	  final nameCtrl = TextEditingController(text: item['name']);
	  final descCtrl = TextEditingController(text: item['description']);
	  final codeCtrl = TextEditingController(text: item['code']);
	  
	  final db = DatabaseHelper.instance;
	  final categories = await db.getAllCategories();

	  // Ensure categoryId is valid (still exists)
	  int? categoryId = item['categoryId'];
	  if (categoryId != null &&
			!categories.any((c) => c['id'] == categoryId)) {
		  categoryId = null; // Category was deleted -> reset
	  }

	  final updated = await showDialog<bool>(
		context: context,
		builder: (context) => AlertDialog(
		  title: const Text('Edit Item'),
		  content: SingleChildScrollView(
			child: Column(
			  mainAxisSize: MainAxisSize.min,
			  children: [
				TextField(controller: codeCtrl, decoration: const InputDecoration(labelText: 'Code')),
				TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Name')),
				TextField(controller: descCtrl, decoration: const InputDecoration(labelText: 'Description')),
				const SizedBox(height: 8),
				DropdownButtonFormField<int>(
				  value: categoryId,
				  decoration: const InputDecoration(labelText: 'Category'),
				  items: [
					const DropdownMenuItem<int>(
						value: null, child: Text('None')),
					...categories.map((c) => DropdownMenuItem<int>(
						  value: c['id'],
						  child: Text(c['name']),
						)),
				  ],
				  onChanged: (v) => categoryId = v,
				),
			  ],
			),
		  ),
		  actions: [
			TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
			FilledButton(
			  onPressed: () async {
				if (nameCtrl.text.isEmpty) return;
				await db.database.then((dbConn) => dbConn.update(
					  'items',
					  {
						'code': codeCtrl.text,
						'name': nameCtrl.text,
						'description': descCtrl.text,
						'categoryId': categoryId,
						'updatedAt': DateTime.now().toIso8601String(),
					  },
					  where: 'id = ?',
					  whereArgs: [item['id']],
					));
				Navigator.pop(context, true);
			  },
			  child: const Text('Save'),
			),
		  ],
		),
	  );

	  if (updated == true) _loadItems();
	}

	Future<void> _deleteItem(int id) async {
	  final db = DatabaseHelper.instance;

	  // ✅ 1️⃣ Get item name and current stock
	  final itemData = await (await db.database)
		  .rawQuery('SELECT name FROM items WHERE id = ?', [id]);
	  final itemName = itemData.isNotEmpty ? itemData.first['name'] as String : 'this item';
	  final stock = await db.getCurrentStock(id);

	  // ✅ 2️⃣ Build dynamic message
	  String message = 'Are you sure you want to delete "$itemName"?';
	  if (stock > 0) {
		message +=
			'\n\n⚠️ This item still has $stock units in stock. Deleting it will also remove its stock history.';
	  } else {
		message += '\n\nThis item has no remaining stock.';
	  }

	  // ✅ 3️⃣ Show confirmation dialog
	  final confirmed = await showDialog<bool>(
		context: context,
		builder: (context) => AlertDialog(
		  title: const Text('Delete Item'),
		  content: Text(
			message,
			style: const TextStyle(height: 1.4),
		  ),
		  actions: [
			TextButton(
			  onPressed: () => Navigator.pop(context, false),
			  child: const Text('Cancel'),
			),
			FilledButton(
			  style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
			  onPressed: () => Navigator.pop(context, true),
			  child: const Text('Delete'),
			),
		  ],
		),
	  );

	  // ✅ 4️⃣ Delete if confirmed
	  if (confirmed == true) {
		await db.deleteItem(id);

		ScaffoldMessenger.of(context).showSnackBar(
		  SnackBar(content: Text('Item "$itemName" deleted successfully')),
		);

		_loadItems(); // refresh the list
	  }
	}

  void _applyFilters() {
    setState(() {
      filteredItems = allItems.where((item) {
        final matchesCategory = selectedCategoryId == null ||
            item['categoryId'] == selectedCategoryId;
        final matchesSearch = searchQuery.isEmpty ||
            (item['name']?.toLowerCase().contains(searchQuery.toLowerCase()) ?? false) ||
            (item['code']?.toLowerCase().contains(searchQuery.toLowerCase()) ?? false);
        return matchesCategory && matchesSearch;
      }).toList();
    });
  }

  void _openAddItem() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const AddItemScreen()),
    );
    _loadItems();
  }

  void _openManageCategories() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const ManageCategoriesScreen()),
    );
    _loadCategories();
    _loadItems();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
			children: [
			  Image.asset(
				'assets/images/logo_icon.png',
				height: 32,
			  ),
			  const SizedBox(width: 8),
			  const Text('Event Collection'),
			],
		  ),
		  actions: [
          IconButton(
            icon: const Icon(Icons.category_outlined),
            tooltip: 'Manage Categories',
            onPressed: _openManageCategories,
          ),
		  IconButton(
			icon: const Icon(Icons.settings_outlined),
			tooltip: 'Settings',
			onPressed: () async {
			  final imported = await Navigator.push(
				context,
				MaterialPageRoute(builder: (_) => const SettingsScreen()),
			  );
			  if (imported == true) {
				  _loadItems();
				  _loadCategories();
				}
			},
		  ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openAddItem,
        label: const Text('Add Item'),
        icon: const Icon(Icons.add),
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            // 🔍 Search Field
            TextField(
              decoration: InputDecoration(
                hintText: 'Search by name or code',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
              ),
              onChanged: (value) {
                searchQuery = value;
                _applyFilters();
              },
            ),
            const SizedBox(height: 8),

            // 🗂️ Category Filter Dropdown
            DropdownButtonFormField<int>(
              value: selectedCategoryId,
              decoration: InputDecoration(
                labelText: 'Filter by Category',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              ),
              items: [
                const DropdownMenuItem<int>(
                    value: null, child: Text('All Categories')),
                ...categories.map((c) => DropdownMenuItem<int>(
                      value: c['id'],
                      child: Text(c['name']),
                    )),
              ],
              onChanged: (value) {
                selectedCategoryId = value;
                _applyFilters();
              },
            ),

            const SizedBox(height: 8),

            // 📋 Item List
            Expanded(
              child: filteredItems.isEmpty
                  ? const Center(child: Text('No items found'))
                  : Scrollbar(
                      thumbVisibility: true,
                      radius: const Radius.circular(12),
                      child: ListView.separated(
                        itemCount: filteredItems.length,
                        separatorBuilder: (_, __) =>
                            const Divider(height: 1, thickness: 0.2),
                        itemBuilder: (context, index) {
						  final item = filteredItems[index];
						  return ListTile(
							title: Text(
							  '${item['name']} — ${item['code']}',
							  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
							),
							subtitle: Column(
								crossAxisAlignment: CrossAxisAlignment.start,
								children: [
								  if (item['description'] != null && item['description'].toString().isNotEmpty)
									Text(item['description'], style: const TextStyle(color: Colors.black54)),
								  Text(
									'Stock: ${item['stock']}',
									style: TextStyle(
									  color: item['stock'] > 0 ? Colors.green : Colors.redAccent,
									  fontWeight: FontWeight.w500,
									),
								  ),
								],
							  ),
							onTap: () {
							  Navigator.push(
								context,
								MaterialPageRoute(
								  builder: (_) => ItemDetailScreen(item: item),
								),
							  ).then((_) => _loadItems());
							},
							trailing: PopupMenuButton<String>(
							  tooltip: 'More actions',
							  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
							  onSelected: (value) {
								switch (value) {
								  case 'edit':
									_editItem(item);
									break;
								  case 'delete':
									_deleteItem(item['id']);
									break;
								}
							  },
							  itemBuilder: (context) => [
								const PopupMenuItem(
								  value: 'edit',
								  child: Row(
									children: [
									  Icon(Icons.edit_outlined, size: 20),
									  SizedBox(width: 8),
									  Text('Edit'),
									],
								  ),
								),
								const PopupMenuItem(
								  value: 'delete',
								  child: Row(
									children: [
									  Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
									  SizedBox(width: 8),
									  Text('Delete'),
									],
								  ),
								),
							  ],
							),
						  );
						},
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}