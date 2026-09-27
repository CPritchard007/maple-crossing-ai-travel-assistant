import 'package:flutter/material.dart';

import '../services/action_service.dart';

class ActionCommandForm extends StatefulWidget {
  const ActionCommandForm({super.key, required this.actions});

  final ActionService actions;

  static const testCase =
      '''((highlight name="Goyeau Street closure — Elliott to Wyandotte" type="hazard" path="42.3124467,-83.0334787;42.3125062,-83.0335170;42.3128685,-83.0337508;42.3132733,-83.0340109;42.3135108,-83.0341649;42.3135881,-83.0342157;42.3136746,-83.0342692;42.3139469,-83.0344446;42.3140101,-83.0344853;42.3142998,-83.0346723;42.3143721,-83.0347183;42.3145431,-83.0348282;42.3146953,-83.0349261;42.3147690,-83.0349738"))
Goyeau Street is closed between Elliott Street and Wyandotte Street. Avoid the highlighted red section.

((highlight name="Detour via Elliott Street, Ouellette Avenue and Wyandotte Street" type="summary" action="reroute" path="42.3124467,-83.0334787;42.3124003,-83.0336074;42.3123012,-83.0338908;42.3121437,-83.0343331;42.3120968,-83.0344652;42.3119593,-83.0348528;42.3118343,-83.0352051;42.3117850,-83.0353441;42.3118525,-83.0353893;42.3122261,-83.0356398;42.3123489,-83.0356603;42.3127742,-83.0359367;42.3128435,-83.0360246;42.3128884,-83.0360529;42.3129252,-83.0360766;42.3130238,-83.0360891;42.3134462,-83.0363513;42.3135469,-83.0364668;42.3140182,-83.0367641;42.3141189,-83.0368248;42.3141615,-83.0367037;42.3143141,-83.0362644;42.3144663,-83.0358275;42.3146146,-83.0354093;42.3147138,-83.0351295;42.3147690,-83.0349738"))
The blue route avoids the closure. Travel west on Elliott Street, turn right onto Ouellette Avenue, then turn right onto Wyandotte Street. Continue east to the north end of the closed section.

((highlight name="Ambassador Bridge" lat="42.3118477" lng="-83.0739929" highlight="destination" type="summary"))
The Ambassador Bridge option takes 29 minutes, including the drive and border wait, with a toll of 10 Canadian dollars for a passenger car.

((highlight name="Detroit–Windsor Tunnel" lat="42.3158962" lng="-83.0367874" highlight="destination" type="recommendation"))
The Detroit–Windsor Tunnel is the fastest and cheapest of the two options compared. Total travel time is 18 minutes, including the detour and border wait, with a toll of 7 Canadian dollars for a passenger car. This option saves 11 minutes and 3 Canadian dollars. Use the tunnel for this trip.''';

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
