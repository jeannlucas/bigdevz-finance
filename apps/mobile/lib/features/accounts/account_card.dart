import 'package:flutter/material.dart';

import '../../ui/app_brand.dart';
import '../../ui/app_icons.dart';
import '../../ui/app_tokens.dart';
import '../../ui/widgets.dart';
import '../auth/auth_models.dart';
import 'account.dart';

/// Cartão financeiro institucional para contas bancárias.
/// Aplica a direção fintech: gradiente nobre, geometria de luz discreta,
/// gorila oficial como marca-d'água suave e assinatura BigDev.Z no rodapé.
/// Não representa cartão de crédito (sem número, CVV, chip ou bandeira).
class AccountCard extends StatelessWidget {
  const AccountCard({
    super.key,
    required this.space,
    required this.account,
    this.onTap,
    this.isHighlighted = false,
  });

  final Space space;
  final Account account;
  final VoidCallback? onTap;
  final bool isHighlighted;

  @override
  Widget build(BuildContext context) {
    final isPf = space.isPf;
    final isArchived = account.isArchived;

    // Paleta de gradiente sofisticada centralizada
    final List<Color> gradientColors = AppTokens.cardGradientFor(
      isPf: isPf,
      isArchived: isArchived,
    );

    return Semantics(
      label: 'Conta ${account.name}, saldo ${account.balance.brl}',
      button: onTap != null,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppTokens.r20),
          child: Container(
            constraints: const BoxConstraints(minHeight: 185),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: gradientColors,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(AppTokens.r20),
              border: Border.all(
                color: isHighlighted
                    ? Colors.white.withValues(alpha: 0.3)
                    : Colors.white.withValues(alpha: 0.12),
                width: isHighlighted ? 1.5 : 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: isPf
                      ? const Color(0xFF1E40AF).withValues(alpha: 0.25)
                      : const Color(0xFF065F46).withValues(alpha: 0.25),
                  offset: const Offset(0, 8),
                  blurRadius: 20,
                  spreadRadius: -4,
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppTokens.r20),
              child: Stack(
                children: [
                  // Luz decorativa no canto superior esquerdo
                  Positioned(
                    top: -40,
                    left: -40,
                    child: Container(
                      width: 140,
                      height: 140,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha: 0.08),
                      ),
                    ),
                  ),

                  // Marca-d'água suave do gorila oficial
                  const BrandWatermark(
                    size: 150,
                    opacity: 0.07,
                    color: Colors.white,
                  ),

                  // Conteúdo do cartão
                  Padding(
                    padding: const EdgeInsets.all(AppTokens.p20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Cabeçalho do cartão: Nome e Status
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(
                                  AppTokens.r10,
                                ),
                              ),
                              child: AppIcon(
                                isArchived
                                    ? AppIcons.archive
                                    : AppIcons.accounts,
                                color: Colors.white,
                                size: 18,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  RichText(
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    text: TextSpan(
                                      text: account.name,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: -0.2,
                                        fontFamily: 'Inter',
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    isArchived
                                        ? 'Conta arquivada'
                                        : (isPf
                                              ? 'Conta financeira PF'
                                              : 'Conta financeira PJ'),
                                    style: TextStyle(
                                      color: Colors.white.withValues(
                                        alpha: 0.7,
                                      ),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (isArchived)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.3),
                                  borderRadius: BorderRadius.circular(
                                    AppTokens.r8,
                                  ),
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.2),
                                  ),
                                ),
                                child: const Text(
                                  'Arquivada',
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                          ],
                        ),

                        const SizedBox(height: 18),

                        // Bloco central: Saldo atual
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Saldo disponível',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.75),
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                letterSpacing: 0.3,
                              ),
                            ),
                            const SizedBox(height: 4),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: MoneyText(
                                account.balance,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 26,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.5,
                                  fontFeatures: [FontFeature.tabularFigures()],
                                ),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 16),

                        // Rodapé: Somente a assinatura institucional da marca (data de abertura preservada no detalhe da conta)
                        const Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [CardBrandSignature(color: Colors.white70)],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
