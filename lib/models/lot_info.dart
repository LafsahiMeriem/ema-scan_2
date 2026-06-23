class LotInfo {
  final String itemCode;
  final String itemName;
  final String distNumber;
  final double qteCarton;
  final double numInCnt;
  final String? mfrDate;
  final String? expDate;
  final String? mfrSerial;
  final String? docDate;
  final String? warehouse; // Récupération du magasin depuis SAP

  LotInfo({
    required this.itemCode,
    required this.itemName,
    required this.distNumber,
    required this.qteCarton,
    required this.numInCnt,


    this.mfrDate,
    this.expDate,
    this.mfrSerial,
    this.docDate,
    this.warehouse,
  });

  factory LotInfo.fromJson(Map<String, dynamic> json) {
    String name = json['ItemDescription'] ?? json['ItemName'] ?? '';
    double extractedNumInCnt = 1.0;

    try {
      final regExp = RegExp(r'(\d+)UN');
      final match = regExp.firstMatch(name);
      if (match != null) {
        extractedNumInCnt = double.parse(match.group(1)!);
      }
    } catch (e) {
      print("Erreur extraction NumInCnt: $e");
    }

    return LotInfo(
      itemCode: json['ItemCode'] ?? '',
      itemName: name,
      distNumber: json['Batch'] ?? json['BatchNumber'] ?? json['DistNumber'] ?? '',
      qteCarton: (json['U_U_QteCarton'] ?? json['Quantity'] ?? 0).toDouble(),
      numInCnt: extractedNumInCnt,
      warehouse: json['WhsCode'] ?? json['WarehouseCode'] ?? json['Warehouse'], // Récupère le code magasin

      mfrDate: (json['ManufacturingDate'] != null)
          ? json['ManufacturingDate'].toString().split('T')[0]
          : (json['AdmissionDate'] != null ? json['AdmissionDate'].toString().split('T')[0] : "-"),

      expDate: json['ExpirationDate']?.toString().split('T')[0],
      mfrSerial: json['BatchAttribute1'] ?? "-",
      docDate: json['AdmissionDate']?.toString().split('T')[0],
    );
  }

  // totalQuantity est calculé dynamiquement à partir de qteCarton
  double get totalQuantity => (qteCarton * numInCnt).roundToDouble();

  LotInfo copyWith({
    String? itemCode,
    String? itemName,
    String? distNumber,
    double? qteCarton,
    double? numInCnt,
    String? mfrDate,
    String? expDate,
    String? mfrSerial,
    String? docDate,
    String? warehouse,
  }) {
    return LotInfo(
      itemCode: itemCode ?? this.itemCode,
      itemName: itemName ?? this.itemName,
      distNumber: distNumber ?? this.distNumber,
      qteCarton: qteCarton ?? this.qteCarton,
      numInCnt: numInCnt ?? this.numInCnt,
      mfrDate: mfrDate ?? this.mfrDate,
      expDate: expDate ?? this.expDate,
      mfrSerial: mfrSerial ?? this.mfrSerial,
      docDate: docDate ?? this.docDate,
      warehouse: warehouse ?? this.warehouse,
    );
  }
}