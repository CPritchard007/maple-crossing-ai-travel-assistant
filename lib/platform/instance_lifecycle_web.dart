import 'dart:js_interop';

@JS('mapleInstanceLifecycle')
external JSFunction? get _lifecycle;

void installInstanceClose(String url) =>
    _lifecycle?.callAsFunction(null, url.toJS);
void removeInstanceClose() => _lifecycle?.callAsFunction(null, null);
