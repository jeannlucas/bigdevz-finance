import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/config.dart';
import '../../core/dates.dart';
import '../../ui/app_brand.dart';
import '../../ui/app_icons.dart';
import '../audit/audit_screen.dart';
import '../auth/session_controller.dart';
import '../categories/categories_screen.dart';
import '../members/space_members_screen.dart';
import '../period/accounting_period_dialog.dart';
import '../planning/planning_screen.dart';
import '../reconciliation/ofx_screen.dart';
import 'preferences_controller.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final preferences = context.watch<PreferencesController>();

    Future<void> onTogglePrivacy(bool value) async {
      final scaffoldMessenger = ScaffoldMessenger.of(context);
      final success = await preferences.setHideValuesByDefault(value);
      if (!success && context.mounted) {
        scaffoldMessenger.hideCurrentSnackBar();
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: const Text(
              'Não foi possível salvar a preferência de privacidade.',
            ),
            action: SnackBarAction(
              label: 'Tentar novamente',
              onPressed: () => onTogglePrivacy(value),
            ),
          ),
        );
      }
    }

    final space = context.watch<SessionController?>()?.activeSpace;
    final hasTools = space != null && (space.isAdmin || space.isFinancial);

    void open(Widget screen) {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
    }

    final preferencesSections = [
      _SettingsSection(
        title: 'Aparência',
        subtitle: 'Escolha o tema neste dispositivo.',
        icon: AppIcons.sun,
        tiles: [
          for (final (mode, title, description, icon) in [
            (
              ThemeMode.system,
              'Automático',
              'Acompanha o tema do dispositivo.',
              AppIcons.computer,
            ),
            (
              ThemeMode.light,
              'Claro',
              'Usa sempre o tema claro.',
              AppIcons.sun,
            ),
            (
              ThemeMode.dark,
              'Escuro',
              'Usa sempre o tema escuro.',
              AppIcons.moon,
            ),
          ])
            _ThemeOptionTile(
              title: title,
              subtitle: description,
              icon: icon,
              selected: preferences.themeMode == mode,
              onTap: () => preferences.setThemeMode(mode),
            ),
        ],
      ),
      _SettingsSection(
        title: 'Privacidade',
        subtitle: 'Visibilidade dos valores neste dispositivo.',
        icon: AppIcons.viewOff,
        tiles: [
          SwitchListTile.adaptive(
            value: preferences.hideValuesByDefault,
            onChanged: preferences.isSavingPrivacy ? null : onTogglePrivacy,
            title: const Text('Ocultar valores por padrão'),
            subtitle: Text(
              preferences.isSavingPrivacy
                  ? 'Salvando preferência...'
                  : 'Iniciar com os valores ocultos nas telas compatíveis.',
            ),
          ),
        ],
      ),
    ];

    final spaceSections = [
      if (space != null)
        _SettingsSection(
          title: 'Categorias',
          subtitle: space.label,
          icon: AppIcons.wallet,
          tiles: [
            _SettingsLink(
              icon: Icons.category_rounded,
              title: 'Gerenciar Categorias',
              subtitle: 'Organize receitas e despesas deste espaço.',
              onTap: () => showCategoriesManagementModal(context, space: space),
            ),
          ],
        ),
      if (hasTools) ...[
        _SettingsSection(
          title: 'Ferramentas financeiras',
          subtitle: 'Planejamento e conferência de extratos.',
          icon: AppIcons.wallet,
          tiles: [
            _SettingsLink(
              icon: Icons.insights_rounded,
              title: 'Fluxo de Caixa e Planejamento',
              subtitle: 'Projete o saldo diário para 30, 60 ou 90 dias.',
              onTap: () => open(PlanningScreen(space: space)),
            ),
            _SettingsLink(
              icon: Icons.receipt_long_rounded,
              title: 'Conciliação Bancária OFX',
              subtitle: 'Importe um extrato e confira as correspondências.',
              onTap: () => open(OfxScreen(space: space)),
            ),
          ],
        ),
        _SettingsSection(
          title: 'Segurança e Governança',
          subtitle: 'Histórico e controles do espaço.',
          icon: AppIcons.lock,
          tiles: [
            _SettingsLink(
              icon: Icons.history_edu_rounded,
              title: 'Auditoria e Conformidade',
              subtitle: 'Consulte alterações, estornos e cancelamentos.',
              onTap: () => open(const AuditScreen()),
            ),
            if (space.isAdmin)
              _SettingsLink(
                icon: space.closedUntil == null
                    ? Icons.lock_open_rounded
                    : Icons.lock_clock_rounded,
                title: 'Período Contábil',
                subtitle: space.closedUntil == null
                    ? 'Aberto para movimentações e correções.'
                    : 'Fechado até ${formatDateBr(space.closedUntil!)}',
                onTap: () => AccountingPeriodDialog.show(context, space: space),
              ),
            if (space.isAdmin && !space.isPf)
              _SettingsLink(
                icon: Icons.group_rounded,
                title: 'Equipe e Perfis de Acesso',
                subtitle: 'Gerencie os membros e permissões da empresa.',
                onTap: () => open(const SpaceMembersScreen()),
              ),
          ],
        ),
      ],
    ];

    final about = _SettingsSection(
      title: 'Sobre o aplicativo',
      subtitle: 'Identificação do build em uso.',
      icon: AppIcons.info,
      tiles: [
        ListTile(
          leading: GorillaSymbol(size: 28, color: theme.colorScheme.primary),
          title: const Text('BigDev.Z Finance'),
          subtitle: const Text(appVersionLabel),
        ),
        ListTile(
          title: const Text('Ambiente'),
          subtitle: Text(currentEnvironment.label),
        ),
        const ListTile(title: Text('Licença'), subtitle: Text('MIT')),
      ],
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Configurações')),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final desktop = constraints.maxWidth >= 840;
          return SingleChildScrollView(
            padding: EdgeInsets.symmetric(
              horizontal: desktop ? 32 : 16,
              vertical: 20,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1120),
                child: desktop
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              children: [...preferencesSections, about],
                            ),
                          ),
                          const SizedBox(width: 24),
                          Expanded(child: Column(children: spaceSections)),
                        ],
                      )
                    : Column(
                        children: [
                          ...preferencesSections,
                          ...spaceSections,
                          about,
                        ],
                      ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.tiles,
  });

  final String title;
  final String subtitle;
  final List<List<dynamic>> icon;
  final List<Widget> tiles;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeader(title: title, subtitle: subtitle, icon: icon),
        const SizedBox(height: 8),
        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (var index = 0; index < tiles.length; index++) ...[
                if (index > 0)
                  const Divider(height: 1, indent: 16, endIndent: 16),
                tiles[index],
              ],
            ],
          ),
        ),
      ],
    ),
  );
}

class _SettingsLink extends StatelessWidget {
  const _SettingsLink({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
    title: Text(title),
    subtitle: Text(subtitle),
    trailing: const Icon(Icons.chevron_right_rounded),
    onTap: onTap,
  );
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  final String title;
  final String subtitle;
  final List<List<dynamic>> icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AppIcon(icon, size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _ThemeOptionTile extends StatelessWidget {
  const _ThemeOptionTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final List<List<dynamic>> icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      selected: selected,
      inMutuallyExclusiveGroup: true,
      child: ListTile(
        selected: selected,
        leading: AppIcon(
          icon,
          size: 22,
          color: selected
              ? theme.colorScheme.primary
              : theme.colorScheme.onSurfaceVariant,
        ),
        title: Text(
          title,
          style: TextStyle(
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected
                ? theme.colorScheme.primary
                : theme.colorScheme.onSurface,
          ),
        ),
        subtitle: Text(subtitle),
        trailing: selected
            ? Icon(Icons.check_circle_rounded, color: theme.colorScheme.primary)
            : Icon(
                Icons.radio_button_unchecked,
                color: theme.colorScheme.outline.withValues(alpha: 0.7),
              ),
        onTap: onTap,
      ),
    );
  }
}
