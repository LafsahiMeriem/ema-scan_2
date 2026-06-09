import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/lot_info.dart';
import '../services/sap_service.dart';
import 'scanner_screen.dart';
import 'setting_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _lotController = TextEditingController();
  final TextEditingController _cartonController = TextEditingController();

  final SapService _sapService = SapService();
  LotInfo? lotDetails;
  bool isLoading = false;

  // États pour la gestion des magasins
  List<Map<String, String>> _warehouses = [];
  String? _selectedSourceWhs;
  bool _isLoadingWhs = true;

  // Facteur de conversion unitaire
  double _quantiteParCarton = 1.0;
  double _calculatedTotalQuantity = 0.0;

  // Palette Premium (Slate & Indigo Deep)
  final Color primaryDark = const Color(0xFF0F172A);
  final Color accentIndigo = const Color(0xFF6366F1);
  final Color surfaceLight = const Color(0xFFF8FAFC);

  @override
  void initState() {
    super.initState();
    _loadWarehouses();
  }

  Future<void> _loadWarehouses() async {
    setState(() => _isLoadingWhs = true);
    try {
      final list = await _sapService.fetchAllWarehouses();
      final prefs = await SharedPreferences.getInstance();
      String? savedWhs = prefs.getString('whsSource');

      setState(() {
        _warehouses = list;
        if (savedWhs != null && _warehouses.any((w) => w['code'] == savedWhs)) {
          _selectedSourceWhs = savedWhs;
        } else if (_warehouses.isNotEmpty) {
          _selectedSourceWhs = _warehouses.first['code'];
          prefs.setString('whsSource', _selectedSourceWhs!);
        }
        _isLoadingWhs = false;
      });
    } catch (e) {
      setState(() => _isLoadingWhs = false);
      _showStatusSnackBar("Erreur de chargement des magasins.", isError: true);
    }
  }

  Future<void> _onWarehouseChanged(String? newWhs) async {
    if (newWhs == null) return;
    setState(() {
      _selectedSourceWhs = newWhs;
      // Réinitialisation pour forcer un contrôle strict au prochain scan
      lotDetails = null;
      _lotController.clear();
      _cartonController.clear();
      _calculatedTotalQuantity = 0.0;
    });
  }

  void _fetchData() async {
    if (_lotController.text.isEmpty) return;
    if (_selectedSourceWhs == null) {
      _showStatusSnackBar("Veuillez d'abord sélectionner un magasin source à l'accueil.", isError: true);
      return;
    }

    setState(() => isLoading = true);
    final data = await _sapService.fetchLotData(_lotController.text);

    if (data == null) {
      setState(() => isLoading = false);
      _showStatusSnackBar("Aucun lot correspondant trouvé dans SAP.", isError: true);
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    // 1ère VÉRIFICATION : Correspondance avec le magasin par défaut configuré dans les Paramètres
    String? globalParamWhs = prefs.getString('whsSource');
    if (data.warehouse != null && data.warehouse != globalParamWhs) {
      setState(() => isLoading = false);
      _showStatusSnackBar(
          "Vérification 1 échouée : Ce lot appartient au magasin [${data.warehouse}] et non au magasin Source par défaut des Paramètres [$globalParamWhs].",
          isError: true
      );
      return;
    }

    // 2ème VÉRIFICATION : Correspondance avec le magasin sélectionné sur l'écran d'accueil
    if (data.warehouse != null && data.warehouse != _selectedSourceWhs) {
      setState(() => isLoading = false);
      _showStatusSnackBar(
          "Vérification 2 échouée : Ce lot est localisé dans [${data.warehouse}] et ne correspond pas au choix actuel de l'accueil [$_selectedSourceWhs].",
          isError: true
      );
      return;
    }

    setState(() {
      lotDetails = data;
      _cartonController.text = lotDetails!.qteCarton.toString();

      _quantiteParCarton = lotDetails!.qteCarton > 0
          ? (lotDetails!.totalQuantity / lotDetails!.qteCarton)
          : lotDetails!.totalQuantity;

      _calculatedTotalQuantity = lotDetails!.totalQuantity;
      isLoading = false;
    });
    _showStatusSnackBar("Double validation réussie pour le lot !");
  }

  Future<void> _executerTransfert(String type) async {
    if (lotDetails == null || _calculatedTotalQuantity <= 0) return;
    setState(() => isLoading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      String? sourceWhs = _selectedSourceWhs;
      String? targetWhs = (type == "QUARANTAINE")
          ? prefs.getString('whsQuarantaine')
          : prefs.getString('whsLiberer');

      if (sourceWhs == null || targetWhs == null) {
        _showStatusSnackBar("Configuration manquante : Magasins cibles non définis dans les paramètres.", isError: true);
        setState(() => isLoading = false);
        return;
      }

      String? error = await _sapService.createStockTransfer(
        itemCode: lotDetails!.itemCode,
        batchNumber: lotDetails!.distNumber,
        fromWhs: sourceWhs,
        toWhs: targetWhs,
        quantity: _calculatedTotalQuantity,
      );

      setState(() => isLoading = false);
      if (error == null) {
        _showStatusSnackBar("Transfert de $_calculatedTotalQuantity unités complété vers $targetWhs");

        setState(() {
          double cartonsTransferes = double.tryParse(_cartonController.text) ?? 0;
          double resteCartons = lotDetails!.qteCarton - cartonsTransferes;

          if (resteCartons <= 0) {
            lotDetails = null;
            _lotController.clear();
            _cartonController.clear();
            _calculatedTotalQuantity = 0.0;
          } else {
            lotDetails = lotDetails!.copyWith(qteCarton: resteCartons);
            _cartonController.text = lotDetails!.qteCarton.toStringAsFixed(0);
            _calculatedTotalQuantity = lotDetails!.totalQuantity;
          }
        });
      } else {
        _showStatusSnackBar("Erreur SAP : $error", isError: true);
      }
    } catch (e) {
      setState(() => isLoading = false);
      _showStatusSnackBar("Exception système : $e", isError: true);
    }
  }

  void _updateCalculatedQuantity(String value) {
    if (value.isEmpty) {
      setState(() => _calculatedTotalQuantity = 0.0);
      return;
    }
    final double? packs = double.tryParse(value);
    if (packs != null) {
      setState(() {
        _calculatedTotalQuantity = packs * _quantiteParCarton;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: surfaceLight,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        title: const Text('EMA CHOCOSCAN',
            style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 2, fontSize: 16, color: Colors.white)),
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      drawer: _buildDrawer(),
      body: Column(
        children: [
          _buildPremiumHeader(),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 400),
              child: _buildContent(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (isLoading) {
      return Center(child: CircularProgressIndicator(color: accentIndigo, strokeWidth: 2));
    }
    if (lotDetails != null) {
      return SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 25),
        child: Column(
          children: [
            _buildMainInfoCard(),
            const SizedBox(height: 30),
            _buildActionButtons(),
          ],
        ),
      );
    }
    return _buildEmptyState();
  }

  Widget _buildPremiumHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 95, 20, 30),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [primaryDark, const Color(0xFF1E293B)],
        ),
        borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(50)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Gestion des Flux", style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w500)),
          const SizedBox(height: 4),
          const Text("Identification Lot", style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold)),
          const SizedBox(height: 20),
          _buildWarehouseDropdown(),
          const SizedBox(height: 15),
          _buildSearchBox(),
        ],
      ),
    );
  }

  Widget _buildWarehouseDropdown() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 15),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.white.withOpacity(0.15)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warehouse_rounded, color: Colors.white70, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: _isLoadingWhs
                ? const LinearProgressIndicator(backgroundColor: Colors.transparent, color: Colors.white38)
                : DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedSourceWhs,
                dropdownColor: primaryDark,
                icon: const Icon(Icons.arrow_drop_down_rounded, color: Colors.white),
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
                hint: const Text("Sélectionner magasin d'accueil...", style: TextStyle(color: Colors.white30)),
                isExpanded: true,
                items: _warehouses.map((whs) {
                  return DropdownMenuItem<String>(
                    value: whs['code'],
                    child: Text("[${whs['code']}] ${whs['name']}", overflow: TextOverflow.ellipsis),
                  );
                }).toList(),
                onChanged: _onWarehouseChanged,
              ),
            ),
          ),
          if (!_isLoadingWhs)
            IconButton(
              icon: const Icon(Icons.refresh_rounded, color: Colors.white60, size: 18),
              onPressed: _loadWarehouses,
              visualDensity: VisualDensity.compact,
            )
        ],
      ),
    );
  }

  Widget _buildSearchBox() {
    return Container(
      height: 60,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.2)),
      ),
      child: TextField(
        controller: _lotController,
        onSubmitted: (_) => _fetchData(),
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        decoration: InputDecoration(
          hintText: "Saisir ou scanner un lot...",
          hintStyle: TextStyle(color: Colors.white.withOpacity(0.5), fontWeight: FontWeight.normal),
          prefixIcon: const Icon(Icons.search_rounded, color: Colors.white70),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 20),
          suffixIcon: IconButton(
            icon: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(color: accentIndigo, borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.qr_code_scanner_rounded, color: Colors.white, size: 20),
            ),
            onPressed: () async {
              final res = await Navigator.push(context, MaterialPageRoute(builder: (_) => const ScannerScreen()));
              if (res != null) { _lotController.text = res; _fetchData(); }
            },
          ),
        ),
      ),
    );
  }

  Widget _buildMainInfoCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(30),
        boxShadow: [BoxShadow(color: primaryDark.withOpacity(0.05), blurRadius: 30, offset: const Offset(0, 10))],
      ),
      child: Column(
        children: [
          _buildCardHeader(),
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                _infoTile(Icons.api_rounded, "REFERENCE ARTICLE", lotDetails!.itemCode),
                _infoTile(Icons.layers_rounded, "IDENTIFIANT LOT", lotDetails!.distNumber),
                _editableCartonTile(Icons.inventory_2_outlined, "CONDITIONNEMENT (CARTONS)"),
                const Padding(padding: EdgeInsets.symmetric(vertical: 15), child: Divider(color: Color(0xFFF1F5F9))),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _dateBlock("FABRICATION", lotDetails!.mfrDate ?? "--/--/--"),
                    _dateBlock("EXPIRATION", lotDetails!.expDate ?? "--/--/--"),
                  ],
                ),
                const SizedBox(height: 25),
                _buildQuantityDisplay(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCardHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      decoration: BoxDecoration(
        color: accentIndigo.withOpacity(0.08),
        borderRadius: const BorderRadius.only(topLeft: Radius.circular(30), topRight: Radius.circular(30)),
      ),
      child: Row(
        children: [
          CircleAvatar(backgroundColor: accentIndigo, radius: 18, child: const Icon(Icons.shopping_bag_rounded, size: 18, color: Colors.white)),
          const SizedBox(width: 12),
          Expanded(child: Text(lotDetails!.itemName.toUpperCase(),
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: primaryDark, letterSpacing: 0.5))),
        ],
      ),
    );
  }

  Widget _buildQuantityDisplay() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: primaryDark,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: accentIndigo.withOpacity(0.2), blurRadius: 15, offset: const Offset(0, 5))],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("QUANTITÉ À TRANSFERER", style: TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1)),
              Text("Calcul unitaire", style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500)),
            ],
          ),
          Text(_calculatedTotalQuantity.toStringAsFixed(0),
              style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -1)),
        ],
      ),
    );
  }

  Widget _infoTile(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Icon(icon, size: 20, color: accentIndigo.withOpacity(0.5)),
          const SizedBox(width: 15),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(color: Colors.grey[400], fontWeight: FontWeight.w800, fontSize: 9, letterSpacing: 1)),
              Text(value, style: TextStyle(fontWeight: FontWeight.bold, color: primaryDark, fontSize: 15)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _editableCartonTile(IconData icon, String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Icon(icon, size: 20, color: accentIndigo),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(color: Colors.grey[400], fontWeight: FontWeight.w800, fontSize: 9, letterSpacing: 1)),
                const SizedBox(height: 2),
                SizedBox(
                  height: 40,
                  child: TextField(
                    controller: _cartonController,
                    keyboardType: TextInputType.number,
                    onChanged: _updateCalculatedQuantity,
                    style: TextStyle(fontWeight: FontWeight.bold, color: primaryDark, fontSize: 16),
                    decoration: InputDecoration(
                      contentPadding: const EdgeInsets.symmetric(vertical: 5, horizontal: 10),
                      filled: true,
                      fillColor: surfaceLight,
                      suffixIcon: const Icon(Icons.edit_rounded, size: 16, color: Colors.grey),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.withOpacity(0.2))),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: accentIndigo)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _dateBlock(String label, String date) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 10, color: Colors.grey[400], fontWeight: FontWeight.w900)),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(color: surfaceLight, borderRadius: BorderRadius.circular(8)),
          child: Text(date, style: TextStyle(fontWeight: FontWeight.bold, color: primaryDark, fontSize: 13)),
        ),
      ],
    );
  }

  Widget _buildActionButtons() {
    bool canTransfer = lotDetails != null && _calculatedTotalQuantity > 0;
    return Row(
      children: [
        Expanded(child: _actionBtn("QUARANTAINE", const Color(0xFFF97316), Icons.shield_outlined,
            canTransfer ? () => _executerTransfert("QUARANTAINE") : null)),
        const SizedBox(width: 15),
        Expanded(child: _actionBtn("LIBÉRER", const Color(0xFF10B981), Icons.verified_user_outlined,
            canTransfer ? () => _executerTransfert("LIBERER") : null)),
      ],
    );
  }

  Widget _actionBtn(String label, Color color, IconData icon, VoidCallback? onTap) {
    return Material(
      color: onTap == null ? Colors.grey[200] : color,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Column(
            children: [
              Icon(icon, color: onTap == null ? Colors.grey[400] : Colors.white),
              const SizedBox(height: 8),
              Text(label, style: TextStyle(color: onTap == null ? Colors.grey[500] : Colors.white, fontWeight: FontWeight.w900, fontSize: 11)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(30),
            decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: [BoxShadow(color: primaryDark.withOpacity(0.05), blurRadius: 20)]),
            child: Icon(Icons.document_scanner_outlined, size: 60, color: accentIndigo.withOpacity(0.2)),
          ),
          const SizedBox(height: 25),
          Text("Système prêt pour analyse", style: TextStyle(color: primaryDark, fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text("Veuillez scanner un lot SAP pour commencer", style: TextStyle(color: Colors.grey[500], fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildDrawer() {
    return Drawer(
      backgroundColor: Colors.white,
      child: Column(
        children: [
          Container(
            height: 200,
            width: double.infinity,
            color: primaryDark,
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const CircleAvatar(backgroundColor: Colors.white24, radius: 30, child: Icon(Icons.admin_panel_settings_rounded, color: Colors.white, size: 30)),
                const SizedBox(height: 15),
                const Text("Administrateur EMA", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                Text("v1.2.0 stable", style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12)),
              ],
            ),
          ),
          const SizedBox(height: 20),
          _drawerItem(Icons.settings_suggest_rounded, "Paramètres Système", () {
            Navigator.pop(context);
            _showLoginDialog();
          }),
          const Spacer(),
          const Padding(padding: EdgeInsets.all(20), child: Text("LOGISTIC EXPERT MODE", style: TextStyle(letterSpacing: 2, fontSize: 10, fontWeight: FontWeight.w900, color: Colors.grey))),
        ],
      ),
    );
  }

  Widget _drawerItem(IconData icon, String title, VoidCallback onTap) {
    return ListTile(
      leading: Icon(icon, color: primaryDark),
      title: Text(title, style: TextStyle(fontWeight: FontWeight.w700, color: primaryDark)),
      onTap: onTap,
    );
  }

  void _showStatusSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message, style: const TextStyle(fontWeight: FontWeight.w600)),
      backgroundColor: isError ? Colors.redAccent : accentIndigo,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      margin: const EdgeInsets.all(15),
    ));
  }

  void _showLoginDialog() {
    final u = TextEditingController();
    final p = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
        title: const Text("Authentification Requise", style: TextStyle(fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: u, decoration: const InputDecoration(labelText: "Utilisateur")),
            const SizedBox(height: 10),
            TextField(controller: p, obscureText: true, decoration: const InputDecoration(labelText: "Clé d'accès")),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Annuler")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: primaryDark, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            onPressed: () {
              if (u.text.trim() == "admin" && p.text.trim() == "Bp5@maroc") {
                Navigator.pop(context);
                Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()));
              } else { _showStatusSnackBar("Accès refusé : Identifiants invalides", isError: true); }
            },
            child: const Text("Vérifier", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}