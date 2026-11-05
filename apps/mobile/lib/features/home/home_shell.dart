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
import '../loans/loans_screen.dart';
import '../payables/payables_tab.dart';
import '../settings/preferences_controller.dart';
import '../settings/settings_screen.dart';
import '../statement/statement_tab.dart';
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
    final preferences = context.watch<PreferencesController?>();
    final space = session.activeSpace!;
    final platformBrightness = MediaQuery.platformBrightnessOf(context);
    final isDark = switch (preferences?.themeMode ?? ThemeMode.system) {
      ThemeMode.system => platformBrightness == Brightness.dark,
      ThemeMode.dark => true,
      ThemeMode.light => false,
    };
    final brightness = isDark ? Brightness.dark : Brightness.light;
    final isDesktop = MediaQuery.sizeOf(context).width >= 840;

    final bodyContent = KeyedSubtree(
      key: ValueKey('space-${space.id}-tab-$_tab'),
      child: switch (_tab) {
        0 => SummaryTab(
          space: space,
          onOpenTab: (tab, {filter}) => setState(() {
            _tab = switch (tab) {
              1 => 2, // A receber
              2 => 3, // A pagar
              3 => 4, // Contas
              _ => tab,
            };
            if (tab == 1) {
              _agreementsFilter = filter ?? 'open';
            }
          }),
        ),
        1 => StatementTab(
          key: ValueKey('statement-tab-${space.id}'),
          space: space,
        ),
        2 => AgreementsTab(
          key: ValueKey('agreements-tab-${space.id}-$_agreementsFilter'),
          space: space,
          initialFilter: _agreementsFilter ?? 'open',
        ),
        3 => PayablesTab(space: space),
        _ => AccountsTab(space: space),
      },
    );

    // Cor e conteúdo vinculados ao espaço: a chave descarta todo estado do anterior.
    return Theme(
      data: buildTheme(brightness, seed: seedForSpace(space.isPf)),
      child: Builder(
        builder: (context) {
          if (isDesktop) {
            return Scaffold(
              body: Row(
                children: [
                  _DesktopSidebar(
                    space: space,
                    session: session,
                    selectedIndex: _tab,
                    onDestinationSelected: (tab) => setState(() {
                      _tab = tab;
                      if (tab == 2) {
                        _agreementsFilter = 'open';
                      }
                    }),
                    onOpenLoans: () {
                      Navigator.of(context).push(
                        spaceRoute(
                          isPf: space.isPf,
                          child: LoansScreen(space: space),
                        ),
                      );
                    },
                    onOpenSettings: () {
                      Navigator.of(context).push(
                        spaceRoute(
                          isPf: space.isPf,
                          child: const SettingsScreen(),
                        ),
                      );
                    },
                    onLogout: () => _confirmLogout(context, session),
                  ),
                  const VerticalDivider(width: 1, thickness: 1),
                  Expanded(
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1200),
                        child: bodyContent,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }

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
                      if (action == 'settings') {
                        Navigator.of(context).push(
                          spaceRoute(
                            isPf: space.isPf,
                            child: const SettingsScreen(),
                          ),
                        );
                      } else if (action == 'logout') {
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
                        value: 'settings',
                        child: Row(
                          children: [
                            AppIcon(AppIcons.settings, size: 18),
                            SizedBox(width: 8),
                            Text('Configurações'),
                          ],
                        ),
                      ),
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
            body: bodyContent,
            bottomNavigationBar: NavigationBar(
              selectedIndex: _tab,
              onDestinationSelected: (tab) => setState(() {
                _tab = tab;
                if (tab == 2) {
                  _agreementsFilter = 'open';
                }
              }),
              destinations: const [
                NavigationDestination(
                  icon: AppIcon(AppIcons.home, size: 22),
                  selectedIcon: AppIcon(AppIcons.home, size: 22),
                  label: 'Dashboard',
                ),
                NavigationDestination(
                  icon: AppIcon(AppIcons.receipt, size: 22),
                  selectedIcon: AppIcon(AppIcons.receipt, size: 22),
                  label: 'Extrato',
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

class _DesktopSidebar extends StatelessWidget {
  const _DesktopSidebar({
    required this.space,
    required this.session,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.onOpenLoans,
    required this.onOpenSettings,
    required this.onLogout,
  });

  final Space space;
  final SessionController session;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final VoidCallback onOpenLoans;
  final VoidCallback onOpenSettings;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: theme.colorScheme.surface,
      child: SizedBox(
        width: 250,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(
                AppTokens.p16,
                AppTokens.p20,
                AppTokens.p16,
                AppTokens.p12,
              ),
              child: BrandHeader(compact: false),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppTokens.p16,
                vertical: AppTokens.p8,
              ),
              child: _SpaceSwitcher(spaces: session.spaces, active: space),
            ),
            const SizedBox(height: AppTokens.p12),
            const Divider(height: 1),
            const SizedBox(height: AppTokens.p12),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: AppTokens.p8),
                children: [
                  _SidebarNavTile(
                    icon: AppIcons.home,
                    label: 'Dashboard',
                    selected: selectedIndex == 0,
                    onTap: () => onDestinationSelected(0),
                  ),
                  _SidebarNavTile(
                    icon: AppIcons.receipt,
                    label: 'Extrato',
                    selected: selectedIndex == 1,
                    onTap: () => onDestinationSelected(1),
                  ),
                  _SidebarNavTile(
                    icon: AppIcons.receivables,
                    label: 'A receber',
                    selected: selectedIndex == 2,
                    onTap: () => onDestinationSelected(2),
                  ),
                  _SidebarNavTile(
                    icon: AppIcons.payables,
                    label: 'A pagar',
                    selected: selectedIndex == 3,
                    onTap: () => onDestinationSelected(3),
                  ),
                  _SidebarNavTile(
                    icon: AppIcons.accounts,
                    label: 'Contas',
                    selected: selectedIndex == 4,
                    onTap: () => onDestinationSelected(4),
                  ),
                  const SizedBox(height: AppTokens.p8),
                  const Divider(height: 1),
                  const SizedBox(height: AppTokens.p8),
                  _SidebarNavTile(
                    icon: AppIcons.loan,
                    label: 'Empréstimos',
                    selected: false,
                    onTap: onOpenLoans,
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(AppTokens.p12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _SidebarNavTile(
                    icon: AppIcons.settings,
                    label: 'Configurações',
                    selected: false,
                    onTap: onOpenSettings,
                  ),
                  const SizedBox(height: AppTokens.p4),
                  Material(
                    color: Colors.transparent,
                    child: ListTile(
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: AppTokens.p8,
                      ),
                      leading: const AppIcon(AppIcons.user, size: 20),
                      title: Text(
                        session.user?.email ?? '',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: IconButton(
                        tooltip: 'Sair',
                        icon: const AppIcon(AppIcons.logout, size: 18),
                        onPressed: onLogout,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SidebarNavTile extends StatelessWidget {
  const _SidebarNavTile({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final List<List<dynamic>> icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = selected
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurfaceVariant;

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: selected
            ? theme.colorScheme.primaryContainer.withValues(alpha: 0.4)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(AppTokens.r8),
        child: ListTile(
          dense: true,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTokens.r8),
          ),
          leading: AppIcon(icon, size: 20, color: color),
          title: Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: color,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
          selected: selected,
          onTap: onTap,
        ),
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
