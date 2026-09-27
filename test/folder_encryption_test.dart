/*
 * SPDX-FileCopyrightText: 2024 GitJournal Contributors
 *
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

import 'dart:convert';
import 'package:gitjournal/core/encryption/folder_encryption_service.dart';
import 'package:gitjournal/core/file/file.dart';
import 'package:gitjournal/core/file/file_storage.dart';
import 'package:gitjournal/core/folder/flattened_notes_folder.dart';
import 'package:gitjournal/core/folder/notes_folder_config.dart';
import 'package:gitjournal/core/folder/notes_folder_fs.dart';
import 'package:gitjournal/core/note_storage.dart';
import 'package:gitjournal/settings/git_config.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:test/test.dart';
import 'package:universal_io/io.dart' as io;

import 'lib.dart';

void main() {
  late String repoPath;
  late io.Directory tempDir;
  late NotesFolderConfig config;
  late FileStorage fileStorage;
  late SharedPreferences pref;
  late GitConfig gitConfig;

  final gitDt = DateTime.now();

  setUpAll(() async {
    tempDir = await io.Directory.systemTemp.createTemp('__folder_encryption_test__');
    repoPath = tempDir.path + p.separator;

    SharedPreferences.setMockInitialValues({});
    pref = await SharedPreferences.getInstance();
    config = NotesFolderConfig('', pref);
    gitConfig = GitConfig('default', pref);
    fileStorage = await FileStorage.fake(repoPath);

    FolderEncryptionService.instance.init(preferences: pref);

    await gjSetupAllTests();
  });

  tearDownAll(() async {
    tempDir.deleteSync(recursive: true);
  });

  test('Key derivation and AES-GCM encryption/decryption round-trip', () async {
    final service = FolderEncryptionService.instance;
    final salt = List<int>.generate(16, (i) => i);
    final key = await service.deriveKey('superSecretPassword', salt);

    final plaintext = utf8.encode('Top secret notes data here!');
    final encrypted = await service.encryptBytes(plaintext, key);

    expect(FolderEncryptionService.isEncryptedBytes(encrypted), isTrue);
    expect(FolderEncryptionService.isEncryptedBytes(plaintext), isFalse);

    final decrypted = await service.decryptBytes(encrypted, key);
    expect(utf8.decode(decrypted), equals('Top secret notes data here!'));

    // Wrong password / key must fail decryption
    final wrongKey = await service.deriveKey('wrongPassword', salt);
    expect(
      () => service.decryptBytes(encrypted, wrongKey),
      throwsA(anything),
    );
  });

  test('Marker file creation and password verification', () async {
    final service = FolderEncryptionService.instance;
    final folderDir = io.Directory(p.join(repoPath, 'vault'));
    await folderDir.create(recursive: true);

    final marker = await service.createMarker(folderDir.path, 'MasterKey99');
    expect(marker.salt.length, equals(16));

    final markerFile = io.File(p.join(folderDir.path, FolderEncryptionService.markerFileName));
    expect(markerFile.existsSync(), isTrue);

    final isValid = await service.verifyPassword(folderDir.path, 'MasterKey99');
    expect(isValid, isTrue);

    final isInvalid = await service.verifyPassword(folderDir.path, 'WrongKey');
    expect(isInvalid, isFalse);
  });

  test('90-day persistence of unlocked state in SharedPreferences', () async {
    final service = FolderEncryptionService.instance;
    await service.lock(preferences: pref);
    expect(service.isUnlocked(), isFalse);

    await service.markUnlocked('MasterKey99', preferences: pref);
    expect(service.isUnlocked(), isTrue);
    expect(service.cachedPassword, equals('MasterKey99'));

    final storedExpiry = pref.getString(FolderEncryptionService.prefUnlockedUntil);
    expect(storedExpiry, isNotNull);
    final expiryDate = DateTime.parse(storedExpiry!);
    final daysUntilExpiry = expiryDate.difference(DateTime.now()).inDays;
    expect(daysUntilExpiry, inInclusiveRange(89, 90));

    // Lock resets state and removes keys from preferences
    await service.lock(preferences: pref);
    expect(service.isUnlocked(), isFalse);
    expect(service.cachedPassword, isNull);
    expect(pref.getString(FolderEncryptionService.prefUnlockedUntil), isNull);
  });

  test('Simulated app restart preserves unlocked state for 90 days', () async {
    final service = FolderEncryptionService.instance;
    await service.markUnlocked('RestartSecretPass', preferences: pref);
    expect(service.isUnlocked(), isTrue);

    // Simulate app restart by instantiating a fresh service or re-initing with same pref
    final restartedService = FolderEncryptionService();
    expect(restartedService.isUnlocked(), isFalse); // Before init

    restartedService.init(preferences: pref);
    expect(restartedService.isUnlocked(), isTrue); // Restored from SharedPreferences
    expect(await restartedService.resolvePassword(), equals('RestartSecretPass'));

    // Test expiry: if 91 days pass
    final pastDate = DateTime.now().subtract(const Duration(days: 1));
    await pref.setString(FolderEncryptionService.prefUnlockedUntil, pastDate.toIso8601String());

    final expiredService = FolderEncryptionService();
    expiredService.init(preferences: pref);
    expect(expiredService.isUnlocked(), isFalse);
    expect(await expiredService.resolvePassword(), isNull);
  });

  test('Folder conversion, disk encryption, and note loading/saving', () async {
    final service = FolderEncryptionService.instance;
    final folderPath = p.join(repoPath, 'confidential');
    final confidentialDir = io.Directory(folderPath);
    await confidentialDir.create(recursive: true);

    // Create plain notes
    final note1Path = p.join(folderPath, 'note1.md');
    await io.File(note1Path).writeAsString("""---
title: Secret Plan
---

Confidential operational roadmap.
""");

    final note2Path = p.join(folderPath, 'note2.txt');
    await io.File(note2Path).writeAsString("Raw confidential note without frontmatter");

    final rootFolder = NotesFolderFS.root(config, fileStorage);
    await rootFolder.loadRecursively();
    final confidentialFolder = rootFolder.subFoldersFS.firstWhere((f) => f.folderPath == 'confidential');

    expect(confidentialFolder.isEncrypted, isFalse);

    // Convert folder to encrypted
    await service.convertFolderToEncrypted(
      confidentialFolder,
      'VaultPass123',
      gitConfig: gitConfig,
      preferences: pref,
    );

    expect(confidentialFolder.isEncrypted, isTrue);
    expect(confidentialFolder.isUnlocked, isTrue);
    expect(gitConfig.encryptionPassword, equals('VaultPass123'));

    // Check files on disk are ciphertext
    final note1Bytes = await io.File(note1Path).readAsBytes();
    final note2Bytes = await io.File(note2Path).readAsBytes();
    expect(FolderEncryptionService.isEncryptedBytes(note1Bytes), isTrue);
    expect(FolderEncryptionService.isEncryptedBytes(note2Bytes), isTrue);

    // Load note via NoteStorage: should be decrypted transparently
    final file1 = File.short("confidential/note1.md", repoPath, gitDt);
    final loadedNote1 = await NoteStorage.load(file1, confidentialFolder);
    expect(loadedNote1.title, equals('note1'));
    expect(loadedNote1.body.contains('Confidential operational roadmap.'), isTrue);

    final file2 = File.short("confidential/note2.txt", repoPath, gitDt);
    final loadedNote2 = await NoteStorage.load(file2, confidentialFolder);
    expect(loadedNote2.body, equals('Raw confidential note without frontmatter'));

    // Edit and save note: on disk it must remain encrypted
    final modifiedNote = loadedNote1.copyWith(body: 'Updated secret roadmap').resetOid();
    final savedNote = await NoteStorage.save(modifiedNote);
    expect(savedNote.oid, isNotEmpty);

    final diskBytesAfterSave = await io.File(note1Path).readAsBytes();
    expect(FolderEncryptionService.isEncryptedBytes(diskBytesAfterSave), isTrue);

    // Reload note from disk to ensure it decrypts updated content
    final reloadedNote = await NoteStorage.load(file1, confidentialFolder);
    expect(reloadedNote.body.trim(), equals('Updated secret roadmap'));
  });

  test('Locked folder hides notes and FlattenedNotesFolder excludes locked notes', () async {
    final service = FolderEncryptionService.instance;
    final rootFolder = NotesFolderFS.root(config, fileStorage);
    final confidentialFolder = NotesFolderFS(rootFolder, 'confidential', config);
    expect(confidentialFolder.isEncrypted, isTrue);

    // Lock folder
    await service.lock(preferences: pref);
    expect(confidentialFolder.isUnlocked, isFalse);
    expect(confidentialFolder.hasNotes, isFalse);
    expect(confidentialFolder.notes.isEmpty, isTrue);

    // Loading locked note directly throws FolderLockedException
    final file1 = File.short("confidential/note1.md", repoPath, gitDt);
    expect(
      () => NoteStorage.load(file1, confidentialFolder),
      throwsA(isA<FolderLockedException>()),
    );

    // FlattenedNotesFolder excludes locked folder
    final flattened = FlattenedNotesFolder(confidentialFolder, title: 'Confidential Notes');
    expect(flattened.notes.isEmpty, isTrue);

    // Unlock folder with password
    final unlocked = await service.unlockWithPassword(
      confidentialFolder,
      'VaultPass123',
      preferences: pref,
    );
    expect(unlocked, isTrue);
    expect(confidentialFolder.isUnlocked, isTrue);

    // Now note loads and decrypts successfully
    final loadedNote = await NoteStorage.load(file1, confidentialFolder);
    expect(loadedNote.title, equals('note1'));
    expect(loadedNote.body.trim(), equals('Updated secret roadmap'));
  });
}
