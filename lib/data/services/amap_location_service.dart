import 'dart:convert';

import 'package:http/http.dart' as http;

import 'location_weather_service.dart';

class AmapLocationService {
  const AmapLocationService({http.Client? client}) : _client = client;

  static const jsApiKey = String.fromEnvironment(
    'AMAP_JS_API_KEY',
    defaultValue: '23aab56d297730c1bf702c66e3762db6',
  );
  static const securityJsCode = String.fromEnvironment(
    'AMAP_SECURITY_JS_CODE',
    defaultValue: '23aab56d297730c1bf702c66e3762db6',
  );
  static const _key = String.fromEnvironment(
    'AMAP_WEB_SERVICE_KEY',
    defaultValue: '23aab56d297730c1bf702c66e3762db6',
  );
  static const _timeout = Duration(seconds: 8);

  final http.Client? _client;

  bool get isConfigured => _key.trim().isNotEmpty;

  Future<List<LocationWeather>> search(String keyword) async {
    final value = keyword.trim();
    if (value.isEmpty || !isConfigured) return const [];
    final client = _client ?? http.Client();
    try {
      final uri = Uri.https('restapi.amap.com', '/v3/place/text', {
        'key': _key,
        'keywords': value,
        'offset': '10',
        'page': '1',
        'extensions': 'all',
      });
      final response = await client.get(uri).timeout(_timeout);
      if (response.statusCode != 200) return const [];
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final pois = data['pois'] as List<dynamic>? ?? const [];
      return pois
          .map((item) => _poiToLocation(item as Map<String, dynamic>))
          .where((item) => item.locationName.trim().isNotEmpty)
          .toList();
    } finally {
      if (_client == null) client.close();
    }
  }

  Future<LocationWeather?> reverse({
    required double latitude,
    required double longitude,
  }) async {
    if (!isConfigured) return null;
    final client = _client ?? http.Client();
    try {
      final uri = Uri.https('restapi.amap.com', '/v3/geocode/regeo', {
        'key': _key,
        'location': '$longitude,$latitude',
        'extensions': 'all',
        'radius': '1000',
        'roadlevel': '0',
      });
      final response = await client.get(uri).timeout(_timeout);
      if (response.statusCode != 200) return null;
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final regeocode = data['regeocode'] as Map<String, dynamic>?;
      if (regeocode == null) return null;
      return _regeoToLocation(regeocode, latitude, longitude);
    } finally {
      if (_client == null) client.close();
    }
  }

  String staticMapUrl({
    required double latitude,
    required double longitude,
    int zoom = 15,
  }) {
    if (!isConfigured) return '';
    return Uri.https('restapi.amap.com', '/v3/staticmap', {
      'key': _key,
      'location': '$longitude,$latitude',
      'zoom': '$zoom',
      'size': '750*520',
      'markers': 'mid,,A:$longitude,$latitude',
    }).toString();
  }

  LocationWeather _poiToLocation(Map<String, dynamic> poi) {
    final location = poi['location']?.toString() ?? '';
    final parts = location.split(',');
    final longitude = parts.isNotEmpty ? double.tryParse(parts[0]) ?? 0.0 : 0.0;
    final latitude = parts.length > 1 ? double.tryParse(parts[1]) ?? 0.0 : 0.0;
    final province = poi['pname']?.toString() ?? '';
    final city = poi['cityname']?.toString() ?? '';
    final district = poi['adname']?.toString() ?? '';
    final name = poi['name']?.toString() ?? '';
    final address = poi['address']?.toString() ?? '';
    return LocationWeather(
      latitude: latitude,
      longitude: longitude,
      locationName:
          name.isEmpty ? [city, district].where(_notEmpty).join(' · ') : name,
      weather: '天气',
      temperature: '',
      details: {
        'source': 'amap',
        'poiId': poi['id']?.toString(),
        'poiType': poi['type']?.toString(),
        'country': '中国',
        'province': province,
        'city': city,
        'district': district,
        'address': address,
        'formattedAddress':
            [province, city, district, address, name].where(_notEmpty).join(''),
        'latitude': latitude,
        'longitude': longitude,
        'raw': poi,
      },
    );
  }

  LocationWeather _regeoToLocation(
    Map<String, dynamic> regeocode,
    double latitude,
    double longitude,
  ) {
    final address =
        regeocode['addressComponent'] as Map<String, dynamic>? ?? {};
    final street = address['streetNumber'] as Map<String, dynamic>? ?? {};
    final pois = regeocode['pois'] as List<dynamic>? ?? const [];
    final firstPoi = pois.isEmpty ? null : pois.first as Map<String, dynamic>;
    final formatted = regeocode['formatted_address']?.toString() ?? '';
    final name = firstPoi?['name']?.toString() ?? formatted;
    return LocationWeather(
      latitude: latitude,
      longitude: longitude,
      locationName: name.isEmpty ? '当前位置' : name,
      weather: '天气',
      temperature: '',
      details: {
        'source': 'amap',
        'country': address['country']?.toString(),
        'province': address['province']?.toString(),
        'city': address['city']?.toString(),
        'district': address['district']?.toString(),
        'township': address['township']?.toString(),
        'street': street['street']?.toString(),
        'streetNumber': street['number']?.toString(),
        'address': formatted,
        'formattedAddress': formatted,
        'poiId': firstPoi?['id']?.toString(),
        'poiType': firstPoi?['type']?.toString(),
        'latitude': latitude,
        'longitude': longitude,
        'raw': regeocode,
      },
    );
  }

  bool _notEmpty(Object? value) => value?.toString().trim().isNotEmpty ?? false;
}
