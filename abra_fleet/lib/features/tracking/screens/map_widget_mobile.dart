// lib/features/tracking/screens/map_widget_mobile.dart
// Used on Android / iOS — wraps a WebViewController running Leaflet.
// NOT compiled on Flutter Web (conditional import in enhanced_tracking_screen.dart).

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'dart:convert';
import 'package:abra_fleet/core/services/enhanced_customer_tracking_service.dart';

// ============================================================================
// LEAFLET MAP CONTROLLER — push data into the WebView via JS injection
// ============================================================================
class LeafletMapController {
  WebViewController? _webViewController;
  bool _mapReady = false;
  TripTrackingData? _pendingData;

  void _attach(WebViewController controller) {
    _webViewController = controller;
  }

  void _onMapReady() {
    _mapReady = true;
    if (_pendingData != null) {
      updateMapData(_pendingData!);
      _pendingData = null;
    }
  }

  /// Call this every time new tracking data arrives to update the Leaflet map.
  void updateMapData(TripTrackingData data) {
    if (_webViewController == null || !_mapReady) {
      _pendingData = data;
      return;
    }

    final driverLoc = data.driverLocation;
    final payload = {
      'driverName': data.driver?.name ?? '',
      'vehicleNumber': data.vehicle?.registrationNumber ?? '',
      'driverLocation': driverLoc != null
          ? {
              'latitude': driverLoc.latitude,
              'longitude': driverLoc.longitude,
              'speed': (driverLoc.speed ?? 0) * 3.6,
              'heading': driverLoc.heading ?? 0,
            }
          : null,
      'stops': [
        {
          'type': 'pickup',
          'location': {
            'coordinates': {
              'latitude': data.customerLocation.latitude,
              'longitude': data.customerLocation.longitude,
            },
            'address': 'Pickup Location',
          },
          'customer': {'name': ''},
        },
      ],
    };

    final jsonStr = jsonEncode(payload);
    _webViewController!.runJavaScript('window.updateMapData($jsonStr);');
  }
}

// ============================================================================
// LEAFLET MAP WIDGET — self-contained Leaflet HTML in a WebView
// ============================================================================
class LeafletMapWidget extends StatefulWidget {
  final void Function(LeafletMapController controller)? onControllerReady;

  const LeafletMapWidget({Key? key, this.onControllerReady}) : super(key: key);

  @override
  State<LeafletMapWidget> createState() => _LeafletMapWidgetState();
}

class _LeafletMapWidgetState extends State<LeafletMapWidget> {
  late final WebViewController _webViewController;
  final LeafletMapController _controller = LeafletMapController();

  @override
  void initState() {
    super.initState();
    _webViewController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFFF0F4FF))
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (url) {
            _controller._onMapReady();
          },
        ),
      )
      ..loadHtmlString(_buildLeafletHtml());

    _controller._attach(_webViewController);
    widget.onControllerReady?.call(_controller);
  }

  String _buildLeafletHtml() {
    return '''<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8"/>
  <meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no"/>
  <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/leaflet/1.9.4/leaflet.min.css"/>
  <style>
    *,*::before,*::after{box-sizing:border-box;margin:0;padding:0}
    html,body{height:100%;width:100%;overflow:hidden;background:#F0F4FF;}
    #map{position:absolute;inset:0;z-index:1;}
    #no-gps{
      position:absolute;top:50%;left:50%;transform:translate(-50%,-50%);
      background:white;border-radius:16px;padding:24px 28px;text-align:center;
      box-shadow:0 8px 40px rgba(13,71,161,0.18);z-index:300;display:none;max-width:260px;
    }
    #no-gps.show{display:block;}
    #no-gps .icon{font-size:40px;margin-bottom:10px;}
    #no-gps h3{font-size:15px;font-weight:800;color:#1A237E;margin-bottom:4px;}
    #no-gps p{font-size:12px;color:#5C6BC0;line-height:1.5;}
    .leaflet-control-attribution{font-size:9px!important;}
    @keyframes markerPulse{
      0%,100%{box-shadow:0 4px 16px rgba(13,71,161,0.5);}
      50%{box-shadow:0 4px 28px rgba(13,71,161,0.85),0 0 0 10px rgba(13,71,161,0.1);}
    }
  </style>
</head>
<body>
  <div id="map"></div>
  <div id="no-gps">
    <div class="icon">📡</div>
    <h3>GPS Signal Unavailable</h3>
    <p>Driver\'s location will appear here once tracking begins.</p>
  </div>
  <script src="https://cdnjs.cloudflare.com/ajax/libs/leaflet/1.9.4/leaflet.min.js"></script>
  <script>
  (function(){
    'use strict';
    var map = L.map('map',{center:[12.9716,77.5946],zoom:13,zoomControl:true});
    L.tileLayer('https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}.png',{
      attribution:'© OpenStreetMap © CARTO',
      subdomains:['a','b','c','d'],
      maxZoom:19,
    }).addTo(map);

    var vehicleMarker=null, routeLine=null, stopMarkers=[], firstLoad=true;

    function vehicleIcon(){
      return L.divIcon({
        className:'',iconSize:[48,48],iconAnchor:[24,24],
        html:'<div style="width:48px;height:48px;background:linear-gradient(135deg,#0D47A1,#1E88E5);border-radius:50%;border:3px solid white;box-shadow:0 4px 16px rgba(13,71,161,0.5);display:flex;align-items:center;justify-content:center;animation:markerPulse 2s ease-in-out infinite;"><svg width=26 height=26 viewBox=\\"0 0 24 24\\" fill=\\"white\\"><path d=\\"M18.92 6.01C18.72 5.42 18.16 5 17.5 5h-11c-.66 0-1.21.42-1.42 1.01L3 12v8c0 .55.45 1 1 1h1c.55 0 1-.45 1-1v-1h12v1c0 .55.45 1 1 1h1c.55 0 1-.45 1-1v-8l-2.08-5.99zM6.5 16c-.83 0-1.5-.67-1.5-1.5S5.67 13 6.5 13s1.5.67 1.5 1.5S7.33 16 6.5 16zm11 0c-.83 0-1.5-.67-1.5-1.5s.67-1.5 1.5-1.5 1.5.67 1.5 1.5-.67 1.5-1.5 1.5zM5 11l1.5-4.5h11L19 11H5z\\"/></svg></div>'
      });
    }
    function pickupIcon(){
      return L.divIcon({
        className:'',iconSize:[34,34],iconAnchor:[17,34],
        html:'<div style="width:34px;height:34px;background:linear-gradient(135deg,#00C853,#00E676);border-radius:50% 50% 50% 0;transform:rotate(-45deg);border:3px solid white;box-shadow:0 3px 10px rgba(0,200,83,0.45);display:flex;align-items:center;justify-content:center;"><svg width=16 height=16 viewBox=\\"0 0 24 24\\" fill=\\"white\\" style=\\"transform:rotate(45deg)\\"><path d=\\"M12 2C8.13 2 5 5.13 5 9c0 5.25 7 13 7 13s7-7.75 7-13c0-3.87-3.13-7-7-7zm0 9.5c-1.38 0-2.5-1.12-2.5-2.5s1.12-2.5 2.5-2.5 2.5 1.12 2.5 2.5-1.12 2.5-2.5 2.5z\\"/></svg></div>'
      });
    }
    function dropIcon(){
      return L.divIcon({
        className:'',iconSize:[34,34],iconAnchor:[17,34],
        html:'<div style="width:34px;height:34px;background:linear-gradient(135deg,#F44336,#FF6F60);border-radius:50% 50% 50% 0;transform:rotate(-45deg);border:3px solid white;box-shadow:0 3px 10px rgba(244,67,54,0.45);display:flex;align-items:center;justify-content:center;"><svg width=16 height=16 viewBox=\\"0 0 24 24\\" fill=\\"white\\" style=\\"transform:rotate(45deg)\\"><path d=\\"M12 2C8.13 2 5 5.13 5 9c0 5.25 7 13 7 13s7-7.75 7-13c0-3.87-3.13-7-7-7zm0 9.5c-1.38 0-2.5-1.12-2.5-2.5s1.12-2.5 2.5-2.5 2.5 1.12 2.5 2.5-1.12 2.5-2.5 2.5z\\"/></svg></div>'
      });
    }

    function drawRoute(vLat,vLng,dLat,dLng){
      if(routeLine){map.removeLayer(routeLine);}
      if(!dLat||!dLng) return;
      routeLine=L.polyline([[vLat,vLng],[dLat,dLng]],{color:'#1E88E5',weight:4,dashArray:'8,6',opacity:0.8}).addTo(map);
    }

    window.updateMapData = function(json){
      try{
        var data = typeof json==='string'? JSON.parse(json): json;
        var loc = data.driverLocation;
        var stops = data.stops||[];
        var noGps = document.getElementById('no-gps');
        var hasGPS = loc && loc.latitude && loc.longitude;

        stopMarkers.forEach(function(m){map.removeLayer(m);});
        stopMarkers=[];

        if(!hasGPS){
          noGps.classList.add('show');
          var validStops=[];
          stops.forEach(function(stop){
            if(!stop.location||!stop.location.coordinates) return;
            var lat=stop.location.coordinates.latitude;
            var lng=stop.location.coordinates.longitude;
            var isPickup=stop.type==='pickup';
            var m=L.marker([lat,lng],{icon:isPickup?pickupIcon():dropIcon()}).addTo(map);
            m.bindPopup('<b>'+(isPickup?'🟢 Pickup':'🔴 Drop')+'</b><br>'+(stop.location.address||''));
            stopMarkers.push(m);
            validStops.push([lat,lng]);
          });
          if(validStops.length>0){map.fitBounds(L.latLngBounds(validStops),{padding:[50,50]});}
          return;
        }

        noGps.classList.remove('show');
        var latlng=[loc.latitude,loc.longitude];

        if(!vehicleMarker){
          vehicleMarker=L.marker(latlng,{icon:vehicleIcon(),zIndexOffset:1000}).addTo(map);
          vehicleMarker.bindPopup('<b>'+(data.vehicleNumber||'')+'</b><br>'+(data.driverName||''));
        } else {
          vehicleMarker.setLatLng(latlng);
          vehicleMarker.setIcon(vehicleIcon());
        }

        stops.forEach(function(stop){
          if(!stop.location||!stop.location.coordinates) return;
          var lat=stop.location.coordinates.latitude;
          var lng=stop.location.coordinates.longitude;
          var isPickup=stop.type==='pickup';
          var m=L.marker([lat,lng],{icon:isPickup?pickupIcon():dropIcon()}).addTo(map);
          m.bindPopup('<b>'+(isPickup?'🟢 Pickup':'🔴 Drop')+'</b><br>'+(stop.location.address||''));
          stopMarkers.push(m);
        });

        var lastDrop=null;
        for(var i=stops.length-1;i>=0;i--){
          if(stops[i].type==='drop'&&stops[i].location&&stops[i].location.coordinates){
            lastDrop=stops[i];break;
          }
        }
        if(lastDrop){
          drawRoute(loc.latitude,loc.longitude,lastDrop.location.coordinates.latitude,lastDrop.location.coordinates.longitude);
        }

        if(firstLoad){
          map.setView(latlng,15,{animate:true});
          firstLoad=false;
        }
      }catch(e){console.warn('updateMapData error:',e);}
    };
  })();
  </script>
</body>
</html>''';
  }

  @override
  Widget build(BuildContext context) {
    return WebViewWidget(controller: _webViewController);
  }
}