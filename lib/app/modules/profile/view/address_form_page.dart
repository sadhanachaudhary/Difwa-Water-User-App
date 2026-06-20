import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../data/models/food_models.dart';
import '../../../data/services/db_service.dart';
import '../../../core/constants/app_colors.dart';
import '../../../routes/app_routes.dart';

class AddressFormPage extends StatefulWidget {
  final UserAddress? address;
  final Map<String, dynamic>? initialData;

  const AddressFormPage({super.key, this.address, this.initialData});

  @override
  State<AddressFormPage> createState() => _AddressFormPageState();
}

class _AddressFormPageState extends State<AddressFormPage> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _titleCtrl;
  late TextEditingController _streetCtrl;
  late TextEditingController _cityCtrl;
  late TextEditingController _stateCtrl;
  late TextEditingController _pincodeCtrl;
  late TextEditingController _floorNumberCtrl;
  late bool _isDefault;
  late bool _hasLift;
  double? _latitude;
  double? _longitude;

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(text: widget.address?.title ?? 'Home');
    _streetCtrl = TextEditingController(text: widget.address?.street ?? '');
    _latitude = widget.address?.latitude;
    _longitude = widget.address?.longitude;
    _floorNumberCtrl = TextEditingController(text: widget.address?.floorNumber?.toString() ?? '0');
    _hasLift = widget.address?.hasLift ?? true;

    // Parse details string back to discrete parts if editing
    String city = '';
    String state = '';
    String pincode = '';
    
    if (widget.address != null) {
      final details = widget.address!.details;
      final parts = details.split(',');
      if (parts.isNotEmpty) {
        city = parts[0].trim();
        if (parts.length > 1) {
          final statePin = parts[1].trim();
          if (statePin.contains(' ')) {
            pincode = statePin.split(' ').last;
            state = statePin.substring(0, statePin.lastIndexOf(' ')).trim();
          } else {
            state = statePin;
          }
        }
      }
    } else if (widget.initialData != null) {
      // Pre-fill from Map data
      _streetCtrl.text = widget.initialData!['street'] ?? '';
      city = widget.initialData!['city'] ?? '';
      state = widget.initialData!['state'] ?? '';
      pincode = widget.initialData!['pincode'] ?? '';
      _latitude = widget.initialData!['latitude'];
      _longitude = widget.initialData!['longitude'];
      _floorNumberCtrl.text = widget.initialData!['floorNumber']?.toString() ?? '0';
      _hasLift = widget.initialData!['hasLift'] == true;
    }

    _cityCtrl = TextEditingController(text: city);
    _stateCtrl = TextEditingController(text: state);
    _pincodeCtrl = TextEditingController(text: pincode);
    _isDefault = widget.address?.isDefault ?? false;

    if (widget.address == null) {
      _loadAddressDraft().then((_) {
        _setupDraftListeners();
      });
    }
  }

  @override
  void dispose() {
    if (widget.address == null) {
      _titleCtrl.removeListener(_saveAddressDraft);
      _streetCtrl.removeListener(_saveAddressDraft);
      _cityCtrl.removeListener(_saveAddressDraft);
      _stateCtrl.removeListener(_saveAddressDraft);
      _pincodeCtrl.removeListener(_saveAddressDraft);
    }
    _titleCtrl.dispose();
    _streetCtrl.dispose();
    _cityCtrl.dispose();
    _stateCtrl.dispose();
    _pincodeCtrl.dispose();
    _floorNumberCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAddressDraft() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final title = prefs.getString('address_draft_title');
      final street = prefs.getString('address_draft_street');
      final city = prefs.getString('address_draft_city');
      final state = prefs.getString('address_draft_state');
      final pincode = prefs.getString('address_draft_pincode');
      final lat = prefs.getDouble('address_draft_lat');
      final lng = prefs.getDouble('address_draft_lng');

      if (mounted) {
        setState(() {
          if (title != null && title.isNotEmpty) _titleCtrl.text = title;
          if (street != null && street.isNotEmpty) _streetCtrl.text = street;
          if (city != null && city.isNotEmpty) _cityCtrl.text = city;
          if (state != null && state.isNotEmpty) _stateCtrl.text = state;
          if (pincode != null && pincode.isNotEmpty) _pincodeCtrl.text = pincode;
          if (lat != null) _latitude = lat;
          if (lng != null) _longitude = lng;
        });
      }
    } catch (e) {
      debugPrint('Error loading address draft: $e');
    }
  }

  void _setupDraftListeners() {
    _titleCtrl.addListener(_saveAddressDraft);
    _streetCtrl.addListener(_saveAddressDraft);
    _cityCtrl.addListener(_saveAddressDraft);
    _stateCtrl.addListener(_saveAddressDraft);
    _pincodeCtrl.addListener(_saveAddressDraft);
  }

  Future<void> _saveAddressDraft() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('address_draft_title', _titleCtrl.text);
      await prefs.setString('address_draft_street', _streetCtrl.text);
      await prefs.setString('address_draft_city', _cityCtrl.text);
      await prefs.setString('address_draft_state', _stateCtrl.text);
      await prefs.setString('address_draft_pincode', _pincodeCtrl.text);
      if (_latitude != null) {
        await prefs.setDouble('address_draft_lat', _latitude!);
      } else {
        await prefs.remove('address_draft_lat');
      }
      if (_longitude != null) {
        await prefs.setDouble('address_draft_lng', _longitude!);
      } else {
        await prefs.remove('address_draft_lng');
      }
    } catch (e) {
      debugPrint('Error saving address draft: $e');
    }
  }

  Future<void> _clearAddressDraft() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('address_draft_title');
      await prefs.remove('address_draft_street');
      await prefs.remove('address_draft_city');
      await prefs.remove('address_draft_state');
      await prefs.remove('address_draft_pincode');
      await prefs.remove('address_draft_lat');
      await prefs.remove('address_draft_lng');
    } catch (e) {
      debugPrint('Error clearing address draft: $e');
    }
  }

  bool _isSaving = false;

  Future<void> _save(BuildContext context) async {
    if (_formKey.currentState!.validate()) {
      setState(() => _isSaving = true);
      try {
        final provider = CartProviderScope.of(context);
        
        // AUTO-FILL: Default to profile name/email if empty
        final String name = provider.userProfile.name;
        final String email = provider.userProfile.email;
        final String title = _titleCtrl.text.trim().isEmpty ? 'Home' : _titleCtrl.text.trim();

        final String details = '${_cityCtrl.text.trim()}, ${_stateCtrl.text.trim()} ${_pincodeCtrl.text.trim()}';

        final newAddress = UserAddress(
          id: widget.address?.id ?? '',
          title: title,
          fullName: name, 
          email: email,    
          street: _streetCtrl.text.trim(),
          details: details,
          isDefault: _isDefault,
          latitude: _latitude,
          longitude: _longitude,
          floorNumber: int.tryParse(_floorNumberCtrl.text) ?? 0,
          hasLift: _hasLift,
        );

        Map<String, dynamic> result;
        if (widget.address == null) {
          result = await provider.addAddress(newAddress);
        } else {
          result = await provider.updateAddress(newAddress);
        }
        
        final bool isSuccess = result['success'] == true || result['data'] != null || result['_id'] != null;
        if (mounted) {
          if (isSuccess) {
            await _clearAddressDraft();
            Navigator.pop(context);
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(result['message'] ?? 'Failed to save address'),
                backgroundColor: Colors.redAccent,
              ),
            );
          }
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error saving address: $e')),
          );
        }
      } finally {
        if (mounted) setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _pickFromMap() async {
    final result = await Navigator.pushNamed(context, AppRoutes.locationPicker);

    if (result != null && result is Map) {
      setState(() {
        _streetCtrl.text = result['street'] ?? '';
        _cityCtrl.text = result['city'] ?? '';
        _stateCtrl.text = result['state'] ?? '';
        _pincodeCtrl.text = result['pincode'] ?? '';
        _latitude = result['latitude'];
        _longitude = result['longitude'];
        // Ensure Tag is never empty for fast-track
        if (_titleCtrl.text.isEmpty) _titleCtrl.text = 'Home';
      });
      // FAST-TRACK: Automatically save and return after map pick
      if (mounted) _save(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        title: Text(
          widget.address == null ? 'Add New Address' : 'Edit Address',
          style: const TextStyle(
            color: Color(0xFF1A1A1A),
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF1A1A1A)),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Map Picker Button
              InkWell(
                onTap: _pickFromMap,
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: AppColors.primary,
                        radius: 20,
                        child: Icon(
                            _latitude != null ? Icons.check_circle : Icons.map,
                            color: Colors.white,
                            size: 20),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                                _latitude != null
                                    ? 'Location Selected'
                                    : 'Pick from Map',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF1A1A1A))),
                            Text(
                                _latitude != null && _longitude != null
                                    ? 'Coordinates: ${_latitude!.toStringAsFixed(4)}, ${_longitude!.toStringAsFixed(4)}'
                                    : 'Set your location for accurate delivery',
                                style: TextStyle(
                                    color: _latitude != null
                                        ? AppColors.primary
                                        : Colors.grey,
                                    fontSize: 12)),
                          ],
                        ),
                      ),
                      const Icon(Icons.refresh, color: AppColors.primary, size: 20),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 32),
              _buildTagSelector(),
              const SizedBox(height: 16),

              const SizedBox(height: 16),
              _buildField(
                controller: _streetCtrl,
                label: 'House / Flat / Floor *',
                hint: 'Flat No, Floor, etc.',
                icon: Icons.home_work_outlined,
                validator: (v) => v!.isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _buildField(
                      controller: _cityCtrl,
                      label: 'City',
                      hint: 'Indore',
                      icon: Icons.location_city_outlined,
                      validator: (v) => v!.isEmpty ? 'Required' : null,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildField(
                      controller: _stateCtrl,
                      label: 'State',
                      hint: 'MP',
                      icon: Icons.map_outlined,
                      validator: (v) => v!.isEmpty ? 'Required' : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _buildField(
                controller: _pincodeCtrl,
                label: 'Pincode',
                hint: '123456',
                icon: Icons.pin_drop_outlined,
                keyboardType: TextInputType.number,
                maxLength: 6,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                validator: (v) {
                  if (v!.isEmpty) return 'Please enter pincode';
                  if (!RegExp(r'^\d{6}$').hasMatch(v)) {
                    return 'Please enter a valid 6-digit pincode';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _buildField(
                      controller: _floorNumberCtrl,
                      label: 'Floor Number *',
                      hint: 'e.g. 3',
                      icon: Icons.layers_outlined,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      validator: (v) => v!.isEmpty ? 'Required' : null,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Lift Available?',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey.shade700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Transform.scale(
                              scale: 0.9,
                              child: Switch(
                                value: _hasLift,
                                onChanged: (v) => setState(() => _hasLift = v),
                                activeThumbColor: AppColors.primary,
                                activeTrackColor: AppColors.primaryLight,
                              ),
                            ),
                            Text(
                              _hasLift ? 'Yes' : 'No',
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
              Row(
                children: [
                   Transform.scale(
                    scale: 0.9,
                    child: Switch(
                      value: _isDefault,
                      onChanged: (v) => setState(() => _isDefault = v),
                      activeThumbColor: AppColors.primary,
                      activeTrackColor: AppColors.primaryLight,
                    ),
                  ),
                  const Text(
                    'Set as default address',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1A1A1A),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 40),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _isSaving ? null : () => _save(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 0,
                  ),
                  child: _isSaving
                      ? const SizedBox(
                          height: 24,
                          width: 24,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : Text(
                          widget.address == null ? 'Save Address' : 'Update Address',
                          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTagSelector() {
    final tags = [
      {'label': 'Home', 'icon': Icons.home_rounded},
      {'label': 'Office', 'icon': Icons.work_rounded},
      {'label': 'Other', 'icon': Icons.near_me_rounded},
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Save as',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: Color(0xFF1A1A1A),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: tags.map((tag) {
            final isSelected = _titleCtrl.text.toLowerCase() == tag['label'].toString().toLowerCase();
            return GestureDetector(
              onTap: () {
                setState(() {
                  _titleCtrl.text = tag['label'].toString();
                });
              },
              child: Container(
                margin: const EdgeInsets.only(right: 12),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: isSelected ? Colors.black : const Color(0xFFF1F4F8),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(
                    color: isSelected ? Colors.black : Colors.transparent,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      tag['icon'] as IconData,
                      size: 18,
                      color: isSelected ? Colors.white : Colors.black87,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      tag['label'].toString(),
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: isSelected ? Colors.white : Colors.black87,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    TextInputType? keyboardType,
    int? maxLength,
    List<TextInputFormatter>? inputFormatters,
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: Colors.grey.shade700,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          validator: validator,
          keyboardType: keyboardType,
          maxLength: maxLength,
          inputFormatters: inputFormatters,
          style: const TextStyle(fontWeight: FontWeight.w500),
          decoration: InputDecoration(
            counterText: '',
            hintText: hint,
            hintStyle: TextStyle(color: Colors.grey.shade400, fontWeight: FontWeight.w400),
            prefixIcon: Icon(icon, size: 22, color: Colors.grey),
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey.shade200),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey.shade200),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Colors.redAccent, width: 1),
            ),
          ),
        ),
      ],
    );
  }
}
