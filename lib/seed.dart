// ============================================================
// SEED DATA
// The product catalog. Edit, add or remove products here.
// Colors are hex strings like "#B55239".
// ============================================================

const List<Map<String, dynamic>> seedProducts = [
  // ---------------- LIPSTICK ----------------
  {
    'id': 'maybelline-superstay-matte-ink',
    'category': 'Lipstick',
    'name': 'SuperStay Matte Ink',
    'brand': 'Maybelline',
    'image': 'assets/products/maybelline.png',
    'price': 499,
    'shades': [
      {'name': 'Red', 'hex': '#F44336'},
      {'name': 'Pink', 'hex': '#E91E63'},
      {'name': 'Nude', 'hex': '#B97862'},
      {'name': 'Plum', 'hex': '#9C27B0'},
    ],
  },
  {
    'id': 'loreal-rouge-signature',
    'category': 'Lipstick',
    'name': 'Rouge Signature',
    'brand': "L'Oreal",
    'image': 'assets/products/loreal.png',
    'price': 550,
    'shades': [
      {'name': 'Ruby', 'hex': '#F44336'},
      {'name': 'Rose', 'hex': '#FF4081'},
      {'name': 'Nude', 'hex': '#C58B72'},
    ],
  },
  {
    'id': 'sunnies-fluffmatte',
    'category': 'Lipstick',
    'name': 'Fluffmatte',
    'brand': 'Sunnies Face',
    'image': 'assets/products/sunnies.png',
    'price': 395,
    'shades': [
      {'name': 'Terracotta', 'hex': '#B55239'},
      {'name': 'Brick', 'hex': '#8E3F35'},
      {'name': 'Brown', 'hex': '#795548'},
      {'name': 'Pink', 'hex': '#E91E63'},
    ],
  },
  {
    'id': 'careline-lip-cheek-tint',
    'category': 'Lipstick',
    'name': 'Lip and Cheek Tint',
    'brand': 'Careline',
    'image': 'assets/products/careline.png',
    'price': 299,
    'shades': [
      {'name': 'Cherry', 'hex': '#F44336'},
      {'name': 'Peach', 'hex': '#FF9800'},
      {'name': 'Rose', 'hex': '#E91E63'},
    ],
  },

  // ---------------- BLUSH ----------------
  {
    'id': 'maybelline-fit-me-blush',
    'category': 'Blush',
    'name': 'Fit Me Blush',
    'brand': 'Maybelline',
    'image': 'assets/products/maybelline_blush.png',
    'price': 399,
    'shades': [
      {'name': 'Pink', 'hex': '#E91E63'},
      {'name': 'Peach', 'hex': '#FF9800'},
      {'name': 'Rose', 'hex': '#FF5252'},
    ],
  },
  {
    'id': 'loreal-true-match-blush',
    'category': 'Blush',
    'name': 'True Match Blush',
    'brand': "L'Oreal",
    'image': 'assets/products/loreal_blush.png',
    'price': 450,
    'shades': [
      {'name': 'Coral', 'hex': '#FF5722'},
      {'name': 'Rose', 'hex': '#E91E63'},
      {'name': 'Nude', 'hex': '#B9826B'},
    ],
  },
  {
    'id': 'sunnies-airblush',
    'category': 'Blush',
    'name': 'Airblush',
    'brand': 'Sunnies Face',
    'image': 'assets/products/sunnies_blush.png',
    'price': 495,
    'shades': [
      {'name': 'Pink', 'hex': '#FF4081'},
      {'name': 'Peach', 'hex': '#FF5252'},
      {'name': 'Berry', 'hex': '#9C27B0'},
    ],
  },

  // ---------------- FOUNDATION ----------------
  {
    'id': 'maybelline-fit-me-foundation',
    'category': 'Foundation',
    'name': 'Fit Me Foundation',
    'brand': 'Maybelline',
    'image': 'assets/products/maybelline_foundation.png',
    'price': 499,
    'shades': [
      {'name': 'Light', 'hex': '#F3D2B8'},
      {'name': 'Medium', 'hex': '#D9A77E'},
      {'name': 'Tan', 'hex': '#AD704C'},
    ],
  },
  {
    'id': 'loreal-true-match-foundation',
    'category': 'Foundation',
    'name': 'True Match Foundation',
    'brand': "L'Oreal",
    'image': 'assets/products/loreal_foundation.png',
    'price': 650,
    'shades': [
      {'name': 'Light', 'hex': '#F0CFB2'},
      {'name': 'Medium', 'hex': '#D5A078'},
      {'name': 'Deep', 'hex': '#9A603F'},
    ],
  },
  {
    'id': 'careline-skin-so-good',
    'category': 'Foundation',
    'name': 'Skin So Good',
    'brand': 'Careline',
    'image': 'assets/products/careline_foundation.png',
    'price': 399,
    'shades': [
      {'name': 'Fair', 'hex': '#F2D1B5'},
      {'name': 'Natural', 'hex': '#D7A17B'},
      {'name': 'Honey', 'hex': '#B9784F'},
    ],
  },
];