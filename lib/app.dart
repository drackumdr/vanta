import 'package:flutter/material.dart';

import 'models/device_model.dart';
import 'theme.dart';
import 'ui/dashboard_page.dart';
import 'ui/devices_page.dart';
import 'ui/device_form_page.dart';

class VantaApp extends StatelessWidget {
  const VantaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VANTA',
      debugShowCheckedModeBanner: false,
      theme: VantaTheme.dark(),
      home: const DashboardPage(),
      routes: {
        DevicesPage.route: (_) => const DevicesPage(),
        DeviceFormPage.route: (ctx) => DeviceFormPage(
              device:
                  ModalRoute.of(ctx)?.settings.arguments as Device?,
            ),
      },
    );
  }
}