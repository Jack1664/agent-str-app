import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/wallet.dart';

class WalletProvider with ChangeNotifier {
  List<Wallet> _wallets = [];
  Wallet? _activeWallet;

  List<Wallet> get wallets => _wallets;
  Wallet? get activeWallet => _activeWallet;

  Future<void> loadWallets() async {
    final prefs = await SharedPreferences.getInstance();
    final String? walletsJson = prefs.getString('wallets');
    if (walletsJson != null) {
      final List<dynamic> decoded = jsonDecode(walletsJson);
      _wallets = decoded.map((e) => Wallet.fromJson(e)).toList();

      // Auto-set the first wallet as active if none is set
      if (_wallets.isNotEmpty && _activeWallet == null) {
        _activeWallet = _wallets[0];
      }
    } else {
      _wallets = [];
    }
    notifyListeners();
  }

  Future<void> addWallet(Wallet wallet) async {
    _wallets.add(wallet);
    await _saveWallets();
    setActiveWallet(wallet);
  }

  Future<void> deleteWallet(String id) async {
    _wallets.removeWhere((w) => w.id == id);
    if (_activeWallet?.id == id) {
      _activeWallet = _wallets.isNotEmpty ? _wallets[0] : null;
    }
    await _saveWallets();
  }

  Future<void> updateWalletName(String id, String newName) async {
    final index = _wallets.indexWhere((w) => w.id == id);
    if (index != -1) {
      _wallets[index].name = newName;
      await _saveWallets();
      if (_activeWallet?.id == id) {
        _activeWallet!.name = newName;
        notifyListeners();
      }
    }
  }

  void setActiveWallet(Wallet wallet) {
    _activeWallet = wallet;
    notifyListeners();
  }

  Future<void> _saveWallets() async {
    final prefs = await SharedPreferences.getInstance();
    final String encoded = jsonEncode(_wallets.map((e) => e.toJson()).toList());
    await prefs.setString('wallets', encoded);
    notifyListeners();
  }
}
