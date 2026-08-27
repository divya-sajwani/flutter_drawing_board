import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_drawing_board/paint_contents.dart';
import 'package:flutter_test/flutter_test.dart';

const Size _size = Size(64, 64);

Future<Uint8List> _render(SimpleLine line) async {
  final ui.PictureRecorder recorder = ui.PictureRecorder();
  final Canvas canvas = Canvas(recorder, Offset.zero & _size);
  line.draw(canvas, _size, true);
  final ui.Image image = await recorder.endRecording().toImage(64, 64);
  final ByteData data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  return data.buffer.asUint8List();
}

SimpleLine _line() {
  final SimpleLine line = SimpleLine()
    ..paint = (Paint()
      ..color = Colors.black
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round);
  return line;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a settled stroke renders identically once its path is cached', () async {
    final SimpleLine line = _line();
    line.startDraw(const Offset(4, 4));
    for (int i = 1; i <= 10; i++) {
      line.drawing(Offset(4.0 + i * 5, 4.0 + i * 4));
    }

    final Uint8List first = await _render(line); // 点数稳定的第一帧 / first settled frame
    final Uint8List second = await _render(line); // 命中缓存 / cache hit
    final Uint8List third = await _render(line);

    expect(second, equals(first));
    expect(third, equals(first));
  });

  test('the cache is dropped when the stroke grows', () async {
    final SimpleLine line = _line();
    line.startDraw(const Offset(4, 4));
    line.drawing(const Offset(20, 20));
    line.drawing(const Offset(36, 20));

    final Uint8List before = await _render(line);
    await _render(line); // settle -> cached

    line.drawing(const Offset(52, 52));

    final Uint8List after = await _render(line);
    expect(after, isNot(equals(before)));
  });

  test('a cached stroke matches an identical freshly built one', () async {
    final SimpleLine cached = _line();
    final SimpleLine fresh = _line();

    for (final SimpleLine line in <SimpleLine>[cached, fresh]) {
      line.startDraw(const Offset(6, 6));
      for (int i = 1; i <= 8; i++) {
        line.drawing(Offset(6.0 + i * 6, 6.0 + (i.isEven ? i * 3 : i * 5)));
      }
    }

    await _render(cached);
    await _render(cached); // now served from the cache

    expect(await _render(cached), equals(await _render(fresh)));
  });
}
