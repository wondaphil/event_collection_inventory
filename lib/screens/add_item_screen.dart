import 'dart:typed_data';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import '../db/database_helper.dart';

class AddItemScreen extends StatefulWidget {
  const AddItemScreen({super.key});

  @override
  State<AddItemScreen> createState() => _AddItemScreenState();
}

class _AddItemScreenState extends State<AddItemScreen> {
  final _formKey = GlobalKey<FormState>();
  final _codeCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();

  List<Map<String, dynamic>> categories = [];
  int? selectedCategoryId;
  Uint8List? _photoBytes;

  @override
  void initState() {
    super.initState();
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    final result = await DatabaseHelper.instance.getAllCategories();
    setState(() => categories = result);
  }

  Future<void> _pickPhoto() async {
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Pick from Gallery'),
              onTap: () async {
                Navigator.pop(context);
                await _pickFromGallery();
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('Take Photo'),
              onTap: () async {
                Navigator.pop(context);
                await _pickFromCamera();
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickFromGallery() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowCompression: false,
      );
      if (result == null) return;

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
      await _processImage(rawBytes);
    } catch (e) {
      debugPrint('❌ Gallery pick failed: $e');
    }
  }

  Future<void> _pickFromCamera() async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(source: ImageSource.camera);
      if (picked == null) return;
      final rawBytes = await picked.readAsBytes();
      await _processImage(rawBytes);
    } catch (e) {
      debugPrint('❌ Camera pick failed: $e');
    }
  }

  Future<void> _processImage(Uint8List? rawBytes) async {
    if (rawBytes == null) return;
    try {
      final decoded = img.decodeImage(rawBytes);
      if (decoded != null) {
        final resized = img.copyResize(decoded, 
										width: decoded.width > decoded.height ? 500 : null,
										height: decoded.height >= decoded.width ? 500 : null,);
        final compressed = Uint8List.fromList(img.encodeJpg(resized, quality: 85));
        setState(() => _photoBytes = compressed);
      }
    } catch (e) {
      debugPrint('❌ Image processing failed: $e');
    }
  }

  Future<void> _saveItem() async {
    if (_formKey.currentState!.validate()) {
      await DatabaseHelper.instance.insertItem({
        'categoryId': selectedCategoryId,
        'code': _codeCtrl.text,
        'name': _nameCtrl.text,
        'description': _descCtrl.text,
        'photo': _photoBytes,
        'createdAt': DateTime.now().toIso8601String(),
        'updatedAt': DateTime.now().toIso8601String(),
      });
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add Item')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              Center(
                child: GestureDetector(
                  onTap: _pickPhoto,
                  child: _photoBytes != null
                      ? Stack(
                          alignment: Alignment.topRight,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.memory(
                                _photoBytes!,
                                width: 120,
                                height: 120,
                                fit: BoxFit.cover,
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close_rounded,
                                  color: Colors.redAccent),
                              onPressed: () =>
                                  setState(() => _photoBytes = null),
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
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _codeCtrl,
                decoration: const InputDecoration(labelText: 'Item Code'),
                validator: (v) => v!.isEmpty ? 'Enter code' : null,
              ),
              TextFormField(
                controller: _nameCtrl,
                decoration: const InputDecoration(labelText: 'Item Name'),
                validator: (v) => v!.isEmpty ? 'Enter name' : null,
              ),
              TextFormField(
                controller: _descCtrl,
                decoration: const InputDecoration(labelText: 'Description'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                value: selectedCategoryId,
                decoration: const InputDecoration(labelText: 'Category'),
                items: categories.map((c) {
                  return DropdownMenuItem<int>(
                    value: c['id'] as int,
                    child: Text(c['name']),
                  );
                }).toList(),
                onChanged: (value) => setState(() => selectedCategoryId = value),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _saveItem,
                icon: const Icon(Icons.save),
                label: const Text('Save'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}