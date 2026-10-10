import 'package:flutter/material.dart';

import '../../../core/utils/product_icons.dart';

/// Shows a modal dialog letting the user pick a single **emoji** to represent
/// a product. Returns the selected emoji string, or null if the user cancels.
/// An empty-string result means "clear/none" (fall back to auto/default).
Future<String?> showProductIconPicker(
  BuildContext context, {
  String? selected,
}) {
  return showDialog<String?>(
    context: context,
    builder: (_) => _EmojiPickerDialog(selected: selected),
  );
}

class _EmojiPickerDialog extends StatefulWidget {
  const _EmojiPickerDialog({this.selected});

  final String? selected;

  @override
  State<_EmojiPickerDialog> createState() => _EmojiPickerDialogState();
}

class _EmojiPickerDialogState extends State<_EmojiPickerDialog> {
  late String? _selected = widget.selected;
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final q = _query.trim();
    // When searching, flatten all emojis and keep those whose section title
    // contains the query, or just show everything if the query is empty.
    final sections = <String, List<String>>{};
    ProductIcons.catalogByCategory.forEach((title, emojis) {
      if (q.isEmpty || title.toLowerCase().contains(q.toLowerCase())) {
        sections[title] = emojis;
      }
    });

    return AlertDialog(
      title: const Text('Choose an emoji'),
      content: SizedBox(
        width: 380,
        height: 440,
        child: Column(
          children: [
            TextField(
              autofocus: false,
              decoration: const InputDecoration(
                hintText: 'Search categories (e.g. fruit, cleaning)',
                prefixIcon: Icon(Icons.search),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: sections.isEmpty
                  ? const Center(child: Text('No matches'))
                  : ListView(
                      children: [
                        for (final entry in sections.entries) ...[
                          Padding(
                            padding:
                                const EdgeInsets.symmetric(vertical: 6),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                entry.key.toUpperCase(),
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.grey.shade600,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                          ),
                          GridView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 6,
                              mainAxisSpacing: 8,
                              crossAxisSpacing: 8,
                            ),
                            itemCount: entry.value.length,
                            itemBuilder: (context, i) {
                              final emoji = entry.value[i];
                              final isSelected = emoji == _selected;
                              return InkWell(
                                borderRadius: BorderRadius.circular(12),
                                onTap: () =>
                                    setState(() => _selected = emoji),
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? const Color(0xFFEAF1E7)
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: isSelected
                                          ? const Color(0xFF2E7D32)
                                          : Colors.grey.shade300,
                                      width: isSelected ? 2 : 1,
                                    ),
                                  ),
                                  alignment: Alignment.center,
                                  child: Text(
                                    emoji,
                                    style: const TextStyle(fontSize: 24),
                                  ),
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: 8),
                        ],
                      ],
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        // Clear the selection (fall back to auto/default emoji).
        TextButton(
          onPressed: () => Navigator.pop(context, ''),
          child: const Text('Clear'),
        ),
        FilledButton(
          onPressed: _selected == null
              ? null
              : () => Navigator.pop(context, _selected),
          child: const Text('Select'),
        ),
      ],
    );
  }
}