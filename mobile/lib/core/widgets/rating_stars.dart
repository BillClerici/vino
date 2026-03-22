import 'package:flutter/material.dart';

class RatingStars extends StatelessWidget {
  final int? rating;
  final double size;
  final ValueChanged<int>? onChanged;

  const RatingStars({
    super.key,
    this.rating,
    this.size = 20,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (index) {
        final starNum = index + 1;
        final filled = (rating ?? 0) >= starNum;
        return GestureDetector(
          onTap: onChanged != null ? () => onChanged!(starNum) : null,
          child: Icon(
            filled ? Icons.star : Icons.star_border,
            size: size,
            color: filled ? colorScheme.primary : Colors.grey[400],
          ),
        );
      }),
    );
  }
}
