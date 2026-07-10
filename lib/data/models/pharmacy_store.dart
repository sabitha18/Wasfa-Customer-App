import 'package:flutter/material.dart';

class PharmacyStore {
  final String name;
  final String nameAr;
  final String area;
  final String category; // pharmacy, beauty, eyecare, nutrition
  final String eta; // "20-30"
  final bool fast;
  final bool pro;
  final bool freeDelivery;
  final String? offer; // "60% off"
  final String seller; // maps to Seller.name used across PRODUCTS
  final List<Color> gradient;
  final String monogram;

  const PharmacyStore({
    required this.name,
    required this.nameAr,
    required this.area,
    required this.category,
    required this.eta,
    required this.fast,
    required this.pro,
    required this.freeDelivery,
    this.offer,
    required this.seller,
    required this.gradient,
    required this.monogram,
  });

  String label(bool arabic) => arabic ? nameAr : name;
}

class StoreCategory {
  final String key;
  final String emoji;
  final String labelEn;
  final String labelAr;
  const StoreCategory(this.key, this.emoji, this.labelEn, this.labelAr);
}
