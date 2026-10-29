import 'package:equatable/equatable.dart';

/// The closed-economy audit.
///
///     sum of all balances  +  credits held in escrow
///                =  total granted  -  total penalised
///
/// Every session writes one HOLD and one TRANSFER that cancel out, so
/// the only things that can move the total are a new starter grant or a
/// penalty. Any drift means credits were created or destroyed outside
/// the ledger, which should be impossible.
class Audit extends Equatable {
  final double balances;
  final double escrow;
  final double grantsLessPenalties;
  final double drift;
  final bool balanced;

  const Audit({
    required this.balances,
    required this.escrow,
    required this.grantsLessPenalties,
    required this.drift,
    required this.balanced,
  });

  @override
  List<Object?> get props => [balances, escrow, grantsLessPenalties, drift];
}
