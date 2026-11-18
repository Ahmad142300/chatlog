import 'package:flutter/material.dart';

abstract class AppButtonStyles {
  static ButtonStyle primaryWithHoverBorder(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ButtonStyle(
      backgroundColor: WidgetStateProperty.resolveWith<Color>((
        Set<WidgetState> states,
      ) {
        return colorScheme.primary;
      }),
      side: WidgetStateProperty.resolveWith<BorderSide>((
        Set<WidgetState> states,
      ) {
        if (states.contains(WidgetState.hovered)) {
          return BorderSide(color: colorScheme.secondary, width: 4.0);
        }
        return BorderSide(color: colorScheme.primary, width: 2.0);
      }),
    );
  }
}
