import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../network/api_client.dart';
import 'package:startgold/core/providers/commodity_provider.dart';

class CountryCode {
  final String id;
  final String name;
  final String code; // ISO code (e.g., IN)
  final String prefix; // Phone prefix (e.g., +91)
  final String flag;

  CountryCode({
    required this.id,
    required this.name,
    required this.code,
    required this.prefix,
    required this.flag,
  });

  factory CountryCode.fromJson(Map<String, dynamic> json) {
    return CountryCode(
      id: json['id_country']?.toString() ?? '101',
      name: json['name'] ?? '',
      code: json['iso'] ?? '',
      prefix: json['code'] ?? '',
      flag: json['flag'] ?? '',
    );
  }
}

class Commodity {
  final String id;
  final int webSocketId;
  final String name;

  Commodity({
    required this.id,
    required this.webSocketId,
    required this.name,
  });

  factory Commodity.fromJson(Map<String, dynamic> json) {
    return Commodity(
      id: json['id_metal']?.toString() ?? '',
      webSocketId: int.tryParse(json['web_soc_id']?.toString() ?? '0') ?? 0,
      name: json['name'] ?? '',
    );
  }
}

class AmountDenomination {
  final double value;
  final bool isPopular;

  AmountDenomination({
    required this.value,
    required this.isPopular,
  });

  factory AmountDenomination.fromJson(Map<String, dynamic> json) {
    return AmountDenomination(
      value: (json['value'] ?? 0).toDouble(),
      isPopular: (json['is_popular'] ?? 0) == 1,
    );
  }
}

class WeightDenomination {
  final double value;
  final bool isPopular;

  WeightDenomination({
    required this.value,
    required this.isPopular,
  });

  factory WeightDenomination.fromJson(Map<String, dynamic> json) {
    return WeightDenomination(
      value: (json['value'] ?? 0).toDouble(),
      isPopular: (json['is_popular'] ?? 0) == 1,
    );
  }
}

class SharedService {
  final ApiClient _apiClient = ApiClient();

  Future<List<CountryCode>> getCountryCodes() async {
    try {
      final response = await _apiClient.post('users/shared/country-codes');
      if (response.data != null && response.data['data'] != null) {
        final List list = response.data['data'];
        return list.map((item) => CountryCode.fromJson(item)).toList();
      }
      return [
        CountryCode(
            id: '101',
            name: 'India',
            code: 'IN',
            prefix: '+91',
            flag: '\u{1F1EE}\u{1F1F3}')
      ]; // Fallback
    } catch (e) {
      return [
        CountryCode(
            id: '101',
            name: 'India',
            code: 'IN',
            prefix: '+91',
            flag: '\u{1F1EE}\u{1F1F3}')
      ]; // Fallback
    }
  }

  Future<List<Commodity>> getCommodities() async {
    try {
      final response = await _apiClient.post('users/shared/commodities');
      if (response.data != null && response.data['data'] != null) {
        final List list = response.data['data'];
        return list.map((item) => Commodity.fromJson(item)).toList();
      }
      return [
        Commodity(id: '1', webSocketId: 1, name: 'Gold 24K'),
        Commodity(id: '3', webSocketId: 3, name: 'Silver'),
      ]; // Fallback
    } catch (e) {
      return [
        Commodity(id: '1', webSocketId: 1, name: 'Gold 24K'),
        Commodity(id: '3', webSocketId: 3, name: 'Silver'),
      ]; // Fallback
    }
  }

  Future<List<AmountDenomination>> getAmountDenominations(
      String idMetal) async {
    try {
      final response =
          await _apiClient.post('users/shared/amount-denominations', data: {
        'id_metal': idMetal,
      });
      if (response.data != null && response.data['data'] != null) {
        final List list = response.data['data'];
        return list.map((item) => AmountDenomination.fromJson(item)).toList();
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  Future<List<WeightDenomination>> getWeightDenominations(
      String idMetal) async {
    try {
      final response =
          await _apiClient.post('users/shared/weight-denominations', data: {
        'id_metal': idMetal,
      });
      if (response.data != null && response.data['data'] != null) {
        final List list = response.data['data'];
        return list.map((item) => WeightDenomination.fromJson(item)).toList();
      }
      return [];
    } catch (e) {
      return [];
    }
  }
}

final sharedServiceProvider = Provider<SharedService>((ref) => SharedService());

final countryCodesProvider =
    FutureProvider.autoDispose<List<CountryCode>>((ref) {
  final service = ref.watch(sharedServiceProvider);
  return service.getCountryCodes();
});

// Non-disposing: stays alive for the full app session so selectedMetalIdProvider
// always has the real id_metal ready for denomination providers on first load.
final commoditiesProvider = FutureProvider<List<Commodity>>((ref) {
  final service = ref.watch(sharedServiceProvider);
  return service.getCommodities();
});

final amountDenominationsProvider =
    FutureProvider.autoDispose<List<AmountDenomination>>((ref) {
  final service = ref.watch(sharedServiceProvider);
  final idMetal = ref.watch(selectedMetalIdProvider); // dynamic from API
  return service.getAmountDenominations(idMetal);
});

final weightDenominationsProvider =
    FutureProvider.autoDispose<List<WeightDenomination>>((ref) {
  final service = ref.watch(sharedServiceProvider);
  final idMetal = ref.watch(selectedMetalIdProvider); // dynamic from API
  return service.getWeightDenominations(idMetal);
});
