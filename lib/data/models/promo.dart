enum PromoType { percent, flat, freeDelivery }

class Promo {
  final String code;
  final PromoType type;
  final double value;
  final double min;
  final String labelEn;
  final String labelAr;

  const Promo({
    required this.code,
    required this.type,
    required this.value,
    required this.min,
    required this.labelEn,
    required this.labelAr,
  });

  String label(bool arabic) => arabic ? labelAr : labelEn;

  double savings(double subtotal, double deliveryFee) {
    if (subtotal < min) return 0;
    switch (type) {
      case PromoType.percent:
        return double.parse((subtotal * value / 100).toStringAsFixed(3));
      case PromoType.flat:
        return value < subtotal ? value : subtotal;
      case PromoType.freeDelivery:
        return deliveryFee;
    }
  }
}
