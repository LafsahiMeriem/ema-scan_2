import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../models/lot_info.dart';

// Bypass SSL pour les certificats auto-signés
class MyHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback = (X509Certificate cert, String host, int port) => true;
  }
}

class SapService {
  final String baseUrl = "https://EMA.bpsMaroc.com:50000/b1s/v1";
  String? sessionId;

  // 1. Connexion à SAP
  Future<bool> login() async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/Login'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "CompanyDB": "DB_APP_WEB_HK",
          "UserName": "manager",
          "Password": "20@Y0ur20"
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        sessionId = data['SessionId'];
        print("✅ Connexion réussie ! SessionId: $sessionId");
        return true;
      } else {
        print("❌ Échec de connexion : ${response.body}");
        return false;
      }
    } catch (e) {
      print("❌ Erreur réseau Login : $e");
      return false;
    }
  }

  // 2. Récupérer tous les magasins (avec pagination)
  Future<List<Map<String, String>>> fetchAllWarehouses() async {
    if (sessionId == null) await login();

    List<Map<String, String>> whsList = [];
    String? nextUrl = "$baseUrl/Warehouses?\$select=WarehouseCode,WarehouseName&\$top=100";

    try {
      while (nextUrl != null) {
        final response = await http.get(
          Uri.parse(nextUrl),
          headers: {
            "Cookie": "B1SESSION=$sessionId",
            "Content-Type": "application/json",
            "B1S-PageSize": "500",
          },
        );

        if (response.statusCode != 200) {
          print("Erreur API: ${response.statusCode} - ${response.body}");
          break;
        }

        final data = jsonDecode(response.body);
        final List<dynamic> values = data['value'] ?? [];

        for (var item in values) {
          whsList.add({
            'code': item['WarehouseCode']?.toString() ?? '',
            'name': item['WarehouseName']?.toString() ?? '',
          });
        }

        if (data['@odata.nextLink'] != null) {
          String nextPath = data['@odata.nextLink'];
          if (nextPath.startsWith('/')) {
            nextPath = nextPath.substring(1);
          }
          nextUrl = nextPath.startsWith('http') ? nextPath : "$baseUrl/$nextPath";
        } else {
          nextUrl = null;
        }
      }

      whsList.sort((a, b) => a['code']!.compareTo(b['code']!));
      return whsList;
    } catch (e) {
      print("Error fetching warehouses: $e");
      return whsList;
    }
  }

  // 3. Récupérer tous les lots de manière globale
  Future<List<Map<String, dynamic>>> fetchAllLotsGlobal() async {
    if (sessionId == null) await login();
    List<Map<String, dynamic>> allLots = [];
    String? nextUrl = "$baseUrl/BatchNumberDetails?\$top=500";

    try {
      while (nextUrl != null) {
        final response = await http.get(
          Uri.parse(nextUrl),
          headers: {
            "Cookie": "B1SESSION=$sessionId",
            "Content-Type": "application/json",
            "Prefer": "odata.maxpagesize=500",
          },
        );

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          final List<dynamic> values = data['value'] ?? [];

          if (values.isNotEmpty) {
            print("NOMS DES COLONNES SAP REÇUES : ${values[0].keys.toList()}");
          }

          final currentPageLots = values.map((item) {
            var rawQty = item['Quantity'] ?? item['TotalInStock'] ?? item['InStock'] ?? item['Available'] ?? '0';
            return {
              'itemCode': item['ItemCode']?.toString() ?? '',
              'itemName': item['ItemDescription']?.toString() ?? 'Sans nom',
              'distNumber': (item['Batch'] ?? item['BatchNumber'] ?? item['DistNumber'] ?? 'N/A').toString(),
              'warehouse': (item['WhsCode'] ?? item['WarehouseCode'] ?? item['Warehouse'] ?? 'N/A').toString(),
              'quantity': (item['Quantity'] ?? item['quantity'] ?? rawQty ?? 0).toString(),
              'expDate': item['ExpirationDate']?.toString()?.split('T')[0] ?? '-',
              'mfrDate': item['ManufacturingDate']?.toString()?.split('T')[0] ?? '-',
            };
          }).toList();

          allLots.addAll(currentPageLots);

          if (data['@odata.nextLink'] != null) {
            String nextPath = data['@odata.nextLink'];
            nextUrl = nextPath.startsWith('http') ? nextPath : "$baseUrl/$nextPath";
          } else {
            nextUrl = null;
          }
        } else {
          break;
        }
      }

      print("Affichage de ${allLots.length} lots sans filtrage.");
      return allLots;
    } catch (e) {
      print("❌ Erreur fetchAllLotsGlobal : $e");
      return [];
    }
  }

  // 4. Récupérer les lots par magasin (Filtre la liste globale)
  Future<List<Map<String, dynamic>>> fetchLotsByWarehouse(String whsCode) async {
    final allLots = await fetchAllLotsGlobal();
    return allLots.where((lot) => lot['warehouse'] == whsCode).toList();
  }

  // 5. Recherche d'un lot spécifique (Scan)
  Future<LotInfo?> fetchLotData(String scanCode) async {
    if (sessionId == null) await login();
    try {
      final String url = "$baseUrl/BatchNumberDetails?\$filter=Batch eq '${scanCode.trim()}'";
      final response = await http.get(
        Uri.parse(url),
        headers: {"Cookie": "B1SESSION=$sessionId", "Content-Type": "application/json"},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['value'] != null && data['value'].isNotEmpty) {
          return LotInfo.fromJson(data['value'][0]);
        }
      }
    } catch (e) {
      print("❌ Erreur fetchLotData : $e");
    }
    return null;
  }

  // 6. Création du transfert de stock de Lot (StockTransfers)
  // 6. Création du transfert de stock de Lot (StockTransfers)
  // 6. Création du transfert de stock de Lot (StockTransfers)
  Future<String?> createStockTransfer({
    required String itemCode,
    required String batchNumber,
    required String fromWhs,
    required String toWhs,
    required double quantity,
  }) async {
    if (sessionId == null) {
      bool isLoggedIn = await login();
      if (!isLoggedIn) return "Échec d'authentification SAP.";
    }

    try {
      // Construction du JSON corrigé (Sans le WarehouseCode dans BatchNumbers)
      final Map<String, dynamic> payload = {
        "FromWarehouse": fromWhs,
        "ToWarehouse": toWhs,
        "StockTransferLines": [
          {
            "ItemCode": itemCode,
            "Quantity": quantity,
            "FromWarehouseCode": fromWhs,
            "WarehouseCode": toWhs,
            "BatchNumbers": [
              {
                "BatchNumber": batchNumber,
                "Quantity": quantity, // 👈 Seul ce champ et BatchNumber sont valides ici
              }
            ],
            // 💡 SI VOTRE MAGASIN GÈRE LES EMPLACEMENTS (BINS) :
            // Vous devez décommenter la section ci-dessous et y passer l'ID de l'emplacement (AbsEntry).
            /*
            "StockTransferLinesBinAllocations": [
              {
                "BinAbsEntry": 12, // 👈 Remplacer par l'ID de l'emplacement système SAP d'où sort le chocolat
                "Quantity": quantity,
                "BaseLineNumber": 0,
                "BinActionType": "batFromWarehouse" // Indique que l'on sort de cet emplacement
              }
            ]
            */
          }
        ]
      };

      print("Sending Corrected Payload to SAP: ${jsonEncode(payload)}");

      final response = await http.post(
        Uri.parse('$baseUrl/StockTransfers'),
        headers: {
          "Cookie": "B1SESSION=$sessionId",
          "Content-Type": "application/json",
        },
        body: jsonEncode(payload),
      );

      if (response.statusCode == 201 || response.statusCode == 200) {
        print("✅ Transfert SAP réussi avec succès.");
        return null;
      } else {
        final errorData = jsonDecode(response.body);
        String sapErrorMessage = errorData['error']?['message']?['value'] ?? response.body;
        print("❌ Erreur SAP Service Layer: $sapErrorMessage");
        return sapErrorMessage;
      }
    } catch (e) {
      print("❌ Exception lors du transfert: $e");
      return "Exception réseau: $e";
    }
  }

  // 7. Lier l'article au magasin de destination (Obligatoire SAP)
  Future<bool> lierArticleAuMagasin(String itemCode, String toWhs) async {
    if (sessionId == null) await login();
    try {
      final response = await http.patch(
        Uri.parse('$baseUrl/Items(\'$itemCode\')'),
        headers: {"Cookie": "B1SESSION=$sessionId", "Content-Type": "application/json"},
        body: jsonEncode({
          "ItemWarehouseInfoCollection": [{"WarehouseCode": toWhs}]
        }),
      );
      return response.statusCode == 204 || response.statusCode == 200;
    } catch (e) {
      print("❌ Erreur lierArticleAuMagasin : $e");
      return false;
    }
  }
} // Fin finale de la classe SapService