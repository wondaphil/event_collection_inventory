// lib/utils/sync_service.dart
import 'dart:typed_data';
import 'dart:convert';
import 'package:crypto/crypto.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../db/database_helper.dart';

class SyncService {
  static final SyncService instance = SyncService._internal();
  SyncService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;

  String? _deviceId;

  Map<String, String?> lastSyncTimes = {
    "categories": null,
    "items": null,
    "transactions": null,
  };

  // SHA1 helper
  String _hash(Uint8List? bytes) =>
      (bytes == null || bytes.isEmpty) ? "" : sha1.convert(bytes).toString();

  // Safe timestamp convert
  String _ts(dynamic v) => v?.toString() ?? "";

  // ---------------------------------------------------------------------------
  // DEVICE ID
  // ---------------------------------------------------------------------------
  Future<String> get deviceId async {
    if (_deviceId != null) return _deviceId!;
    final db = await DatabaseHelper.instance.database;

    await db.execute("""
      CREATE TABLE IF NOT EXISTS device_info (
        device_id TEXT PRIMARY KEY
      )
    """);

    final rows = await db.query("device_info");
    if (rows.isNotEmpty) {
      _deviceId = rows.first["device_id"] as String;
      return _deviceId!;
    }

    _deviceId = const Uuid().v4();
    await db.insert("device_info", {"device_id": _deviceId});
    return _deviceId!;
  }

  // ---------------------------------------------------------------------------
  // LOAD / SAVE TIMESTAMPS
  // ---------------------------------------------------------------------------
  Future<Map<String, dynamic>> _loadTimes() async {
    final id = await deviceId;
    final doc = await _firestore.collection("sync").doc(id).get();
    return doc.data() ??
        {
          "categories": null,
          "items": null,
          "transactions": null,
        };
  }

  Future<void> _saveTimes(String ts) async {
    final id = await deviceId;
    await _firestore.collection("sync").doc(id).set({
      "categories": ts,
      "items": ts,
      "transactions": ts,
    }, SetOptions(merge: true));
  }

  // ---------------------------------------------------------------------------
  // MASTER SYNC
  // ---------------------------------------------------------------------------
  Future<void> syncAll() async {
    lastSyncTimes = Map.from(await _loadTimes());

    await _syncCategories();
    await _syncItems();
    await _syncTransactions();

    final now = DateTime.now().millisecondsSinceEpoch.toString();
    await _saveTimes(now);

    lastSyncTimes = {
      "categories": now,
      "items": now,
      "transactions": now,
    };
  }

  // ========================================================================
  //  CATEGORIES
  // ========================================================================
  Future<void> _syncCategories() async {
    final db = await DatabaseHelper.instance.database;
    final localRows = await db.query("categories");

    // ------------------ UPLOAD → FIRESTORE ------------------
    for (final row in localRows) {
      final uuid = row["uuid"]?.toString();
      if (uuid == null || uuid.isEmpty) continue;

      await _firestore.collection("categories").doc(uuid).set({
        "uuid": uuid,
        "name": row["name"],
        "description": row["description"],
        "createdAt": row["createdAt"],
        "updated_at": row["updated_at"], // FIXED
        "deleted": row["deleted"] == 1,
      }, SetOptions(merge: true));
    }

    // ------------------ DOWNLOAD ← FIRESTORE ------------------
    final snap = await _firestore.collection("categories").get();

    for (final doc in snap.docs) {
      final data = doc.data();
      final uuid = data["uuid"];
      if (uuid == null) continue;

      final remoteUpdated = _ts(data["updated_at"]);

      final local = await db.query(
        "categories",
        where: "uuid = ?",
        whereArgs: [uuid],
      );

      final localUpdated =
          local.isEmpty ? "" : _ts(local.first["updated_at"]);

      // skip if timestamps match
      if (localUpdated == remoteUpdated) continue;

      await db.insert(
        "categories",
        {
          "uuid": uuid,
          "name": data["name"],
          "description": data["description"],
          "createdAt": data["createdAt"],
          "updated_at": remoteUpdated,
          "deleted": data["deleted"] == true ? 1 : 0,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }

  // ========================================================================
  //  ITEMS (with photoHash incremental sync)
  // ========================================================================
  Future<void> _syncItems() async {
    final db = await DatabaseHelper.instance.database;

    final localRows = await db.query("items");

    // ------------------ UPLOAD → FIRESTORE ------------------
    // UPLOAD →
	for (final row in localRows) {
	  final String uuid = row["uuid"].toString();

	  Uint8List? photo;
	  final raw = row["photo"];
	  if (raw is Uint8List) {
	    photo = raw;
	  } 
	  else if (raw is List<int>) {
	    photo = Uint8List.fromList(raw);
	  }

	  final String localHash = row["photoHash"]?.toString() ?? "";
	  String? photoUrl;

	  // Upload ONLY if hash exists AND photo exists
	  if (localHash.isNotEmpty && photo != null) {
		final ref = _storage.ref("items/photos/$uuid.jpg");
		await ref.putData(photo, SettableMetadata(contentType: "image/jpeg"));
		photoUrl = await ref.getDownloadURL();
	  }

	  await _firestore.collection("items").doc(uuid).set({
		"uuid": uuid,
		"code": row["code"],
		"name": row["name"],
		"description": row["description"],
		"category_uuid": row["category_uuid"],
		"createdAt": row["createdAt"],
		"updatedAt": row["updatedAt"],
		"deleted": row["deleted"] == 1,
		"photoHash": localHash,
		"photoUrl": photoUrl, // stays unchanged if null
	  }, SetOptions(merge: true));
	}

    // ------------------ DOWNLOAD ← FIRESTORE ------------------
    final remoteSnap = await _firestore.collection("items").get();

    for (final doc in remoteSnap.docs) {
      final data = doc.data();
      final uuid = data["uuid"];
      if (uuid == null) continue;

      final remoteUpdated = _ts(data["updatedAt"]);
      final remoteHash = data["photoHash"]?.toString() ?? "";

      final local = await db.query(
        "items",
        where: "uuid = ?",
        whereArgs: [uuid],
      );

      final localUpdated =
          local.isEmpty ? "" : _ts(local.first["updatedAt"]);
      final localHash =
          local.isEmpty ? "" : (local.first["photoHash"]?.toString() ?? "");

      // 🔍 DEBUG PRINTS
		print("🔍 ITEM CHECK — $uuid");
		print("  localUpdated : $localUpdated");
		print("  remoteUpdated: $remoteUpdated");
		print("  localHash    : $localHash");
		print("  remoteHash   : $remoteHash");

		if (localUpdated != remoteUpdated) {
		  print("  ⚠️ updatedAt mismatch → will sync");
		} else {
		  print("  ✔️ updatedAt match");
		}

		if (localHash != remoteHash) {
		  print("  ⚠️ photoHash mismatch → will sync");
		} else {
		  print("  ✔️ photoHash match");
		}

	  // skip if BOTH timestamp and hash match
      if (localUpdated == remoteUpdated && localHash == remoteHash) continue;

      Uint8List? newPhoto;

      // Download photo if hash changed
      if (remoteHash != "" && remoteHash != localHash) {
        try {
          if (data["photoUrl"] != null) {
            final ref = _storage.refFromURL(data["photoUrl"]);
            newPhoto = await ref.getData();
          }
        } catch (_) {}
      }

      // Map category uuid → local categoryId
      int? categoryId;
      if (data["category_uuid"] != null) {
        final cat = await db.query(
          "categories",
          where: "uuid = ?",
          whereArgs: [data["category_uuid"]],
        );
        if (cat.isNotEmpty) categoryId = cat.first["id"] as int;
      }

      await db.insert(
        "items",
        {
          "uuid": uuid,
          "code": data["code"],
          "name": data["name"],
          "description": data["description"],
          "photo": newPhoto ?? (local.isNotEmpty ? local.first["photo"] : null),
          "photoHash": remoteHash,
          "createdAt": data["createdAt"],
          "updatedAt": remoteUpdated,
          "category_uuid": data["category_uuid"],
          "categoryId": categoryId,
          "deleted": data["deleted"] == true ? 1 : 0,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }

  // ========================================================================
  //  TRANSACTIONS
  // ========================================================================
  Future<void> _syncTransactions() async {
    final db = await DatabaseHelper.instance.database;
    final localRows = await db.query("stock_transactions");

    // ------------------ UPLOAD → FIRESTORE ------------------
    for (final row in localRows) {
      final String uuid = row["uuid"].toString();
      final itemUuid = row["item_uuid"];
      if (uuid == null || itemUuid == null) continue;

      await _firestore.collection("stock_transactions").doc(uuid).set({
        "uuid": uuid,
        "item_uuid": itemUuid,
        "quantity": row["quantity"],
        "type": row["type"],
        "date": row["date"],
        "notes": row["notes"],
        "updated_at": row["updated_at"],
        "deleted": row["deleted"] == 1,
      }, SetOptions(merge: true));
    }

    // ------------------ DOWNLOAD ← FIRESTORE ------------------
    final snap = await _firestore.collection("stock_transactions").get();

    for (final doc in snap.docs) {
      final data = doc.data();
      final uuid = data["uuid"];
      if (uuid == null) continue;

      final remoteUpdated = _ts(data["updated_at"]);

      final local = await db.query(
        "stock_transactions",
        where: "uuid = ?",
        whereArgs: [uuid],
      );

      final localUpdated =
          local.isEmpty ? "" : _ts(local.first["updated_at"]);

      if (localUpdated == remoteUpdated) continue;

      // map item uuid → itemId
      final itemUuid = data["item_uuid"];
      final itemMatch = await db.query(
        "items",
        where: "uuid = ?",
        whereArgs: [itemUuid],
      );

      if (itemMatch.isEmpty) continue;

      final itemId = itemMatch.first["id"] as int;

      await db.insert(
        "stock_transactions",
        {
          "uuid": uuid,
          "item_uuid": itemUuid,
          "itemId": itemId,
          "quantity": data["quantity"],
          "type": data["type"],
          "date": data["date"],
          "notes": data["notes"],
          "updated_at": remoteUpdated,
          "deleted": data["deleted"] == true ? 1 : 0,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }
}