import 'package:flutter/material.dart';

class EmptyImageRegion extends StatelessWidget {
  const EmptyImageRegion({
    super.key,
    required this.message,
    required this.folderName,
    required this.onPickFolder,
  });

  final String? message;
  final String folderName;
  final VoidCallback onPickFolder;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return InkWell(
      onTap: onPickFolder,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                Icons.add_photo_alternate_outlined,
                size: 40,
                color: colorScheme.primary,
              ),
              const SizedBox(height: 10),
              Text(
                '选择文件夹',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Colors.white,
                    ),
              ),
              if (message != null) ...<Widget>[
                const SizedBox(height: 8),
                Text(
                  message!,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: const Color(0xFFE4E4E7),
                      ),
                ),
              ] else if (folderName.isNotEmpty) ...<Widget>[
                const SizedBox(height: 8),
                Text(
                  folderName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: const Color(0xFFA1A1AA),
                      ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
