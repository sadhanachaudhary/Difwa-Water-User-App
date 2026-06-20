import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../../../core/utils/loader_utils.dart';
import '../../../data/models/food_models.dart';
import '../../../data/services/db_service.dart';

class LocationPickerPage extends StatefulWidget {
  final UserAddress? initialAddress;
  const LocationPickerPage({super.key, this.initialAddress});

  @override
  State<LocationPickerPage> createState() => _LocationPickerPageState();
}

class _LocationPickerPageState extends State<LocationPickerPage> {
  final Completer<GoogleMapController> _controller = Completer<GoogleMapController>();
  LatLng _lastPickedLocation = const LatLng(20.5937, 78.9629); // Default to India
  String _address = "Picking location...";
  bool _isLoading = true;
  Placemark? _currentPlacemark;

  // Google Places Autocomplete state
  final TextEditingController _searchCtrl = TextEditingController();
  List<dynamic> _predictions = [];
  Timer? _debounce;
  final String _apiKey = dotenv.env['GOOGLE_MAPS_API_KEY'] ?? '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _getSuggestions(String input) async {
    if (input.isEmpty) {
      setState(() => _predictions = []);
      return;
    }

    final url =
        'https://maps.googleapis.com/maps/api/place/autocomplete/json?input=$input&key=$_apiKey&components=country:in';
    
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'OK') {
          setState(() => _predictions = data['predictions']);
        }
      }
    } catch (e) {
      debugPrint('Autocomplete Error: $e');
    }
  }

  Future<void> _getPlaceDetails(String placeId) async {
    setState(() => _isLoading = true);
    final url =
        'https://maps.googleapis.com/maps/api/place/details/json?place_id=$placeId&fields=geometry&key=$_apiKey';

    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'OK') {
          final lat = data['result']['geometry']['location']['lat'];
          final lng = data['result']['geometry']['location']['lng'];
          final pos = LatLng(lat, lng);
          
          final GoogleMapController controller = await _controller.future;
          controller.animateCamera(CameraUpdate.newCameraPosition(
            CameraPosition(target: pos, zoom: 17),
          ));
          _updateLocation(pos);
          setState(() {
            _predictions = [];
            _searchCtrl.clear();
          });
        }
      }
    } catch (e) {
      debugPrint('Place Details Error: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  void initState() {
    super.initState();
    if (widget.initialAddress != null) {
      final addr = widget.initialAddress!;
      if (addr.latitude != null && addr.longitude != null) {
        _lastPickedLocation = LatLng(addr.latitude!, addr.longitude!);
        _address = addr.street;
        _isLoading = false;
      } else {
        _determinePosition();
      }
    } else {
      _determinePosition();
    }
  }

  Future<void> _determinePosition() async {
    bool serviceEnabled;
    LocationPermission permission;

    setState(() => _isLoading = true);

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Location services are disabled.')));
      return;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Location permissions are denied.')));
        return;
      }
    }
    
    if (permission == LocationPermission.deniedForever) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Location permissions are permanently denied.')));
      return;
    } 

    Position position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
    _updateLocation(LatLng(position.latitude, position.longitude));
    
    final GoogleMapController controller = await _controller.future;
    controller.animateCamera(CameraUpdate.newCameraPosition(
      CameraPosition(target: LatLng(position.latitude, position.longitude), zoom: 17),
    ));
    
    setState(() => _isLoading = false);
  }

  Future<void> _updateLocation(LatLng position) async {
    setState(() {
      _lastPickedLocation = position;
      _address = "Loading address...";
    });

    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(position.latitude, position.longitude);
      if (placemarks.isNotEmpty) {
        Placemark place = placemarks[0];
        setState(() {
          _address = "${place.name}, ${place.subLocality}, ${place.locality}, ${place.postalCode}";
        });
        _currentPlacemark = place;
      }
    } catch (e) {
      setState(() => _address = "Address not found");
    }
  }

  void _showRefinementSheet() {
    final houseCtrl = TextEditingController(text: "${_currentPlacemark?.name ?? ''}, ${_currentPlacemark?.subLocality ?? ''}");
    final floorCtrl = TextEditingController(text: widget.initialAddress?.floorNumber?.toString() ?? '0');
    String selectedTag = 'Home';
    bool isSavingLocal = false;
    bool hasLift = widget.initialAddress?.hasLift ?? true;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
          ),
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 32,
            left: 24,
            right: 24,
            top: 32,
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Complete your address',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1A1A1A),
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'HOUSE / FLAT / BLOCK NO.',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey,
                      letterSpacing: 1.1),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: houseCtrl,
                  decoration: InputDecoration(
                    hintText: 'e.g. Flat 101, Block B',
                    filled: true,
                    fillColor: const Color(0xFFF7F8FA),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'FLOOR NUMBER',
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Colors.grey,
                                letterSpacing: 1.1),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: floorCtrl,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              hintText: 'e.g. 3',
                              filled: true,
                              fillColor: const Color(0xFFF7F8FA),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: BorderSide.none,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'LIFT AVAILABLE?',
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Colors.grey,
                                letterSpacing: 1.1),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Switch(
                                value: hasLift,
                                onChanged: (v) {
                                  setSheetState(() => hasLift = v);
                                },
                                activeColor: const Color(0xFF06B6D4),
                              ),
                              Text(
                                hasLift ? 'Yes' : 'No',
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                const Text(
                  'SAVE AS',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey,
                      letterSpacing: 1.1),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    {'tag': 'Home', 'icon': Icons.home_rounded},
                    {'tag': 'Office', 'icon': Icons.work_rounded},
                    {'tag': 'Other', 'icon': Icons.near_me_rounded},
                  ].map((item) {
                    final tag = item['tag'] as String;
                    final icon = item['icon'] as IconData;
                    bool isSelected = selectedTag == tag;
                    return Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(
                            right: tag == 'Other' ? 0 : 8),
                        child: ChoiceChip(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          label: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                icon,
                                size: 14,
                                color: isSelected ? Colors.white : Colors.grey,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                tag,
                                style: const TextStyle(fontSize: 11),
                              ),
                            ],
                          ),
                          selected: isSelected,
                          onSelected: (val) {
                            if (val) setSheetState(() => selectedTag = tag);
                          },
                          selectedColor: const Color(0xFF06B6D4),
                          labelStyle: TextStyle(
                            color: isSelected ? Colors.white : Colors.grey,
                            fontWeight: FontWeight.bold,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          showCheckmark: false,
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 40),
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: isSavingLocal ? null : () async {
                      setSheetState(() => isSavingLocal = true);
                      try {
                        final provider = CartProviderScope.of(context);
                        final String details = "${_currentPlacemark?.locality ?? ''}, ${_currentPlacemark?.administrativeArea ?? ''} ${_currentPlacemark?.postalCode ?? ''}";
                        
                        final isUpdate = widget.initialAddress != null;
                        
                        final newAddress = UserAddress(
                          id: isUpdate ? widget.initialAddress!.id : '',
                          title: selectedTag,
                          fullName: provider.userProfile.name,
                          email: provider.userProfile.email,
                          street: houseCtrl.text.trim(),
                          details: details,
                          isDefault: isUpdate ? widget.initialAddress!.isDefault : provider.addresses.isEmpty,
                          latitude: _lastPickedLocation.latitude,
                          longitude: _lastPickedLocation.longitude,
                          floorNumber: int.tryParse(floorCtrl.text) ?? 0,
                          hasLift: hasLift,
                        );
  
                        final result = await LoaderUtils.timedAction(context, () async {
                          return isUpdate 
                            ? await provider.updateAddress(newAddress)
                            : await provider.addAddress(newAddress);
                        });
                        if (result['success'] == true && mounted) {
                          Navigator.pop(sheetContext); // Close sheet
                          Navigator.pop(context, result['data']); // Return with data
                        } else if (mounted) {
                           ScaffoldMessenger.of(sheetContext).showSnackBar(SnackBar(content: Text(result['message'] ?? 'Failed to save address')));
                        }
                      } catch (e) {
                        if (mounted) ScaffoldMessenger.of(sheetContext).showSnackBar(SnackBar(content: Text('Error: $e')));
                      } finally {
                        if (mounted) setSheetState(() => isSavingLocal = false);
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF06B6D4),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    child: isSavingLocal 
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Text('Save Address', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pick Delivery Location', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: Stack(
        children: [
          GoogleMap(
            mapType: MapType.normal,
            initialCameraPosition: CameraPosition(target: _lastPickedLocation, zoom: 14),
            onMapCreated: (GoogleMapController controller) {
              _controller.complete(controller);
            },
            onCameraMove: (position) {
              _lastPickedLocation = position.target;
            },
            onCameraIdle: () {
              _updateLocation(_lastPickedLocation);
            },
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
          ),
          
          // Search Bar & Autocomplete Overlay
          Positioned(
            top: 16,
            left: 16,
            right: 16,
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 5))],
                  ),
                  child: TextField(
                    controller: _searchCtrl,
                    onChanged: (value) {
                      if (_debounce?.isActive ?? false) _debounce!.cancel();
                      _debounce = Timer(const Duration(milliseconds: 500), () {
                        _getSuggestions(value);
                      });
                    },
                    decoration: InputDecoration(
                      hintText: 'Search for area, landmark...',
                      border: InputBorder.none,
                      icon: const Icon(Icons.search, color: Color(0xFF06B6D4)),
                      hintStyle: const TextStyle(fontSize: 14, color: Colors.grey),
                      suffixIcon: _searchCtrl.text.isNotEmpty 
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () {
                              _searchCtrl.clear();
                              setState(() => _predictions = []);
                            },
                          )
                        : null,
                    ),
                  ),
                ),
                if (_predictions.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(top: 8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 5))],
                    ),
                    constraints: const BoxConstraints(maxHeight: 300),
                    child: ListView.separated(
                      shrinkWrap: true,
                      padding: EdgeInsets.zero,
                      itemCount: _predictions.length,
                      separatorBuilder: (context, index) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final p = _predictions[index];
                        return ListTile(
                          leading: const Icon(Icons.location_on_outlined, color: Colors.grey, size: 20),
                          title: Text(
                            p['description'],
                            style: const TextStyle(fontSize: 14),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () => _getPlaceDetails(p['place_id']),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),

          // Static Marker
          const Center(
            child: Padding(
              padding: EdgeInsets.only(bottom: 35),
              child: Icon(Icons.location_on, color: Colors.red, size: 50),
            ),
          ),
          // Loading Overlay
          if (_isLoading)
            const Center(child: CircularProgressIndicator(color: Color(0xFF06B6D4))),
          
          // Address Info Card
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, -5))],
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                     const Text("SELECT LOCATION", style: TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                     const SizedBox(height: 8),
                     Row(
                       children: [
                         const Icon(Icons.location_pin, color: Color(0xFF06B6D4), size: 20),
                         const SizedBox(width: 8),
                         Expanded(
                           child: Text(_address, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15), maxLines: 2, overflow: TextOverflow.ellipsis),
                         ),
                       ],
                     ),
                     const SizedBox(height: 24),
                     SizedBox(
                       width: double.infinity,
                       height: 54,
                       child: ElevatedButton(
                         onPressed: _showRefinementSheet,
                         style: ElevatedButton.styleFrom(
                           backgroundColor: const Color(0xFF06B6D4),
                           foregroundColor: Colors.white,
                           shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                           elevation: 0,
                         ),
                         child: const Text("Confirm Location", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                       ),
                     ),
                  ],
                ),
              ),
            ),
          ),
          
          // My Location Button
          Positioned(
            right: 20,
            bottom: 180,
            child: FloatingActionButton(
              onPressed: _determinePosition,
              backgroundColor: Colors.white,
              child: const Icon(Icons.my_location, color: Color(0xFF06B6D4)),
            ),
          ),
        ],
      ),
    );
  }
}
