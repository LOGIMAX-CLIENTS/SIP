import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/environment_service.dart';

final environmentProvider = StateProvider<String>((ref) => EnvironmentService.currentEnv);
