import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class SupportButton extends StatelessWidget {
  const SupportButton({super.key});

  static final _url = Uri.parse('https://buymeacoffee.com/cpritchard007');

  Future<void> _openProfile(BuildContext context) async {
    try {
      if (await launchUrl(
        _url,
        mode: LaunchMode.externalApplication,
        webOnlyWindowName: '_blank',
      )) {
        return;
      }
    } catch (_) {
      // Show the same recovery message if the platform cannot open the link.
    }
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Could not open Buy Me a Coffee. Visit buymeacoffee.com/cpritchard007.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Support Maple Crossing (opens in your browser)',
      child: TextButton(
        onPressed: () => _openProfile(context),
        style: TextButton.styleFrom(
          padding: const EdgeInsets.all(4),
          minimumSize: const Size(48, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: Image.asset(
          'assets/images/buy-me-a-coffee.png',
          width: 240,
          height: 44,
          fit: BoxFit.contain,
          semanticLabel: 'Buy me a coffee',
          errorBuilder: (context, error, stackTrace) => Container(
            width: 240,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFFFFDD00),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.coffee_outlined, color: Colors.black),
                SizedBox(width: 10),
                Text(
                  'Buy me a coffee',
                  style: TextStyle(
                    color: Colors.black,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
