import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

/// Ícones do BigDev.Z Finance centralizados com Hugeicons Free (Stroke Rounded).
/// Atribuição e licença: Hugeicons Free (https://hugeicons.com).
class AppIcons {
  const AppIcons._();

  // Navegação principal
  static const List<List<dynamic>> home = HugeIcons.strokeRoundedHome01;
  static const List<List<dynamic>> receivables = HugeIcons.strokeRoundedCoins01;
  static const List<List<dynamic>> payables = HugeIcons.strokeRoundedInvoice01;
  static const List<List<dynamic>> accounts = HugeIcons.strokeRoundedBuilding03;

  // Ações e navegação comum
  static const List<List<dynamic>> add = HugeIcons.strokeRoundedAdd01;
  static const List<List<dynamic>> back = HugeIcons.strokeRoundedArrowLeft01;
  static const List<List<dynamic>> forward =
      HugeIcons.strokeRoundedArrowRight01;
  static const List<List<dynamic>> check =
      HugeIcons.strokeRoundedCheckmarkCircle02;
  static const List<List<dynamic>> alert = HugeIcons.strokeRoundedAlertCircle;
  static const List<List<dynamic>> error = HugeIcons.strokeRoundedCancelCircle;
  static const List<List<dynamic>> info =
      HugeIcons.strokeRoundedInformationCircle;
  static const List<List<dynamic>> edit = HugeIcons.strokeRoundedEdit02;
  static const List<List<dynamic>> delete = HugeIcons.strokeRoundedDelete02;
  static const List<List<dynamic>> more = HugeIcons.strokeRoundedMoreHorizontal;
  static const List<List<dynamic>> refresh = HugeIcons.strokeRoundedRefresh;
  static const List<List<dynamic>> calendar = HugeIcons.strokeRoundedCalendar03;
  static const List<List<dynamic>> clock = HugeIcons.strokeRoundedClock01;
  static const List<List<dynamic>> filter = HugeIcons.strokeRoundedFilter;
  static const List<List<dynamic>> search = HugeIcons.strokeRoundedSearch01;

  // Recursos financeiros
  static const List<List<dynamic>> wallet = HugeIcons.strokeRoundedWallet01;
  static const List<List<dynamic>> card = HugeIcons.strokeRoundedCreditCard;
  static const List<List<dynamic>> cash = HugeIcons.strokeRoundedMoney03;
  static const List<List<dynamic>> receipt = HugeIcons.strokeRoundedReceipt;
  static const List<List<dynamic>> recurrence = HugeIcons.strokeRoundedRepeat;
  static const List<List<dynamic>> archive = HugeIcons.strokeRoundedArchive;
  static const List<List<dynamic>> unarchive =
      HugeIcons.strokeRoundedPackageProcess;
  static const List<List<dynamic>> reverse = HugeIcons.strokeRoundedExchange01;
  static const List<List<dynamic>> correction =
      HugeIcons.strokeRoundedArrowTurnBackward;
  static const List<List<dynamic>> lock = HugeIcons.strokeRoundedLockPassword;
  static const List<List<dynamic>> pending = HugeIcons.strokeRoundedHourglass;

  // Espaços e usuário
  static const List<List<dynamic>> user = HugeIcons.strokeRoundedUser;
  static const List<List<dynamic>> business = HugeIcons.strokeRoundedBuilding04;
  static const List<List<dynamic>> logout = HugeIcons.strokeRoundedLogout01;
}

/// Widget padronizado para renderizar ícones do app com Hugeicons.
class AppIcon extends StatelessWidget {
  const AppIcon(this.icon, {super.key, this.size = 22, this.color});

  final List<List<dynamic>> icon;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return HugeIcon(
      icon: icon,
      size: size,
      color:
          color ??
          IconTheme.of(context).color ??
          Theme.of(context).colorScheme.onSurface,
    );
  }
}
