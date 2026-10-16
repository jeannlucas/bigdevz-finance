import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/config.dart';
import '../../ui/app_brand.dart';
import '../../ui/app_icons.dart';
import '../../ui/app_tokens.dart';
import 'preferences_controller.dart';

/// Central de Configurações do BigDev.Z Finance:
/// - Aparência: Automático (sistema), Claro, Escuro
/// - Privacidade: Ocultar valores financeiros por padrão
/// - Sobre o aplicativo: Identidade institucional e versão
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final preferences = context.watch<PreferencesController>();

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
                onChanged: (value) => preferences.setHideValuesByDefault(value),
                title: const Text(
                  'Ocultar valores por padrão',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: const Text(
                  'Iniciar com os valores financeiros ocultos.',
                ),
                secondary: const AppIcon(AppIcons.viewOff, size: 22),
              ),
            ),
          ),
          const SizedBox(height: 24),

          // SEÇÃO C: SOBRE O APLICATIVO
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
