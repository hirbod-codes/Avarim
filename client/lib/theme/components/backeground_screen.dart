import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class PersianBackgroundScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Background Layer
          Positioned.fill(
            child: SvgPicture.asset(
              'assets/background.svg',
              fit: BoxFit.cover, // Ensures the 100% width/height fills the screen
            ),
          ),

          // Foreground App Content
          SafeArea(
            child: Center(
              child: Text('Your App Content Here', style: TextStyle(color: Colors.white, fontSize: 24)),
            ),
          ),
        ],
      ),
    );
  }
}
