import 'dart:convert';

import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

class LocationWeatherService {
  const LocationWeatherService({http.Client? client}) : _client = client;

  static const timeout = Duration(seconds: 8);
  static LocationWeather? _cachedCurrent;
  static Future<LocationWeather>? _currentRequest;

  final http.Client? _client;

  Future<LocationWeather> getCurrent() async {
    return _loadCurrent();
  }

  Future<LocationWeather> getCachedCurrent() async {
    final cached = _cachedCurrent;
    if (cached != null) return cached;

    final existingRequest = _currentRequest;
    if (existingRequest != null) return existingRequest;

    final request = _loadCurrent();
    _currentRequest = request;
    try {
      final value = await request;
      _cachedCurrent = value;
      return value;
    } finally {
      if (identical(_currentRequest, request)) {
        _currentRequest = null;
      }
    }
  }

  Future<LocationWeather> _loadCurrent() async {
    final client = _client ?? http.Client();

    try {
      final position = await _getPosition();
      final locationName = await _reverseGeocode(client, position);
      final weather = await _fetchWeather(client, position);
      return weather.copyWith(locationName: locationName);
    } on Object {
      return const LocationWeather(
        latitude: 0,
        longitude: 0,
        locationName: '未选择地点',
        weather: '',
        temperature: '',
      );
    } finally {
      if (_client == null) client.close();
    }
  }

  Future<Position> _getPosition() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw const LocationWeatherException('定位服务未开启');
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied) {
      throw const LocationWeatherException('定位权限被拒绝');
    }
    if (permission == LocationPermission.deniedForever) {
      throw const LocationWeatherException('定位权限已永久拒绝，请在系统设置中开启');
    }

    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    ).timeout(timeout);
  }

  Future<String> _reverseGeocode(http.Client client, Position position) async {
    final uri = Uri.https('nominatim.openstreetmap.org', '/reverse', {
      'format': 'jsonv2',
      'lat': position.latitude.toString(),
      'lon': position.longitude.toString(),
      'accept-language': 'zh-CN',
    });

    final response = await client.get(uri, headers: const {
      'User-Agent': 'Shinen/0.1 location metadata',
    }).timeout(timeout);
    if (response.statusCode != 200) {
      return '${position.latitude.toStringAsFixed(4)}, ${position.longitude.toStringAsFixed(4)}';
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final address = data['address'] as Map<String, dynamic>?;
    if (address == null) {
      final displayName = data['display_name']?.toString() ?? '';
      return _shortDisplayName(displayName, position);
    }

    final city = address['city'] ??
        address['town'] ??
        address['county'] ??
        address['state'];
    final district = address['suburb'] ??
        address['city_district'] ??
        address['district'] ??
        address['road'];
    final name = [city, district]
        .whereType<String>()
        .where((value) => value.isNotEmpty)
        .join(' · ');
    if (name.isNotEmpty) return name;
    return _shortDisplayName(data['display_name']?.toString() ?? '', position);
  }

  String _shortDisplayName(String displayName, Position position) {
    final parts = displayName
        .split(',')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .take(2)
        .toList();
    if (parts.isNotEmpty) return parts.join(' · ');
    return '${position.latitude.toStringAsFixed(4)}, ${position.longitude.toStringAsFixed(4)}';
  }

  Future<LocationWeather> _fetchWeather(
      http.Client client, Position position) async {
    final uri = Uri.https('api.open-meteo.com', '/v1/forecast', {
      'latitude': position.latitude.toString(),
      'longitude': position.longitude.toString(),
      'current': 'temperature_2m,weather_code',
      'timezone': 'auto',
    });

    final response = await client.get(uri).timeout(timeout);
    if (response.statusCode != 200) {
      throw const LocationWeatherException('天气服务暂时不可用');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final current = data['current'] as Map<String, dynamic>;
    final temperature = (current['temperature_2m'] as num).round();
    final code = current['weather_code'] as int;

    return LocationWeather(
      latitude: position.latitude,
      longitude: position.longitude,
      locationName: '当前位置',
      weather: _weatherText(code),
      temperature: '$temperature℃',
    );
  }

  String _weatherText(int code) {
    if (code == 0) return '晴';
    if ([1, 2, 3].contains(code)) return '多云';
    if ([45, 48].contains(code)) return '雾';
    if ([51, 53, 55, 56, 57].contains(code)) return '毛毛雨';
    if ([61, 63, 65, 66, 67, 80, 81, 82].contains(code)) return '雨';
    if ([71, 73, 75, 77, 85, 86].contains(code)) return '雪';
    if ([95, 96, 99].contains(code)) return '雷雨';
    return '天气';
  }
}

class LocationWeather {
  const LocationWeather({
    required this.latitude,
    required this.longitude,
    required this.locationName,
    required this.weather,
    required this.temperature,
    this.details = const {},
  });

  final double latitude;
  final double longitude;
  final String locationName;
  final String weather;
  final String temperature;
  final Map<String, dynamic> details;

  bool get isMissing =>
      locationName.trim().isEmpty ||
      locationName == '未选择地点' ||
      (weather.trim().isEmpty && temperature.trim().isEmpty);

  LocationWeather copyWith({
    String? locationName,
    String? weather,
    String? temperature,
    Map<String, dynamic>? details,
  }) {
    return LocationWeather(
      latitude: latitude,
      longitude: longitude,
      locationName: locationName ?? this.locationName,
      weather: weather ?? this.weather,
      temperature: temperature ?? this.temperature,
      details: details ?? this.details,
    );
  }
}

class LocationWeatherException implements Exception {
  const LocationWeatherException(this.message);

  final String message;

  @override
  String toString() => message;
}
