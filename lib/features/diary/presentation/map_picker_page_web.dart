import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

import '../../../data/services/amap_location_service.dart';
import '../../../data/services/location_weather_service.dart';

class MapPickerPage extends StatefulWidget {
  const MapPickerPage({
    super.key,
    required this.weather,
    required this.temperature,
  });

  final String weather;
  final String? temperature;

  @override
  State<MapPickerPage> createState() => _MapPickerPageState();
}

class _MapPickerPageState extends State<MapPickerPage> {
  static var _viewTypeSeed = 0;

  late final String _mapViewType = 'amap-picker-${_viewTypeSeed++}';
  StreamSubscription? _messageSubscription;
  web.HTMLIFrameElement? _iframeElement;
  bool _isMapReady = false;
  String? _error;

  bool get _hasAmapKey => AmapLocationService.jsApiKey.trim().isNotEmpty;

  String _mapUrl() =>
      '/amap_picker.html?key=${Uri.encodeComponent(AmapLocationService.jsApiKey)}&code=${Uri.encodeComponent(AmapLocationService.securityJsCode)}';

  void _registerMapView() {
    ui_web.platformViewRegistry.registerViewFactory(_mapViewType, (viewId) {
      final iframe = web.HTMLIFrameElement()
        ..src = _mapUrl()
        ..allow = 'geolocation *; fullscreen *'
        ..style.border = '0'
        ..style.width = '100%'
        ..style.height = '100%';
      iframe.setAttribute('referrerpolicy', 'no-referrer-when-downgrade');
      iframe.setAttribute('allowfullscreen', 'true');
      iframe.setAttribute('loading', 'eager');
      iframe.style.pointerEvents = 'auto';
      iframe.style.background = '#fff';
      _iframeElement = iframe;
      return iframe;
    });
  }

  void _bindMessages() {
    _messageSubscription = web.window.onMessage.listen((event) {
      try {
        final raw = event.data.toString();
        if (!raw.startsWith('{') || !raw.contains('trace_stone_amap')) return;
        final data = jsonDecode(raw) as Map<String, dynamic>;
        if (data['source'] != 'trace_stone_amap') return;
        final type = data['type']?.toString();
        if (type == 'ready') {
          if (!mounted) return;
          setState(() => _isMapReady = true);
          return;
        }
        if (type == 'error') {
          if (!mounted) return;
          setState(() => _error = data['payload']?.toString());
          return;
        }
        if (type == 'confirm') {
          final payload = data['payload'] as Map<String, dynamic>? ?? const {};
          final location = LocationWeather(
            latitude: (payload['latitude'] as num?)?.toDouble() ?? 0,
            longitude: (payload['longitude'] as num?)?.toDouble() ?? 0,
            locationName: payload['locationName']?.toString() ?? '当前位置',
            weather: widget.weather,
            temperature: widget.temperature ?? '',
            details: payload['details'] as Map<String, dynamic>? ?? const {},
          );
          if (!mounted) return;
          Navigator.of(context).pop(location.copyWith(
            weather: widget.weather,
            temperature: widget.temperature ?? location.temperature,
          ));
        }
      } catch (_) {}
    });
  }

  void _postToMap(Map<String, dynamic> data) {
    _iframeElement?.contentWindow?.postMessage(jsonEncode(data).toJS, '*'.toJS);
  }

  @override
  void initState() {
    super.initState();
    _registerMapView();
    _bindMessages();
  }

  @override
  void dispose() {
    _messageSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('选择地点'),
        actions: [
          IconButton(
            tooltip: '重新定位',
            onPressed: () => _postToMap(
              {'source': 'trace_stone_flutter', 'type': 'locate'},
            ),
            icon: const Icon(Icons.my_location),
          ),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: _hasAmapKey
                ? HtmlElementView(viewType: _mapViewType)
                : const Center(child: Text('未配置高德地图 Key')),
          ),
          if (!_isMapReady && _hasAmapKey)
            Positioned.fill(
              child: IgnorePointer(
                child: ColoredBox(
                  color: Theme.of(context)
                      .colorScheme
                      .surface
                      .withValues(alpha: 0.64),
                  child: const Center(child: CircularProgressIndicator()),
                ),
              ),
            ),
          if (_error != null && !_isMapReady)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(_error!, textAlign: TextAlign.center),
              ),
            ),
        ],
      ),
    );
  }
}
