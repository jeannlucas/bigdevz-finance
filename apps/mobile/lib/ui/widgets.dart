import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api_client.dart';
import '../core/money.dart';
import '../features/auth/auth_models.dart';
import '../features/auth/session_controller.dart';

/// Carrega dados da API com estados de carregamento, erro e vazio.
/// Recarrega quando a sessão sinaliza mudança e descarta respostas antigas.
class LoadView<T> extends StatefulWidget {
  const LoadView({
    super.key,
    required this.load,
    required this.builder,
    this.isEmpty,
    this.empty,
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
    if (data == null) return const Center(child: CircularProgressIndicator());
    final content = widget.isEmpty?.call(data) == true && widget.empty != null
        ? widget.empty!(context, _reload)
        : widget.builder(context, data, _reload);
    return Stack(
      children: [
        content,
        if (_loading)
          const Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: LinearProgressIndicator(minHeight: 2),
          ),
        // Dados anteriores continuam visíveis, mas sinalizados como desatualizados.
        if (_error != null)
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: Material(
              elevation: 2,
              borderRadius: BorderRadius.circular(12),
              color: Theme.of(context).colorScheme.errorContainer,
              child: ListTile(
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
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: scheme.primaryContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              space.isPf ? Icons.person_outline : Icons.business_outlined,
              size: 18,
              color: scheme.onPrimaryContainer,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                '${prefix != null ? '$prefix ' : ''}${space.label}',
                style: TextStyle(
                  color: scheme.onPrimaryContainer,
                  fontWeight: FontWeight.w600,
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
    icon: Icons.cloud_off_outlined,
    title: 'Algo deu errado',
    message: message,
    action: OutlinedButton.icon(
      onPressed: onRetry,
      icon: const Icon(Icons.refresh),
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

  final IconData icon;
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

  final IconData icon;
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
        Icon(icon, size: 48, color: theme.colorScheme.outline),
        const SizedBox(height: 16),
        Text(
          title,
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium,
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
    final scheme = Theme.of(context).colorScheme;
    final (background, foreground) = switch (tone) {
      StatusTone.success => (
        scheme.secondaryContainer,
        scheme.onSecondaryContainer,
      ),
      StatusTone.warning => (
        scheme.tertiaryContainer,
        scheme.onTertiaryContainer,
      ),
      StatusTone.danger => (scheme.errorContainer, scheme.onErrorContainer),
      StatusTone.neutral => (
        scheme.surfaceContainerHighest,
        scheme.onSurfaceVariant,
      ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: foreground,
          fontSize: 12,
          fontWeight: FontWeight.w600,
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
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: scheme.errorContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(Icons.error_outline, color: scheme.onErrorContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: TextStyle(color: scheme.onErrorContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
