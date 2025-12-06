// lib/screens/item_detail_screen.dart
import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:csv/csv.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:image/image.dart' as img;
import 'package:uuid/uuid.dart';

import '../utils/ethiopian_date_helper.dart';
import '../widgets/ethiopian_date_picker.dart';
import '../db/database_helper.dart';

class ItemDetailScreen extends StatefulWidget {
  final Map<String, dynamic> item;
  const ItemDetailScreen({super.key, required this.item});

  @override
  State<ItemDetailScreen> createState() => _ItemDetailScreenState();
}

class _ItemDetailScreenState extends State<ItemDetailScreen> {
  int currentStock = 0;
  List<Map<String, dynamic>> transactions = [];

  @override
  void initState() {
    super.initState();
    _loadStockAndHistory();
  }

  Future<void> _loadStockAndHistory() async {
    final db = await DatabaseHelper.instance.database;

    final stock = await db.rawQuery('''
      SELECT IFNULL(SUM(
        CASE WHEN type='IN' THEN quantity
             WHEN type='OUT' THEN -quantity END
      ), 0) AS total
      FROM stock_transactions
      WHERE itemId = ? AND deleted = 0
    ''', [widget.item['id']]);

    final hist = await db.query(
      'stock_transactions',
      where: 'itemId = ? AND deleted = 0',
      whereArgs: [widget.item["id"]],
      orderBy: 'date DESC',
    );

    setState(() {
      currentStock = (stock.first['total'] as num).toInt();
      transactions = hist;
    });
  }

  double _getImageAspectRatio(Uint8List bytes) {
    try {
      final decoded = img.decodeImage(bytes);
      if (decoded != null && decoded.height != 0) {
        return decoded.width / decoded.height;
      }
    } catch (_) {}
    return 1.0;
  }

  String _toEthiopianText(String iso) {
    final greg = DateTime.parse(iso);
    final eth = EthiopianDateHelper.toEthiopian(greg);
    final month = EthiopianDateHelper.monthNamesGeez[eth['month']! - 1];
    return '$month ${eth['day']}, ${eth['year']}';
  }

  DateTime _ethiopianToGregorian(Map<String, int> eth) {
    return EthiopianDateHelper.toGregorian(
      eth['year']!,
      eth['month']!,
      eth['day']!,
    );
  }

  // ===========================================================================
  // ADD / EDIT TRANSACTION (sync-ready)
  // ===========================================================================
  Future<void> _openTransactionDialog({
    Map<String, dynamic>? tx,
    String? initialType,
  }) async {
    final qtyCtrl =
        TextEditingController(text: tx?['quantity']?.toString() ?? '');
    final notesCtrl = TextEditingController(text: tx?['notes'] ?? '');
    String type = tx?['type'] ?? (initialType ?? 'IN');

    DateTime initialGreg =
        tx != null ? DateTime.parse(tx['date'] as String) : DateTime.now();
    Map<String, int> ethInitial = EthiopianDateHelper.toEthiopian(initialGreg);

    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (_, setDialog) => AlertDialog(
          title: Text(tx == null ? 'Add Stock Transaction' : 'Edit Transaction'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: qtyCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Quantity'),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: type,
                  decoration: const InputDecoration(labelText: 'Type'),
                  items: const [
                    DropdownMenuItem(value: 'IN', child: Text('Stock In')),
                    DropdownMenuItem(value: 'OUT', child: Text('Stock Out')),
                  ],
                  onChanged: (v) => type = v!,
                ),
                const SizedBox(height: 8),

                // Ethiopian Date
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Date (E.C.)'),
                    TextButton.icon(
                      icon: const Icon(Icons.calendar_today_outlined),
                      label: Text(
                        '${EthiopianDateHelper.monthNamesGeez[ethInitial['month']! - 1]} '
                        '${ethInitial['day']}, ${ethInitial['year']}',
                      ),
                      onPressed: () async {
                        final picked =
                            await showEthiopianDatePickerDialog(context,
                                initialYear: ethInitial['year']!,
                                initialMonth: ethInitial['month']!,
                                initialDay: ethInitial['day']!);
                        if (picked != null) {
                          setDialog(() => ethInitial = picked);
                        }
                      },
                    ),
                  ],
                ),

                const SizedBox(height: 8),
                TextField(
                  controller: notesCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Notes'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                final qty = int.tryParse(qtyCtrl.text);
                if (qty == null || qty <= 0) return;

                final now = DateTime.now().millisecondsSinceEpoch.toString();
                final greg = _ethiopianToGregorian(ethInitial);
                final db = await DatabaseHelper.instance.database;

                Map<String, dynamic> row = {
                  'itemId': widget.item['id'],
                  'item_uuid': widget.item['uuid'],
                  'quantity': qty,
                  'type': type,
                  'date': greg.toIso8601String(),
                  'notes': notesCtrl.text.trim(),
                  'updated_at': now,
                };

                if (tx == null) {
                  row['uuid'] = const Uuid().v4();
                  row['deleted'] = 0;
                  await db.insert("stock_transactions", row);
                } else {
                  row['uuid'] = tx['uuid'];
                  row['deleted'] = tx['deleted'] ?? 0;

                  await db.update(
                    'stock_transactions',
                    row,
                    where: 'id = ?',
                    whereArgs: [tx['id']],
                  );
                }

                Navigator.pop(context, true);
              },
              child: const Text('Save'),
            )
          ],
        ),
      ),
    );

    if (saved == true) _loadStockAndHistory();
  }

  // ===========================================================================
  // SOFT DELETE
  // ===========================================================================
  Future<void> _deleteTransaction(int id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Transaction'),
        content: const Text('Are you sure you want to delete this entry?'),
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

    if (confirm != true) return;

    final db = await DatabaseHelper.instance.database;

    await db.update(
      "stock_transactions",
      {
        "deleted": 1,
        "updated_at": DateTime.now().millisecondsSinceEpoch.toString(),
      },
      where: "id = ?",
      whereArgs: [id],
    );

    _loadStockAndHistory();

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Transaction deleted")),
    );
  }

  // ===========================================================================
  // EXPORT CSV (type-safe)
  // ===========================================================================
  Future<void> _exportToCSV() async {
    final db = await DatabaseHelper.instance.database;
    final item = widget.item;
    final itemId = item['id'];

    String categoryName = '';
    try {
      final cat = await db.rawQuery('''
        SELECT c.name AS category
        FROM categories c
        JOIN items i ON i.categoryId = c.id
        WHERE i.id = ?
      ''', [itemId]);
      if (cat.isNotEmpty && cat.first['category'] != null) {
        categoryName = cat.first['category'] as String;
      }
    } catch (_) {}

    final txs = await db.query(
      'stock_transactions',
      where: 'itemId = ? AND deleted = 0',
      whereArgs: [itemId],
      orderBy: 'date ASC',
    );

    if (txs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No transactions to export')),
      );
      return;
    }

    final rows = <List<dynamic>>[];
    rows.add(['Item Name', 'Category', 'Date (E.C.)', 'Notes', 'IN', 'OUT', 'STOCK']);

    int runningStock = 0;
    int totalIn = 0;
    int totalOut = 0;

    for (final tx in txs) {
      final dateStr = tx['date'] as String;
      final greg = DateTime.parse(dateStr);
      final eth = EthiopianDateHelper.toEthiopian(greg);
      final ethDate =
          '${EthiopianDateHelper.monthNamesGeez[eth['month']! - 1]} ${eth['day']}, ${eth['year']}';

      final type = tx['type'] as String;
      final qty = (tx['quantity'] as num).toInt();
      final notes = tx['notes']?.toString() ?? '';

      int inQty = 0, outQty = 0;
      if (type == 'IN') {
        inQty = qty;
        totalIn += qty;
        runningStock += qty;
      } else {
        outQty = qty;
        totalOut += qty;
        runningStock -= qty;
      }

      rows.add([
        item['name'],
        categoryName,
        ethDate,
        notes,
        inQty == 0 ? '' : inQty,
        outQty == 0 ? '' : outQty,
        runningStock,
      ]);
    }

    rows.add([]);
    rows.add(['TOTALS', '', '', '', totalIn, totalOut, runningStock]);

    final csvText = const ListToCsvConverter().convert(rows);
    final csvBytes = Uint8List.fromList([
      0xEF, 0xBB, 0xBF,
      ...utf8.encode(csvText),
    ]);

    final tempDir = await getTemporaryDirectory();
    final filePath = '${tempDir.path}/${item['name']}_transactions.csv';
    final file = File(filePath);
    await file.writeAsBytes(csvBytes);

    await Share.shareXFiles(
      [XFile(file.path)],
      text: 'Transaction history for ${item['name']}',
    );
  }

  // ===========================================================================
  // UI (unchanged)
  // ===========================================================================
  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final photo = item['photo'];

    return Scaffold(
      appBar: AppBar(
        title: Text(item['name'] ?? 'Item Details'),
        actions: [
          IconButton(
            icon: const Icon(Icons.share_outlined),
            onPressed: _exportToCSV,
          )
        ],
      ),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FloatingActionButton.extended(
            heroTag: 'in',
            onPressed: () => _openTransactionDialog(initialType: 'IN'),
            icon: const Icon(Icons.arrow_downward),
            label: const Text('Stock In'),
          ),
          const SizedBox(height: 12),
          FloatingActionButton.extended(
            heroTag: 'out',
            backgroundColor: Colors.redAccent,
            onPressed: () => _openTransactionDialog(initialType: 'OUT'),
            icon: const Icon(Icons.arrow_upward),
            label: const Text('Stock Out'),
          ),
        ],
      ),

      // BODY (unchanged)
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (photo != null)
              GestureDetector(
                onTap: () => _openImageFullscreen(photo),
                child: Center(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxHeight: 180,
                        maxWidth: 180,
                      ),
                      child: AspectRatio(
                        aspectRatio: _getImageAspectRatio(photo),
                        child: Image.memory(photo, fit: BoxFit.contain),
                      ),
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 10),

            Text('Code: ${item['code']}',
                style: Theme.of(context).textTheme.titleMedium),
            Text('Description: ${item['description'] ?? ''}'),

            const SizedBox(height: 12),
            Text(
              'Current Stock: $currentStock',
              style: Theme.of(context).textTheme.titleLarge!.copyWith(
                    color: Colors.teal,
                    fontWeight: FontWeight.bold,
                  ),
            ),

            const Divider(height: 30),
            const Text(
              'Transaction History',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),

            if (transactions.isEmpty)
              const Center(child: Text('No stock transactions yet'))
            else
              ListView.builder(
                physics: const NeverScrollableScrollPhysics(),
                shrinkWrap: true,
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(context).padding.bottom + 170,
                ),
                itemCount: transactions.length,
                itemBuilder: (_, i) {
                  final tx = transactions[i];
                  final qty = (tx['quantity'] as num).toInt();
                  final isIn = tx['type'] == 'IN';
                  final notes = tx['notes']?.toString() ?? '';
                  final date = _toEthiopianText(tx['date'] as String);

                  return Card(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    child: ListTile(
                      leading: Icon(
                        isIn ? Icons.arrow_downward : Icons.arrow_upward,
                        color: isIn ? Colors.teal : Colors.redAccent,
                      ),
                      title: Text(
                        '${isIn ? '+' : '-'}$qty pcs',
                        style: TextStyle(
                          color: isIn ? Colors.teal : Colors.redAccent,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: Text(
                        notes.isEmpty ? date : '$date\n$notes',
                        style: const TextStyle(height: 1.3),
                      ),
                      isThreeLine: notes.isNotEmpty,
                      trailing: PopupMenuButton(
                        onSelected: (value) {
                          if (value == 'edit') {
                            _openTransactionDialog(tx: tx);
                          } else if (value == 'delete') {
                            _deleteTransaction(tx['id'] as int);
                          }
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(
                            value: 'edit',
                            child: Row(children: [
                              Icon(Icons.edit_outlined, size: 20),
                              SizedBox(width: 8),
                              Text('Edit'),
                            ]),
                          ),
                          PopupMenuItem(
                            value: 'delete',
                            child: Row(children: [
                              Icon(Icons.delete_outline,
                                  size: 20, color: Colors.redAccent),
                              SizedBox(width: 8),
                              Text('Delete'),
                            ]),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  void _openImageFullscreen(Uint8List photo) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.black.withOpacity(0.7),
        insetPadding: const EdgeInsets.all(12),
        child: InteractiveViewer(
          maxScale: 5,
          minScale: 0.5,
          child: AspectRatio(
            aspectRatio: _getImageAspectRatio(photo),
            child: Image.memory(photo, fit: BoxFit.contain),
          ),
        ),
      ),
    );
  }
}