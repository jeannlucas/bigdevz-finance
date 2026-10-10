import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api_client.dart';
import '../core/money.dart';
import '../features/auth/auth_models.dart';
import '../features/auth/session_controller.dart';
import 'app_icons.dart';
import 'app_tokens.dart';

/// Carrega dados da API com estados de carregamento, erro e vazio.
/// Recarrega quando a sessão sinaliza mudança e descarta respostas antigas.
class LoadView<T> extends StatefulWidget {
  const LoadView({
    super.key,
    required this.load,
    required this.builder,
    this.isEmpty,
    this.empty,
    this.emptyWithData,
  });

  final Future<T> Function() load;
  final Widget Function(
    BuildContext context,
    T data,
    Future<void> Function() refresh,
  )
  builder;
  final bool Function(T data)? isEmpty;
  final Widget Function(BuildContext context, Future<void> Function() refresh)?
  empty;
  final Widget Function(
    BuildContext context,
    T data,
    Future<void> Function() refresh,
  )?
  emptyWithData;

  @override
  State<LoadView<T>> createState() => _LoadViewState<T>();
}

class _LoadViewState<T> extends State<LoadView<T>> {
  T? _data;
  Object? _error;
  bool _loading = true;
  int _ticket = 0;
  int? _seenVersion;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final version = Provider.of<SessionController>(context).dataVersion;
    if (version != _seenVersion) {
      _seenVersion = version;
      _reload(inBuild: true);
    }
  }

  Future<void> _reload({bool inBuild = false}) async {
    final ticket = ++_ticket;
    void start() {
      _loading = true;
      _error = null;
    }

    inBuild ? start() : setState(start);
    try {
      final data = await widget.load();
      if (!mounted || ticket != _ticket) return;
      setState(() {
        _data = data;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || ticket != _ticket) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    if (_error != null && data == null) {
      return ErrorState(
        message: _error is ApiException
            ? '$_error'
            : 'Não foi possível carregar os dados.',
        onRetry: _reload,
      );
    }
    if (data == null) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2.5));
    }
    final isDataEmpty = widget.isEmpty?.call(data) == true;
    final Widget content;
    if (isDataEmpty && widget.emptyWithData != null) {
      content = widget.emptyWithData!(context, data, _reload);
    } else if (isDataEmpty && widget.empty != null) {
      content = widget.empty!(context, _reload);
    } else {
      content = widget.builder(context, data, _reload);
    }
    return Stack(
      children: [
        content,
        if (_loading)
          const Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: LinearProgressIndicator(minHeight: 2.5),
          ),
        if (_error != null)
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: Material(
              elevation: 3,
              borderRadius: BorderRadius.circular(AppTokens.r12),
              color: Theme.of(context).colorScheme.errorContainer,
              child: ListTile(
                leading: const AppIcon(AppIcons.alert),
                title: const Text('Dados possivelmente desatualizados'),
                subtitle: Text('$_error'),
                trailing: TextButton(
                  onPressed: _reload,
                  child: const Text('Atualizar'),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class MoneyText extends StatelessWidget {
  const MoneyText(this.value, {super.key, this.style});

  final Money value;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => Text(
    value.brl,
    style: (style ?? DefaultTextStyle.of(context).style).copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    ),
  );
}

class SpaceBadge extends StatelessWidget {
  const SpaceBadge(this.space, {super.key, this.prefix});

  final Space space;
  final String? prefix;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: '${prefix ?? 'Espaço'}: ${space.label}',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: scheme.primaryContainer.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(AppTokens.r8),
          border: Border.all(color: scheme.primary.withValues(alpha: 0.15)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppIcon(
              space.isPf ? AppIcons.user : AppIcons.business,
              size: 15,
              color: scheme.onPrimaryContainer,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                '${prefix != null ? '$prefix ' : ''}${space.label}',
                style: TextStyle(
                  color: scheme.onPrimaryContainer,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ErrorState extends StatelessWidget {
  const ErrorState({super.key, required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => _CenteredMessage(
    icon: AppIcons.error,
    title: 'Algo deu errado',
    message: message,
    action: OutlinedButton.icon(
      onPressed: onRetry,
      icon: const AppIcon(AppIcons.refresh, size: 18),
      label: const Text('Tentar novamente'),
    ),
  );
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final List<List<dynamic>> icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) => _CenteredMessage(
    icon: icon,
    title: title,
    message: message,
    action: action,
  );
}

class _CenteredMessage extends StatelessWidget {
  const _CenteredMessage({
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final List<List<dynamic>> icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(32),
      children: [
        const SizedBox(height: 48),
        Center(
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withValues(
                alpha: 0.5,
              ),
              shape: BoxShape.circle,
            ),
            child: AppIcon(icon, size: 40, color: theme.colorScheme.primary),
          ),
        ),
        const SizedBox(height: 20),
        Text(
          title,
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          message,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        if (action != null) ...[
          const SizedBox(height: 24),
          Center(child: action),
        ],
      ],
    );
  }
}

class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.label, required this.tone});

  final String label;
  final StatusTone tone;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final (background, foreground) = switch (tone) {
      StatusTone.success => (
        AppTokens.income.withValues(alpha: isDark ? 0.25 : 0.12),
        isDark ? const Color(0xFF4ADE80) : AppTokens.income,
      ),
      StatusTone.warning => (
        AppTokens.warning.withValues(alpha: isDark ? 0.25 : 0.12),
        isDark ? const Color(0xFFFBBF24) : AppTokens.warning,
      ),
      StatusTone.danger => (
        AppTokens.expense.withValues(alpha: isDark ? 0.25 : 0.12),
        isDark ? const Color(0xFFF87171) : AppTokens.expense,
      ),
      StatusTone.neutral => (
        Theme.of(context).colorScheme.surfaceContainerHighest,
        Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppTokens.r8),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: foreground,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

enum StatusTone { success, warning, danger, neutral }

/// Faixa de erro para formulários.
class FormErrorBanner extends StatelessWidget {
  const FormErrorBanner(this.message, {super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: scheme.errorContainer,
          borderRadius: BorderRadius.circular(AppTokens.r12),
          border: Border.all(color: scheme.error.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            AppIcon(AppIcons.alert, color: scheme.onErrorContainer, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  color: scheme.onErrorContainer,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Envoltório acessível para campos de formulário.
/// Em escalas padrão, mantém a decoração interna nativa do campo.
/// Quando o texto é ampliado (>= 1.25x), apresenta o rótulo acima do campo
/// permitindo múltiplas linhas completas sem truncamento, reticências ou
/// overflow, preservando indicação de opcional e associação acessível.
class AccessibleFieldWrapper extends StatelessWidget {
  const AccessibleFieldWrapper({
    super.key,
    required this.label,
    required this.child,
    this.isOptional = false,
  });

  final String label;
  final Widget child;
  final bool isOptional;

  @override
  Widget build(BuildContext context) {
    final textScaler = MediaQuery.textScalerOf(context);
    final isTextEnlarged = textScaler.scale(1.0) > 1.2;

    if (!isTextEnlarged) {
      return child;
    }

    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            header: true,
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
          const SizedBox(height: 6),
          child,
        ],
      ),
    );
  }
}
