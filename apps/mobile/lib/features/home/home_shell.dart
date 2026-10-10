import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../ui/app_brand.dart';
import '../../ui/app_icons.dart';
import '../../ui/app_tokens.dart';
import '../../ui/theme.dart';
import '../accounts/accounts_tab.dart';
import '../agreements/agreements_tab.dart';
import '../auth/auth_models.dart';
import '../auth/session_controller.dart';
import '../payables/payables_tab.dart';
import '../summary/summary_tab.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;
  String? _agreementsFilter;

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionController>();
    final space = session.activeSpace!;
    final brightness = Theme.of(context).brightness;

    // Cor e conteúdo vinculados ao espaço: a chave descarta todo estado do anterior.
    return Theme(
      data: buildTheme(brightness, seed: seedForSpace(space.isPf)),
      child: Builder(
        builder: (context) {
          return Scaffold(
            appBar: AppBar(
              titleSpacing: AppTokens.p16,
              title: Row(
                children: [
                  const BrandHeader(compact: true),
                  const Spacer(),
                  _SpaceSwitcher(spaces: session.spaces, active: space),
                ],
              ),
              actions: [
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: PopupMenuButton<String>(
                    tooltip: 'Conta',
                    icon: const AppIcon(AppIcons.user, size: 22),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppTokens.r12),
                    ),
                    onSelected: (action) {
                      if (action == 'logout') {
                        _confirmLogout(context, session);
                      }
                    },
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        enabled: false,
                        child: Text(
                          session.user?.email ?? '',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      const PopupMenuDivider(),
                      const PopupMenuItem(
                        value: 'logout',
                        child: Row(
                          children: [
                            AppIcon(AppIcons.logout, size: 18),
                            SizedBox(width: 8),
                            Text('Sair'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            body: KeyedSubtree(
              key: ValueKey('space-${space.id}-tab-$_tab'),
              child: switch (_tab) {
                0 => SummaryTab(
                  space: space,
                  onOpenTab: (tab, {filter}) => setState(() {
                    _tab = tab;
                    if (tab == 1) {
                      _agreementsFilter = filter ?? 'open';
                    }
                  }),
                ),
                1 => AgreementsTab(
                  key: ValueKey(
                    'agreements-tab-${space.id}-$_agreementsFilter',
                  ),
                  space: space,
                  initialFilter: _agreementsFilter ?? 'open',
                ),
                2 => PayablesTab(space: space),
                _ => AccountsTab(space: space),
              },
            ),
            bottomNavigationBar: NavigationBar(
              selectedIndex: _tab,
              onDestinationSelected: (tab) => setState(() {
                _tab = tab;
                if (tab == 1) {
                  _agreementsFilter = 'open';
                }
              }),
              destinations: const [
                NavigationDestination(
                  icon: AppIcon(AppIcons.home, size: 22),
                  selectedIcon: AppIcon(AppIcons.home, size: 22),
                  label: 'Resumo',
                ),
                NavigationDestination(
                  icon: AppIcon(AppIcons.receivables, size: 22),
                  selectedIcon: AppIcon(AppIcons.receivables, size: 22),
                  label: 'A receber',
                ),
                NavigationDestination(
                  icon: AppIcon(AppIcons.payables, size: 22),
                  selectedIcon: AppIcon(AppIcons.payables, size: 22),
                  label: 'A pagar',
                ),
                NavigationDestination(
                  icon: AppIcon(AppIcons.accounts, size: 22),
                  selectedIcon: AppIcon(AppIcons.accounts, size: 22),
                  label: 'Contas',
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _confirmLogout(BuildContext context, SessionController session) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Confirmar saída'),
        content: const Text('Deseja realmente sair da sua conta?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              session.logout();
            },
            child: const Text('Sair'),
          ),
        ],
      ),
    );
  }
}

class _SpaceSwitcher extends StatelessWidget {
  const _SpaceSwitcher({required this.spaces, required this.active});

  final List<Space> spaces;
  final Space active;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<int>(
      showSelectedIcon: false,
      style: const ButtonStyle(
        visualDensity: VisualDensity.compact,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      segments: [
        for (final space in spaces)
          ButtonSegment(
            value: space.id,
            icon: AppIcon(
              space.isPf ? AppIcons.user : AppIcons.business,
              size: 15,
            ),
            label: Text(
              space.kind,
              semanticsLabel: space.label,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            ),
          ),
      ],
      selected: {active.id},
      onSelectionChanged: (selection) =>
          context.read<SessionController>().selectSpace(
            spaces.firstWhere((space) => space.id == selection.first),
          ),
    );
  }
}
