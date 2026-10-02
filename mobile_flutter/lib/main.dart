import 'package:flutter/material.dart';

import 'app/cloud_only_app.dart';
import 'data/device_settings.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const CloudOnlyApp(settings: DeviceSettings()));
}
