import 'package:flutter/material.dart';

/// Reusable vehicle logo widget that displays the custom car logo
/// Used across all dashboards to maintain consistent branding
class VehicleLogoIcon extends StatelessWidget {
  final double size;
  final Color? color;
  final BoxFit fit;

  const VehicleLogoIcon({
    Key? key,
    this.size = 24.0,
    this.color,
    this.fit = BoxFit.contain,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/images/car_logo.png',
      width: size,
      height: size,
      fit: fit,
      color: color,
      errorBuilder: (context, error, stackTrace) {
        // Fallback to icon if image fails to load
        return Icon(
          Icons.directions_car,
          size: size,
          color: color ?? Theme.of(context).primaryColor,
        );
      },
    );
  }
}
