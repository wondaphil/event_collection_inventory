// lib/screens/add_item_screen.dart

import 'dart:typed_data';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';

import '../db/database_helper.dart';

class AddItemScreen extends StatefulWidget {
  const AddItemScreen({super.key});

  @override
  State<AddItemScreen> createState() => _AddItemScreenState();
}

class _AddItemScreenState extends State<AddItemScreen> {
  final TextEditingController codeCtrl = TextEditingController();
  final TextEditingController nameCtrl = TextEditingController();
  final TextEditingController descCtrl = TextEditingController();

  Uint8List? photoBytes;
  int? categoryId;
  List<Map<String, dynamic>> categories = [];

  @override
  void initState() {
    super.initState();
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    final db = DatabaseHelper.instance;
    final result = await db.getAllCategories();
    setState(() => categories = result);
  }

  // ---------------------------------------------------------------------------
  // HASH
  // ---------------------------------------------------------------------------
  String _computeHash(Uint8List? bytes) {
    if (bytes == null || bytes.isEmpty) return "";
    return sha1.convert(bytes).toString();
  }

  // ---------------------------------------------------------------------------
  // IMAGE PICKING
  // ---------------------------------------------------------------------------
  Future<Uint8List?> _pickPhotoDialog() async {
    return await showModalBottomSheet<Uint8List?>(
      context: context,
      builder: (_) => Wrap(
        children: [
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Pick from Gallery'),
            onTap: () async => Navigator.pop(context, await _pickFromGallery()),
          ),
          ListTile(
            leading: const Icon(Icons.camera_alt_outlined),
            title: const Text('Take Photo'),
            onTap: () async => Navigator.pop(context, await _pickFromCamera()),
          ),
        ],
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
        final safeCopy =
            File('${tempDir.path}/${pickedFile.uri.pathSegments.last}');
        await pickedFile.copy(safeCopy.path);
        rawBytes = await safeCopy.readAsBytes();
      }

      return _processImage(rawBytes);
    } catch (_) {
      return null;
    }
  }

  Future<Uint8List?> _pickFromCamera() async {
    try {
      final picked =
          await ImagePicker().pickImage(source: ImageSource.camera);

      if (picked == null) return null;

      final rawBytes = await picked.readAsBytes();
      return _processImage(rawBytes);
    } catch (_) {
      return null;
    }
  }

  Uint8List? _processImage(Uint8List? rawBytes) {
    if (rawBytes == null) return null;

    try {
      final decoded = img.decodeImage(rawBytes);
      if (decoded != null) {
        final resized = img.copyResize(
          decoded,
          width: decoded.width > decoded.height ? 1600 : null,
          height: decoded.height >= decoded.width ? 1600 : null,
        );
        return Uint8List.fromList(img.encodeJpg(resized, quality: 80));
      }
    } catch (_) {}

    return rawBytes;
  }

  // ---------------------------------------------------------------------------
  // SAVE (with correct "photo_hash")
  // ---------------------------------------------------------------------------
  Future<void> _saveItem() async {
    if (nameCtrl.text.trim().isEmpty || codeCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Code & Name are required")),
      );
      return;
    }

    final db = DatabaseHelper.instance;
    final uuid = const Uuid().v4();
    final now = DateTime.now().millisecondsSinceEpoch.toString();

    String? categoryUuid;
    if (categoryId != null) {
      final rows = await db.database.then((dbConn) => dbConn.query(
            "categories",
            where: "id=?",
            whereArgs: [categoryId],
            limit: 1,
          ));
      if (rows.isNotEmpty) {
        categoryUuid = rows.first["uuid"] as String?;
      }
    }

    await db.insertItem({
      "uuid": uuid,
      "code": codeCtrl.text.trim(),
      "name": nameCtrl.text.trim(),
      "description": descCtrl.text.trim(),
      "photo": photoBytes,
      "photo_hash": _computeHash(photoBytes), // 🔥 FIXED: correct DB column
      "createdAt": now,
      "updatedAt": now,
      "categoryId": categoryId,
      "category_uuid": categoryUuid,
      "deleted": 0,
    });

    Navigator.pop(context, true);
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Add Item")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            GestureDetector(
              onTap: () async {
                final picked = await _pickPhotoDialog();
                if (picked != null) setState(() => photoBytes = picked);
              },
              child: photoBytes != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.memory(
                        photoBytes!,
                        width: 140,
                        height: 140,
                        fit: BoxFit.cover,
                      ),
                    )
                  : Container(
                      width: 140,
                      height: 140,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.add_a_photo_outlined,
                          size: 40, color: Colors.grey),
                    ),
            ),

            const SizedBox(height: 16),

            TextField(
              controller: codeCtrl,
              decoration: const InputDecoration(labelText: 'Code'),
            ),
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            TextField(
              controller: descCtrl,
              decoration: const InputDecoration(labelText: 'Description'),
            ),

            const SizedBox(height: 12),

            DropdownButtonFormField<int>(
              value: categoryId,
              decoration: const InputDecoration(labelText: "Category"),
              items: [
                const DropdownMenuItem<int>(
                  value: null,
                  child: Text("None"),
                ),
                ...categories.map(
                  (c) => DropdownMenuItem<int>(
                    value: c['id'],
                    child: Text(c['name']),
                  ),
                ),
              ],
              onChanged: (v) => setState(() => categoryId = v),
            ),

            const SizedBox(height: 20),

            FilledButton.icon(
              icon: const Icon(Icons.check),
              label: const Text("Save Item"),
              onPressed: _saveItem,
            ),
          ],
        ),
      ),
    );
  }
}