import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:csv/csv.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../utils/ethiopian_date_helper.dart';
import '../widgets/ethiopian_date_picker.dart';
import '../db/database_helper.dart';
import '../utils/ethiopian_date_helper.dart';

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
      SELECT IFNULL(SUM(CASE WHEN type='IN' THEN quantity
                             WHEN type='OUT' THEN -quantity END), 0) AS total
      FROM stock_transactions WHERE itemId = ?
    ''', [widget.item['id']]);

    final hist = await db.query(
      'stock_transactions',
      where: 'itemId = ?',
      whereArgs: [widget.item['id']],
      orderBy: 'date DESC',
    );

    setState(() {
      currentStock = stock.first['total'] as int;
      transactions = hist;
    });
  }

  String _toEthiopianText(String isoString) {
    final greg = DateTime.parse(isoString);
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

  Future<void> _openTransactionDialog(
      {Map<String, dynamic>? tx, String? initialType}) async {
    final qtyCtrl =
        TextEditingController(text: tx?['quantity']?.toString() ?? '');
    final notesCtrl = TextEditingController(text: tx?['notes'] ?? '');
    String type = tx?['type'] ?? (initialType ?? 'IN');

    DateTime initialGreg =
        tx != null ? DateTime.parse(tx['date']) : DateTime.now();
    Map<String, int> ethInitial = EthiopianDateHelper.toEthiopian(initialGreg);

    final saved = await showDialog<bool>(
      context: context,
	  barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
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
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Date (E.C.):',
                        style: TextStyle(fontSize: 16)),
                    TextButton.icon(
                      icon: const Icon(Icons.calendar_today_outlined),
                      label: Text(
                        '${EthiopianDateHelper.monthNamesGeez[ethInitial['month']! - 1]} '
                        '${ethInitial['day']}, ${ethInitial['year']}',
                      ),
                      onPressed: () async {
                        final picked = await showEthiopianDatePickerDialog(
                          context,
                          initialYear: ethInitial['year']!,
                          initialMonth: ethInitial['month']!,
                          initialDay: ethInitial['day']!,
                        );

                        if (picked != null) {
                          setStateDialog(() => ethInitial = picked);
                        }
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: notesCtrl,
                  decoration:
                      const InputDecoration(labelText: 'Notes (optional)'),
                  maxLines: 2,
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

                final gregDate = _ethiopianToGregorian(ethInitial);
                final db = await DatabaseHelper.instance.database;
                final data = {
                  'itemId': widget.item['id'],
                  'quantity': qty,
                  'type': type,
                  'date': gregDate.toIso8601String(),
                  'notes': notesCtrl.text.trim(),
                };

                if (tx == null) {
                  await db.insert('stock_transactions', data);
                } else {
                  await db.update(
                    'stock_transactions',
                    data,
                    where: 'id = ?',
                    whereArgs: [tx['id']],
                  );
                }

                Navigator.pop(context, true);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    if (saved == true) _loadStockAndHistory();
  }

  Future<void> _deleteTransaction(int id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Transaction'),
        content: const Text('Are you sure you want to delete this entry?'),
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

    if (confirmed == true) {
      final db = await DatabaseHelper.instance.database;
      await db.delete('stock_transactions',
          where: 'id = ?', whereArgs: [id]);
      _loadStockAndHistory();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Transaction deleted')),
      );
    }
  }
  
  Future<void> _exportToCSV() async {
	  final db = await DatabaseHelper.instance.database;
	  final item = widget.item;
	  final itemId = item['id'];

	  // ✅ Get category name (if available)
	  String categoryName = '';
	  try {
		final cat = await db.rawQuery('''
		  SELECT c.name AS category
		  FROM categories c
		  JOIN items i ON i.categoryId = c.id
		  WHERE i.id = ?
		''', [itemId]);
		if (cat.isNotEmpty && cat.first['category'] != null) {
		  categoryName = cat.first['category'].toString();
		}
	  } catch (_) {
		categoryName = '';
	  }

	  // ✅ Fetch transactions
	  final txs = await db.query(
		'stock_transactions',
		where: 'itemId = ?',
		whereArgs: [itemId],
		orderBy: 'date ASC',
	  );

	  if (txs.isEmpty) {
		ScaffoldMessenger.of(context).showSnackBar(
		  const SnackBar(content: Text('No transactions to export.')),
		);
		return;
	  }

	  // ✅ Prepare rows
	  final rows = <List<dynamic>>[];
	  rows.add(['Item Name', 'Category', 'Date (E.C.)', 'Notes', 'IN', 'OUT', 'STOCK']);

	  int runningStock = 0;
	  int totalIn = 0;
	  int totalOut = 0;

	  for (final tx in txs) {
		final dateStr = tx['date']?.toString() ?? '';
		final greg = DateTime.tryParse(dateStr) ?? DateTime.now();
		final eth = EthiopianDateHelper.toEthiopian(greg);
		final ethDate =
			'${EthiopianDateHelper.monthNamesGeez[eth['month']! - 1]} ${eth['day']}, ${eth['year']}';

		final type = tx['type']?.toString() ?? '';
		final qty = int.tryParse(tx['quantity'].toString()) ?? 0;
		final notes = tx['notes']?.toString() ?? '';

		int inQty = 0, outQty = 0;
		if (type == 'IN') {
		  inQty = qty;
		  totalIn += qty;
		  runningStock += qty;
		} else if (type == 'OUT') {
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

	  // ✅ Add summary row
	  rows.add([]);
	  rows.add(['TOTALS', '', '', '', totalIn, totalOut, runningStock]);

	  // ✅ Convert to CSV (with BOM for Excel)
	  final csvText = const ListToCsvConverter().convert(rows);
	  final csvBytes = Uint8List.fromList([
		0xEF, 0xBB, 0xBF, // BOM for UTF-8 Excel compatibility
		...utf8.encode(csvText),
	  ]);

	  // ✅ Write to temporary file for sharing
	  final tempDir = await getTemporaryDirectory();
	  final filePath = '${tempDir.path}/${item['name']}_transactions.csv';
	  final file = File(filePath);
	  await file.writeAsBytes(csvBytes, flush: true);

	  // ✅ Open system share dialog
	  await Share.shareXFiles(
		[XFile(file.path)],
		text: 'Transaction history for ${item['name']}',
	  );

	  ScaffoldMessenger.of(context).showSnackBar(
		const SnackBar(content: Text('✅ CSV ready to share')),
	  );
	}

  @override
  Widget build(BuildContext context) {
    final item = widget.item;

    return Scaffold(
      appBar: AppBar(
		  title: Text(item['name'] ?? 'Item Details'),
		  actions: [
			IconButton(
			  icon: const Icon(Icons.share_outlined),
			  tooltip: 'Export to CSV',
			  onPressed: _exportToCSV,
			),
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
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
            const Text('Transaction History',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Expanded(
              child: transactions.isEmpty
                  ? const Center(child: Text('No stock transactions yet'))
                  : ListView.builder(
					  padding: EdgeInsets.only(
						bottom: MediaQuery.of(context).padding.bottom + 120, // 👈 enough for 2 FABs
					  ),
					  itemCount: transactions.length,
					  itemBuilder: (context, index) {
						final tx = transactions[index];
						final isIn = tx['type'] == 'IN';
						final qty = tx['quantity'];
						final notes = tx['notes'] ?? '';
						final date = _toEthiopianText(tx['date']);

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
							trailing: PopupMenuButton<String>(
							  tooltip: 'More actions',
							  onSelected: (value) {
								switch (value) {
								  case 'edit':
									_openTransactionDialog(tx: tx);
									break;
								  case 'delete':
									_deleteTransaction(tx['id'] as int);
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
									  Icon(Icons.delete_outline,
										  color: Colors.redAccent, size: 20),
									  SizedBox(width: 8),
									  Text('Delete'),
									],
								  ),
								),
							  ],
							),
						  ),
						);
					  },
					)
            ),
          ],
        ),
      ),
    );
  }
}