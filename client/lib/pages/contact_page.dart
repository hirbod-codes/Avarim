import 'package:flutter/material.dart';

class ContactPage extends StatelessWidget {
  const ContactPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text('Contact us — coming soon.', style: Theme.of(context).textTheme.headlineSmall),
      ),
    );
  }
}
