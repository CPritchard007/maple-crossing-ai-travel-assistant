import 'package:flutter/material.dart';

import '../services/action_service.dart';

class ActionCommandForm extends StatefulWidget {
  const ActionCommandForm({super.key, required this.actions});

  final ActionService actions;

  static const testCase =
      'Let’s visit the Windsor tunnel entrance. '
      '((geo lat="42.3149" lng="-83.0364")) '
      'Now look at this highlighted section of Lauzon Road. '
      '((highlight name="Lauzon Road" type="hazard" path="42.326792,-82.9397677;42.3261168,-82.9393305;42.3254421,-82.938907;42.3246604,-82.9384236;42.3241214,-82.9380766;42.3236127,-82.9378624")) '
      'The test is complete. You have seen a location move, a road highlight, and spoken text.';

  @override
  State<ActionCommandForm> createState() => _ActionCommandFormState();
}

class _ActionCommandFormState extends State<ActionCommandForm> {
  final _controller = TextEditingController();
  bool _running = false;
  String? _message;
  bool _failed = false;

  Future<void> _run() async {
    final command = _controller.text.trim();
    if (_running || command.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _running = true;
      _message = null;
      _failed = false;
    });
    try {
      await widget.actions.execute(command);
      if (mounted) setState(() => _message = 'Actions completed.');
    } catch (error) {
      if (mounted) {
        setState(() {
          _failed = true;
          _message = error is FormatException
              ? error.message
              : error.toString();
        });
      }
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _controller,
          minLines: 4,
          maxLines: 8,
          keyboardType: TextInputType.multiline,
          style: const TextStyle(color: Colors.white, fontSize: 14),
          decoration: const InputDecoration(
            labelText: 'Action commands',
            labelStyle: TextStyle(color: Colors.white70),
            hintText: 'Paste text, ((geo ...)), or ((highlight ...)) commands',
            hintStyle: TextStyle(color: Colors.white54),
            filled: true,
            fillColor: Color(0xFF263238),
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: _controller,
          builder: (context, value, child) => FilledButton.icon(
            onPressed: _running || value.text.trim().isEmpty ? null : _run,
            icon: _running
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.play_arrow),
            label: Text(_running ? 'Running…' : 'Run actions'),
          ),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _running
              ? null
              : () {
                  _controller.text = ActionCommandForm.testCase;
                  _run();
                  Scaffold.maybeOf(context)?.closeDrawer();
                },
          icon: const Icon(Icons.science_outlined),
          label: const Text('Test narration, geo & highlight'),
        ),
        if (_message != null) ...[
          const SizedBox(height: 8),
          Semantics(
            liveRegion: true,
            child: Text(
              _message!,
              style: TextStyle(
                color: _failed ? Colors.redAccent.shade100 : Colors.greenAccent,
              ),
            ),
          ),
        ],
      ],
    );
  }
}
