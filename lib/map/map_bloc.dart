
import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';
import 'dart:math';

import 'package:flutter/services.dart' show ByteData, rootBundle;
import 'package:bloc/bloc.dart';

import 'package:fluster/fluster.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:image/image.dart' as images;

import 'map_marker.dart';
import 'map_state.dart';
import 'map_event.dart';

class MapBloc extends Bloc<MapEvent, MapState> {
  static const maxZoom = 21;
  static const thumbnailWidth = 64;

  // Current pool of available media that can be displayed on the map.
  final Map<String, MapMarker> _mediaPool;

  /// Markers currently displayed on the map.
  final _markerController = StreamController<Map<MarkerId, Marker>>.broadcast();

  /// Camera zoom level after end of user gestures / movement.
  final _cameraZoomController = StreamController<double>.broadcast();

  /// Outputs.
  Stream<Map<MarkerId, Marker>> get markers => _markerController.stream;
  Stream<double> get cameraZoom => _cameraZoomController.stream;

  /// Inputs.
  Function(Map<MarkerId, Marker>) get addMarkers => _markerController.sink.add;
  Function(double) get setCameraZoom => _cameraZoomController.sink.add;

  /// Internal listener.
  StreamSubscription _cameraZoomSubscription;

  /// Keep track of the current Google Maps zoom level.
  var _currentZoom = 12.0; // As per _initialCameraPosition in main.dart

  /// Fluster!
  Fluster<MapMarker> _fluster;

  @override
  MapState get initialState => MapInitial();

  @override
  Stream<MapState> mapEventToState(MapEvent event) async* {
    if (event is MapLoad) {
      _buildMediaPool();
      yield MapLoading();
    }
    if(event is MapMovementStart) {
      _displayMarkers(event.zoom);
      yield MapMovementStarted();
    }
    if(event is MapMovementStop) {
      yield MapMovementStopped();
    }
    if(event is MapMarkerTap) {
      yield MapMarkerTapped(zoom: event.addZoom);
    }
  }

  MapBloc() : _mediaPool = LinkedHashMap<String, MapMarker>();

  @override
  dispose() {
    super.dispose();
    _cameraZoomSubscription.cancel();

    _markerController.close();
    _cameraZoomController.close();
  }

  _buildMediaPool() async {
    var response = await _parsedApiResponse();

    _mediaPool.addAll(response);

    _fluster = Fluster<MapMarker>(
        minZoom: 0,
        maxZoom: maxZoom,
        radius: thumbnailWidth*4,
        extent: 2048,
        nodeSize: 32,
        points: _mediaPool.values.toList(),
        createCluster:
            (BaseCluster cluster, double longitude, double latitude) =>
                MapMarker(
                    locationName: null,
                    latitude: latitude,
                    longitude: longitude,
                    isCluster: true,
                    clusterId: cluster.id,
                    pointsSize: cluster.pointsSize,
                    markerId: cluster.id.toString(),
                    childMarkerId: cluster.childMarkerId));

    _displayMarkers(_currentZoom);
  }

  _displayMarkers(double zoom) async {
    if (_fluster == null) {
      return;
    }

    // Get the clusters at the current zoom level.
    List<MapMarker> clusters =
        _fluster.clusters([-180, -85, 180, 85], zoom.toInt());

    // Finalize the markers to display on the map.
    Map<MarkerId, Marker> markers = Map();

    for (MapMarker feature in clusters) {
      BitmapDescriptor bitmapDescriptor;

      if (feature.isCluster) {
        bitmapDescriptor = await _createClusterBitmapDescriptor(feature);
      } else {
        bitmapDescriptor =
            await _createImageBitmapDescriptor(feature.thumbnailSrc);
      }

      var marker = Marker(
          markerId: MarkerId(feature.markerId),
          position: LatLng(feature.latitude, feature.longitude),
          infoWindow: feature.isCluster ? InfoWindow.noText : InfoWindow(title: feature.locationName),
          icon: bitmapDescriptor,
          onTap: () {feature.isCluster ? MapMarkerTap(addZoom: 5.0) : _getInfo();}
         );

      markers.putIfAbsent(MarkerId(feature.markerId), () => marker);
    }

    // Publish markers to subscribers.
    addMarkers(markers);
  }

  void _getInfo()
  {

  }

  Future<BitmapDescriptor> _createClusterBitmapDescriptor(
      MapMarker feature) async {
    MapMarker childMarker = _mediaPool[feature.childMarkerId];

    var child = await _createImage(
        childMarker.thumbnailSrc, thumbnailWidth, thumbnailWidth);

    if (child == null) {
      return null;
    }

    images.brightness(child, -50);
    images.drawString(child, images.arial_24, 16, 12, feature.pointsSize.toString());

    var resized =
        images.copyResize(child, width: thumbnailWidth, height: thumbnailWidth);

    var png = images.encodePng(resized);

    return BitmapDescriptor.fromBytes(png);
  }

  Future<BitmapDescriptor> _createImageBitmapDescriptor(
      String thumbnailSrc) async {
    var resized =
        await _createImage(thumbnailSrc, thumbnailWidth, thumbnailWidth);

    if (resized == null) {
      return null;
    }

    var png = images.encodePng(resized);

    return BitmapDescriptor.fromBytes(png);
  }

  Future<images.Image> _createImage(
      String imageFile, int width, int height) async {
    ByteData imageData;
    try {
      imageData = await rootBundle.load('assets/images/$imageFile');
    } catch (e) {
      print('caught $e');
      return null;
    }

    if (imageData == null) {
      return null;
    }

    List<int> bytes = Uint8List.view(imageData.buffer);
    var image = images.decodeImage(bytes);

    return images.copyResize(image, width: width, height: height);
  }

  /// Hard-coded example of what could be returned from some API call.
  /// The item IDs should be different that possible cluster IDs since we're
  /// using a Map data structure where the keys are either these item IDs or
  /// the cluster IDs.
  Future<Map<String, MapMarker>> _parsedApiResponse() async {
    await Future.delayed(const Duration(milliseconds: 2000), () {});
    Map<String,MapMarker> markers = new Map<String,MapMarker>();
    Random rand = new Random(DateTime.now().millisecondsSinceEpoch);
      for(var i = 0; i < 45; i++ ) {
        markers[i.toString()] = MapMarker(
            locationName: 'Place No. '+ i.toString(),
            markerId: i.toString(),
            latitude: 56.01 + rand.nextDouble(),
            longitude: 59.52 + rand.nextDouble(),
            thumbnailSrc:'pin.png');
      }
    return markers;
  }
}