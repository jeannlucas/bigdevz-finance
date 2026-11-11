import 'package:flutter/material.dart';

import '../../core/text_formatters.dart';
import '../../ui/app_brand.dart';
import '../../ui/app_icons.dart';
import '../../ui/app_tokens.dart';
import '../../ui/widgets.dart';
import '../auth/auth_models.dart';
import 'account.dart';
import 'bank_catalog.dart';

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
    this.obscureBalance = false,
  });

  final Space space;
  final Account account;
  final VoidCallback? onTap;
  final bool isHighlighted;
  final bool obscureBalance;

  @override
  Widget build(BuildContext context) {
    final isPf = space.isPf;
    final isArchived = account.isArchived;

    // Paleta de gradiente sofisticada centralizada
    final List<Color> gradientColors = AppTokens.cardGradientFor(
      isPf: isPf,
      isArchived: isArchived,
    );

    final upperName = toFinancialUpper(account.name);
    final semanticLabel = obscureBalance
        ? 'Conta $upperName, saldo oculto'
        : 'Conta $upperName, saldo ${account.balance.brl}';

    return Semantics(
      label: semanticLabel,
      button: onTap != null,
      onTap: onTap,
      excludeSemantics: true,
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

                  // Conteúdo do cartão (nós semânticos descendentes excluídos nativamente
                  // pelo excludeSemantics: true no nó pai)
                  Padding(
                    padding: const EdgeInsets.all(AppTokens.p20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Cabeçalho do cartão: Nome e Status
                        Builder(
                          builder: (context) {
                            final bank = BankCatalog.findByAccountName(
                              account.name,
                            );
                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: 38,
                                  height: 38,
                                  alignment: Alignment.center,
                                  padding: EdgeInsets.all(bank != null ? 5 : 8),
                                  decoration: BoxDecoration(
                                    color: bank != null
                                        ? Colors.white
                                        : Colors.white.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(
                                      AppTokens.r10,
                                    ),
                                    boxShadow: bank != null
                                        ? [
                                            BoxShadow(
                                              color: Colors.black.withValues(
                                                alpha: 0.15,
                                              ),
                                              blurRadius: 4,
                                              offset: const Offset(0, 2),
                                            ),
                                          ]
                                        : null,
                                  ),
                                  child: bank != null
                                      ? ClipRRect(
                                          borderRadius: BorderRadius.circular(
                                            6,
                                          ),
                                          child: Image.asset(
                                            bank.assetPath,
                                            width: 26,
                                            height: 26,
                                            fit: BoxFit.contain,
                                          ),
                                        )
                                      : AppIcon(
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
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        toFinancialUpper(account.name),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 16,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: -0.2,
                                          fontFamily: 'Inter',
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Builder(
                                        builder: (context) {
                                          String? accountTypeLabel;
                                          final lowerName = account.name
                                              .toLowerCase();
                                          if (lowerName.contains('poupança') ||
                                              lowerName.contains('poupanca')) {
                                            accountTypeLabel = 'Poupança';
                                          } else if (lowerName.contains(
                                                'salário',
                                              ) ||
                                              lowerName.contains('salario')) {
                                            accountTypeLabel = 'Salário';
                                          } else if (lowerName.contains(
                                                'investimento',
                                              ) ||
                                              lowerName.contains('pagamento')) {
                                            accountTypeLabel = 'Investimento';
                                          } else if (lowerName.contains(
                                            'corrente',
                                          )) {
                                            accountTypeLabel = 'Corrente';
                                          }

                                          final subtitle = isArchived
                                              ? 'Conta arquivada'
                                              : (bank != null &&
                                                        !bank.isCashOrWallet &&
                                                        !bank.isOther
                                                    ? (accountTypeLabel != null
                                                          ? '${bank.name} · $accountTypeLabel · ${isPf ? 'PF' : 'PJ'}'
                                                          : '${bank.name} · ${isPf ? 'PF' : 'PJ'}')
                                                    : (accountTypeLabel != null
                                                          ? '$accountTypeLabel · ${isPf ? 'PF' : 'PJ'}'
                                                          : (isPf
                                                                ? 'Conta financeira PF'
                                                                : 'Conta financeira PJ')));

                                          return Text(
                                            subtitle,
                                            style: TextStyle(
                                              color: Colors.white.withValues(
                                                alpha: 0.7,
                                              ),
                                              fontSize: 12,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          );
                                        },
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
                                      color: Colors.black.withValues(
                                        alpha: 0.3,
                                      ),
                                      borderRadius: BorderRadius.circular(
                                        AppTokens.r8,
                                      ),
                                      border: Border.all(
                                        color: Colors.white.withValues(
                                          alpha: 0.2,
                                        ),
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
                            );
                          },
                        ),

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
                            if (obscureBalance)
                              const Text(
                                r'R$ ••••••••',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 26,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1.5,
                                ),
                              )
                            else
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
                                    fontFeatures: [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),

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
