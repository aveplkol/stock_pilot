/// A comprehensive catalog of product **emojis** that users can pick from to
/// represent an inventory item. We use emojis (plain strings) rather than
/// Material `IconData` so products display colourful, instantly-recognisable
/// glyphs (🥛 🍞 📦) instead of monochrome line icons.
///
/// The catalog is organised by category so the picker can show grouped tabs,
/// and [autoEmojiFor] provides smart auto-assignment from a product's
/// name/category when the user hasn't explicitly chosen one.
class ProductIcons {
  ProductIcons._();

  /// Default emoji used when nothing matches.
  static const String fallback = '📦';

  /// Emojis grouped by category. Keys are human-readable section titles used
  /// by the picker; values are the emojis offered in that section.
  static const Map<String, List<String>> catalogByCategory = {
    'Grocery & Staples': [
      '🥛', '🍞', '🥚', '🍚', '🌾', '🫓', '🥖', '🥐', '🧈', '🧀',
      '🫗', '🧂', '🍯', '🥜', '🫘', '🌽', '🥣',
    ],
    'Fruits': [
      '🍎', '🍏', '🍌', '🍊', '🍋', '🍉', '🍇', '🍓', '🫐', '🍍',
      '🥭', '🍑', '🍒', '🥝', '🥥', '🍈', '🍐',
    ],
    'Vegetables': [
      '🥦', '🥕', '🧄', '🧅', '🥔', '🍅', '🥒', '🌶️', '🫑', '🍆',
      '🥬', '🥗', '🫛', '🍄', '🫚',
    ],
    'Beverages': [
      '☕', '🍵', '🧃', '🧋', '🥤', '🧉', '🍶', '🍷', '🍺', '🍻',
      '🥂', '🍸', '🫖', '🧊',
    ],
    'Meat & Seafood': [
      '🍗', '🍖', '🥩', '🥓', '🐟', '🐠', '🦐', '🦞', '🦀', '🦑',
      '🍤', '🥚',
    ],
    'Snacks & Sweets': [
      '🍪', '🍩', '🍰', '🎂', '🧁', '🍫', '🍬', '🍭', '🍿', '🥨',
      '🍡', '🍮', '🍧', '🍨', '🍦', '🥮',
    ],
    'Prepared Food': [
      '🍕', '🍔', '🌭', '🥪', '🌮', '🌯', '🥙', '🍝', '🍜', '🍲',
      '🍱', '🍛', '🍟', '🥘',
    ],
    'Household': [
      '🏠', '🧺', '🧻', '🧼', '🧽', '🧴', '🪣', '🧹', '🪥', '🧯',
      '🕯️', '💡', '🔋',
    ],
    'Cleaning': [
      '🧹', '🧽', '🧼', '🧴', '🪣', '🧺', '♻️', '🚰', '🫧',
    ],
    'Health & Medicine': [
      '💊', '💉', '🩹', '🩺', '🌡️', '🧬', '🩻', '🫙',
    ],
    'Baby & Kids': [
      '🍼', '👶', '🧸', '🧷',
    ],
    'Pet': [
      '🐕', '🐈', '🐾', '🦴', '🐦', '🐠',
    ],
    'Stationery': [
      '✏️', '🖊️', '📝', '📚', '📖', '📒', '📎', '✂️', '📐', '🖍️',
    ],
    'Electronics': [
      '💻', '📱', '⌚', '🖥️', '🎧', '🔌', '🔋', '📷', '🖨️', '💽',
    ],
    'Tools & Hardware': [
      '🔧', '🔨', '⚒️', '🛠️', '🪛', '🔩', '⚙️', '🧰', '🪚', '🪝',
    ],
    'Flowers & Gifts': [
      '🌷', '🌹', '🌸', '💐', '🎁', '🎀', '🌻', '🪴',
    ],
    'Other': [
      '📦', '🛒', '🏷️', '🧾', '🪙', '📬',
    ],
  };

  /// A flat, de-duplicated list of every emoji in the catalog, preserving
  /// first-seen order. Handy for a single-grid picker.
  static List<String> get all {
    final seen = <String>{};
    final out = <String>[];
    for (final list in catalogByCategory.values) {
      for (final e in list) {
        if (seen.add(e)) out.add(e);
      }
    }
    return out;
  }

  /// Returns the stored emoji [value] if present, otherwise the [fallback].
  ///
  /// Note: items now store the emoji itself (e.g. '🥛'). For backward
  /// compatibility with the old Material-icon keys (e.g. 'milk'), we map a
  /// handful of legacy keys to emojis via [_legacyKeyToEmoji].
  static String resolve(String? value) {
    if (value == null || value.isEmpty) return fallback;
    // If it's already an emoji we stored, use it directly.
    if (!_legacyKeyToEmoji.containsKey(value)) return value;
    // Legacy Material-icon key → emoji.
    return _legacyKeyToEmoji[value] ?? fallback;
  }

  /// Smart auto-assignment: picks a representative emoji from a product's
  /// [name] and optional [category] when the user hasn't chosen one.
  static String autoEmojiFor(String name, [String? category]) {
    final n = name.toLowerCase();
    final c = (category ?? '').toLowerCase();
    bool has(String s) => n.contains(s) || c.contains(s);

    if (has('milk')) return '🥛';
    if (has('cheese')) return '🧀';
    if (has('butter') || has('ghee')) return '🧈';
    if (has('curd') || has('yogurt') || has('yoghurt') || has('dahi')) {
      return '🥣';
    }
    if (has('bread') || has('loaf') || has('bakery') || has('bun')) {
      return '🍞';
    }
    if (has('egg')) return '🥚';
    if (has('rice')) return '🍚';
    if (has('wheat') || has('atta') || has('flour')) return '🌾';
    if (has('oil')) return '🫗';
    if (has('honey')) return '🍯';
    if (has('water')) return '💧';
    if (has('juice')) return '🧃';
    if (has('tea')) return '🍵';
    if (has('coffee')) return '☕';
    if (has('apple')) return '🍎';
    if (has('banana')) return '🍌';
    if (has('orange')) return '🍊';
    if (has('grape')) return '🍇';
    if (has('fruit')) return '🍎';
    if (has('tomato')) return '🍅';
    if (has('potato')) return '🥔';
    if (has('onion')) return '🧅';
    if (has('garlic')) return '🧄';
    if (has('carrot')) return '🥕';
    if (has('vegetable') || has('veg')) return '🥦';
    if (has('sugar') || has('salt') || has('pantry')) return '🧂';
    if (has('chicken')) return '🍗';
    if (has('mutton') || has('meat') || has('beef')) return '🥩';
    if (has('fish')) return '🐟';
    if (has('prawn') || has('shrimp')) return '🦐';
    if (has('biscuit') || has('cookie')) return '🍪';
    if (has('chocolate')) return '🍫';
    if (has('cake')) return '🍰';
    if (has('chips') || has('snack')) return '🍿';
    if (has('clean')) return '🧼';
    if (has('soap')) return '🧼';
    if (has('detergent')) return '🧴';
    if (has('tissue') || has('paper')) return '🧻';
    if (has('medicine') || has('medicines') || has('tablet') || has('pill')) {
      return '💊';
    }
    if (has('baby')) return '🍼';
    if (has('pet') || has('dog') || has('cat')) return '🐾';
    if (has('pen') || has('pencil') || has('stationery')) return '✏️';
    if (has('household')) return '🧺';
    return fallback;
  }

  /// Legacy Material-icon string keys (used by older saved items) mapped to
  /// their closest emoji, so previously-saved products still render sensibly.
  static const Map<String, String> _legacyKeyToEmoji = {
    'inventory': '📦',
    'milk': '🥛',
    'bread': '🍞',
    'egg': '🥚',
    'rice': '🍚',
    'grocery': '🛒',
    'water': '💧',
    'fruit': '🍎',
    'vegetable': '🥦',
    'tea': '🍵',
    'coffee': '☕',
    'spices': '🧂',
    'cleaning': '🧼',
    'soap': '🧼',
    'medicine': '💊',
    'household': '🧺',
    'snacks': '🍪',
    'icecream': '🍨',
    'cake': '🍰',
    'pizza': '🍕',
    'fastfood': '🍔',
    'meat': '🥩',
    'fish': '🐟',
    'oil': '🫗',
    'bottle': '🍶',
    'baby': '🍼',
    'pet': '🐾',
    'stationery': '✏️',
    'electronics': '💻',
    'tools': '🔧',
    'flower': '🌷',
    'gift': '🎁',
    'box': '📦',
  };
}