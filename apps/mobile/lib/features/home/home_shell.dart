import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../ui/theme.dart';
import '../accounts/account_form_screen.dart';
import '../accounts/accounts_tab.dart';
import '../agreements/agreement_form_screen.dart';
import '../agreements/agreements_tab.dart';
import '../auth/auth_models.dart';
import '../auth/session_controller.dart';
import '../summary/summary_tab.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionController>();
    final space = session.activeSpace!;
    final brightness = Theme.of(context).brightness;

    // Cor e conteúdo vinculados ao espaço: a chave descarta todo estado do anterior.
    return Theme(
      data: buildTheme(brightness, seed: seedForSpace(space.isPf)),
      child: Builder(builder: (context) {
        return Scaffold(
          appBar: AppBar(
            titleSpacing: 16,
            title: _SpaceSwitcher(spaces: session.spaces, active: space),
            actions: [
              PopupMenuButton<String>(
                tooltip: 'Conta',
                icon: const Icon(Icons.account_circle_outlined),
                onSelected: (_) => session.logout(),
                itemBuilder: (_) => [
                  PopupMenuItem(enabled: false, child: Text(session.user?.email ?? '')),
                  const PopupMenuItem(value: 'logout', child: Text('Sair')),
                ],
              ),
            ],
          ),
          body: KeyedSubtree(
            key: ValueKey('space-${space.id}-tab-$_tab'),
            child: switch (_tab) {
              0 => SummaryTab(space: space, onOpenTab: (tab) => setState(() => _tab = tab)),
              1 => AgreementsTab(space: space),
              _ => AccountsTab(space: space),
            },
          ),
          floatingActionButton: switch (_tab) {
            1 => FloatingActionButton.extended(
                onPressed: () => Navigator.of(context).push(spaceRoute(isPf: space.isPf, child: AgreementFormScreen(space: space))),
                icon: const Icon(Icons.add),
                label: const Text('Novo acordo'),
              ),
            2 => FloatingActionButton.extended(
                onPressed: () => Navigator.of(context).push(spaceRoute(isPf: space.isPf, child: AccountFormScreen(space: space))),
                icon: const Icon(Icons.add),
                label: const Text('Nova conta'),
              ),
            _ => null,
          },
          bottomNavigationBar: NavigationBar(
            selectedIndex: _tab,
            onDestinationSelected: (tab) => setState(() => _tab = tab),
            destinations: const [
              NavigationDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard), label: 'Resumo'),
              NavigationDestination(icon: Icon(Icons.handshake_outlined), selectedIcon: Icon(Icons.handshake), label: 'A receber'),
              NavigationDestination(icon: Icon(Icons.account_balance_outlined), selectedIcon: Icon(Icons.account_balance), label: 'Contas'),
            ],
          ),
        );
      }),
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
      style: const ButtonStyle(visualDensity: VisualDensity.compact),
      segments: [
        for (final space in spaces)
          ButtonSegment(
            value: space.id,
            icon: Icon(space.isPf ? Icons.person_outline : Icons.business_outlined),
            label: Text(space.kind, semanticsLabel: space.label),
          ),
      ],
      selected: {active.id},
      onSelectionChanged: (selection) =>
          context.read<SessionController>().selectSpace(spaces.firstWhere((space) => space.id == selection.first)),
    );
  }
}
