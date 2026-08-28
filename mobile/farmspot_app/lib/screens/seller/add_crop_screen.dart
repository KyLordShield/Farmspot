import 'package:flutter/material.dart';
import '../../../theme.dart';
import '../../../widgets/seller_widgets.dart';
import 'farm_live_screen.dart';

enum AvailabilityStatus { availableNow, soonToHarvest, notAvailable }

class AddCropScreen extends StatefulWidget {
  /// True when this is the very first crop added right after farm setup —
  /// shows a simpler header and skips the "Which Farm?" picker, and finishes
  /// by navigating to the "Farm is Live" celebration screen instead of
  /// just popping back.
  final bool isFirstCrop;

  const AddCropScreen({super.key, this.isFirstCrop = false});

  @override
  State<AddCropScreen> createState() => _AddCropScreenState();
}

class _AddCropScreenState extends State<AddCropScreen> {
  static const _crops = [
    (Icons.grass, 'Carrot'),
    (Icons.eco, 'Cabbage'),
    (Icons.eco_outlined, 'Kangkong'),
    (Icons.local_fire_department, 'Chili'),
    (Icons.spa, 'Lettuce'),
    (Icons.add, 'Other'),
  ];

  int _selectedCropIndex = -1;
  int _selectedFarmIndex = 0;
  AvailabilityStatus _status = AvailabilityStatus.availableNow;
  int _photoCount = 0;

  void _submit() {
    if (widget.isFirstCrop) {
      final cropName =
          _selectedCropIndex >= 0 ? _crops[_selectedCropIndex].$2 : 'Cabbage';
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => FarmLiveScreen(cropName: cropName)),
      );
    } else {
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            SetupHeader(
              title: widget.isFirstCrop ? 'Add First Crop' : 'Add Crop',
              subtitle: widget.isFirstCrop
                  ? 'What are you selling this harvest?'
                  : 'Pick farm, crop, and availability',
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                children: [
                  if (!widget.isFirstCrop) ...[
                    const FieldLabel('WHICH FARM?'),
                    SelectableOptionTile(
                      icon: Icons.location_on,
                      title: 'Belle Farm • Maraag',
                      subtitle: 'Current location',
                      selected: _selectedFarmIndex == 0,
                      onTap: () => setState(() => _selectedFarmIndex = 0),
                    ),
                    SelectableOptionTile(
                      icon: Icons.location_on_outlined,
                      title: '2nd location',
                      subtitle: 'Different location',
                      selected: _selectedFarmIndex == 1,
                      onTap: () => setState(() => _selectedFarmIndex = 1),
                    ),
                    const SizedBox(height: 8),
                  ],
                  const FieldLabel('SELECT CROP'),
                  GridView.count(
                    crossAxisCount: 3,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 1.1,
                    children: List.generate(_crops.length, (i) {
                      return CropPickerTile(
                        icon: _crops[i].$1,
                        label: _crops[i].$2,
                        selected: _selectedCropIndex == i,
                        onTap: () => setState(() => _selectedCropIndex = i),
                      );
                    }),
                  ),
                  const SizedBox(height: 18),
                  const FieldLabel('SET AVAILABILITY STATUS'),
                  SelectableOptionTile(
                    icon: Icons.check_circle_outline,
                    title: 'Available Now',
                    subtitle: 'Ready for buyers to contact you',
                    selected: _status == AvailabilityStatus.availableNow,
                    onTap: () =>
                        setState(() => _status = AvailabilityStatus.availableNow),
                  ),
                  SelectableOptionTile(
                    icon: Icons.schedule,
                    title: 'Soon to Harvest',
                    subtitle: "Let buyers know it's coming",
                    selected: _status == AvailabilityStatus.soonToHarvest,
                    onTap: () =>
                        setState(() => _status = AvailabilityStatus.soonToHarvest),
                  ),
                  SelectableOptionTile(
                    icon: Icons.bedtime_outlined,
                    title: 'Not Available',
                    subtitle: 'Hidden from marketplace',
                    selected: _status == AvailabilityStatus.notAvailable,
                    onTap: () =>
                        setState(() => _status = AvailabilityStatus.notAvailable),
                  ),
                  const SizedBox(height: 10),
                  const FieldLabel('CROP PHOTOS', badge: '(optional, up to 5)', badgeColor: Colors.black38),
                  SizedBox(
                    height: 64,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        for (int i = 0; i < _photoCount; i++) ...[
                          const PhotoPlaceholder(),
                          const SizedBox(width: 10),
                        ],
                        if (_photoCount < 5)
                          PhotoPlaceholder(
                            isAddButton: true,
                            onTap: () => setState(() => _photoCount++),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 26),
                  WizardNextButton(
                    label: widget.isFirstCrop ? 'Add Crop & Go Live' : 'Add Crop',
                    icon: Icons.check,
                    onPressed: _submit,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
