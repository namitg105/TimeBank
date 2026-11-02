import '../models/ledger_models.dart';

abstract interface class LedgerRemoteDataSource {
  Future<List<LedgerEntryModel>> passbook(int studentId);
  Future<AuditModel> audit();
  Future<int> postAdjustment(Map<String, dynamic> body);
  Future<List<String>> leaderboard();
  Future<List<String>> collusion();
}

class LedgerRemoteDataSourceImpl implements LedgerRemoteDataSource {
  final ApiClient client;
  const LedgerRemoteDataSourceImpl(this.client);

  @override
  Future<List<LedgerEntryModel>> passbook(int studentId) async {
    final data = await client.get('/api/ledger/student/$studentId');
    return (data as List)
        .map((e) => LedgerEntryModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<AuditModel> audit() async {
    final data = await client.get('/api/ledger/audit');
    return AuditModel.fromJson(data as Map<String, dynamic>);
  }

  @override
  Future<int> postAdjustment(Map<String, dynamic> body) async {
    final data = await client.post('/api/ledger/adjustments', body: body);
    return ((data as Map)['txnId'] as num).toInt();
  }

  @override
  Future<List<String>> leaderboard() async {
    final data = await client.get('/api/ledger/leaderboard');
    return (data as List).map((e) => e.toString()).toList();
  }

  @override
  Future<List<String>> collusion() async {
    final data = await client.get('/api/ledger/collusion');
    return (data as List).map((e) => e.toString()).toList();
  }
}
