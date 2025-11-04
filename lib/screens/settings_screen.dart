import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:file_picker/file_picker.dart';
import 'package:sqflite/sqflite.dart';
import '../db/database_helper.dart';
import '../utils/drive_backup.dart';
import 'about_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  Future<String> _getDatabasePath() async {
    final dbPath = await getDatabasesPath();
    return p.join(dbPath, 'inventory.db');
  }

  // ✅ Export using SAF so user can pick "Downloads" or any folder
  Future<void> _extractData() async {
	  try {
		final dbPath = await _getDatabasePath();
		final dbFile = File(dbPath);
		final dbBytes = await dbFile.readAsBytes();

		// Ask the user where to save it (system dialog)
		final savedPath = await FilePicker.platform.saveFile(
		  dialogTitle: 'Export inventory.db',
		  fileName: 'inventory.db',
		  bytes: dbBytes, // ✅ REQUIRED on Android/iOS
		);

		if (savedPath == null) return; // cancelled
		ScaffoldMessenger.of(context).showSnackBar(
		  SnackBar(content: Text('✅ Data exported to $savedPath')),
		);
	  } catch (e) {
		ScaffoldMessenger.of(context)
			.showSnackBar(SnackBar(content: Text('Export failed: $e')));
	  }
	}

  // ✅ Import using SAF picker
  Future<void> _importData() async {
	  final result = await FilePicker.platform.pickFiles(
		dialogTitle: 'Select a database file',
		type: FileType.any,
		allowMultiple: false,
	  );
	  if (result == null) return;

	  final selected = File(result.files.single.path!);

	  // ✅ STEP 1: Validate it's an actual SQLite database
	  bool isValid = false;
	  try {
		final db = await openDatabase(selected.path);
		final tables = await db.rawQuery(
			"SELECT name FROM sqlite_master WHERE type='table'");
		await db.close();

		// Ensure it contains the expected tables
		final tableNames =
			tables.map((t) => t['name'] as String).toList(growable: false);
		if (tableNames.contains('items') &&
			tableNames.contains('categories') &&
			tableNames.contains('stock_transactions')) {
		  isValid = true;
		}
	  } catch (e) {
		isValid = false;
	  }

	  if (!isValid) {
		ScaffoldMessenger.of(context).showSnackBar(
		  const SnackBar(content: Text('❌ Invalid database file selected')),
		);
		return;
	  }

	  // ✅ STEP 2: Confirm replacement
	  final confirm = await showDialog<bool>(
		context: context,
		builder: (_) => AlertDialog(
		  title: const Text('Replace Existing Data?'),
		  content: const Text(
			  'This will overwrite your current database with the selected file. Continue?'),
		  actions: [
			TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
			FilledButton(
			  style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
			  onPressed: () => Navigator.pop(context, true),
			  child: const Text('Replace'),
			),
		  ],
		),
	  );

	  if (confirm != true) return;

	  // ✅ STEP 3: Replace app database safely
	  try {
		final dbPath = await _getDatabasePath();
		await File(dbPath).writeAsBytes(await selected.readAsBytes(), flush: true);
		
		final dbHelper = DatabaseHelper.instance;
		await dbHelper.reloadDatabase();
		
		// Trigger refresh in the rest of the app
		Navigator.pop(context, true);

		ScaffoldMessenger.of(context).showSnackBar(
		  const SnackBar(content: Text('✅ Database replaced successfully.')),
		);
	  } catch (e) {
		ScaffoldMessenger.of(context)
			.showSnackBar(SnackBar(content: Text('Import failed: $e')));
	  }
	}

  // ✅ Back to Google Drive
  Future<void> _backuoDataToDrive() async {
	  try {
		await DriveBackup.uploadBackup();
		ScaffoldMessenger.of(context).showSnackBar(
		  const SnackBar(content: Text('✅ Backup uploaded to Google Drive')),
		);
	  } catch (e) {
		ScaffoldMessenger.of(context).showSnackBar(
		  SnackBar(content: Text('Backup failed: $e')),
		);
	  }
	}
	
  // ✅ Restore from Google Drive
  Future<void> _restoreDataFromDrive() async {
	  try {
		await DriveBackup.restoreBackup();
		ScaffoldMessenger.of(context).showSnackBar(
		  const SnackBar(content: Text('✅ Restored from Google Drive')),
		);
	  } catch (e) {
		ScaffoldMessenger.of(context).showSnackBar(
		  SnackBar(content: Text('Restore failed: $e')),
		);
	  }
	}


  @override
  Widget build(BuildContext context) {
    final cardColor = Theme.of(context).colorScheme.surfaceContainerHighest;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            Card(
              color: cardColor,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: ListTile(
                leading: const Icon(Icons.file_download_outlined, color: Colors.teal),
                title: const Text('Extract Data'),
                subtitle: const Text('Choose where to save your database (.db) file'),
                onTap: _extractData,
              ),
            ),
            const SizedBox(height: 12),
            Card(
              color: cardColor,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: ListTile(
                leading: const Icon(Icons.file_upload_outlined, color: Colors.blue),
                title: const Text('Import Data'),
                subtitle: const Text('Select a .db file to replace current data'),
                onTap: _importData,
              ),
            ),
			Card(
			  color: cardColor,
			  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
			  child: ListTile(
				leading: const Icon(Icons.cloud_upload_outlined, color: Colors.indigo),
				title: const Text('Backup to Google Drive'),
				subtitle: const Text('The database (.db) file will be backed up'),
                onTap: _backuoDataToDrive,
			  ),
			),
			const SizedBox(height: 12),
			Card(
			  color: cardColor,
			  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
			  child: ListTile(
				leading: const Icon(Icons.cloud_download_outlined, color: Colors.indigo),
				title: const Text('Restore from Google Drive'),
				subtitle: const Text('The database (.db) file will be restored'),
                onTap: _restoreDataFromDrive,
			  ),
			),
			const SizedBox(height: 12),
			Card(
			  color: cardColor,
			  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
			  child: ListTile(
				leading: const Icon(Icons.info_outline, color: Colors.grey),
				title: const Text('About'),
				subtitle: const Text('App version and developer info'),
				onTap: () {
				  Navigator.push(
					context,
					MaterialPageRoute(builder: (_) => const AboutScreen()),
				  );
				},
			  ),
			),
          ],
        ),
      ),
    );
  }
}