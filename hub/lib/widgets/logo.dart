import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

enum LogoVariant { full, icon }

/// Logo ThibsDarts : la tête aux lunettes spirale, plus le mot ThibsDarts
/// pour la version complète. Visuels générés par brand/generate.py.
class Logo extends StatelessWidget {
  const Logo({super.key, this.height = 48, this.variant = LogoVariant.full});

  final double height;
  final LogoVariant variant;

  @override
  Widget build(BuildContext context) {
    final face = Image.asset(
      'assets/brand/logo-face.png',
      height: height,
      filterQuality: FilterQuality.medium,
      semanticLabel: variant == LogoVariant.icon ? 'ThibsDarts' : null,
    );
    if (variant == LogoVariant.icon) return face;
    return Semantics(
      label: 'ThibsDarts',
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            face,
            SizedBox(width: height * 0.16),
            SvgPicture.asset('assets/brand/logo-wordmark.svg', height: height * 0.40),
          ],
        ),
      ),
    );
  }
}
