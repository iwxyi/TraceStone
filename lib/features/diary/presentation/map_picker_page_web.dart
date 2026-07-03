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
  final _nameController = TextEditingController();
  static var _viewTypeSeed = 0;

  late final String _mapViewType = 'amap-picker-${_viewTypeSeed++}';
  StreamSubscription? _messageSubscription;
  web.HTMLIFrameElement? _iframeElement;
  LocationWeather? _selected;
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
        if (type == 'error') {
          if (!mounted) return;
          setState(() {
            _error = data['payload']?.toString();
            _selected = const LocationWeather(
              latitude: 0,
              longitude: 0,
              locationName: '定位失败',
              weather: '',
              temperature: '',
            );
            _nameController.text = '定位失败';
          });
          return;
        }
        if (type == 'select' || type == 'confirm') {
          final payload = data['payload'] as Map<String, dynamic>? ?? const {};
          final location = LocationWeather(
            latitude: (payload['latitude'] as num?)?.toDouble() ?? 0,
            longitude: (payload['longitude'] as num?)?.toDouble() ?? 0,
            locationName: payload['locationName']?.toString() ?? '当前位置',
            weather: widget.weather,
            temperature: widget.temperature ?? '',
            details: payload['details'] as Map<String, dynamic>? ?? const {},
          );
          final normalized = _normalize(location);
          if (!mounted) return;
          setState(() {
            _selected = normalized;
            _nameController.text = normalized.locationName;
            _error = null;
          });
          if (type == 'confirm') {
            Navigator.of(context).pop(normalized.copyWith(
              weather: widget.weather,
              temperature: widget.temperature ?? normalized.temperature,
            ));
          }
        }
      } catch (_) {}
    });
  }

  String _displayAddress(LocationWeather? selected) {
    if (selected == null) return '';
    return selected.details['formattedAddress']?.toString() ?? '';
  }

  LocationWeather _normalize(LocationWeather location) {
    final address = _displayAddress(location);
    final name = location.locationName == '当前位置' && address.isNotEmpty
        ? address.split(RegExp(r'[·,，]')).first.trim()
        : location.locationName;
    return location.copyWith(
      locationName: name.isEmpty ? location.locationName : name,
    );
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
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selected;
    final address = _displayAddress(selected);

    return Scaffold(
      appBar: AppBar(
        title: const Text('地图选点'),
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
      body: Column(
        children: [
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            ),
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: _hasAmapKey
                      ? HtmlElementView(viewType: _mapViewType)
                      : const Center(child: Text('未配置高德地图 Key')),
                ),
                IgnorePointer(
                  child: Center(
                    child: Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: Colors.white, width: 3),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 16,
                  child: IgnorePointer(
                    ignoring: true,
                    child: Card(
                      elevation: 2,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _nameController.text.isEmpty
                                  ? '请移动地图或搜索地点'
                                  : _nameController.text,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (address.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Text(address,
                                  style: Theme.of(context).textTheme.bodySmall),
                            ],
                            if (selected != null) ...[
                              const SizedBox(height: 6),
                              Text(
                                '${selected.latitude.toStringAsFixed(6)}, ${selected.longitude.toStringAsFixed(6)}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                            const SizedBox(height: 10),
                            Text(
                              '请在地图页内直接搜索、定位、点击地图并确认。',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
