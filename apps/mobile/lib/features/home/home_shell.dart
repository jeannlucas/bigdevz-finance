import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../ui/app_brand.dart';
import '../../ui/app_icons.dart';
import '../../ui/app_tokens.dart';
import '../../ui/theme.dart';
import '../accounts/accounts_tab.dart';
import '../agreements/agreements_tab.dart';
import '../auth/auth_models.dart';
import '../auth/profile_edit_dialog.dart';
import '../auth/session_controller.dart';
import '../categories/categories_screen.dart';
import '../loans/loans_screen.dart';
import '../payables/payables_tab.dart';
import '../settings/preferences_controller.dart';
import '../settings/settings_screen.dart';
import '../statement/statement_tab.dart';
import '../summary/summary.dart';
import '../summary/summary_tab.dart';
import 'notifications_modal.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;
  String? _agreementsFilter;
  String? _payablesFilter;
  SpaceSummary? _summary;
  int? _lastDataVersion;
  int? _lastSpaceId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final session = context.watch<SessionController>();
    if (_lastDataVersion != session.dataVersion ||
        _lastSpaceId != session.activeSpace?.id) {
      _lastDataVersion = session.dataVersion;
      _lastSpaceId = session.activeSpace?.id;
      _refreshSummary();
    }
  }

  Future<void> _refreshSummary() async {
    final session = context.read<SessionController>();
    final space = session.activeSpace;
    if (space == null) return;
    try {
      final summary = await context.read<SummaryRepository>().load(space.id);
      if (mounted) {
        setState(() => _summary = summary);
      }
    } catch (_) {
      // Falha silenciosa
    }
  }

  void _handleNavigation(int tab, {String? filter}) {
    setState(() {
      _tab = tab;
      if (tab == 2) {
        _agreementsFilter = filter ?? 'open';
      } else if (tab == 3) {
        _payablesFilter = filter ?? 'open';
      }
    });
  }

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
            } else if (tab == 2) {
              _payablesFilter = filter ?? 'open';
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
        3 => PayablesTab(
          key: ValueKey('payables-tab-${space.id}-$_payablesFilter'),
          space: space,
          initialFilter: _payablesFilter ?? 'open',
        ),
        _ => AccountsTab(space: space),
      },
    );

    final notificationCount =
        (_summary?.payables.overdueCount ?? 0) +
        (_summary?.overdueInstallments ?? 0) +
        ((_summary?.payables.awaitingAmountCount ?? 0) > 0 ? 1 : 0);

    // Cor e conteúdo vinculados ao espaço: a chave descarta todo estado do anterior.
    return Theme(
      data: buildTheme(brightness, seed: seedForSpace(space.isPf)),
      child: Builder(
        builder: (context) {
          if (isDesktop) {
            return Scaffold(
              body: Column(
                children: [
                  _DesktopTopBar(
                    space: space,
                    session: session,
                    selectedIndex: _tab,
                    notificationCount: notificationCount,
                    onDestinationSelected: (tab) => setState(() {
                      _tab = tab;
                      if (tab == 2) {
                        _agreementsFilter = 'open';
                      } else if (tab == 3) {
                        _payablesFilter = 'open';
                      }
                    }),
                    onOpenNotifications: () => showNotificationsModal(
                      context,
                      summary: _summary,
                      onNavigate: _handleNavigation,
                    ),
                    onOpenCategories: () =>
                        showCategoriesManagementModal(context, space: space),
                    onOpenLoans: () => Navigator.of(context).push(
                      spaceRoute(
                        isPf: space.isPf,
                        child: LoansScreen(space: space),
                      ),
                    ),
                    onEditProfile: () => showProfileEditDialog(context),
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
                  const Divider(height: 1, thickness: 1),
                  Expanded(
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1280),
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
                _NotificationBellButton(
                  count: notificationCount,
                  onTap: () => showNotificationsModal(
                    context,
                    summary: _summary,
                    onNavigate: _handleNavigation,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: PopupMenuButton<String>(
                    tooltip: 'Conta',
                    icon: const AppIcon(AppIcons.user, size: 22),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppTokens.r12),
                    ),
                    onSelected: (action) {
                      if (action == 'edit_profile') {
                        showProfileEditDialog(context);
                      } else if (action == 'categories') {
                        showCategoriesManagementModal(context, space: space);
                      } else if (action == 'loans') {
                        Navigator.of(context).push(
                          spaceRoute(
                            isPf: space.isPf,
                            child: LoansScreen(space: space),
                          ),
                        );
                      } else if (action == 'settings') {
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
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              session.user?.name.isNotEmpty == true
                                  ? session.user!.name
                                  : (session.user?.email ?? ''),
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              session.user?.email ?? '',
                              style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const PopupMenuDivider(),
                      const PopupMenuItem(
                        value: 'edit_profile',
                        child: Row(
                          children: [
                            AppIcon(AppIcons.edit, size: 18),
                            SizedBox(width: 8),
                            Text('Editar perfil'),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'categories',
                        child: Row(
                          children: [
                            Icon(Icons.category_outlined, size: 18),
                            SizedBox(width: 8),
                            Text('Categorias'),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'loans',
                        child: Row(
                          children: [
                            Icon(Icons.account_balance_outlined, size: 18),
                            SizedBox(width: 8),
                            Text('Empréstimos'),
                          ],
                        ),
                      ),
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

class _DesktopTopBar extends StatelessWidget {
  const _DesktopTopBar({
    required this.space,
    required this.session,
    required this.selectedIndex,
    required this.notificationCount,
    required this.onDestinationSelected,
    required this.onOpenNotifications,
    required this.onOpenCategories,
    required this.onOpenLoans,
    required this.onEditProfile,
    required this.onOpenSettings,
    required this.onLogout,
  });

  final Space space;
  final SessionController session;
  final int selectedIndex;
  final int notificationCount;
  final ValueChanged<int> onDestinationSelected;
  final VoidCallback onOpenNotifications;
  final VoidCallback onOpenCategories;
  final VoidCallback onOpenLoans;
  final VoidCallback onEditProfile;
  final VoidCallback onOpenSettings;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: theme.colorScheme.surface,
      elevation: 0,
      child: Container(
        height: 68,
        padding: const EdgeInsets.symmetric(horizontal: AppTokens.p20),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          border: Border(
            bottom: BorderSide(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.35),
            ),
          ),
        ),
        child: Row(
          children: [
            // ZONA 1: Logo & Seletor de Espaço
            const BrandHeader(compact: true),
            const SizedBox(width: AppTokens.p16),
            _SpaceSwitcher(spaces: session.spaces, active: space),

            const SizedBox(width: AppTokens.p12),

            // ZONA 2: Navegação Central em Pills
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _TopNavPill(
                        icon: AppIcons.home,
                        label: 'Dashboard',
                        selected: selectedIndex == 0,
                        onTap: () => onDestinationSelected(0),
                      ),
                      _TopNavPill(
                        icon: AppIcons.receipt,
                        label: 'Extrato',
                        selected: selectedIndex == 1,
                        onTap: () => onDestinationSelected(1),
                      ),
                      _TopNavPill(
                        icon: AppIcons.receivables,
                        label: 'A receber',
                        selected: selectedIndex == 2,
                        onTap: () => onDestinationSelected(2),
                      ),
                      _TopNavPill(
                        icon: AppIcons.payables,
                        label: 'A pagar',
                        selected: selectedIndex == 3,
                        onTap: () => onDestinationSelected(3),
                      ),
                      _TopNavPill(
                        icon: AppIcons.accounts,
                        label: 'Contas',
                        selected: selectedIndex == 4,
                        onTap: () => onDestinationSelected(4),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            const SizedBox(width: AppTokens.p12),

            // ZONA 3: Notificações, Configurações e Perfil do Usuário
            _NotificationBellButton(
              count: notificationCount,
              onTap: onOpenNotifications,
            ),
            const SizedBox(width: AppTokens.p4),
            IconButton(
              tooltip: 'Categorias',
              icon: const Icon(Icons.category_outlined, size: 20),
              onPressed: onOpenCategories,
            ),
            const SizedBox(width: AppTokens.p4),
            IconButton(
              tooltip: 'Empréstimos',
              icon: const Icon(Icons.account_balance_outlined, size: 20),
              onPressed: onOpenLoans,
            ),
            const SizedBox(width: AppTokens.p4),
            IconButton(
              tooltip: 'Configurações',
              icon: const AppIcon(AppIcons.settings, size: 20),
              onPressed: onOpenSettings,
            ),
            const SizedBox(width: AppTokens.p8),
            _UserProfilePill(session: session, onTap: onEditProfile),
            const SizedBox(width: AppTokens.p4),
            IconButton(
              tooltip: 'Sair',
              icon: const AppIcon(AppIcons.logout, size: 18),
              onPressed: onLogout,
            ),
          ],
        ),
      ),
    );
  }
}

class _TopNavPill extends StatelessWidget {
  const _TopNavPill({
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
    final activeBg = theme.colorScheme.primary.withValues(alpha: 0.12);
    final activeColor = theme.colorScheme.primary;
    final inactiveColor = theme.colorScheme.onSurfaceVariant;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Material(
        color: selected ? activeBg : Colors.transparent,
        borderRadius: BorderRadius.circular(AppTokens.r12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppTokens.r12),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppTokens.p12,
              vertical: AppTokens.p8,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppIcon(
                  icon,
                  size: 18,
                  color: selected ? activeColor : inactiveColor,
                ),
                const SizedBox(width: AppTokens.p8),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected ? activeColor : inactiveColor,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _UserProfilePill extends StatelessWidget {
  const _UserProfilePill({required this.session, required this.onTap});

  final SessionController session;
  final VoidCallback onTap;

  String _getInitials(String? name, String? email) {
    final text = (name?.trim().isNotEmpty == true ? name! : (email ?? 'U'))
        .trim();
    final parts = text.split(RegExp(r'\s+'));
    if (parts.length >= 2 && parts[0].isNotEmpty && parts[1].isNotEmpty) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    if (text.length >= 2) {
      return text.substring(0, 2).toUpperCase();
    }
    return text.isNotEmpty ? text[0].toUpperCase() : 'U';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = session.user;
    final displayName = user?.name.trim().isNotEmpty == true
        ? user!.name.trim()
        : (user?.email ?? '');
    final initials = _getInitials(user?.name, user?.email);

    return Tooltip(
      message: 'Editar perfil',
      child: Material(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.45,
        ),
        borderRadius: BorderRadius.circular(AppTokens.r20),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppTokens.r20),
          child: Container(
            padding: const EdgeInsets.fromLTRB(
              AppTokens.p4,
              AppTokens.p4,
              AppTokens.p12,
              AppTokens.p4,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppTokens.r20),
              border: Border.all(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        theme.colorScheme.primary,
                        theme.colorScheme.primary.withValues(alpha: 0.8),
                      ],
                    ),
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    initials,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                  ),
                ),
                const SizedBox(width: AppTokens.p8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 150),
                  child: Text(
                    displayName,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: AppTokens.p4),
                Icon(
                  Icons.keyboard_arrow_down,
                  size: 16,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NotificationBellButton extends StatelessWidget {
  const _NotificationBellButton({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final button = IconButton(
      tooltip: count > 0 ? '$count notificação(ões)' : 'Notificações',
      icon: const AppIcon(AppIcons.notification, size: 22),
      onPressed: onTap,
    );

    if (count == 0) return button;

    return Badge(
      backgroundColor: AppTokens.expense,
      textColor: Colors.white,
      label: Text(
        count > 9 ? '9+' : '$count',
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 10),
      ),
      offset: const Offset(-4, 4),
      child: button,
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
