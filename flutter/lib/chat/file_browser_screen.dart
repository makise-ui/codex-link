import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter_highlight/themes/atom-one-dark.dart';
import 'package:provider/provider.dart';

import '../app_controller.dart';
import '../protocol/bridge_messages.dart';
import '../theme/app_theme.dart';

class FileBrowserScreen extends StatefulWidget {
  const FileBrowserScreen({super.key, this.initialPath});

  final String? initialPath;

  @override
  State<FileBrowserScreen> createState() => _FileBrowserScreenState();
}

class _FileBrowserScreenState extends State<FileBrowserScreen> {
  final _editorController = TextEditingController();
  String? _editorPath;
  bool _editing = false;
  bool _dirty = false;
  bool _mobileEditorVisible = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final controller = context.read<AppController>();
      final initialPath = widget.initialPath?.trim();
      if (initialPath != null && initialPath.isNotEmpty) {
        controller.readAppFile(initialPath);
        controller.listAppDirectory(_parentPath(initialPath));
        setState(() => _mobileEditorVisible = true);
      } else {
        controller.listAppDirectory();
      }
    });
  }

  @override
  void dispose() {
    _editorController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    final file = controller.appPreviewFile;
    _syncEditor(file);
    final canWrite = controller.isConnected && !controller.appFsBusy;
    return AnimatedChatGptBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('Workspace explorer'),
          actions: [
            if (file?.text != null)
              IconButton(
                tooltip: _editing ? 'Preview' : 'Edit file',
                onPressed: () => setState(() => _editing = !_editing),
                icon: Icon(
                  _editing ? Icons.visibility_rounded : Icons.edit_rounded,
                ),
              ),
            if (_editing && file?.text != null)
              IconButton(
                tooltip: 'Save file',
                onPressed: canWrite && _dirty ? () => _save(controller) : null,
                icon: const Icon(Icons.save_rounded),
              ),
            IconButton(
              tooltip: 'New folder',
              onPressed: canWrite
                  ? () => _showCreateFolderDialog(context, controller)
                  : null,
              icon: const Icon(Icons.create_new_folder_rounded),
            ),
            IconButton(
              tooltip: 'Upload file',
              onPressed: canWrite ? () => _uploadFiles(controller) : null,
              icon: const Icon(Icons.upload_file_rounded),
            ),
            IconButton(
              tooltip: 'Refresh',
              onPressed: controller.isConnected
                  ? () => controller.listAppDirectory(controller.appFilePath)
                  : null,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 760;
              if (wide) {
                return Row(
                  children: [
                    SizedBox(
                      width: 320,
                      child: _ExplorerPane(
                        controller: controller,
                        fill: true,
                        onOpenFile: controller.readAppFile,
                      ),
                    ),
                    VerticalDivider(
                      width: 1,
                      color: codexDimColor(context).withValues(alpha: 0.14),
                    ),
                    Expanded(
                      child: _PreviewPane(
                        file: file,
                        fill: true,
                        editing: _editing,
                        dirty: _dirty,
                        editorController: _editorController,
                        onEditChanged: () => setState(() => _dirty = true),
                        onUse: file == null
                            ? null
                            : () => Navigator.of(context).pop(file.path),
                        onSave: canWrite && _dirty
                            ? () => _save(controller)
                            : null,
                      ),
                    ),
                  ],
                );
              }
              return AnimatedSwitcher(
                duration: AppMotion.quick,
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeOutCubic,
                child: _mobileEditorVisible && file != null
                    ? Padding(
                        key: const ValueKey('mobile-file-editor'),
                        padding: const EdgeInsets.fromLTRB(
                          AppSpacing.md,
                          AppSpacing.sm,
                          AppSpacing.md,
                          AppSpacing.lg,
                        ),
                        child: Column(
                          children: [
                            _MobileEditorHeader(
                              file: file,
                              dirty: _dirty,
                              onBack: _showMobileExplorer,
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            Expanded(
                              child: _PreviewPane(
                                file: file,
                                fill: true,
                                editing: _editing,
                                dirty: _dirty,
                                editorController: _editorController,
                                onEditChanged: () =>
                                    setState(() => _dirty = true),
                                onUse: () =>
                                    Navigator.of(context).pop(file.path),
                                onSave: canWrite && _dirty
                                    ? () => _save(controller)
                                    : null,
                              ),
                            ),
                          ],
                        ),
                      )
                    : Padding(
                        key: const ValueKey('mobile-file-explorer'),
                        padding: const EdgeInsets.fromLTRB(
                          AppSpacing.md,
                          AppSpacing.sm,
                          AppSpacing.md,
                          AppSpacing.lg,
                        ),
                        child: _ExplorerPane(
                          controller: controller,
                          fill: true,
                          onOpenFile: (path) {
                            controller.readAppFile(path);
                            setState(() => _mobileEditorVisible = true);
                          },
                        ),
                      ),
              );
            },
          ),
        ),
      ),
    );
  }

  void _showMobileExplorer() {
    setState(() => _mobileEditorVisible = false);
  }

  void _syncEditor(AppFsFileInfo? file) {
    if (file == null) return;
    if (_editorPath == file.path) return;
    _editorPath = file.path;
    _editing = false;
    _dirty = false;
    _editorController.text = file.text ?? '';
  }

  void _save(AppController controller) {
    final path = _editorPath;
    if (path == null || path.trim().isEmpty) return;
    controller.writeAppFile(
      path,
      base64Encode(utf8.encode(_editorController.text)),
    );
    setState(() {
      _dirty = false;
      _editing = false;
    });
  }

  Future<void> _uploadFiles(AppController controller) async {
    final result = await FilePicker.pickFiles(
      allowMultiple: true,
      withData: true,
      type: FileType.any,
    );
    if (!mounted || result == null) return;
    final directory = controller.appFilePath;
    for (final file in result.files) {
      final bytes = file.bytes;
      if (bytes == null || bytes.isEmpty) continue;
      if (bytes.length > 6 * 1024 * 1024) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${file.name} is too large to upload.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        continue;
      }
      controller.writeAppFile(
        _joinPath(directory, _safeUploadName(file.name)),
        base64Encode(bytes),
      );
    }
  }
}

class _MobileEditorHeader extends StatelessWidget {
  const _MobileEditorHeader({
    required this.file,
    required this.dirty,
    required this.onBack,
  });

  final AppFsFileInfo file;
  final bool dirty;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        ChatGptCircleButton(
          icon: Icons.arrow_back_rounded,
          size: 38,
          onPressed: onBack,
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                dirty ? '${file.name} *' : file.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Text(
                _breadcrumbForPath(file.path),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: codexDimColor(context),
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ExplorerPane extends StatelessWidget {
  const _ExplorerPane({
    required this.controller,
    required this.fill,
    required this.onOpenFile,
  });

  final AppController controller;
  final bool fill;
  final ValueChanged<String> onOpenFile;

  @override
  Widget build(BuildContext context) {
    final currentPath = controller.appFilePath;
    final entries = _sortedEntries(controller.appFileEntries);
    final content = Column(
      children: [
        _PathBar(
          path: currentPath,
          busy: controller.appFsBusy,
          status: controller.appFsStatusText,
          onUp: currentPath.trim().isEmpty
              ? null
              : () => controller.listAppDirectory(_parentPath(currentPath)),
        ),
        const SizedBox(height: AppSpacing.sm),
        fill
            ? Expanded(
                child: _EntriesList(
                  entries: entries,
                  activePath: controller.appPreviewFile?.path,
                  onOpenDirectory: controller.listAppDirectory,
                  onOpenFile: onOpenFile,
                  onUseFile: (path) => Navigator.of(context).pop(path),
                  fill: true,
                ),
              )
            : _EntriesList(
                entries: entries,
                activePath: controller.appPreviewFile?.path,
                onOpenDirectory: controller.listAppDirectory,
                onOpenFile: onOpenFile,
                onUseFile: (path) => Navigator.of(context).pop(path),
                fill: false,
              ),
      ],
    );
    return Padding(
      padding: EdgeInsets.all(fill ? AppSpacing.md : 0),
      child: GlassCard(
        padding: const EdgeInsets.all(AppSpacing.sm),
        radius: AppRadius.lg,
        color: codexPanelHighColor(context).withValues(alpha: 0.72),
        child: content,
      ),
    );
  }
}

class _PathBar extends StatelessWidget {
  const _PathBar({
    required this.path,
    required this.busy,
    required this.status,
    required this.onUp,
  });

  final String path;
  final bool busy;
  final String? status;
  final VoidCallback? onUp;

  @override
  Widget build(BuildContext context) {
    final label = path.trim().isEmpty ? 'Workspace root' : path;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            IconButton(
              tooltip: 'Parent folder',
              visualDensity: VisualDensity.compact,
              onPressed: onUp,
              icon: const Icon(Icons.arrow_upward_rounded),
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ],
        ),
        if (busy || status?.trim().isNotEmpty == true) ...[
          const SizedBox(height: AppSpacing.xs),
          if (busy)
            const LinearProgressIndicator(minHeight: 2)
          else
            Text(
              status!.trim(),
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: codexMutedColor(context)),
            ),
        ],
      ],
    );
  }
}

class _EntriesList extends StatelessWidget {
  const _EntriesList({
    required this.entries,
    required this.activePath,
    required this.onOpenDirectory,
    required this.onOpenFile,
    required this.onUseFile,
    required this.fill,
  });

  final List<AppFsEntryInfo> entries;
  final String? activePath;
  final ValueChanged<String> onOpenDirectory;
  final ValueChanged<String> onOpenFile;
  final ValueChanged<String> onUseFile;
  final bool fill;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Text(
            'No files in this folder.',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: codexMutedColor(context)),
          ),
        ),
      );
    }
    return ListView.separated(
      shrinkWrap: !fill,
      physics: fill ? null : const NeverScrollableScrollPhysics(),
      itemCount: entries.length,
      separatorBuilder: (_, _) => Divider(
        height: 1,
        color: codexDimColor(context).withValues(alpha: 0.12),
      ),
      itemBuilder: (context, index) {
        final entry = entries[index];
        final active = entry.path == activePath;
        return Material(
          color: active
              ? Theme.of(context).colorScheme.secondary.withValues(alpha: 0.10)
              : Colors.transparent,
          child: ListTile(
            key: ValueKey('file-browser-entry-${entry.path}'),
            dense: true,
            visualDensity: VisualDensity.compact,
            leading: Icon(
              entry.isDirectory ? Icons.folder_rounded : _iconForFile(entry),
              color: entry.isDirectory
                  ? Theme.of(context).colorScheme.secondary
                  : codexMutedColor(context),
              size: 18,
            ),
            title: Text(
              entry.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: codexTextColor(context),
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
            subtitle: Text(
              [
                entry.path,
                if (entry.sizeBytes != null) _formatBytes(entry.sizeBytes!),
              ].join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: codexDimColor(context),
                fontFamily: 'monospace',
                fontSize: 11,
              ),
            ),
            trailing: entry.isFile
                ? IconButton(
                    tooltip: 'Use in chat',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => onUseFile(entry.path),
                    icon: const Icon(Icons.alternate_email_rounded, size: 18),
                  )
                : null,
            onTap: () => entry.isDirectory
                ? onOpenDirectory(entry.path)
                : onOpenFile(entry.path),
          ),
        );
      },
    );
  }
}

class _PreviewPane extends StatelessWidget {
  const _PreviewPane({
    required this.file,
    required this.fill,
    required this.editing,
    required this.dirty,
    required this.editorController,
    required this.onEditChanged,
    required this.onUse,
    required this.onSave,
  });

  final AppFsFileInfo? file;
  final bool fill;
  final bool editing;
  final bool dirty;
  final TextEditingController editorController;
  final VoidCallback onEditChanged;
  final VoidCallback? onUse;
  final VoidCallback? onSave;

  @override
  Widget build(BuildContext context) {
    final file = this.file;
    final content = file == null
        ? _EmptyPreview(fill: fill)
        : _FilePreview(
            file: file,
            fill: fill,
            editing: editing,
            dirty: dirty,
            editorController: editorController,
            onEditChanged: onEditChanged,
            onUse: onUse,
            onSave: onSave,
          );
    return Padding(
      padding: EdgeInsets.all(fill ? AppSpacing.md : 0),
      child: content,
    );
  }
}

class _EmptyPreview extends StatelessWidget {
  const _EmptyPreview({required this.fill});

  final bool fill;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(AppSpacing.xl),
      radius: AppRadius.lg,
      color: codexPanelHighColor(context).withValues(alpha: 0.62),
      child: SizedBox(
        height: fill ? null : 220,
        child: Center(
          child: Text(
            'Select a file to preview or edit.',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: codexMutedColor(context)),
          ),
        ),
      ),
    );
  }
}

class _FilePreview extends StatelessWidget {
  const _FilePreview({
    required this.file,
    required this.fill,
    required this.editing,
    required this.dirty,
    required this.editorController,
    required this.onEditChanged,
    required this.onUse,
    required this.onSave,
  });

  final AppFsFileInfo file;
  final bool fill;
  final bool editing;
  final bool dirty;
  final TextEditingController editorController;
  final VoidCallback onEditChanged;
  final VoidCallback? onUse;
  final VoidCallback? onSave;

  @override
  Widget build(BuildContext context) {
    final text = file.text;
    final body = text == null
        ? _BinaryPreview(file: file)
        : editing
        ? _EditorView(controller: editorController, onChanged: onEditChanged)
        : _SyntaxPreview(file: file);
    return GlassCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      radius: AppRadius.lg,
      color: codexPanelHighColor(context).withValues(alpha: 0.68),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_previewIcon(file), color: codexMutedColor(context)),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      file.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(
                      file.path,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: codexDimColor(context),
                        fontFamily: 'monospace',
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              if (dirty)
                Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.xs),
                  child: SoftPill(
                    label: 'edited',
                    color: Theme.of(context).colorScheme.secondary,
                  ),
                ),
              if (text != null)
                TextButton.icon(
                  onPressed: onSave,
                  icon: const Icon(Icons.save_rounded, size: 17),
                  label: const Text('Save'),
                ),
              TextButton.icon(
                onPressed: onUse,
                icon: const Icon(Icons.alternate_email_rounded, size: 17),
                label: const Text('Use'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            [
              _formatBytes(file.sizeBytes),
              if (file.mimeType?.trim().isNotEmpty == true) file.mimeType,
            ].join(' · '),
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: codexMutedColor(context)),
          ),
          const SizedBox(height: AppSpacing.sm),
          if (fill)
            Expanded(child: body)
          else
            SizedBox(height: 420, child: body),
        ],
      ),
    );
  }
}

class _SyntaxPreview extends StatelessWidget {
  const _SyntaxPreview({required this.file});

  final AppFsFileInfo file;

  @override
  Widget build(BuildContext context) {
    final language = _languageForPath(file.path);
    if (language == null) {
      return _PlainTextPreview(text: file.text ?? '');
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: codexComposerColor(context).withValues(alpha: 0.72),
          border: Border.all(
            color: codexDimColor(context).withValues(alpha: 0.14),
          ),
        ),
        child: SingleChildScrollView(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: HighlightView(
              file.text ?? '',
              language: language,
              theme: atomOneDarkTheme,
              padding: const EdgeInsets.all(AppSpacing.md),
              textStyle: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                height: 1.38,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PlainTextPreview extends StatelessWidget {
  const _PlainTextPreview({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: codexComposerColor(context).withValues(alpha: 0.72),
          border: Border.all(
            color: codexDimColor(context).withValues(alpha: 0.14),
          ),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: SelectableText(
            text,
            style: TextStyle(
              color: codexTextColor(context),
              fontFamily: 'monospace',
              fontSize: 12,
              height: 1.38,
            ),
          ),
        ),
      ),
    );
  }
}

class _EditorView extends StatelessWidget {
  const _EditorView({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: codexComposerColor(context).withValues(alpha: 0.76),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: Theme.of(
            context,
          ).colorScheme.secondary.withValues(alpha: 0.22),
        ),
      ),
      child: TextField(
        key: const ValueKey('file-editor-input'),
        controller: controller,
        expands: true,
        minLines: null,
        maxLines: null,
        keyboardType: TextInputType.multiline,
        style: TextStyle(
          color: codexTextColor(context),
          fontFamily: 'monospace',
          fontSize: 12,
          height: 1.38,
        ),
        decoration: const InputDecoration(
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          filled: false,
          contentPadding: EdgeInsets.all(AppSpacing.md),
        ),
        onChanged: (_) => onChanged(),
      ),
    );
  }
}

class _BinaryPreview extends StatelessWidget {
  const _BinaryPreview({required this.file});

  final AppFsFileInfo file;

  @override
  Widget build(BuildContext context) {
    final isImage = file.mimeType?.startsWith('image/') == true;
    final data = file.dataBase64;
    if (isImage && data != null && data.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: codexComposerColor(context),
            border: Border.all(
              color: codexDimColor(context).withValues(alpha: 0.14),
            ),
          ),
          child: Center(
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 5,
              child: Image.memory(base64Decode(data), fit: BoxFit.contain),
            ),
          ),
        ),
      );
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        color: codexComposerColor(context).withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: codexDimColor(context).withValues(alpha: 0.14),
        ),
      ),
      child: Center(
        child: Text(
          'Binary preview is not available.',
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: codexMutedColor(context)),
        ),
      ),
    );
  }
}

Future<void> _showCreateFolderDialog(
  BuildContext context,
  AppController controller,
) async {
  final name = await showDialog<String>(
    context: context,
    builder: (context) => const _CreateFolderDialog(),
  );
  if (name == null || name.trim().isEmpty) return;
  controller.createAppDirectory(
    _joinPath(controller.appFilePath, _safeUploadName(name.trim())),
  );
}

class _CreateFolderDialog extends StatefulWidget {
  const _CreateFolderDialog();

  @override
  State<_CreateFolderDialog> createState() => _CreateFolderDialogState();
}

class _CreateFolderDialogState extends State<_CreateFolderDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() => Navigator.of(context).pop(_controller.text);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New folder'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(
          prefixIcon: Icon(Icons.create_new_folder_rounded),
          labelText: 'Folder name',
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Create')),
      ],
    );
  }
}

List<AppFsEntryInfo> _sortedEntries(List<AppFsEntryInfo> entries) {
  return List<AppFsEntryInfo>.from(entries)..sort((left, right) {
    final typeOrder = (right.isDirectory ? 1 : 0) - (left.isDirectory ? 1 : 0);
    if (typeOrder != 0) return typeOrder;
    return left.name.toLowerCase().compareTo(right.name.toLowerCase());
  });
}

IconData _iconForFile(AppFsEntryInfo entry) {
  final mime = entry.mimeType ?? '';
  if (mime.startsWith('image/')) return Icons.image_rounded;
  if (mime.contains('json') || _languageForPath(entry.name) != null) {
    return Icons.code_rounded;
  }
  return Icons.insert_drive_file_outlined;
}

IconData _previewIcon(AppFsFileInfo file) {
  final mime = file.mimeType ?? '';
  if (mime.startsWith('image/')) return Icons.image_rounded;
  if (file.text != null) return Icons.code_rounded;
  return Icons.insert_drive_file_outlined;
}

String? _languageForPath(String path) {
  final ext = path.split('.').last.toLowerCase();
  return switch (ext) {
    'dart' => 'dart',
    'js' || 'mjs' || 'cjs' => 'javascript',
    'ts' => 'typescript',
    'jsx' => 'javascript',
    'tsx' => 'typescript',
    'json' => 'json',
    'yaml' || 'yml' => 'yaml',
    'md' => 'markdown',
    'html' => 'xml',
    'css' => 'css',
    'py' => 'python',
    'sh' || 'zsh' || 'bash' => 'bash',
    'java' => 'java',
    'kt' => 'kotlin',
    'swift' => 'swift',
    'rs' => 'rust',
    'go' => 'go',
    'rb' => 'ruby',
    'php' => 'php',
    'xml' => 'xml',
    _ => null,
  };
}

String _parentPath(String path) {
  final parts = path
      .split('/')
      .where((part) => part.trim().isNotEmpty)
      .toList(growable: true);
  if (parts.isEmpty) return '';
  parts.removeLast();
  return parts.join('/');
}

String _breadcrumbForPath(String path) {
  final parent = _parentPath(path);
  if (parent.isEmpty) return 'Workspace root';
  return parent.split('/').join(' / ');
}

String _joinPath(String directory, String name) {
  final cleanDirectory = directory.trim().replaceAll(RegExp(r'/+$'), '');
  final cleanName = name.trim().replaceAll(RegExp(r'^/+'), '');
  return cleanDirectory.isEmpty ? cleanName : '$cleanDirectory/$cleanName';
}

String _safeUploadName(String name) {
  final cleaned = name.trim().replaceAll(RegExp(r'[\\/]'), '_');
  return cleaned.isEmpty ? 'untitled' : cleaned;
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '${bytes}B';
  final kib = bytes / 1024;
  if (kib < 1024) return '${kib.toStringAsFixed(kib < 10 ? 1 : 0)}KB';
  final mib = kib / 1024;
  return '${mib.toStringAsFixed(mib < 10 ? 1 : 0)}MB';
}
