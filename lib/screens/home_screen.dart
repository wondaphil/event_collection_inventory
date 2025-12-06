// home_screen.dart
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../db/database_helper.dart';
import '../utils/sync_controller.dart';

import 'add_item_screen.dart';
import 'item_detail_screen.dart';
import 'manage_categories_screen.dart';
import 'settings_screen.dart';

import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'package:collection/collection.dart';

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

  final _searchController = TextEditingController();
  Timer? _autoSyncTimer;

  @override
  void initState() {
    super.initState();
    _loadCategories();
    _loadItems();

    _autoSyncTimer = Timer.periodic(
      const Duration(minutes: 30),
      (_) => Provider.of<SyncController>(context, listen: false).syncNow(),
    );
  }

  @override
  void dispose() {
    _autoSyncTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadCategories() async {
    final db = DatabaseHelper.instance;
    final result = await db.database.then((dbConn) =>
        dbConn.query("categories", where: "deleted = 0", orderBy: "name ASC"));

    setState(() => categories = result);
  }

  Future<void> _loadItems() async {
    final db = DatabaseHelper.instance;
    final result = await db.database.then((dbConn) => dbConn.rawQuery('''
      SELECT 
        i.id,
        i.uuid,
        i.categoryId,
        i.code,
        i.name,
        i.description,
        i.photo,
        i.photoHash,
        i.deleted,
        c.name AS category,
        IFNULL(SUM(
          CASE 
            WHEN t.type='IN' THEN t.quantity
            WHEN t.type='OUT' THEN -t.quantity
            ELSE 0 END
        ),0) AS stock,
        COUNT(t.id) AS tx_count
      FROM items i
      LEFT JOIN categories c ON i.categoryId = c.id
      LEFT JOIN stock_transactions t 
        ON i.id = t.itemId AND t.deleted = 0
      WHERE i.deleted = 0
      GROUP BY i.id
      ORDER BY i.name COLLATE NOCASE ASC
    '''));

    setState(() {
      allItems = result;
      _applyFilters();
    });
  }

  // Filters
  void _applyFilters() {
    setState(() {
      filteredItems = allItems.where((i) {
        final okCat =
            selectedCategoryId == null || i['categoryId'] == selectedCategoryId;
        final q = searchQuery.toLowerCase();

        final okSearch = q.isEmpty ||
            (i['name'] ?? '').toString().toLowerCase().contains(q) ||
            (i['code'] ?? '').toString().toLowerCase().contains(q) ||
            (i['description'] ?? '').toString().toLowerCase().contains(q);

        return okCat && okSearch;
      }).toList();
    });
  }

  Future<void> _pullToRefresh() async {
    await _loadCategories();
    await _loadItems();
  }

  @override
  Widget build(BuildContext context) {
    final sync = context.watch<SyncController>();
    final isSyncing = sync.isSyncing;

    if (sync.errorMessage != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Sync failed: ${sync.errorMessage}"),
            backgroundColor: Colors.red,
          ),
        );
      });
    }

    return Scaffold(
      appBar: AppBar(
        title: Row(children: [
          Image.asset("assets/images/logo_icon.png", height: 32),
          const SizedBox(width: 8),
          const Text("Event Collection"),
        ]),
        actions: [
          isSyncing
              ? Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                )
              : IconButton(
                  icon: const Icon(Icons.sync),
                  onPressed: () =>
                      Provider.of<SyncController>(context, listen: false)
                          .syncNow(),
                ),
          IconButton(
            icon: const Icon(Icons.category_outlined),
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ManageCategoriesScreen()),
              );
              _loadCategories();
              _loadItems();
            },
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
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

      floatingActionButton: isSyncing
          ? null
          : FloatingActionButton.extended(
              icon: const Icon(Icons.add),
              label: const Text("Add Item"),
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AddItemScreen()),
                );
                _loadItems();
              },
            ),

      body: RefreshIndicator(
        onRefresh: _pullToRefresh,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: "Search",
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _searchController.clear();
                            searchQuery = '';
                            _applyFilters();
                          },
                        )
                      : null,
                  filled: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
                onChanged: (v) {
                  searchQuery = v;
                  _applyFilters();
                },
              ),

              const SizedBox(height: 8),

              DropdownButtonFormField<int>(
                value: selectedCategoryId,
                decoration: InputDecoration(
                  labelText: "Category",
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                items: [
                  const DropdownMenuItem(value: null, child: Text("All")),
                  ...categories.map((c) => DropdownMenuItem(
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

              Expanded(
                child: filteredItems.isEmpty
                    ? const Center(child: Text("No items found"))
                    : ListView.separated(
                        padding: const EdgeInsets.only(bottom: 90),
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemCount: filteredItems.length,
                        itemBuilder: (_, i) {
                          final item = filteredItems[i];
                          return ListTile(
                            leading: item['photo'] != null
                                ? CircleAvatar(
                                    backgroundImage: MemoryImage(item['photo']),
                                  )
                                : const CircleAvatar(
                                    child: Icon(Icons.inventory_2_outlined)),
                            title: Text("${item['name']} — ${item['code']}"),
                            subtitle: Text(
                              item['tx_count'] == 0
                                  ? "No transactions"
                                  : (item['stock'] > 0
                                      ? "Stock: ${item['stock']}"
                                      : "Out of stock"),
                              style: TextStyle(
                                color: item['tx_count'] == 0
                                    ? Colors.grey
                                    : (item['stock'] > 0
                                        ? Colors.green
                                        : Colors.redAccent),
                              ),
                            ),
                            onTap: isSyncing
                                ? null
                                : () async {
                                    await Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => ItemDetailScreen(
                                          item: item,
                                        ),
                                      ),
                                    );
                                    _loadItems();
                                  },
                            trailing: isSyncing
                                ? null
                                : PopupMenuButton(
                                    itemBuilder: (context) => [
                                      const PopupMenuItem(
                                        value: "edit",
                                        child: Text("Edit"),
                                      ),
                                      const PopupMenuItem(
                                        value: "delete",
                                        child: Text("Delete"),
                                      ),
                                    ],
                                    onSelected: (v) async {
                                      if (v == "edit") {
                                        await _editItem(item);
                                      } else if (v == "delete") {
                                        await _deleteItem(item['id']);
                                      }
                                    },
                                  ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // =========================
  // EDIT ITEM (WITH PHOTOHASH)
  // =========================
  Future<void> _editItem(Map<String, dynamic> item) async {
    final db = DatabaseHelper.instance;

    final codeCtrl = TextEditingController(text: item['code']);
    final nameCtrl = TextEditingController(text: item['name']);
    final descCtrl = TextEditingController(text: item['description']);

    Uint8List? photoBytes = item['photo'];
    Uint8List? originalPhoto = item['photo'];

    final cats = await db.getAllCategories();
    int? categoryId = item['categoryId'];

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(builder: (_, setD) {
        return AlertDialog(
          title: const Text("Edit Item"),
          content: SingleChildScrollView(
            child: Column(children: [
              GestureDetector(
                onTap: () async {
                  final p = await _pickPhoto();
                  if (p != null) setD(() => photoBytes = p);
                },
                child: photoBytes != null
                    ? Image.memory(photoBytes!,
                        width: 100, height: 100, fit: BoxFit.cover)
                    : Container(
                        width: 100,
                        height: 100,
                        color: Colors.grey.shade300,
                        child: const Icon(Icons.add_a_photo),
                      ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: codeCtrl,
                decoration: const InputDecoration(labelText: "Code"),
              ),
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: "Name"),
              ),
              TextField(
                controller: descCtrl,
                decoration: const InputDecoration(labelText: "Description"),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                value: categoryId,
                items: [
                  const DropdownMenuItem(value: null, child: Text("None")),
                  ...cats.map((c) => DropdownMenuItem(
                        value: c['id'],
                        child: Text(c['name']),
                      )),
                ],
                onChanged: (v) => setD(() => categoryId = v),
              ),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text("Cancel")),
            FilledButton(
              onPressed: () async {
                final now =
                    DateTime.now().millisecondsSinceEpoch.toString();

                // determine if photo changed
                final bool changed =
                    (originalPhoto == null && photoBytes != null) ||
                        (originalPhoto != null &&
                            photoBytes != null &&
                            !ListEquality().equals(
                                originalPhoto, photoBytes));

                String? newHash;
                if (changed && photoBytes != null) {
                  newHash = photoBytes == null ? "" : sha1.convert(photoBytes!).toString();
                }

                // get category_uuid
                String? catUuid;
                if (categoryId != null) {
                  final row = await (await db.database).query(
                    "categories",
                    where: "id=?",
                    whereArgs: [categoryId],
                    limit: 1,
                  );
                  if (row.isNotEmpty) catUuid = row.first["uuid"] as String?;
                }

                await (await db.database).update(
                  "items",
                  {
                    "code": codeCtrl.text,
                    "name": nameCtrl.text,
                    "description": descCtrl.text,
                    "categoryId": categoryId,
                    "category_uuid": catUuid,
                    "photo": photoBytes,
                    "photoHash": changed ? newHash : item["photoHash"],
                    "updatedAt": now,
                  },
                  where: "id = ?",
                  whereArgs: [item['id']],
                );

                Navigator.pop(context, true);
              },
              child: const Text("Save"),
            ),
          ],
        );
      }),
    );

    if (ok == true) _loadItems();
  }

  // pick & resize photo
  Future<Uint8List?> _pickPhoto() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowCompression: false,
    );

    if (result == null) return null;

    Uint8List? rawBytes = result.files.single.bytes ??
        await File(result.files.single.path!).readAsBytes();

    final decoded = img.decodeImage(rawBytes);
    if (decoded == null) return rawBytes;

    final resized = img.copyResize(decoded, width: 1600);
    return Uint8List.fromList(img.encodeJpg(resized, quality: 80));
  }

  Future<void> _deleteItem(int id) async {
    final db = DatabaseHelper.instance;

    final itemData = await (await db.database)
        .rawQuery("SELECT name FROM items WHERE id = ?", [id]);
    final name = itemData.isNotEmpty ? itemData.first["name"] : "this item";

    final stock = await DatabaseHelper.instance.getCurrentStock(id);

    String message = 'Are you sure you want to delete "$name"?';

    if (stock > 0) {
      message +=
          '\n\n⚠️ This item still has $stock units.\nDeleting it removes its history.';
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Delete Item"),
        content: Text(message, style: const TextStyle(height: 1.4)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text("Cancel")),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Delete"),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final now = DateTime.now().millisecondsSinceEpoch.toString();

    await (await db.database).update(
      "items",
      {"deleted": 1, "updatedAt": now},
      where: "id = ?",
      whereArgs: [id],
    );

    Provider.of<SyncController>(context, listen: false).syncNow();

    _loadItems();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Item "$name" deleted')),
    );
  }
}