
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:try_on_me/seed.dart';

import 'seed_data.dart';

// ============================================================
// PRODUCT MODELS
// ============================================================

/// "#B55239" -> Color
Color colorFromHex(String hex) {
  var h = hex.replaceAll('#', '').trim();
  if (h.length == 6) h = 'FF$h';
  return Color(int.tryParse(h, radix: 16) ?? 0xFF000000);
}

class MakeupShade {
  final String name;
  final String hex;
  final Color color;

  MakeupShade({required this.name, required this.hex})
      : color = colorFromHex(hex);

  factory MakeupShade.fromMap(Map<String, dynamic> m) => MakeupShade(
    name: m['name'] as String? ?? '',
    hex: m['hex'] as String? ?? '#000000',
  );
}

class MakeupProduct {
  final String id;
  final String category;
  final String name;
  final String brand;
  final String image;
  final double price;
  final int sortOrder;
  final List<MakeupShade> shades;

  MakeupProduct({
    required this.id,
    required this.category,
    required this.name,
    required this.brand,
    required this.image,
    required this.price,
    required this.shades,
    this.sortOrder = 0,
  });

}

/// A product + the shade the user tried on.
class LookItem {
  final MakeupProduct product;
  final MakeupShade shade;

  const LookItem({required this.product, required this.shade});
}

// ============================================================
// PRODUCT STORE (from seed_data.dart)
// ============================================================

class ProductStore extends ChangeNotifier {
  ProductStore._();
  static final ProductStore instance = ProductStore._();

  List<MakeupProduct> _all = [];

  List<MakeupProduct> get all => _all;

  List<MakeupProduct> byCategory(String category) => _all
      .where((p) => p.category == category && p.shades.isNotEmpty)
      .toList();

  MakeupProduct? byId(String id) {
    for (final p in _all) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// Loads the catalog from [seedProducts].
  Future<void> start() async {
    _all = [
      for (var i = 0; i < seedProducts.length; i++)
        MakeupProduct(
          id: seedProducts[i]['id'] as String,
          category: seedProducts[i]['category'] as String,
          name: seedProducts[i]['name'] as String,
          brand: seedProducts[i]['brand'] as String,
          image: seedProducts[i]['image'] as String,
          price: (seedProducts[i]['price'] as num).toDouble(),
          sortOrder: i,
          shades: (seedProducts[i]['shades'] as List)
              .map((s) => MakeupShade.fromMap(Map<String, dynamic>.from(s as Map)))
              .toList(),
        ),
    ];
    notifyListeners();
  }
}

// ============================================================
// HELPERS
// ============================================================

/// 1234.5 -> ₱1,234.50
String peso(double value) {
  final parts = value.toStringAsFixed(2).split('.');
  final whole = parts[0].replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
        (m) => ',',
  );
  return '₱$whole.${parts[1]}';
}

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// Sep 25, 2026 · 3:05 PM
String formatDateTime(DateTime d) {
  final hour12 = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final minute = d.minute.toString().padLeft(2, '0');
  final amPm = d.hour < 12 ? 'AM' : 'PM';
  return '${_months[d.month - 1]} ${d.day}, ${d.year} · $hour12:$minute $amPm';
}

/// Sep 25
String formatShortDate(DateTime d) => '${_months[d.month - 1]} ${d.day}';

Widget productImage(MakeupProduct p, {double size = 56}) {
  return Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: Colors.grey.shade100,
      borderRadius: BorderRadius.circular(10),
    ),
    padding: const EdgeInsets.all(4),
    child: p.image.startsWith('http')
    // Firestore can also hold a web image URL (e.g. Firebase Storage).
        ? Image.network(
      p.image,
      fit: BoxFit.contain,
      errorBuilder: (context, error, stackTrace) => Icon(
        Icons.shopping_bag_outlined,
        color: Colors.grey.shade500,
        size: size * 0.5,
      ),
    )
        : Image.asset(
      p.image,
      fit: BoxFit.contain,
      errorBuilder: (context, error, stackTrace) => Icon(
        Icons.shopping_bag_outlined,
        color: Colors.grey.shade500,
        size: size * 0.5,
      ),
    ),
  );
}

Widget shadeDot(Color color, {double size = 12}) {
  return Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: color,
      shape: BoxShape.circle,
      border: Border.all(color: Colors.grey.shade300),
    ),
  );
}

const _black = Colors.black;

ButtonStyle _primaryButtonStyle() => ElevatedButton.styleFrom(
  backgroundColor: _black,
  foregroundColor: Colors.white,
  disabledBackgroundColor: Colors.grey.shade300,
  minimumSize: const Size.fromHeight(50),
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
  textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
);

ButtonStyle _secondaryButtonStyle() => OutlinedButton.styleFrom(
  foregroundColor: _black,
  minimumSize: const Size.fromHeight(50),
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
  textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
);

// ============================================================
// CART
// ============================================================

class CartItem {
  /// Firestore document id of this cart line ('' for order items).
  final String id;
  final MakeupProduct product;
  final MakeupShade shade;
  int quantity;

  CartItem({
    this.id = '',
    required this.product,
    required this.shade,
    this.quantity = 1,
  });

  double get total => product.price * quantity;

  bool matches(MakeupProduct p, MakeupShade s) =>
      product.id == p.id && shade.name == s.name;

  Map<String, dynamic> toOrderMap() => {
    'productId': product.id,
    'category': product.category,
    'name': product.name,
    'brand': product.brand,
    'image': product.image,
    'price': product.price,
    'shadeName': shade.name,
    'shadeHex': shade.hex,
    'quantity': quantity,
  };

  /// Order items keep a copy of the product as it was when purchased,
  /// so later price/name changes don't alter old orders.
  factory CartItem.fromOrderMap(Map<String, dynamic> m) {
    final shade = MakeupShade(
      name: m['shadeName'] as String? ?? '',
      hex: m['shadeHex'] as String? ?? '#000000',
    );
    return CartItem(
      product: MakeupProduct(
        id: m['productId'] as String? ?? '',
        category: m['category'] as String? ?? '',
        name: m['name'] as String? ?? '',
        brand: m['brand'] as String? ?? '',
        image: m['image'] as String? ?? '',
        price: (m['price'] as num? ?? 0).toDouble(),
        shades: [shade],
      ),
      shade: shade,
      quantity: (m['quantity'] as num? ?? 1).toInt(),
    );
  }
}

class CartStore extends ChangeNotifier {
  CartStore._();
  static final CartStore instance = CartStore._();

  static const maxQuantity = 10;

  final List<CartItem> _items = [];
  int _nextId = 1;

  List<CartItem> get items => List.unmodifiable(_items);
  bool get isEmpty => _items.isEmpty;
  int get count => _items.fold<int>(0, (sum, i) => sum + i.quantity);
  double get subtotal => _items.fold<double>(0, (sum, i) => sum + i.total);

  void start() {}

  Future<void> add(MakeupProduct product, MakeupShade shade,
      {int quantity = 1}) async {
    for (final item in _items) {
      if (item.matches(product, shade)) {
        item.quantity = math.min(item.quantity + quantity, maxQuantity);
        notifyListeners();
        return;
      }
    }
    _items.add(CartItem(
      id: '${_nextId++}',
      product: product,
      shade: shade,
      quantity: math.min(quantity, maxQuantity),
    ));
    notifyListeners();
  }

  Future<void> addLook(List<LookItem> look) async {
    for (final l in look) {
      await add(l.product, l.shade);
    }
  }

  Future<void> setQuantity(CartItem item, int quantity) async {
    if (quantity <= 0) {
      _items.remove(item);
    } else {
      item.quantity = math.min(quantity, maxQuantity);
    }
    notifyListeners();
  }

  Future<void> remove(CartItem item) async {
    _items.remove(item);
    notifyListeners();
  }

  Future<void> clear() async {
    _items.clear();
    notifyListeners();
  }
}

// ============================================================
// SHIPPING + PAYMENT OPTIONS
// ============================================================

class ShippingOption {
  final String id;
  final String label;
  final String eta;
  final int minDays;
  final int maxDays;
  final double fee;

  const ShippingOption({
    required this.id,
    required this.label,
    required this.eta,
    required this.minDays,
    required this.maxDays,
    required this.fee,
  });
}

const shippingOptions = [
  ShippingOption(
    id: 'standard',
    label: 'Standard Delivery',
    eta: '3–5 business days',
    minDays: 3,
    maxDays: 5,
    fee: 80,
  ),
  ShippingOption(
    id: 'express',
    label: 'Express Delivery',
    eta: '1–2 business days',
    minDays: 1,
    maxDays: 2,
    fee: 150,
  ),
];

ShippingOption shippingOptionById(String? id) => shippingOptions.firstWhere(
      (o) => o.id == id,
  orElse: () => shippingOptions.first,
);

/// Standard shipping is free at or above this subtotal.
const freeShippingThreshold = 1000.0;

double shippingFeeFor(ShippingOption option, double subtotal) {
  if (option.id == 'standard' && subtotal >= freeShippingThreshold) return 0;
  return option.fee;
}

enum PaymentMethod { cod, gcash, card }

String paymentLabel(PaymentMethod m) {
  switch (m) {
    case PaymentMethod.cod:
      return 'Cash on Delivery';
    case PaymentMethod.gcash:
      return 'GCash';
    case PaymentMethod.card:
      return 'Credit / Debit Card';
  }
}

IconData paymentIcon(PaymentMethod m) {
  switch (m) {
    case PaymentMethod.cod:
      return Icons.payments_outlined;
    case PaymentMethod.gcash:
      return Icons.account_balance_wallet_outlined;
    case PaymentMethod.card:
      return Icons.credit_card;
  }
}

class ShippingAddress {
  final String fullName;
  final String phone;
  final String street;
  final String barangay;
  final String city;
  final String province;
  final String postalCode;

  const ShippingAddress({
    required this.fullName,
    required this.phone,
    required this.street,
    required this.barangay,
    required this.city,
    required this.province,
    required this.postalCode,
  });

  String get fullAddress =>
      '$street, Brgy. $barangay, $city, $province $postalCode';

  Map<String, dynamic> toMap() => {
    'fullName': fullName,
    'phone': phone,
    'street': street,
    'barangay': barangay,
    'city': city,
    'province': province,
    'postalCode': postalCode,
  };

  factory ShippingAddress.fromMap(Map<String, dynamic> m) => ShippingAddress(
    fullName: m['fullName'] as String? ?? '',
    phone: m['phone'] as String? ?? '',
    street: m['street'] as String? ?? '',
    barangay: m['barangay'] as String? ?? '',
    city: m['city'] as String? ?? '',
    province: m['province'] as String? ?? '',
    postalCode: m['postalCode'] as String? ?? '',
  );
}

// ============================================================
// ORDERS
// ============================================================

enum OrderStatus { placed, packed, shipped, outForDelivery, delivered, cancelled }

const orderFlow = [
  OrderStatus.placed,
  OrderStatus.packed,
  OrderStatus.shipped,
  OrderStatus.outForDelivery,
  OrderStatus.delivered,
];

OrderStatus orderStatusFromName(String? name) => OrderStatus.values.firstWhere(
      (s) => s.name == name,
  orElse: () => OrderStatus.placed,
);

String statusLabel(OrderStatus s) {
  switch (s) {
    case OrderStatus.placed:
      return 'Order Placed';
    case OrderStatus.packed:
      return 'Packed';
    case OrderStatus.shipped:
      return 'Shipped';
    case OrderStatus.outForDelivery:
      return 'Out for Delivery';
    case OrderStatus.delivered:
      return 'Delivered';
    case OrderStatus.cancelled:
      return 'Cancelled';
  }
}

String statusDescription(OrderStatus s) {
  switch (s) {
    case OrderStatus.placed:
      return 'We received your order.';
    case OrderStatus.packed:
      return 'Your items are packed and ready.';
    case OrderStatus.shipped:
      return 'Your parcel is on its way to your area.';
    case OrderStatus.outForDelivery:
      return 'The rider is on the way to you.';
    case OrderStatus.delivered:
      return 'Your parcel has been delivered. Enjoy!';
    case OrderStatus.cancelled:
      return 'This order was cancelled.';
  }
}

IconData statusIcon(OrderStatus s) {
  switch (s) {
    case OrderStatus.placed:
      return Icons.receipt_long;
    case OrderStatus.packed:
      return Icons.inventory_2_outlined;
    case OrderStatus.shipped:
      return Icons.local_shipping_outlined;
    case OrderStatus.outForDelivery:
      return Icons.delivery_dining;
    case OrderStatus.delivered:
      return Icons.check_circle_outline;
    case OrderStatus.cancelled:
      return Icons.cancel_outlined;
  }
}

Color statusColor(OrderStatus s) {
  switch (s) {
    case OrderStatus.delivered:
      return Colors.green.shade700;
    case OrderStatus.cancelled:
      return Colors.red.shade700;
    default:
      return Colors.orange.shade800;
  }
}

class ShopOrder {
  /// Firestore document id.
  final String docId;

  /// Friendly order number shown to the user, e.g. TOM-482913.
  final String id;
  final String trackingNumber;
  final List<CartItem> items;
  final ShippingAddress address;
  final ShippingOption shipping;
  final PaymentMethod payment;
  final double subtotal;
  final double shippingFee;
  final DateTime placedAt;
  final DateTime? cancelledAt;

  /// Status saved in Firestore. Used when [demoAutoAdvance] is false,
  /// so an admin can move the order along from the Firebase console.
  final OrderStatus storedStatus;

  /// true  = status advances automatically every [stageDuration] (demo).
  /// false = status is whatever "status" says in Firestore.
  final bool demoAutoAdvance;

  /// DEMO speed: each stage advances after this long.
  static const stageDuration = Duration(seconds: 30);

  ShopOrder({
    required this.docId,
    required this.id,
    required this.trackingNumber,
    required this.items,
    required this.address,
    required this.shipping,
    required this.payment,
    required this.subtotal,
    required this.shippingFee,
    required this.placedAt,
    this.cancelledAt,
    this.storedStatus = OrderStatus.placed,
    this.demoAutoAdvance = true,
  });

  double get total => subtotal + shippingFee;
  int get itemCount => items.fold<int>(0, (sum, i) => sum + i.quantity);

  OrderStatus get status {
    if (cancelledAt != null || storedStatus == OrderStatus.cancelled) {
      return OrderStatus.cancelled;
    }
    if (!demoAutoAdvance) return storedStatus;

    final elapsed = DateTime.now().difference(placedAt);
    final step = elapsed.inSeconds ~/ stageDuration.inSeconds;
    return orderFlow[math.min(step, orderFlow.length - 1)];
  }

  int get stageIndex => orderFlow.indexOf(status);

  /// When a stage was reached (null if unknown, e.g. admin-controlled).
  DateTime? stageTime(int index) {
    if (index == 0) return placedAt;
    if (!demoAutoAdvance) return null;
    return placedAt.add(stageDuration * index);
  }

  bool get canCancel =>
      status == OrderStatus.placed || status == OrderStatus.packed;

  String get estimatedDelivery {
    final from = placedAt.add(Duration(days: shipping.minDays));
    final to = placedAt.add(Duration(days: shipping.maxDays));
    return '${formatShortDate(from)} – ${formatShortDate(to)}';
  }

}

class OrderStore extends ChangeNotifier {
  OrderStore._();
  static final OrderStore instance = OrderStore._();

  final _random = math.Random();
  final List<ShopOrder> _orders = [];

  /// Last used address, to pre-fill checkout next time.
  ShippingAddress? lastAddress;

  List<ShopOrder> get orders => List.unmodifiable(_orders);

  ShopOrder? byDocId(String docId) {
    for (final o in _orders) {
      if (o.docId == docId) return o;
    }
    return null;
  }

  Future<void> start() async {}

  String _digits(int n) =>
      List.generate(n, (_) => _random.nextInt(10)).join();

  Future<ShopOrder> placeOrder({
    required List<CartItem> items,
    required ShippingAddress address,
    required ShippingOption shipping,
    required PaymentMethod payment,
  }) async {
    final subtotal = items.fold<double>(0, (sum, i) => sum + i.total);
    final number = 'TOM-${_digits(6)}';
    final order = ShopOrder(
      docId: number,
      id: number,
      trackingNumber: 'PH${_digits(10)}',
      items: items
          .map((i) => CartItem(
        product: i.product,
        shade: i.shade,
        quantity: i.quantity,
      ))
          .toList(),
      address: address,
      shipping: shipping,
      payment: payment,
      subtotal: subtotal,
      shippingFee: shippingFeeFor(shipping, subtotal),
      placedAt: DateTime.now(),
    );
    _orders.insert(0, order);
    lastAddress = address;
    await CartStore.instance.clear();
    notifyListeners();
    return order;
  }

  Future<void> cancel(ShopOrder order) async {
    if (!order.canCancel) return;
    final i = _orders.indexOf(order);
    if (i < 0) return;
    // ShopOrder is immutable, so replace it with a cancelled copy.
    _orders[i] = ShopOrder(
      docId: order.docId,
      id: order.id,
      trackingNumber: order.trackingNumber,
      items: order.items,
      address: order.address,
      shipping: order.shipping,
      payment: order.payment,
      subtotal: order.subtotal,
      shippingFee: order.shippingFee,
      placedAt: order.placedAt,
      cancelledAt: DateTime.now(),
    );
    notifyListeners();
  }
}

// ============================================================
// CART ICON (with badge) — use in any app bar / header
// ============================================================

class CartIconButton extends StatelessWidget {
  const CartIconButton({super.key});

  @override
  Widget build(BuildContext context) {
    final cart = CartStore.instance;
    return AnimatedBuilder(
      animation: cart,
      builder: (context, _) {
        return IconButton(
          tooltip: 'Cart',
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const CartScreen()),
          ),
          icon: Badge(
            isLabelVisible: cart.count > 0,
            label: Text('${cart.count}'),
            child: const Icon(Icons.shopping_bag_outlined),
          ),
        );
      },
    );
  }
}

/// Shows "Added to cart" with a VIEW CART action.
void showAddedToCart(BuildContext context, String message) {
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      content: Text(message),
      behavior: SnackBarBehavior.floating,
      action: SnackBarAction(
        label: 'VIEW CART',
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const CartScreen()),
        ),
      ),
    ),
  );
}

// ============================================================
// SHARED SMALL WIDGETS
// ============================================================

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 8),
      child: Text(
        text,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;
  final bool bold;

  const _SummaryRow(this.label, this.value, {this.bold = false});

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontSize: bold ? 15 : 13,
      fontWeight: bold ? FontWeight.bold : FontWeight.normal,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Text(label, style: style),
          const Spacer(),
          Text(value, style: style),
        ],
      ),
    );
  }
}

class _SelectTile extends StatelessWidget {
  final bool selected;
  final IconData icon;
  final String title;
  final String? subtitle;
  final String? trailingText;
  final VoidCallback onTap;

  const _SelectTile({
    required this.selected,
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.trailingText,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? _black : Colors.grey.shade300,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade600,
                      ),
                    ),
                ],
              ),
            ),
            if (trailingText != null)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text(
                  trailingText!,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: selected ? _black : Colors.grey,
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final OrderStatus status;
  const _StatusChip(this.status);

  @override
  Widget build(BuildContext context) {
    final color = statusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        statusLabel(status),
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

PreferredSizeWidget _appBar(String title, {List<Widget>? actions}) {
  return AppBar(
    title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
    centerTitle: true,
    backgroundColor: Colors.white,
    surfaceTintColor: Colors.white,
    actions: actions,
  );
}

// ============================================================
// CART SCREEN
// ============================================================

class CartScreen extends StatelessWidget {
  const CartScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cart = CartStore.instance;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: _appBar('My Cart', actions: [
        IconButton(
          tooltip: 'My Orders',
          icon: const Icon(Icons.receipt_long_outlined),
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const MyOrdersScreen()),
          ),
        ),
      ]),
      body: AnimatedBuilder(
        animation: cart,
        builder: (context, _) {
          if (cart.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(30),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.shopping_bag_outlined,
                        size: 70, color: Colors.grey.shade400),
                    const SizedBox(height: 12),
                    const Text(
                      'Your cart is empty',
                      style:
                      TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Try on a shade you love, then add it here.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: _primaryButtonStyle(),
                      child: const Text('Start Trying On'),
                    ),
                  ],
                ),
              ),
            );
          }

          final remaining = freeShippingThreshold - cart.subtotal;

          return Column(
            children: [
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.all(20),
                  itemCount: cart.items.length,
                  separatorBuilder: (_, __) => const Divider(height: 24),
                  itemBuilder: (context, index) =>
                      _CartItemTile(item: cart.items[index]),
                ),
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.06),
                      blurRadius: 10,
                      offset: const Offset(0, -2),
                    ),
                  ],
                ),
                child: SafeArea(
                  top: false,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (remaining > 0)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                            'Add ${peso(remaining)} more for FREE standard shipping',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.green.shade700,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      _SummaryRow(
                        'Subtotal (${cart.count} items)',
                        peso(cart.subtotal),
                        bold: true,
                      ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Shipping is calculated at checkout',
                          style: TextStyle(
                              fontSize: 11, color: Colors.grey.shade600),
                        ),
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) => const CheckoutScreen()),
                        ),
                        style: _primaryButtonStyle(),
                        child: const Text('Checkout'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _CartItemTile extends StatelessWidget {
  final CartItem item;
  const _CartItemTile({required this.item});

  @override
  Widget build(BuildContext context) {
    final cart = CartStore.instance;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        productImage(item.product, size: 70),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.product.brand,
                style:
                const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
              ),
              Text(
                item.product.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  shadeDot(item.shade.color),
                  const SizedBox(width: 6),
                  Text(
                    item.shade.name,
                    style:
                    TextStyle(fontSize: 11, color: Colors.grey.shade700),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Text(
                    peso(item.total),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  _QuantityStepper(
                    quantity: item.quantity,
                    onChanged: (q) => cart.setQuantity(item, q),
                  ),
                ],
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Remove',
          visualDensity: VisualDensity.compact,
          icon: Icon(Icons.close, size: 18, color: Colors.grey.shade600),
          onPressed: () => cart.remove(item),
        ),
      ],
    );
  }
}

class _QuantityStepper extends StatelessWidget {
  final int quantity;
  final ValueChanged<int> onChanged;

  const _QuantityStepper({required this.quantity, required this.onChanged});

  Widget _button(IconData icon, VoidCallback? onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Icon(
          icon,
          size: 16,
          color: onTap == null ? Colors.grey.shade400 : _black,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _button(Icons.remove, () => onChanged(quantity - 1)),
          SizedBox(
            width: 24,
            child: Text(
              '$quantity',
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          _button(
            Icons.add,
            quantity < CartStore.maxQuantity
                ? () => onChanged(quantity + 1)
                : null,
          ),
        ],
      ),
    );
  }
}

// ============================================================
// CHECKOUT SCREEN
// ============================================================

class CheckoutScreen extends StatefulWidget {
  const CheckoutScreen({super.key});

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController nameCtrl;
  late final TextEditingController phoneCtrl;
  late final TextEditingController streetCtrl;
  late final TextEditingController barangayCtrl;
  late final TextEditingController cityCtrl;
  late final TextEditingController provinceCtrl;
  late final TextEditingController postalCtrl;

  ShippingOption shipping = shippingOptions.first;
  PaymentMethod payment = PaymentMethod.cod;
  bool isPlacing = false;

  @override
  void initState() {
    super.initState();
    final last = OrderStore.instance.lastAddress;
    nameCtrl = TextEditingController(text: last?.fullName);
    phoneCtrl = TextEditingController(text: last?.phone);
    streetCtrl = TextEditingController(text: last?.street);
    barangayCtrl = TextEditingController(text: last?.barangay);
    cityCtrl = TextEditingController(text: last?.city);
    provinceCtrl = TextEditingController(text: last?.province);
    postalCtrl = TextEditingController(text: last?.postalCode);
  }

  @override
  void dispose() {
    for (final c in [
      nameCtrl,
      phoneCtrl,
      streetCtrl,
      barangayCtrl,
      cityCtrl,
      provinceCtrl,
      postalCtrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _required(String? v) =>
      (v == null || v.trim().isEmpty) ? 'Required' : null;

  String? _validatePhone(String? v) {
    final value = (v ?? '').replaceAll(RegExp(r'[\s-]'), '');
    if (value.isEmpty) return 'Required';
    if (!RegExp(r'^(09|\+639)\d{9}$').hasMatch(value)) {
      return 'Enter a valid PH mobile number (e.g. 09171234567)';
    }
    return null;
  }

  String? _validatePostal(String? v) {
    final value = (v ?? '').trim();
    if (value.isEmpty) return 'Required';
    if (!RegExp(r'^\d{4}$').hasMatch(value)) return '4 digits';
    return null;
  }

  InputDecoration _decoration(String label, {String? hint}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      isDense: true,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _black, width: 2),
      ),
    );
  }

  Widget _field(
      TextEditingController ctrl,
      String label, {
        String? hint,
        TextInputType? keyboard,
        String? Function(String?)? validator,
      }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextFormField(
        controller: ctrl,
        keyboardType: keyboard,
        textInputAction: TextInputAction.next,
        textCapitalization: keyboard == null
            ? TextCapitalization.words
            : TextCapitalization.none,
        decoration: _decoration(label, hint: hint),
        validator: validator ?? _required,
      ),
    );
  }

  Future<void> placeOrder() async {
    if (!_formKey.currentState!.validate()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please complete your shipping details.')),
      );
      return;
    }

    final cart = CartStore.instance;
    if (cart.isEmpty) return;

    setState(() => isPlacing = true);

    final ShopOrder order;
    try {
      // SIMULATED payment processing.
      await Future.delayed(const Duration(seconds: 1));

      // Saves to Firestore and empties the cart (one atomic batch).
      order = await OrderStore.instance.placeOrder(
        items: cart.items,
        address: ShippingAddress(
          fullName: nameCtrl.text.trim(),
          phone: phoneCtrl.text.trim(),
          street: streetCtrl.text.trim(),
          barangay: barangayCtrl.text.trim(),
          city: cityCtrl.text.trim(),
          province: provinceCtrl.text.trim(),
          postalCode: postalCtrl.text.trim(),
        ),
        shipping: shipping,
        payment: payment,
      );
    } on TimeoutException {
      if (!mounted) return;
      setState(() => isPlacing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Slow or no internet. Your order will be sent once you are '
                'back online — check My Orders.',
          ),
        ),
      );
      return;
    } catch (e) {
      if (!mounted) return;
      setState(() => isPlacing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not place order: $e')),
      );
      return;
    }

    if (!mounted) return;

    // Go to confirmation; Back returns to the try-on screen.
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => OrderConfirmationScreen(order: order)),
          (route) => route.isFirst,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cart = CartStore.instance;
    final subtotal = cart.subtotal;
    final fee = shippingFeeFor(shipping, subtotal);
    final total = subtotal + fee;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: _appBar('Checkout'),
      body: AbsorbPointer(
        absorbing: isPlacing,
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            children: [
              // ---------------- ADDRESS ----------------
              const _SectionTitle('Shipping Address'),
              _field(nameCtrl, 'Full name'),
              _field(
                phoneCtrl,
                'Mobile number',
                hint: '09171234567',
                keyboard: TextInputType.phone,
                validator: _validatePhone,
              ),
              _field(streetCtrl, 'House no. / Street / Building'),
              _field(barangayCtrl, 'Barangay'),
              Row(
                children: [
                  Expanded(child: _field(cityCtrl, 'City / Municipality')),
                  const SizedBox(width: 10),
                  Expanded(child: _field(provinceCtrl, 'Province')),
                ],
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: SizedBox(
                  width: 160,
                  child: _field(
                    postalCtrl,
                    'Postal code',
                    keyboard: TextInputType.number,
                    validator: _validatePostal,
                  ),
                ),
              ),

              // ---------------- DELIVERY ----------------
              const _SectionTitle('Delivery Option'),
              for (final option in shippingOptions)
                _SelectTile(
                  selected: shipping.id == option.id,
                  icon: option.id == 'express'
                      ? Icons.bolt
                      : Icons.local_shipping_outlined,
                  title: option.label,
                  subtitle: option.eta,
                  trailingText: shippingFeeFor(option, subtotal) == 0
                      ? 'FREE'
                      : peso(option.fee),
                  onTap: () => setState(() => shipping = option),
                ),

              // ---------------- PAYMENT ----------------
              const _SectionTitle('Payment Method'),
              for (final method in PaymentMethod.values)
                _SelectTile(
                  selected: payment == method,
                  icon: paymentIcon(method),
                  title: paymentLabel(method),
                  subtitle: method == PaymentMethod.cod
                      ? 'Pay the rider when your parcel arrives'
                      : 'Demo only — no real charge',
                  onTap: () => setState(() => payment = method),
                ),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline, size: 16),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Payments are simulated in this version. '
                            'No money will be charged.',
                        style: TextStyle(fontSize: 11),
                      ),
                    ),
                  ],
                ),
              ),

              // ---------------- SUMMARY ----------------
              const _SectionTitle('Order Summary'),
              for (final item in cart.items)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      productImage(item.product, size: 40),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${item.product.brand} ${item.product.name}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12),
                            ),
                            Text(
                              '${item.shade.name} × ${item.quantity}',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(peso(item.total),
                          style: const TextStyle(fontSize: 12)),
                    ],
                  ),
                ),
              const Divider(height: 20),
              _SummaryRow('Subtotal', peso(subtotal)),
              _SummaryRow('Shipping fee', fee == 0 ? 'FREE' : peso(fee)),
              const Divider(height: 20),
              _SummaryRow('Total', peso(total), bold: true),
              const SizedBox(height: 20),

              ElevatedButton(
                onPressed: isPlacing || cart.isEmpty ? null : placeOrder,
                style: _primaryButtonStyle(),
                child: isPlacing
                    ? const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    ),
                    SizedBox(width: 10),
                    Text('Processing payment...'),
                  ],
                )
                    : Text('Place Order · ${peso(total)}'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// ORDER CONFIRMATION SCREEN
// ============================================================

class OrderConfirmationScreen extends StatelessWidget {
  final ShopOrder order;
  const OrderConfirmationScreen({super.key, required this.order});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 30),
            Center(
              child: Container(
                width: 90,
                height: 90,
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.check_rounded,
                    size: 56, color: Colors.green.shade700),
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'Order placed!',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              'Thank you, ${order.address.fullName.split(' ').first}! '
                  'Your makeup is on its way.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade700),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  _SummaryRow('Order ID', order.id, bold: true),
                  _SummaryRow('Items', '${order.itemCount}'),
                  _SummaryRow('Payment', paymentLabel(order.payment)),
                  _SummaryRow('Delivery', order.shipping.label),
                  _SummaryRow('Estimated arrival', order.estimatedDelivery),
                  const Divider(height: 20),
                  _SummaryRow('Total', peso(order.total), bold: true),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.location_on_outlined, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${order.address.fullName} · ${order.address.phone}',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          order.address.fullAddress,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => Navigator.of(context).pushReplacement(
                MaterialPageRoute(
                  builder: (_) => OrderTrackingScreen(order: order),
                ),
              ),
              style: _primaryButtonStyle(),
              icon: const Icon(Icons.local_shipping_outlined),
              label: const Text('Track My Order'),
            ),
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: () => Navigator.of(context).pop(),
              style: _secondaryButtonStyle(),
              child: const Text('Continue Shopping'),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// MY ORDERS SCREEN
// ============================================================

class MyOrdersScreen extends StatefulWidget {
  const MyOrdersScreen({super.key});

  @override
  State<MyOrdersScreen> createState() => _MyOrdersScreenState();
}

class _MyOrdersScreenState extends State<MyOrdersScreen> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // Refresh so statuses advance while this screen is open.
    _timer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = OrderStore.instance;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: _appBar('My Orders'),
      body: AnimatedBuilder(
        animation: store,
        builder: (context, _) {
          if (store.orders.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.receipt_long_outlined,
                      size: 64, color: Colors.grey.shade400),
                  const SizedBox(height: 10),
                  const Text(
                    'No orders yet',
                    style:
                    TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(20),
            itemCount: store.orders.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final order = store.orders[index];
              return InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => OrderTrackingScreen(order: order),
                  ),
                ),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            order.id,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const Spacer(),
                          _StatusChip(order.status),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        formatDateTime(order.placedAt),
                        style: TextStyle(
                            fontSize: 11, color: Colors.grey.shade600),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          for (final item in order.items.take(4))
                            Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: productImage(item.product, size: 40),
                            ),
                          if (order.items.length > 4)
                            Text('+${order.items.length - 4}'),
                          const Spacer(),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                '${order.itemCount} item(s)',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                              Text(
                                peso(order.total),
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

// ============================================================
// ORDER TRACKING SCREEN
// ============================================================

class OrderTrackingScreen extends StatefulWidget {
  final ShopOrder order;
  const OrderTrackingScreen({super.key, required this.order});

  @override
  State<OrderTrackingScreen> createState() => _OrderTrackingScreenState();
}

class _OrderTrackingScreenState extends State<OrderTrackingScreen> {
  Timer? _timer;

  /// Latest copy from Firestore (e.g. after cancelling or an admin update).
  ShopOrder get _order =>
      OrderStore.instance.byDocId(widget.order.docId) ?? widget.order;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _confirmCancel() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel order?'),
        content: Text('Order ${_order.id} will be cancelled.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep order'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Cancel order'),
          ),
        ],
      ),
    );
    if (yes == true) {
      try {
        await OrderStore.instance.cancel(_order);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not cancel: $e')),
          );
        }
      }
      if (mounted) setState(() {});
    }
  }

  Widget _timelineStep(int index, int currentIndex) {
    final stage = orderFlow[index];
    final reached = currentIndex >= index;
    final isCurrent = currentIndex == index;
    final isLast = index == orderFlow.length - 1;
    final color = reached ? _black : Colors.grey.shade300;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 36,
            child: Column(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: reached ? _black : Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(color: color, width: 2),
                  ),
                  child: Icon(
                    statusIcon(stage),
                    size: 16,
                    color: reached ? Colors.white : Colors.grey.shade400,
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      margin: const EdgeInsets.symmetric(vertical: 2),
                      color: currentIndex > index
                          ? _black
                          : Colors.grey.shade300,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 5, bottom: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    statusLabel(stage),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: isCurrent ? FontWeight.bold : FontWeight.w500,
                      color: reached ? _black : Colors.grey.shade500,
                    ),
                  ),
                  if (reached) ...[
                    const SizedBox(height: 2),
                    Text(
                      statusDescription(stage),
                      style:
                      TextStyle(fontSize: 12, color: Colors.grey.shade700),
                    ),
                    if (_order.stageTime(index) != null)
                      Text(
                        formatDateTime(_order.stageTime(index)!),
                        style: TextStyle(
                            fontSize: 11, color: Colors.grey.shade500),
                      ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final order = _order;
    final status = order.status;
    final isCancelled = status == OrderStatus.cancelled;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: _appBar('Track Order'),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // ---------------- HEADER CARD ----------------
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _black,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(statusIcon(status), color: Colors.white),
                    const SizedBox(width: 8),
                    Text(
                      statusLabel(status),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  statusDescription(status),
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: _headerInfo('Order ID', order.id),
                    ),
                    Expanded(
                      child: _headerInfo('Tracking No.', order.trackingNumber),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _headerInfo('Delivery', order.shipping.label),
                    ),
                    Expanded(
                      child: _headerInfo(
                        'Est. arrival',
                        isCancelled ? '—' : order.estimatedDelivery,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // ---------------- TIMELINE ----------------
          const _SectionTitle('Delivery Status'),
          if (isCancelled)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'Cancelled on ${formatDateTime(order.cancelledAt!)}',
                style: TextStyle(color: Colors.red.shade700, fontSize: 12),
              ),
            )
          else
            for (var i = 0; i < orderFlow.length; i++)
              _timelineStep(i, order.stageIndex),

          // ---------------- ADDRESS ----------------
          const _SectionTitle('Shipping To'),
          Text(
            '${order.address.fullName} · ${order.address.phone}',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 2),
          Text(
            order.address.fullAddress,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
          ),

          // ---------------- ITEMS ----------------
          const _SectionTitle('Items'),
          for (final item in order.items)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  productImage(item.product, size: 46),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${item.product.brand} ${item.product.name}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13),
                        ),
                        Row(
                          children: [
                            shadeDot(item.shade.color, size: 10),
                            const SizedBox(width: 4),
                            Text(
                              '${item.shade.name} × ${item.quantity}',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Text(peso(item.total), style: const TextStyle(fontSize: 13)),
                ],
              ),
            ),

          // ---------------- PAYMENT ----------------
          const Divider(height: 24),
          _SummaryRow('Payment', paymentLabel(order.payment)),
          _SummaryRow('Subtotal', peso(order.subtotal)),
          _SummaryRow(
            'Shipping fee',
            order.shippingFee == 0 ? 'FREE' : peso(order.shippingFee),
          ),
          const Divider(height: 20),
          _SummaryRow('Total', peso(order.total), bold: true),
          const SizedBox(height: 20),

          if (order.canCancel)
            OutlinedButton(
              onPressed: _confirmCancel,
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red.shade700,
                side: BorderSide(color: Colors.red.shade200),
                minimumSize: const Size.fromHeight(50),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
              ),
              child: const Text('Cancel Order'),
            ),
        ],
      ),
    );
  }

  Widget _headerInfo(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(color: Colors.white54, fontSize: 10)),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}