import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/config.dart';
import '../../ui/app_brand.dart';
import '../../ui/app_icons.dart';
import '../../ui/app_tokens.dart';
import '../audit/audit_screen.dart';
import '../auth/session_controller.dart';
import '../categories/categories_screen.dart';
import '../members/space_members_screen.dart';
import '../period/accounting_period_dialog.dart';
import '../planning/planning_screen.dart';
import '../reconciliation/ofx_screen.dart';
import 'preferences_controller.dart';

/// Central de Configurações do BigDev.Z Finance:
/// - Aparência: Automático (sistema), Claro, Escuro
/// - Privacidade: Ocultar valores financeiros por padrão
/// - Sobre o aplicativo: Identidade institucional e versão
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  static String _formatDate(String iso) {
    try {
      final parts = iso.split('-');
      if (parts.length == 3) {
        return '${parts[2]}/${parts[1]}/${parts[0]}';
      }
    } catch (_) {}
    return iso;
  }

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

    return Scaffold(
      appBar: AppBar(title: const Text('Configurações')),
      body: ListView(
        padding: const EdgeInsets.symmetric(
          horizontal: AppTokens.p16,
          vertical: AppTokens.p16,
        ),
        children: [
          // SEÇÃO A: APARÊNCIA
          _SectionHeader(
            title: 'Aparência',
            subtitle: 'Escolha como o aplicativo é exibido.',
            icon: AppIcons.sun,
          ),
          const SizedBox(height: 10),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                _ThemeOptionTile(
                  title: 'Automático',
                  subtitle: 'Acompanha a aparência do dispositivo.',
                  icon: AppIcons.computer,
                  selected: preferences.themeMode == ThemeMode.system,
                  onTap: () => preferences.setThemeMode(ThemeMode.system),
                ),
                const Divider(height: 1, indent: 56),
                _ThemeOptionTile(
                  title: 'Claro',
                  subtitle: 'Usar sempre a aparência clara.',
                  icon: AppIcons.sun,
                  selected: preferences.themeMode == ThemeMode.light,
                  onTap: () => preferences.setThemeMode(ThemeMode.light),
                ),
                const Divider(height: 1, indent: 56),
                _ThemeOptionTile(
                  title: 'Escuro',
                  subtitle: 'Usar sempre a aparência escura.',
                  icon: AppIcons.moon,
                  selected: preferences.themeMode == ThemeMode.dark,
                  onTap: () => preferences.setThemeMode(ThemeMode.dark),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // SEÇÃO B: PRIVACIDADE FINANCEIRA
          _SectionHeader(
            title: 'Privacidade',
            subtitle: 'Controle a visibilidade dos valores financeiros.',
            icon: AppIcons.viewOff,
          ),
          const SizedBox(height: 10),
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: SwitchListTile.adaptive(
                value: preferences.hideValuesByDefault,
                onChanged: preferences.isSavingPrivacy ? null : onTogglePrivacy,
                title: const Text(
                  'Ocultar valores por padrão',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  preferences.isSavingPrivacy
                      ? 'Salvando preferência...'
                      : 'Iniciar com os valores financeiros ocultos.',
                ),
                secondary: const AppIcon(AppIcons.viewOff, size: 22),
              ),
            ),
          ),
          const SizedBox(height: 24),

          // SEÇÃO C: CATEGORIAS FINANCEIRAS
          _SectionHeader(
            title: 'Categorias',
            subtitle: 'Personalize as categorias de receitas e despesas.',
            icon: AppIcons.wallet,
          ),
          const SizedBox(height: 10),
          Card(
            clipBehavior: Clip.antiAlias,
            child: ListTile(
              leading: const Icon(Icons.category_rounded),
              title: const Text('Gerenciar Categorias'),
              subtitle: const Text(
                'Visualizar, criar e editar categorias deste espaço',
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () {
                final space = context.read<SessionController?>()?.activeSpace;
                if (space != null) {
                  showCategoriesManagementModal(context, space: space);
                }
              },
            ),
          ),
          const SizedBox(height: 24),

          // SEÇÃO D: SEGURANÇA E GOVERNANÇA (ADMINISTRADOR E FINANCEIRO)
          Builder(
            builder: (context) {
              final space = context.watch<SessionController?>()?.activeSpace;
              if (space == null || (!space.isAdmin && !space.isFinancial)) {
                return const SizedBox.shrink();
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SectionHeader(
                    title: 'Segurança e Governança',
                    subtitle: 'Auditoria de lançamentos, fechamento contábil e equipe.',
                    icon: AppIcons.lock,
                  ),
                  const SizedBox(height: 10),
                  Card(
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      children: [
                        // Auditoria e Conformidade
                        ListTile(
                          leading: const Icon(
                            Icons.history_edu_rounded,
                            color: AppTokens.brandPrimary,
                          ),
                          title: const Text('Auditoria e Conformidade'),
                          subtitle: const Text(
                            'Linha do tempo de alterações, estornos e cancelamentos',
                          ),
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const AuditScreen(),
                              ),
                            );
                          },
                        ),

                        // Fluxo de Caixa Realizado vs. Previsto
                        const Divider(height: 1, indent: 56),
                        ListTile(
                          leading: const Icon(
                            Icons.insights_rounded,
                            color: Color(0xFF10B981),
                          ),
                          title: const Text('Fluxo de Caixa e Planejamento'),
                          subtitle: const Text(
                            'Projeção para 30, 60 e 90 dias com saldo diário e filtros',
                          ),
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => PlanningScreen(space: space),
                              ),
                            );
                          },
                        ),

                        // Conciliação Bancária OFX
                        const Divider(height: 1, indent: 56),
                        ListTile(
                          leading: const Icon(
                            Icons.receipt_long_rounded,
                            color: Color(0xFF0284C7),
                          ),
                          title: const Text('Conciliação Bancária OFX'),
                          subtitle: const Text(
                            'Importe extratos OFX, confira correspondências e elimine duplicidades',
                          ),
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => OfxScreen(space: space),
                              ),
                            );
                          },
                        ),

                        // Período Contábil (Apenas Administrador)
                        if (space.isAdmin) ...[
                          const Divider(height: 1, indent: 56),
                          ListTile(
                            leading: Icon(
                              space.closedUntil != null
                                  ? Icons.lock_clock_rounded
                                  : Icons.lock_open_rounded,
                              color: space.closedUntil != null
                                  ? AppTokens.warning
                                  : AppTokens.income,
                            ),
                            title: const Text('Período Contábil'),
                            subtitle: Text(
                              space.closedUntil != null
                                  ? 'Fechado até ${_formatDate(space.closedUntil!)}'
                                  : 'Aberto para lançamentos e correções',
                            ),
                            trailing: const Icon(Icons.chevron_right_rounded),
                            onTap: () {
                              AccountingPeriodDialog.show(
                                context,
                                space: space,
                              );
                            },
                          ),
                        ],

                        // Gestão de Equipe e Perfis (Apenas Administrador em Espaço PJ)
                        if (space.isAdmin && !space.isPf) ...[
                          const Divider(height: 1, indent: 56),
                          ListTile(
                            leading: const Icon(
                              Icons.group_rounded,
                              color: Color(0xFF0284C7),
                            ),
                            title: const Text('Equipe e Perfis de Acesso'),
                            subtitle: const Text(
                              'Gerencie os membros da empresa e alçadas de permissão',
                            ),
                            trailing: const Icon(Icons.chevron_right_rounded),
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => const SpaceMembersScreen(),
                                ),
                              );
                            },
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              );
            },
          ),

          // SEÇÃO D: SOBRE O APLICATIVO
          _SectionHeader(
            title: 'Sobre o aplicativo',
            subtitle: 'Informações do BigDev.Z Finance.',
            icon: AppIcons.info,
          ),
          const SizedBox(height: 10),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppTokens.p20),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      GorillaSymbol(size: 32, color: theme.colorScheme.primary),
                      const SizedBox(width: 10),
                      Text(
                        'BigDev',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5,
                        ),
                      ),
                      Text(
                        '.Z',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                          color: AppTokens.brandSeed,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'FINANCE',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.5,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Finanças pessoais e da empresa, separadas.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  const Divider(),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Versão',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      Text(
                        appVersionLabel,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Licença',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      Text(
                        'MIT Open Source',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
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
