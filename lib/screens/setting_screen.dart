import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/sap_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final SapService _sapService = SapService();
  List<Map<String, String>> allWarehouses = [];

  String? whsSource;
  String? whsQuarantaine;
  String? whsLiberer;
  bool isLoading = false;

  final Color primaryDark = const Color(0xFF0F172A);
  final Color accentIndigo = const Color(0xFF6366F1);
  final Color surfaceLight = const Color(0xFFF8FAFC);

  @override
  void initState() {
    super.initState();
    _loadAllData();
  }

  Future<void> _loadAllData() async {
    final prefs = await SharedPreferences.getInstance();
    String? savedWhsJson = prefs.getString('all_warehouses_list');

    setState(() {
      whsSource = prefs.getString('whsSource');
      whsQuarantaine = prefs.getString('whsQuarantaine');
      whsLiberer = prefs.getString('whsLiberer');

      if (savedWhsJson != null) {
        List<dynamic> decoded = jsonDecode(savedWhsJson);
        allWarehouses = decoded.map((item) => Map<String, String>.from(item)).toList();
      }
    });
  }

  Future<void> _getDataFromSap() async {
    setState(() => isLoading = true);
    try {
      final list = await _sapService.fetchAllWarehouses();
      if (list.isNotEmpty) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('all_warehouses_list', jsonEncode(list));
        setState(() {
          allWarehouses = list;
          isLoading = false;
        });
        _showSnackBar("Données SAP synchronisées", Colors.green);
      } else {
        setState(() => isLoading = false);
        _showSnackBar("Aucun magasin trouvé", Colors.orange);
      }
    } catch (e) {
      setState(() => isLoading = false);
      _showSnackBar("Erreur de connexion SAP", Colors.red);
    }
  }

  Future<void> _applyAndExit() async {
    final prefs = await SharedPreferences.getInstance();
    if (whsSource != null) await prefs.setString('whsSource', whsSource!);
    if (whsQuarantaine != null) await prefs.setString('whsQuarantaine', whsQuarantaine!);
    if (whsLiberer != null) await prefs.setString('whsLiberer', whsLiberer!);

    if (mounted) {
      _showSnackBar("Configuration enregistrée", accentIndigo);
      Navigator.pop(context);
    }
  }

  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: color, behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: surfaceLight,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: primaryDark,
        title: const Text('CONFIGURATION SYSTÈME',
            style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.5, fontSize: 14, color: Colors.white)),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        children: [
          _buildHeaderStatus(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSectionTitle("FLUX LOGISTIQUE SAP"),
                  const SizedBox(height: 16),
                  _buildConfigCard(),
                  const SizedBox(height: 30),
                  if (isLoading)
                    const Center(child: Padding(
                      padding: EdgeInsets.all(20.0),
                      child: CircularProgressIndicator(),
                    ))
                  else
                    _buildSyncButton(),


                  const SizedBox(height: 12),
                  _buildApplyButton(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderStatus() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 24),
      color: primaryDark,
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.settings_input_component_rounded, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 16),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Mappage des Magasins", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
              Text("Définissez les terminaux de transfert", style: TextStyle(color: Colors.white54, fontSize: 12)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: TextStyle(color: primaryDark.withOpacity(0.4), fontWeight: FontWeight.w900, fontSize: 11, letterSpacing: 1.2),
    );
  }

  Widget _buildConfigCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(25),
        boxShadow: [BoxShadow(color: primaryDark.withOpacity(0.05), blurRadius: 30, offset: const Offset(0, 10))],
      ),
      child: Column(
        children: [
          _buildDropdownField(
            label: "Magasin Source (Stock)",
            currentValue: whsSource,
            icon: Icons.source_rounded,
            color: accentIndigo,
            onChanged: (val) => setState(() => whsSource = val),
          ),
          const Divider(height: 1, indent: 60, color: Color(0xFFF1F5F9)),
          _buildDropdownField(
            label: "Magasin Quarantaine",
            currentValue: whsQuarantaine,
            icon: Icons.lock_clock_rounded,
            color: Colors.orange[700]!,
            onChanged: (val) => setState(() => whsQuarantaine = val),
          ),
          const Divider(height: 1, indent: 60, color: Color(0xFFF1F5F9)),
          _buildDropdownField(
            label: "Magasin de Sortie (Libéré)",
            currentValue: whsLiberer,
            icon: Icons.check_circle_outline_rounded,
            color: const Color(0xFF10B981),
            onChanged: (val) => setState(() => whsLiberer = val),
          ),
        ],
      ),
    );
  }

  Widget _buildDropdownField({
    required String label,
    required String? currentValue,
    required IconData icon,
    required Color color,
    required Function(String?) onChanged,
  }) {
    bool valueExists = allWarehouses.any((w) => w['code'] == currentValue);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(color: Colors.grey[500], fontSize: 10, fontWeight: FontWeight.w800)),
                DropdownButtonFormField<String>(
                  value: valueExists ? currentValue : null,
                  isExpanded: true,
                  icon: Icon(Icons.keyboard_arrow_down_rounded, color: primaryDark.withOpacity(0.3)),
                  decoration: const InputDecoration(border: InputBorder.none, isDense: true),
                  style: TextStyle(color: primaryDark, fontWeight: FontWeight.bold, fontSize: 15),
                  hint: Text("Choisir...", style: TextStyle(color: Colors.grey[300], fontSize: 14)),
                  items: allWarehouses.map((w) => DropdownMenuItem(
                    value: w['code'],
                    child: Text("${w['code']} - ${w['name']}", overflow: TextOverflow.ellipsis),
                  )).toList(),
                  onChanged: onChanged,
                  selectedItemBuilder: (context) {
                    return allWarehouses.map((w) => Text(
                      "${w['code']} - ${w['name']}",
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: primaryDark, fontWeight: FontWeight.bold),
                    )).toList();
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSyncButton() {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: isLoading ? null : _getDataFromSap,
        icon: const Icon(Icons.sync_rounded, size: 18),
        label: const Text("METTRE À JOUR DEPUIS SAP",
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12, letterSpacing: 1)),
        style: OutlinedButton.styleFrom(
          foregroundColor: accentIndigo,
          side: BorderSide(color: accentIndigo.withOpacity(0.5)),
          padding: const EdgeInsets.symmetric(vertical: 15),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        ),
      ),
    );
  }

  Widget _buildApplyButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: _applyAndExit,
        icon: const Icon(Icons.check_circle_outline_rounded, size: 20),
        label: const Text("APPLIQUER LA CONFIGURATION",
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13, letterSpacing: 1)),
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryDark,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 20),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          elevation: 4,
        ),
      ),
    );
  }
}