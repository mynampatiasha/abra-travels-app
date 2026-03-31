import 'package:abra_fleet/features/auth/data/repositories/jwt_auth_repository_impl.dart';

void main() {
  final repo = JwtAuthRepositoryImpl();
  print('JWT Repository created successfully: $repo');
}