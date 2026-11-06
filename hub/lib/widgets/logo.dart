import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

enum LogoVariant { full, icon }

/// Logo ThibsDarts du design system (soleil couchant + fléchette + mot).
/// SVG repris tel quel du composant Logo de Claude Design.
class Logo extends StatelessWidget {
  const Logo({super.key, this.height = 48, this.variant = LogoVariant.full});

  final double height;
  final LogoVariant variant;

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      variant == LogoVariant.full ? 'assets/brand/logo-full.svg' : 'assets/brand/logo-icon.svg',
      height: height,
      semanticsLabel: 'ThibsDarts',
    );
  }
}
