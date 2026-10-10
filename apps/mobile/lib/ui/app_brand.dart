import 'package:flutter/material.dart';

import 'app_tokens.dart';

/// Identidade visual oficial BigDev.Z Finance.
/// Utiliza o símbolo fiel do gorila recortado das referências oficiais da marca
/// e tipografia alinhada à direção fintech.
class AppBrand {
  static const String gorillaWhiteAsset = 'assets/brand/gorilla_white.png';
  static const String gorillaDarkAsset = 'assets/brand/gorilla_dark.png';

  /// Retorna o asset adequado para o brilho do contexto ou da superfície.
  static String assetFor(Brightness brightness) =>
      brightness == Brightness.dark ? gorillaWhiteAsset : gorillaDarkAsset;
}

/// Símbolo do gorila oficial isolado com proporções e fidelidade preservadas.
class GorillaSymbol extends StatelessWidget {
  const GorillaSymbol({
    super.key,
    this.size = 24,
    this.color,
    this.opacity = 1.0,
    this.brightness,
  });

  final double size;
  final Color? color;
  final double opacity;
  final Brightness? brightness;

  @override
  Widget build(BuildContext context) {
    final effectiveBrightness = brightness ?? Theme.of(context).brightness;
    final asset = AppBrand.assetFor(effectiveBrightness);

    Widget image = Image.asset(
      asset,
      width: size * 1.12, // Razão de aspecto original 213x190
      height: size,
      fit: BoxFit.contain,
      color: color,
      colorBlendMode: color != null ? BlendMode.srcIn : null,
      filterQuality: FilterQuality.high,
    );

    if (opacity < 1.0) {
      image = Opacity(opacity: opacity, child: image);
    }

    return image;
  }
}

/// Cabeçalho da marca: Gorila + BigDev.Z + FINANCE.
/// Otimizado para caber confortavelmente na AppBar sem competir com o seletor PF/PJ.
class BrandHeader extends StatelessWidget {
  const BrandHeader({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryTextColor = isDark ? Colors.white : AppTokens.brandText;
    final secondaryTextColor = isDark
        ? const Color(0xFF94A3B8)
        : const Color(0xFF64748B);

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Símbolo do gorila com container de contraste discreto
        Container(
          width: compact ? 32 : 36,
          height: compact ? 32 : 36,
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E293B) : const Color(0xFFEFF4FE),
            borderRadius: BorderRadius.circular(AppTokens.r8),
            border: Border.all(
              color: isDark ? const Color(0xFF334155) : const Color(0xFFDBEAFE),
              width: 1,
            ),
          ),
          alignment: Alignment.center,
          child: GorillaSymbol(
            size: compact ? 18 : 20,
            color: isDark ? Colors.white : AppTokens.brandSeed,
          ),
        ),
        const SizedBox(width: 8),
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'BigDev',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: compact ? 15 : 16,
                    fontWeight: FontWeight.w800,
                    color: primaryTextColor,
                    letterSpacing: -0.4,
                    height: 1.1,
                  ),
                ),
                Text(
                  '.Z',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: compact ? 15 : 16,
                    fontWeight: FontWeight.w900,
                    color: AppTokens.brandSeed,
                    letterSpacing: -0.4,
                    height: 1.1,
                  ),
                ),
              ],
            ),
            Text(
              'FINANCE',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: compact ? 8.5 : 9.5,
                fontWeight: FontWeight.w700,
                color: secondaryTextColor,
                letterSpacing: 1.6,
                height: 1.0,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Marca-d'água decorativa com o gorila oficial para cartões bancários.
class BrandWatermark extends StatelessWidget {
  const BrandWatermark({
    super.key,
    this.size = 140,
    this.opacity = 0.07,
    this.color = Colors.white,
  });

  final double size;
  final double opacity;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      right: -20,
      bottom: -20,
      child: IgnorePointer(
        child: Opacity(
          opacity: opacity,
          child: Image.asset(
            AppBrand.gorillaWhiteAsset,
            width: size * 1.12,
            height: size,
            fit: BoxFit.contain,
            color: color,
            colorBlendMode: BlendMode.srcIn,
          ),
        ),
      ),
    );
  }
}

/// Assinatura da marca no rodapé do cartão financeiro.
class CardBrandSignature extends StatelessWidget {
  const CardBrandSignature({super.key, this.color = Colors.white70});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        GorillaSymbol(size: 14, color: color),
        const SizedBox(width: 6),
        Text(
          'BIGDEV.Z',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.0,
            color: color,
          ),
        ),
      ],
    );
  }
}
