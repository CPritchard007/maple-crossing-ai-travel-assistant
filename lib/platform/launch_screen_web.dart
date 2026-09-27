import 'dart:js_interop';

@JS('mapleLaunchReady')
external JSFunction? get _launchReady;

// An existing browser tab may predate the HTML splash during hot reload.
void finishLaunch() => _launchReady?.callAsFunction();
