import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Logo ThibsDarts : cible stylisée + nom.
class Logo extends StatelessWidget {
  const Logo({super.key, this.height = 40});

  final double height;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: height,
          height: height,
          decoration: const BoxDecoration(shape: BoxShape.circle, gradient: Td.goldenHour),
          alignment: Alignment.center,
          child: Container(
            width: height * 0.42,
            height: height * 0.42,
            decoration: const BoxDecoration(shape: BoxShape.circle, color: Td.beton),
            alignment: Alignment.center,
            child: Container(
              width: height * 0.14,
              height: height * 0.14,
              decoration: const BoxDecoration(shape: BoxShape.circle, color: Td.fluo),
            ),
          ),
        ),
        SizedBox(width: height * 0.3),
        Text('ThibsDarts', style: TdText.title.copyWith(fontSize: height * 0.7, height: 1)),
      ],
    );
  }
}
