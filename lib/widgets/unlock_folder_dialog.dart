/*
 * SPDX-FileCopyrightText: 2024 GitJournal Contributors
 *
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

import 'package:flutter/material.dart';
import 'package:gitjournal/core/encryption/folder_encryption_service.dart';
import 'package:gitjournal/core/folder/notes_folder_fs.dart';
import 'package:gitjournal/repository.dart';
import 'package:provider/provider.dart';

class UnlockFolderDialog extends StatefulWidget {
  final NotesFolderFS folder;

  const UnlockFolderDialog({
    super.key,
    required this.folder,
  });

  @override
  _UnlockFolderDialogState createState() => _UnlockFolderDialogState();
}

class _UnlockFolderDialogState extends State<UnlockFolderDialog> {
  final _passwordController = TextEditingController();
  bool _obscureText = true;
  String? _errorMessage;
  bool _isChecking = false;

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final password = _passwordController.text;
    if (password.isEmpty) {
      setState(() {
        _errorMessage = "Password cannot be empty";
      });
      return;
    }

    setState(() {
      _isChecking = true;
      _errorMessage = null;
    });

    var repo = context.read<GitJournalRepo>();
    var success = await FolderEncryptionService.instance.unlockWithPassword(
      widget.folder,
      password,
      gitConfig: repo.gitConfig,
    );

    if (!mounted) return;

    if (success) {
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _isChecking = false;
        _errorMessage = "Incorrect password. Please try again.";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final folderName =
        widget.folder.name.isEmpty ? "Root Folder" : widget.folder.name;

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.lock, color: Colors.amber),
          const SizedBox(width: 8),
          Expanded(child: Text("Unlock '$folderName'")),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "This folder is encrypted. Enter the encryption password to unlock it for 90 days.",
            style: TextStyle(fontSize: 14),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _passwordController,
            obscureText: _obscureText,
            autofocus: true,
            enabled: !_isChecking,
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              labelText: "Password",
              errorText: _errorMessage,
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureText ? Icons.visibility : Icons.visibility_off,
                ),
                onPressed: () {
                  setState(() {
                    _obscureText = !_obscureText;
                  });
                },
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed:
              _isChecking ? null : () => Navigator.of(context).pop(false),
          child: const Text("Cancel"),
        ),
        ElevatedButton(
          onPressed: _isChecking ? null : _submit,
          child: _isChecking
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text("Unlock"),
        ),
      ],
    );
  }
}
