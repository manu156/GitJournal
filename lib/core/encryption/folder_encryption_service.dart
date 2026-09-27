/*
 * SPDX-FileCopyrightText: 2024 GitJournal Contributors
 *
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:gitjournal/core/folder/notes_folder_fs.dart';
import 'package:gitjournal/settings/git_config.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:universal_io/io.dart' as io;

class EncryptionMarkerData {
  final int version;
  final List<int> salt;
  final List<int> verifierCiphertext;

  EncryptionMarkerData({
    required this.version,
    required this.salt,
    required this.verifierCiphertext,
  });

  Map<String, dynamic> toJson() => {
        'version': version,
        'salt': base64Encode(salt),
        'verifier': base64Encode(verifierCiphertext),
      };

  factory EncryptionMarkerData.fromJson(Map<String, dynamic> json) =>
      EncryptionMarkerData(
        version: json['version'] as int? ?? 1,
        salt: base64Decode(json['salt'] as String),
        verifierCiphertext: base64Decode(json['verifier'] as String),
      );
}

class FolderLockedException implements Exception {
  final String folderPath;
  FolderLockedException(this.folderPath);

  @override
  String toString() => "FolderLockedException: Folder '$folderPath' is locked.";
}

class FolderEncryptionService {
  static final FolderEncryptionService instance = FolderEncryptionService();

  static const String markerFileName = '.gj_encrypted';
  static const List<int> magicHeader = [0x47, 0x4A, 0x45, 0x4E, 0x43, 0x31]; // 'GJENC1'
  static const String verifierPlaintext = "GJ_VERIFIER_V1";
  static const int saltBytesLength = 16;
  static const int pbkdf2Iterations = 10000;

  static const String prefUnlockedUntil = 'encryption_unlocked_until';
  static const String prefCachedPassword = 'encryption_cached_password';

  String? _cachedPassword;
  DateTime? _unlockedUntil;
  final Map<String, SecretKey> _keyCache = {};

  SharedPreferences? pref;

  FolderEncryptionService({this.pref});

  String? get cachedPassword => _cachedPassword;

  void init({SharedPreferences? preferences}) {
    if (preferences != null) {
      pref = preferences;
    }
    _checkPersistence();
  }

  void _checkPersistence() {
    if (pref == null) return;
    var untilStr = pref!.getString(prefUnlockedUntil);
    if (untilStr != null) {
      try {
        var expiry = DateTime.parse(untilStr);
        if (DateTime.now().isBefore(expiry)) {
          _unlockedUntil = expiry;
          _cachedPassword = pref!.getString(prefCachedPassword) ?? _cachedPassword;
        } else {
          _unlockedUntil = null;
          _cachedPassword = null;
        }
      } catch (_) {
        _unlockedUntil = null;
      }
    }
  }

  bool isUnlocked() {
    _checkPersistence();
    if (_unlockedUntil == null) return false;
    return DateTime.now().isBefore(_unlockedUntil!);
  }

  Future<void> markUnlocked(String password, {SharedPreferences? preferences}) async {
    _cachedPassword = password;
    _unlockedUntil = DateTime.now().add(const Duration(days: 90));

    var targetPref = preferences ?? pref ?? await SharedPreferences.getInstance();
    pref ??= targetPref;
    await targetPref.setString(
        prefUnlockedUntil, _unlockedUntil!.toIso8601String());
    await targetPref.setString(prefCachedPassword, password);
  }

  Future<void> lock({SharedPreferences? preferences}) async {
    _cachedPassword = null;
    _unlockedUntil = null;
    _keyCache.clear();

    var targetPref = preferences ?? pref ?? await SharedPreferences.getInstance();
    pref ??= targetPref;
    await targetPref.remove(prefUnlockedUntil);
    await targetPref.remove(prefCachedPassword);
  }

  static bool isEncryptedBytes(List<int> bytes) {
    if (bytes.length < magicHeader.length) return false;
    for (int i = 0; i < magicHeader.length; i++) {
      if (bytes[i] != magicHeader[i]) return false;
    }
    return true;
  }

  Future<SecretKey> deriveKey(String password, List<int> salt) async {
    var cacheKey = '$password:${base64Encode(salt)}';
    if (_keyCache.containsKey(cacheKey)) {
      return _keyCache[cacheKey]!;
    }

    final pbkdf2 = Pbkdf2.hmacSha256(
      bits: 256,
      iterations: pbkdf2Iterations,
    );
    final key = await pbkdf2.deriveKey(
      secretKey: SecretKey(utf8.encode(password)),
      nonce: salt,
    );
    _keyCache[cacheKey] = key;
    return key;
  }

  Future<List<int>> encryptBytes(List<int> plainBytes, SecretKey key) async {
    final algorithm = AesGcm.with256bits();
    final secretBox = await algorithm.encrypt(
      plainBytes,
      secretKey: key,
    );
    final concatenated = secretBox.concatenation();
    return [...magicHeader, ...concatenated];
  }

  Future<List<int>> decryptBytes(List<int> cipherBytes, SecretKey key) async {
    if (!isEncryptedBytes(cipherBytes)) {
      throw const FormatException("Bytes do not have GJENC1 header");
    }
    final rawBox = cipherBytes.sublist(magicHeader.length);
    final algorithm = AesGcm.with256bits();
    final secretBox = SecretBox.fromConcatenation(
      rawBox,
      nonceLength: algorithm.nonceLength,
      macLength: algorithm.macAlgorithm.macLength,
    );
    return await algorithm.decrypt(secretBox, secretKey: key);
  }

  Future<EncryptionMarkerData> createMarker(
      String folderFullPath, String password) async {
    final salt = List<int>.generate(
      saltBytesLength,
      (i) => Random.secure().nextInt(256),
    );
    final key = await deriveKey(password, salt);
    final verifierBytes =
        await encryptBytes(utf8.encode(verifierPlaintext), key);

    final marker = EncryptionMarkerData(
      version: 1,
      salt: salt,
      verifierCiphertext: verifierBytes,
    );

    final markerFile = io.File(p.join(folderFullPath, markerFileName));
    await markerFile.writeAsString(jsonEncode(marker.toJson()), flush: true);
    return marker;
  }

  EncryptionMarkerData? readMarker(String folderFullPath) {
    final markerFile = io.File(p.join(folderFullPath, markerFileName));
    if (!markerFile.existsSync()) return null;
    try {
      final content = markerFile.readAsStringSync();
      final json = jsonDecode(content) as Map<String, dynamic>;
      return EncryptionMarkerData.fromJson(json);
    } catch (_) {
      return null;
    }
  }

  Future<bool> verifyPassword(
      String folderFullPath, String password) async {
    final marker = readMarker(folderFullPath);
    if (marker == null) return false;

    try {
      final key = await deriveKey(password, marker.salt);
      final decryptedBytes =
          await decryptBytes(marker.verifierCiphertext, key);
      final decryptedText = utf8.decode(decryptedBytes);
      return decryptedText == verifierPlaintext;
    } catch (_) {
      return false;
    }
  }

  Future<bool> unlockWithPassword(
    NotesFolderFS folder,
    String password, {
    GitConfig? gitConfig,
    SharedPreferences? preferences,
  }) async {
    final root = folder.encryptionRoot;
    if (root == null) return true;

    final isValid = await verifyPassword(root.fullFolderPath, password);
    if (!isValid) return false;

    await markUnlocked(password, preferences: preferences);
    if (gitConfig != null) {
      gitConfig.encryptionPassword = password;
      await gitConfig.save();
    }
    return true;
  }

  Future<void> convertFolderToEncrypted(
    NotesFolderFS folder,
    String password, {
    GitConfig? gitConfig,
    SharedPreferences? preferences,
  }) async {
    final folderPath = folder.fullFolderPath;
    final marker = await createMarker(folderPath, password);
    final key = await deriveKey(password, marker.salt);

    // Encrypt all files recursively in this directory
    final dir = io.Directory(folderPath);
    if (dir.existsSync()) {
      await for (var entity in dir.list(recursive: true, followLinks: false)) {
        if (entity is io.File) {
          final fileName = p.basename(entity.path);
          if (fileName.startsWith('.')) continue; // skip marker and hidden files

          final bytes = await entity.readAsBytes();
          if (!isEncryptedBytes(bytes)) {
            final encryptedBytes = await encryptBytes(bytes, key);
            await entity.writeAsBytes(encryptedBytes, flush: true);
          }
        }
      }
    }

    await markUnlocked(password, preferences: preferences);
    if (gitConfig != null) {
      gitConfig.encryptionPassword = password;
      await gitConfig.save();
    }
  }

  Future<String?> resolvePassword({GitConfig? gitConfig}) async {
    if (pref == null) {
      try {
        pref = await SharedPreferences.getInstance();
        _checkPersistence();
      } catch (_) {}
    }
    if (!isUnlocked()) {
      return null;
    }
    if (_cachedPassword != null && _cachedPassword!.isNotEmpty) {
      return _cachedPassword;
    }
    if (gitConfig != null && gitConfig.encryptionPassword.isNotEmpty) {
      _cachedPassword = gitConfig.encryptionPassword;
      return _cachedPassword;
    }
    if (pref != null) {
      var pass = pref!.getString(prefCachedPassword);
      if (pass != null && pass.isNotEmpty) {
        _cachedPassword = pass;
        return _cachedPassword;
      }
    }
    return null;
  }

  Future<List<int>> encryptForFolder(
    List<int> plainBytes,
    NotesFolderFS folder, {
    GitConfig? gitConfig,
  }) async {
    final root = folder.encryptionRoot;
    if (root == null) return plainBytes;

    final marker = readMarker(root.fullFolderPath);
    if (marker == null) return plainBytes;

    final password = await resolvePassword(gitConfig: gitConfig);
    if (password == null) {
      throw FolderLockedException(folder.folderPath);
    }

    final key = await deriveKey(password, marker.salt);
    return await encryptBytes(plainBytes, key);
  }

  Future<List<int>> decryptForFolder(
    List<int> cipherBytes,
    NotesFolderFS folder, {
    GitConfig? gitConfig,
  }) async {
    final root = folder.encryptionRoot;
    if (root == null) return cipherBytes;

    final marker = readMarker(root.fullFolderPath);
    if (marker == null) return cipherBytes;

    final password = await resolvePassword(gitConfig: gitConfig);
    if (password == null) {
      throw FolderLockedException(folder.folderPath);
    }

    final key = await deriveKey(password, marker.salt);
    return await decryptBytes(cipherBytes, key);
  }
}
