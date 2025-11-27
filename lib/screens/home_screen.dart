import 'dart:typed_data';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
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
  final TextEditingController _searchController = TextEditingController();

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
      SELECT 
        i.id, 
        i.code, 
        i.name, 
        i.description, 
        i.categoryId,
        c.name AS category,
        i.photo,
        IFNULL(SUM(
          CASE 
            WHEN t.type = 'IN' THEN t.quantity 
            WHEN t.type = 'OUT' THEN -t.quantity 
            ELSE 0 
          END
        ), 0) AS stock,
        COUNT(t.id) AS tx_count
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

  // 🖼️ UNIVERSAL PHOTO PICKER (Camera or Gallery)
  Future<Uint8List?> _pickPhotoDialog(BuildContext context) async {
    return await showModalBottomSheet<Uint8List?>(
      context: context,
      builder: (_) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Pick from Gallery'),
              onTap: () async {
                Navigator.pop(context, await _pickFromGallery());
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('Take Photo'),
              onTap: () async {
                Navigator.pop(context, await _pickFromCamera());
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<Uint8List?> _pickFromGallery() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowCompression: false,
      );
      if (result == null) return null;

      Uint8List? rawBytes;
      if (result.files.single.bytes != null) {
        rawBytes = result.files.single.bytes;
      } else if (result.files.single.path != null) {
        final pickedFile = File(result.files.single.path!);
        final tempDir = await getTemporaryDirectory();
        final safeCopy = File('${tempDir.path}/${pickedFile.uri.pathSegments.last}');
        await pickedFile.copy(safeCopy.path);
        rawBytes = await safeCopy.readAsBytes();
      }
      return _processImage(rawBytes);
    } catch (e) {
      debugPrint('❌ Gallery pick failed: $e');
      return null;
    }
  }

  Future<Uint8List?> _pickFromCamera() async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(source: ImageSource.camera);
      if (picked == null) return null;
      final rawBytes = await picked.readAsBytes();
      return _processImage(rawBytes);
    } catch (e) {
      debugPrint('❌ Camera pick failed: $e');
      return null;
    }
  }

  Future<Uint8List?> _processImage(Uint8List? rawBytes) async {
    if (rawBytes == null) return null;
    try {
      final decoded = img.decodeImage(rawBytes);
      if (decoded != null) {
        final resized = img.copyResize(decoded, 
										width: decoded.width > decoded.height ? 500 : null,
										height: decoded.height >= decoded.width ? 500 : null);
        final compressed = Uint8List.fromList(img.encodeJpg(resized, quality: 85));
        return compressed;
      }
    } catch (e) {
      debugPrint('❌ Image processing failed: $e');
    }
    return null;
  }

  // ✏️ EDIT ITEM DIALOG
  Future<void> _editItem(Map<String, dynamic> item) async {
    final nameCtrl = TextEditingController(text: item['name']);
    final descCtrl = TextEditingController(text: item['description']);
    final codeCtrl = TextEditingController(text: item['code']);
    Uint8List? photoBytes = item['photo'];

    final db = DatabaseHelper.instance;
    final categories = await db.getAllCategories();

    int? categoryId = item['categoryId'];
    if (categoryId != null && !categories.any((c) => c['id'] == categoryId)) {
      categoryId = null;
    }

    final updated = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          title: const Text('Edit Item'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  onTap: () async {
                    final picked = await _pickPhotoDialog(context);
                    if (picked != null) setStateDialog(() => photoBytes = picked);
                  },
                  child: photoBytes != null
                      ? Stack(
                          alignment: Alignment.topRight,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.memory(
                                photoBytes!,
                                width: 120,
                                height: 120,
                                fit: BoxFit.cover,
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close_rounded,
                                  color: Colors.redAccent),
                              onPressed: () =>
                                  setStateDialog(() => photoBytes = null),
                            ),
                          ],
                        )
                      : Container(
                          width: 120,
                          height: 120,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.add_a_photo_outlined,
                              size: 40, color: Colors.grey),
                        ),
                ),
                const SizedBox(height: 12),
                TextField(controller: codeCtrl, decoration: const InputDecoration(labelText: 'Code')),
                TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Name')),
                TextField(controller: descCtrl, decoration: const InputDecoration(labelText: 'Description')),
                const SizedBox(height: 8),
                DropdownButtonFormField<int>(
                  value: categoryId,
                  decoration: const InputDecoration(labelText: 'Category'),
                  items: [
                    const DropdownMenuItem<int>(value: null, child: Text('None')),
                    ...categories.map((c) => DropdownMenuItem<int>(
                          value: c['id'],
                          child: Text(c['name']),
                        )),
                  ],
                  onChanged: (v) => setStateDialog(() => categoryId = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel')),
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
                        'photo': photoBytes,
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
      ),
    );

    if (updated == true) _loadItems();
  }

  // ❌ DELETE ITEM
  Future<void> _deleteItem(int id) async {
    final db = DatabaseHelper.instance;
    final itemData =
        await (await db.database).rawQuery('SELECT name FROM items WHERE id = ?', [id]);
    final itemName = itemData.isNotEmpty ? itemData.first['name'] as String : 'this item';
    final stock = await db.getCurrentStock(id);

    String message = 'Are you sure you want to delete "$itemName"?';
    if (stock > 0) {
      message +=
          '\n\n⚠️ This item still has $stock units in stock. Deleting it will also remove its stock history.';
    } else {
      message += '\n\nThis item has no remaining stock.';
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Item'),
        content: Text(message, style: const TextStyle(height: 1.4)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await db.deleteItem(id);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Item "$itemName" deleted successfully')),
      );
      _loadItems();
    }
  }

  // 🔍 FILTER LOGIC
  void _applyFilters() {
    setState(() {
      filteredItems = allItems.where((item) {
        final matchesCategory = selectedCategoryId == null ||
            item['categoryId'] == selectedCategoryId;
        final matchesSearch = searchQuery.isEmpty ||
            (item['name']?.toLowerCase().contains(searchQuery.toLowerCase()) ?? false) ||
            (item['code']?.toLowerCase().contains(searchQuery.toLowerCase()) ?? false) ||
            (item['description']?.toLowerCase().contains(searchQuery.toLowerCase()) ?? false);
        return matchesCategory && matchesSearch;
      }).toList();
    });
  }

  // 🧭 NAVIGATION HELPERS
  void _openAddItem() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const AddItemScreen()));
    _loadItems();
  }

  void _openManageCategories() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const ManageCategoriesScreen()));
    _loadCategories();
    _loadItems();
  }

  // 🖼️ UI
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(children: [
          Image.asset('assets/images/logo_icon.png', height: 32),
          const SizedBox(width: 8),
          const Text('Event Collection'),
        ]),
        actions: [
          IconButton(icon: const Icon(Icons.category_outlined), tooltip: 'Manage Categories', onPressed: _openManageCategories),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
            onPressed: () async {
              final imported = await Navigator.push(
                context, MaterialPageRoute(builder: (_) => const SettingsScreen()));
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
            // 🔍 SEARCH
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          setState(() {
                            _searchController.clear();
                            searchQuery = '';
                            _applyFilters();
                          });
                          FocusScope.of(context).unfocus();
                        },
                      )
                    : null,
                filled: true,
                fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
              ),
              onChanged: (v) {
                setState(() => searchQuery = v);
                _applyFilters();
              },
            ),
            const SizedBox(height: 8),
            // 🗂️ CATEGORY FILTER
            DropdownButtonFormField<int>(
              value: selectedCategoryId,
              decoration: InputDecoration(
                labelText: 'Filter by Category',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              ),
              items: [
                const DropdownMenuItem<int>(value: null, child: Text('All Categories')),
                ...categories.map((c) => DropdownMenuItem<int>(
                      value: c['id'],
                      child: Text(c['name']),
                    )),
              ],
              onChanged: (v) {
                selectedCategoryId = v;
                _applyFilters();
              },
            ),
            const SizedBox(height: 8),
            // 📋 ITEM LIST
            Expanded(
              child: filteredItems.isEmpty
                  ? const Center(child: Text('No items found'))
                  : Scrollbar(
                      thumbVisibility: true,
                      radius: const Radius.circular(12),
                      child: ListView.separated(
                        padding: const EdgeInsets.only(bottom: 90),
                        itemCount: filteredItems.length,
                        separatorBuilder: (_, __) => const Divider(height: 1, thickness: 0.2),
                        itemBuilder: (context, index) {
                          final item = filteredItems[index];
                          return ListTile(
                            leading: (item['photo'] != null)
                                ? CircleAvatar(backgroundImage: MemoryImage(item['photo']))
                                : const CircleAvatar(child: Icon(Icons.inventory_2_outlined)),
                            title: Text('${item['name']} — ${item['code']}',
                                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (item['description'] != null && item['description'].toString().isNotEmpty)
                                  Text(item['description'], style: const TextStyle(color: Colors.black54)),
                                Text(
                                  item['tx_count'] == 0
                                      ? 'No transactions yet'
                                      : (item['stock'] == 0
                                          ? 'Out of stock'
                                          : 'Stock: ${item['stock']}'),
                                  style: TextStyle(
                                    color: item['tx_count'] == 0
                                        ? Colors.grey
                                        : (item['stock'] > 0 ? Colors.green : Colors.redAccent),
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
                                  child: Row(children: [
                                    Icon(Icons.edit_outlined, size: 20),
                                    SizedBox(width: 8),
                                    Text('Edit'),
                                  ]),
                                ),
                                const PopupMenuItem(
                                  value: 'delete',
                                  child: Row(children: [
                                    Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                                    SizedBox(width: 8),
                                    Text('Delete'),
                                  ]),
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