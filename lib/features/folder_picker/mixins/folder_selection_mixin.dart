import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../core/platform/android_root_storage.dart';
import '../android_root_folder_picker_page.dart';
import '../models/folder_pick_result.dart';

/// Folder selection and Android permission dialogs tied to a page lifecycle.
mixin FolderSelectionMixin<T extends StatefulWidget> on State<T> {
  Future<FolderPickResult> selectImageFolder() async {
    if (Platform.isAndroid) {
      return _selectAndroidRootFolder();
    }

    final directoryPath = await FilePicker.getDirectoryPath(
      dialogTitle: '选择图片文件夹',
    );
    return FolderPickResult(path: directoryPath);
  }

  Future<FolderPickResult> _selectAndroidRootFolder() async {
    final hasAccess = await AndroidRootStorage.hasRootStorageAccess();

    if (!hasAccess) {
      if (!mounted) {
        return const FolderPickResult();
      }

      final shouldOpenSettings = await showDialog<bool>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('需要根目录访问权限'),
            content: const Text('请在系统设置中允许所有文件访问权限，开启后返回应用再选择文件夹。'),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('去开启'),
              ),
            ],
          );
        },
      );

      if (shouldOpenSettings == true) {
        await AndroidRootStorage.requestRootStorageAccess();
      }

      return const FolderPickResult(
        message: '请开启所有文件访问权限后再次选择文件夹',
      );
    }

    final rootPath =
        await AndroidRootStorage.getStorageRoot() ?? '/storage/emulated/0';

    if (!mounted) {
      return const FolderPickResult();
    }

    final directoryPath = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        builder: (_) => AndroidRootFolderPickerPage(rootPath: rootPath),
      ),
    );

    return FolderPickResult(path: directoryPath);
  }
}
