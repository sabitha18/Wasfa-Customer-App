import 'package:flutter/material.dart';
import '../models/product.dart';
import '../models/seller.dart';
import '../models/pharmacy_store.dart';
import '../models/promo.dart';
import '../models/address.dart';
import '../models/prescription.dart';

/// Reference/static catalog data (categories, concerns, delivery slots) plus
/// a synchronous in-memory *cache* of products/prescriptions.
///
/// Product/prescription data now comes from the API (see
/// CatalogService/AccountService + the ViewModels that call them) — but a
/// few places in the app (CartState's BOGO math, deep-link "open product by
/// id" flows) need to look a product up synchronously without awaiting a
/// network call. Whenever a ViewModel fetches products from the API, it
/// calls [cacheProducts] so those lookups keep working. The `_mock*` lists
/// below only act as a seed so the app isn't blank before the first fetch
/// completes, and as an offline fallback if a fetch fails.
///
/// `stores` stays entirely mock: `GET /app/stores` doesn't exist on the
/// server yet (see the Postman collection note on that request) — swap this
/// out once `AppCatalogController@stores` ships.
class CatalogRepository {
  CatalogRepository._();
  static final CatalogRepository instance = CatalogRepository._();

  /// Merges freshly-fetched products into the synchronous lookup cache.
  void cacheProducts(List<Product> fetched) {
    for (final p in fetched) {
      final idx = products.indexWhere((existing) => existing.id == p.id);
      if (idx >= 0) {
        products[idx] = p;
      } else {
        products.add(p);
      }
    }
  }

  void cachePrescriptions(List<Prescription> fetched) {
    prescriptions
      ..clear()
      ..addAll(fetched);
  }

  static const categories = <StoreCategory>[
    StoreCategory('all', '🏬', 'All stores', 'كل المتاجر'),
    StoreCategory('pharmacy', '💊', 'Pharmacy', 'صيدلية'),
    StoreCategory('beauty', '💄', 'Beauty', 'تجميل'),
    StoreCategory('eyecare', '👁️', 'Eyecare', 'العناية بالعين'),
    StoreCategory('nutrition', '🥤', 'Nutrition', 'تغذية'),
  ];

  static const productCategories = <Map<String, String>>[
    {'emoji': '💊', 'cat': 'Medicine'},
    {'emoji': '💇', 'cat': 'Hair care'},
    {'emoji': '🧴', 'cat': 'Skin care'},
    {'emoji': '🟡', 'cat': 'Vitamins'},
    {'emoji': '🍼', 'cat': 'Mom & baby'},
    {'emoji': '🪥', 'cat': 'Personal care'},
    {'emoji': '❤️', 'cat': 'Health'},
  ];

  static const concerns = <Map<String, String>>[
    {'k': 'pain', 'en': 'Pain relief', 'ar': 'تسكين الألم'},
    {'k': 'skin', 'en': 'Skin', 'ar': 'البشرة'},
    {'k': 'energy', 'en': 'Energy', 'ar': 'الطاقة'},
    {'k': 'hair', 'en': 'Hair', 'ar': 'الشعر'},
    {'k': 'baby', 'en': 'Baby', 'ar': 'الطفل'},
    {'k': 'oral', 'en': 'Oral', 'ar': 'الفم'},
  ];

  static const brands = <String>[
    'Panadol', 'CeraVe', 'Centrum', 'Nordic', 'Vichy', 'Eucerin', 'Sebamed', 'Nivea',
  ];

  /// Mutable cache — populated via [cacheProducts]; seeded with mock data.
  final List<Product> products = List<Product>.from(_mockProducts);

  static final List<Product> _mockProducts = [
    Product(
      id: 1, nameEn: 'Panadol Extra', nameAr: 'بانادول إكسترا', brand: 'Panadol',
      category: 'Medicine', concern: 'pain', form: '24 tablets',
      scientificName: 'Paracetamol + Caffeine', emoji: '💊', rating: 4.8, reviews: 212,
      flags: const ['offer', 'best'],
      sellers: const [
        Seller(name: 'Royal Pharmacy', price: 1.250, was: 1.650, eta: '45 min', stock: true),
        Seller(name: 'Al Dawaeya', price: 1.300, was: 1.650, eta: '1 hr', stock: true),
        Seller(name: 'City Pharmacy', price: 1.350, eta: '30 min', stock: true),
      ],
    ),
    Product(
      id: 2, nameEn: 'CeraVe Moisturising', nameAr: 'سيرافي مرطب', brand: 'CeraVe',
      category: 'Skin care', concern: 'skin', form: '454 ml',
      scientificName: 'Ceramides', emoji: '🧴', rating: 4.7, reviews: 54,
      flags: const ['offer', 'best'],
      sellers: const [
        Seller(name: 'City Pharmacy', price: 8.250, was: 9.900, eta: '40 min', stock: true),
        Seller(name: 'Royal Pharmacy', price: 8.400, was: 9.900, eta: '50 min', stock: true),
      ],
    ),
    Product(
      id: 3, nameEn: 'Omega-3 1000mg', nameAr: 'أوميغا ٣ ١٠٠٠', brand: 'Nordic',
      category: 'Vitamins', concern: 'energy', form: '60 softgels',
      scientificName: 'Fish oil', emoji: '🟡', rating: 4.9, reviews: 88,
      flags: const ['best', 'offer'], tag: '1+1',
      sellers: const [
        Seller(name: 'Al Dawaeya', price: 5.400, eta: '1 hr', stock: true),
        Seller(name: 'Royal Pharmacy', price: 5.600, eta: '45 min', stock: true),
        Seller(name: 'City Pharmacy', price: 5.500, eta: '35 min', stock: true),
        Seller(name: 'Care Plus', price: 5.450, eta: '1 hr', stock: true),
        Seller(name: 'Salmiya Rx', price: 5.700, eta: '55 min', stock: false),
      ],
    ),
    Product(
      id: 4, nameEn: 'Centrum Adults', nameAr: 'سنتروم للكبار', brand: 'Centrum',
      category: 'Vitamins', concern: 'energy', form: '100 tablets',
      scientificName: 'Multivitamin', emoji: '🟠', rating: 4.6, reviews: 140,
      flags: const ['offer', 'best'],
      sellers: const [
        Seller(name: 'Royal Pharmacy', price: 6.900, was: 8.500, eta: '45 min', stock: true),
        Seller(name: 'City Pharmacy', price: 7.100, was: 8.500, eta: '35 min', stock: true),
      ],
    ),
    Product(
      id: 5, nameEn: 'Pampers Premium 4', nameAr: 'بامبرز بريميوم ٤', brand: 'Pampers',
      category: 'Mom & baby', concern: 'baby', form: '52 diapers',
      scientificName: 'Maxi 9-14kg', emoji: '🍼', rating: 4.9, reviews: 320,
      flags: const ['best', 'offer'], tag: '1+1',
      sellers: const [
        Seller(name: 'Al Dawaeya', price: 6.200, eta: '1 hr', stock: true),
        Seller(name: 'City Pharmacy', price: 6.400, eta: '40 min', stock: true),
      ],
    ),
    Product(
      id: 6, nameEn: 'Sebamed Anti-Hairloss', nameAr: 'سيباميد ضد التساقط', brand: 'Sebamed',
      category: 'Hair care', concern: 'hair', form: '200 ml',
      scientificName: 'Hair shampoo', emoji: '🧴', rating: 4.5, reviews: 33,
      flags: const ['offer', 'new'],
      sellers: const [
        Seller(name: 'Care Plus', price: 6.100, was: 7.500, eta: '1 hr', stock: true),
        Seller(name: 'Royal Pharmacy', price: 6.300, was: 7.500, eta: '45 min', stock: true),
      ],
    ),
    Product(
      id: 7, nameEn: 'Eucerin Sun SPF50', nameAr: 'يوسيرين واقي ٥٠', brand: 'Eucerin',
      category: 'Skin care', concern: 'skin', form: '50 ml',
      scientificName: 'SPF 50+', emoji: '🧴', rating: 4.8, reviews: 76,
      flags: const ['offer'],
      sellers: const [
        Seller(name: 'City Pharmacy', price: 6.750, was: 7.900, eta: '35 min', stock: true),
        Seller(name: 'Salmiya Rx', price: 6.900, was: 7.900, eta: '55 min', stock: true),
      ],
    ),
    Product(
      id: 8, nameEn: 'Listerine Cool Mint', nameAr: 'ليسترين كول منت', brand: 'Listerine',
      category: 'Personal care', concern: 'oral', form: '500 ml',
      scientificName: 'Mouthwash', emoji: '🦷', rating: 4.7, reviews: 61,
      flags: const ['best', 'new'],
      sellers: const [
        Seller(name: 'Royal Pharmacy', price: 2.250, eta: '45 min', stock: true),
        Seller(name: 'Al Dawaeya', price: 2.300, eta: '1 hr', stock: true),
      ],
    ),
  ];

  final List<PharmacyStore> stores = [
    PharmacyStore(name: 'Clear Pharmacy', nameAr: 'صيدلية كلير', area: '', category: 'pharmacy', eta: '25-40', fast: false, pro: false, freeDelivery: true, seller: 'Royal Pharmacy', gradient: const [Color(0xFF7C5CFF), Color(0xFF1E9CD7)], monogram: '℞'),
    PharmacyStore(name: 'Heba Pharmacy, Hawally', nameAr: 'صيدلية هبة، حولي', area: 'Hawally', category: 'pharmacy', eta: '20-30', fast: true, pro: true, freeDelivery: true, seller: 'Al Dawaeya', gradient: const [Color(0xFF023B60), Color(0xFF1E9CD7)], monogram: '℞'),
    PharmacyStore(name: 'Al Bimaristan Pharmacy, Hawally', nameAr: 'صيدلية البيمارستان، حولي', area: 'Hawally', category: 'pharmacy', eta: '25-40', fast: false, pro: true, freeDelivery: true, offer: '60% off', seller: 'City Pharmacy', gradient: const [Color(0xFF7A1F1F), Color(0xFFB34B4B)], monogram: '℞'),
    PharmacyStore(name: 'Life Care Pharmacy, Salmiya', nameAr: 'صيدلية لايف كير، السالمية', area: 'Salmiya', category: 'pharmacy', eta: '20-30', fast: true, pro: true, freeDelivery: true, offer: '60% off', seller: 'Care Plus', gradient: const [Color(0xFF0E3554), Color(0xFF1E9CD7)], monogram: '℞'),
    PharmacyStore(name: 'Wesal Pharmacy, Kaifan', nameAr: 'صيدلية وصال، كيفان', area: 'Kaifan', category: 'pharmacy', eta: '15-25', fast: true, pro: true, freeDelivery: true, seller: 'Royal Pharmacy', gradient: const [Color(0xFF0B6B4F), Color(0xFF23B487)], monogram: '℞'),
    PharmacyStore(name: 'Cardia Pharmacy, Sharq', nameAr: 'صيدلية كارديا، شرق', area: 'Sharq', category: 'pharmacy', eta: '10-20', fast: true, pro: true, freeDelivery: true, seller: 'Al Dawaeya', gradient: const [Color(0xFF444444), Color(0xFF888888)], monogram: '℞'),
    PharmacyStore(name: 'Pharma.C, Jabriya', nameAr: 'فارما سي، الجابرية', area: 'Jabriya', category: 'pharmacy', eta: '20-40', fast: false, pro: true, freeDelivery: true, seller: 'City Pharmacy', gradient: const [Color(0xFF5A3A2E), Color(0xFF9C6B4F)], monogram: 'C'),
    PharmacyStore(name: 'Glow Beauty, Salmiya', nameAr: 'جلو بيوتي، السالمية', area: 'Salmiya', category: 'beauty', eta: '30-50', fast: false, pro: true, freeDelivery: true, offer: '15% off', seller: 'Care Plus', gradient: const [Color(0xFFE7609F), Color(0xFFF6A5C0)], monogram: 'G'),
    PharmacyStore(name: 'VisionCare Optics, Hawally', nameAr: 'فيجن كير، حولي', area: 'Hawally', category: 'eyecare', eta: '25-45', fast: false, pro: false, freeDelivery: true, seller: 'Royal Pharmacy', gradient: const [Color(0xFF1E9CD7), Color(0xFF58C4E4)], monogram: '👁'),
    PharmacyStore(name: 'NutriHub, Jabriya', nameAr: 'نيوتري هَب، الجابرية', area: 'Jabriya', category: 'nutrition', eta: '20-35', fast: false, pro: true, freeDelivery: true, offer: '20% off select items', seller: 'City Pharmacy', gradient: const [Color(0xFF0E7A3A), Color(0xFF3BBF6B)], monogram: 'N'),
  ];

  final List<Promo> promos = const [
    Promo(code: 'WASFA15', type: PromoType.percent, value: 15, min: 5, labelEn: '15% off · min KWD 5', labelAr: 'خصم ١٥٪ · حد أدنى ٥ د.ك'),
    Promo(code: 'SAVE2', type: PromoType.flat, value: 2.000, min: 10, labelEn: 'KWD 2 off · min KWD 10', labelAr: 'خصم ٢ د.ك · حد أدنى ١٠ د.ك'),
    Promo(code: 'FREEDEL', type: PromoType.freeDelivery, value: 0, min: 3, labelEn: 'Free delivery · min KWD 3', labelAr: 'توصيل مجاني · حد أدنى ٣ د.ك'),
    Promo(code: 'NEW10', type: PromoType.percent, value: 10, min: 0, labelEn: '10% off · new users', labelAr: 'خصم ١٠٪ · للمستخدمين الجدد'),
  ];

  static const govs = <String>['Al Asimah', 'Hawalli', 'Farwaniya', 'Mubarak Al-Kabeer', 'Ahmadi', 'Jahra'];
  static const areas = <String>['Salmiya', 'Hawalli', 'Jabriya', 'Sharq', 'Salwa', 'Mishref', 'Bayan', 'Rumaithiya', 'Mangaf', 'Fintas', 'Farwaniya', 'Jahra'];
  static const deliverySlots = <List<String>>[
    ['8:00 AM', '12:00 PM'], ['12:00 PM', '4:00 PM'], ['4:00 PM', '8:00 PM'], ['8:00 PM', '12:00 AM'],
  ];

  Address defaultAddress() => Address(
        title: 'Home/Apartment',
        first: 'Nouhad',
        last: 'Dabliz',
        email: 'nouhad.dabliz99@gmail.com',
        phone: '5157 7926',
        gov: 'Al Asimah',
        area: 'Salmiya',
        block: '10',
        street: 'St 5',
        building: '2',
        apt: '3',
        floor: '1',
      );

  Product? findProduct(int id) {
    try {
      return products.firstWhere((p) => p.id == id);
    } catch (_) {
      return null;
    }
  }

  List<Product> productsByPharmacy(String seller) =>
      products.where((p) => p.sellers.any((s) => s.name == seller)).toList();

  /// {pharmacyName: {count, minPrice}} — mirrors JS `pharmList()`.
  List<Map<String, dynamic>> pharmacyList() {
    final map = <String, Map<String, dynamic>>{};
    for (final p in products) {
      for (final s in p.sellers) {
        final entry = map.putIfAbsent(s.name, () => {'name': s.name, 'n': 0, 'min': double.infinity});
        entry['n'] = (entry['n'] as int) + 1;
        if (s.price < (entry['min'] as double)) entry['min'] = s.price;
      }
    }
    return map.values.toList();
  }

  /// Mutable cache — populated via [cachePrescriptions]; seeded with mock.
  final List<Prescription> prescriptions = List<Prescription>.from(_mockPrescriptions);

  static final List<Prescription> _mockPrescriptions = [
    Prescription(
      id: 'RX100021-9948', date: 'Jun 17, 2026', doctor: 'Dr. Lamia Farrag',
      specialty: 'Dermatologist', clinic: 'Hadi Clinic', diagnosis: 'Eczema', status: 'priced',
      items: [
        RxItem(name: 'Hyaline Eye Drops 2ml', nameAr: 'هيالين قطرة ٢مل', emoji: '💧',
            dosage: '10 drops daily before meal · 10 days', dosageAr: '١٠ قطرات يومياً قبل الأكل · ١٠ أيام',
            refillable: true, sellers: const [
              Seller(name: 'Royal Pharmacy', price: 4.900, eta: '', stock: true),
              Seller(name: 'City Pharmacy', price: 5.100, eta: '', stock: true),
            ]),
        RxItem(name: 'SVR Xerial 10 Emulsion 200ml', nameAr: 'إس في آر زيريال ١٠', emoji: '🧴',
            dosage: 'Apply nightly · 1 month', dosageAr: 'يُدهن ليلاً · شهر',
            refillable: false, sellers: const [
              Seller(name: 'Care Plus', price: 7.250, eta: '', stock: true),
              Seller(name: 'Royal Pharmacy', price: 7.500, eta: '', stock: true),
            ]),
      ],
    ),
    Prescription(
      id: 'RX100021-1167', date: 'Jun 15, 2026', doctor: 'Dr. Khaled Al Saleh',
      specialty: 'GP', clinic: 'Al Zuhair Center', diagnosis: 'Hypertension', status: 'priced',
      items: [
        RxItem(name: 'Concor 5mg', nameAr: 'كونكور ٥', emoji: '💊',
            dosage: '1 tablet daily morning · 30 days', dosageAr: 'قرص يومياً صباحاً · ٣٠ يوم',
            refillable: true, sellers: const [
              Seller(name: 'City Pharmacy', price: 3.200, eta: '', stock: true),
              Seller(name: 'Al Dawaeya', price: 3.350, eta: '', stock: true),
            ]),
      ],
    ),
    Prescription(
      id: 'RX100021-9168', date: 'Jun 8, 2026', doctor: 'Dr. Ghadeer Akbar',
      specialty: 'OB-GYN', clinic: 'Royal Hospital', diagnosis: 'Prenatal care', status: 'review',
      items: [
        RxItem(name: 'Iron + Folic Acid', nameAr: 'حديد + حمض الفوليك', emoji: '🔴',
            dosage: '1 tablet daily · 60 days', dosageAr: 'قرص يومياً · ٦٠ يوم',
            refillable: false, sellers: const []),
      ],
    ),
  ];

  Prescription? findPrescription(String id) {
    try {
      return prescriptions.firstWhere((r) => r.id == id);
    } catch (_) {
      return null;
    }
  }
}
