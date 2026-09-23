import 'dart:convert';

import 'package:bluebubbles/utils/logger/logger.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:vector_map_tiles/vector_map_tiles.dart';
import 'package:vector_tile_renderer/vector_tile_renderer.dart' show ThemeReader, SpriteIndexReader;

/// The Apple Maps-inspired vector style shared with DealFinder (assets/maps/map-style.json): a curated,
/// recolored subset of OpenFreeMap's "liberty" style. Only the layer list and colors are bundled; tiles
/// and sprites come from tiles.openfreemap.org (free, no API key).
///
/// vector_map_tiles' own StyleReader only reads styles over HTTP, so this loads the bundled JSON and
/// resolves its sources the same way. Loaded once per app run; a failure resolves to null so the map
/// falls back to plain raster tiles instead of rendering nothing.
class FindMyMapStyle {
  static const attribution = '© OpenFreeMap © OpenMapTiles © OpenStreetMap contributors';

  static Future<Style?>? _style;

  static Future<Style?> load() => _style ??= _read().catchError((Object e, StackTrace s) {
        Logger.error("Failed to load the Find My map style, using raster tiles", error: e, trace: s);
        _style = null; // retry next time the page opens
        return null;
      });

  static Future<Style?> _read() async {
    final style = jsonDecode(await rootBundle.loadString('assets/maps/map-style.json')) as Map<String, dynamic>;
    final theme = ThemeReader().read(style);

    final providers = <String, VectorTileProvider>{};
    final sources = style['sources'] as Map<String, dynamic>;
    for (final name in theme.tileSources) {
      final source = sources[name];
      if (source is! Map || source['type'] != 'vector') continue;
      // "url" points at a TileJSON whose tile path carries a dated build id, so it's resolved live
      final tileJson = source['url'] is String ? jsonDecode(await _get(source['url'])) as Map : source;
      final tiles = tileJson['tiles'] as List;
      providers[name] = NetworkVectorTileProvider(
        urlTemplate: tiles.first as String,
        maximumZoom: tileJson['maxzoom'] as int? ?? 14,
        minimumZoom: tileJson['minzoom'] as int? ?? 0,
      );
    }

    SpriteStyle? sprites;
    final sprite = style['sprite'];
    if (sprite is String) {
      try {
        final index = jsonDecode(await _get('$sprite@2x.json'));
        sprites = SpriteStyle(
          atlasProvider: () async => (await http.get(Uri.parse('$sprite@2x.png'))).bodyBytes,
          index: SpriteIndexReader().read(index),
        );
      } catch (e) {
        // icons are optional; labels and shapes still render
        Logger.warn("Find My map sprites unavailable: $e");
      }
    }

    return Style(name: style['name'] as String?, theme: theme, providers: TileProviders(providers), sprites: sprites);
  }

  static Future<String> _get(String url) async {
    final response = await http.get(Uri.parse(url));
    if (response.statusCode != 200) throw 'HTTP ${response.statusCode} for $url';
    return response.body;
  }
}
