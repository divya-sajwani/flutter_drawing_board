import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../paint_contents.dart';
import 'drawing_controller.dart';
import 'helper/ex_value_builder.dart';
import 'paint_contents/paint_content.dart';

/// 绘图板组件
///
/// 负责处理用户触摸交互并将绘制请求传递给DrawingController
/// 内置手掌拒绝功能，支持实时绘制和历史记录分层渲染
///
/// Painter Widget
///
/// Handles user touch interactions and passes drawing requests to DrawingController
/// Built-in palm rejection, supports real-time drawing and layered rendering of history
class Painter extends StatefulWidget {
  const Painter({
    super.key,
    required this.drawingController,
    this.clipBehavior = Clip.antiAlias,
    this.onPointerDown,
    this.onPointerMove,
    this.onPointerUp,
    this.enablePalmRejection = false,
  });

  /// 绘制控制器
  ///
  /// Drawing controller
  final DrawingController drawingController;

  /// 手指按下回调
  ///
  /// Callback when pointer is pressed down
  final void Function(PointerDownEvent pde)? onPointerDown;

  /// 手指移动回调
  ///
  /// Callback when pointer is moving
  final void Function(PointerMoveEvent pme)? onPointerMove;

  /// 手指抬起回调
  ///
  /// Callback when pointer is released
  final void Function(PointerUpEvent pue)? onPointerUp;

  /// 边缘裁剪方式
  ///
  /// Clip behavior
  final Clip clipBehavior;

  /// 启用手掌拒绝功能，防止手掌误触
  ///
  /// Enable palm rejection to prevent accidental palm touches
  final bool enablePalmRejection;

  @override
  State<Painter> createState() => _PainterState();
}

class _PainterState extends State<Painter> {
  /// 最近一次触摸的时间戳，用于手掌拒绝检测
  ///
  /// Timestamp of the last touch, used for palm rejection detection
  DateTime? _lastTouchTime;

  /// 处理手指按下事件
  ///
  /// Handle pointer down event
  void _onPointerDown(PointerDownEvent pde) {
    if (!widget.drawingController.couldStartDraw) {
      return;
    }

    // 手掌拒绝检测
    if (widget.enablePalmRejection) {
      // 检测触摸面积过大（可能是手掌）
      // size 值通常在 0-20 之间，手掌通常 > 15
      if (pde.size > 15.0) {
        return;
      }

      // 检测是否在短时间内有多个触摸点（可能是手掌和手指同时触摸）
      final DateTime now = DateTime.now();
      if (_lastTouchTime != null) {
        final Duration difference = now.difference(_lastTouchTime!);
        if (difference.inMilliseconds < 100) {
          // 100ms 内有多次触摸，可能是手掌，拒绝
          return;
        }
      }
      _lastTouchTime = now;
    }

    widget.drawingController.startDraw(pde.localPosition);
    widget.onPointerDown?.call(pde);
  }

  /// 处理手指移动事件
  ///
  /// Handle pointer move event
  void _onPointerMove(PointerMoveEvent pme) {
    if (!widget.drawingController.couldDrawing) {
      if (widget.drawingController.hasPaintingContent) {
        widget.drawingController.endDraw();
      }

      return;
    }

    if (!widget.drawingController.hasPaintingContent) {
      return;
    }

    widget.drawingController.drawing(pme.localPosition);
    widget.onPointerMove?.call(pme);
  }

  /// 处理手指抬起事件
  ///
  /// Handle pointer up event
  void _onPointerUp(PointerUpEvent pue) {
    if (!widget.drawingController.couldDrawing || !widget.drawingController.hasPaintingContent) {
      return;
    }

    if (widget.drawingController.startPoint == pue.localPosition) {
      widget.drawingController.drawing(pue.localPosition);
    }

    widget.drawingController.endDraw();
    widget.onPointerUp?.call(pue);
  }

  /// 处理手指取消事件
  ///
  /// Handle pointer cancel event
  void _onPointerCancel(PointerCancelEvent pce) {
    if (!widget.drawingController.couldDrawing) {
      return;
    }

    widget.drawingController.endDraw();
  }

  /// GestureDetector 占位方法（防止单指绘制时触发画布平移）
  ///
  /// GestureDetector placeholder methods (prevent canvas panning during single-finger drawing)
  void _onPanDown(DragDownDetails ddd) {}

  void _onPanUpdate(DragUpdateDetails dud) {}

  void _onPanEnd(DragEndDetails ded) {}

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: _onPointerDown,
      onPointerMove: _onPointerMove,
      onPointerUp: _onPointerUp,
      onPointerCancel: _onPointerCancel,
      behavior: HitTestBehavior.opaque,
      child: ExValueBuilder<DrawConfig>(
        valueListenable: widget.drawingController.drawConfig,
        shouldRebuild: (DrawConfig p, DrawConfig n) => p.fingerCount != n.fingerCount,
        builder: (_, DrawConfig config, Widget? child) {
          // 是否能拖动画布
          final bool isPanEnabled = config.fingerCount > 1;

          return GestureDetector(
            onPanDown: !isPanEnabled ? _onPanDown : null,
            onPanUpdate: !isPanEnabled ? _onPanUpdate : null,
            onPanEnd: !isPanEnabled ? _onPanEnd : null,
            child: child,
          );
        },
        child: ClipRect(
          clipBehavior: widget.clipBehavior,
          child: RepaintBoundary(
            child: CustomPaint(
              isComplex: true,
              painter: _DeepPainter(controller: widget.drawingController, devicePixelRatio: MediaQuery.of(context).devicePixelRatio),
              child: RepaintBoundary(
                child: CustomPaint(
                  isComplex: true,
                  painter: _UpPainter(controller: widget.drawingController),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 表层画板绘制器
///
/// 负责绘制当前正在进行的实时绘制内容
/// 对于橡皮擦模式，还会显示底层内容叠加橡皮擦效果
///
/// Surface Layer Painter
///
/// Responsible for drawing the current real-time drawing content
/// For eraser mode, also displays the base content with eraser effect applied
class _UpPainter extends CustomPainter {
  _UpPainter({required this.controller}) : super(repaint: controller.painter);

  final DrawingController controller;

  @override
  void paint(Canvas canvas, Size size) {
    if (!controller.hasPaintingContent) {
      return;
    }

    if (controller.eraserContent != null) {
      // 橡皮擦模式：先绘制底层内容，再应用橡皮擦效果
      canvas.saveLayer(Offset.zero & size, Paint());

      // 优先使用缓存图像，如果缓存不可用则实时绘制历史内容
      if (controller.cachedImage != null) {
        canvas.drawImageRect(
        controller.cachedImage!,
        Rect.fromLTWH(0, 0, controller.cachedImage!.width.toDouble(), controller.cachedImage!.height.toDouble()),
        Offset.zero & size,
        Paint()..filterQuality = FilterQuality.high,
      );
      } else {
        // 缓存图像还未生成，实时绘制历史内容
        final List<PaintContent> history = controller.getHistory;
        for (int i = 0; i < controller.currentIndex; i++) {
          if (i < history.length) {
            history[i].draw(canvas, size, false);
          }
        }
      }

      // 应用橡皮擦效果
      controller.eraserContent?.draw(canvas, size, false);

      canvas.restore();
    } else {
      controller.drawingContent?.draw(canvas, size, false);
    }
  }

  @override
  bool shouldRepaint(covariant _UpPainter oldDelegate) => false;
}

/// 底层画板绘制器
///
/// 负责绘制所有历史记录内容，并生成缓存图片
/// 使用缓存机制优化性能，避免重复绘制
///
/// Deep Layer Painter
///
/// Responsible for drawing all historical content and generating cached images
/// Uses caching mechanism to optimize performance and avoid redundant drawing
class _DeepPainter extends CustomPainter {
  _DeepPainter({required this.controller, required this.devicePixelRatio})
      : super(repaint: controller.realPainter);
  final DrawingController controller;
  final double devicePixelRatio;

  static int _lastRenderedIndex = -1;
  static Size? _lastRenderedSize;

  @override
  void paint(Canvas canvas, Size size) {
    if (controller.eraserContent != null) return;

    final List<PaintContent> contents = <PaintContent>[...controller.getHistory];
    if (contents.isEmpty) return;

    final bool cacheValid = _lastRenderedIndex == controller.currentIndex &&
        _lastRenderedSize == size &&
        controller.cachedImage != null;

    if (cacheValid) {
      _drawCached(canvas, size);
      return;
    }

    final int width = (size.width * devicePixelRatio).round();
    final int height = (size.height * devicePixelRatio).round();

    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final Canvas tempCanvas = Canvas(
      recorder,
      Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()), // physical-size cull rect
    );
    tempCanvas.scale(devicePixelRatio); // <-- the actual fix: logical draws now fill physical space

    // 只有历史中存在橡皮擦时才需要图层
    //
    // The layer exists only so Eraser content, which paints with
    // BlendMode.clear, has something to clear against. With no eraser in the
    // visible history it is pure cost, and on Skia that cost is large: a
    // saveLayer allocates an offscreen render target, switches render pass and
    // blits back.
    //
    // The bounds mattered even more. Passing the whole board made Skia size
    // that target to the entire canvas - which this app makes several times
    // the screen - instead of the part actually on screen. Explicit bounds
    // defeat the surrounding clip, so nothing culled it back down. The clip
    // bounds are what is really being drawn.
    bool needsLayer = false;
    for (int i = 0; i < controller.currentIndex && i < contents.length; i++) {
      if (contents[i] is Eraser) {
        needsLayer = true;
        break;
      }
    }

    if (needsLayer) {
      final Rect layerBounds = canvas.getLocalClipBounds();
      canvas.saveLayer(
        layerBounds.isEmpty ? (Offset.zero & size) : layerBounds,
        Paint(),
      );
    }
    for (int i = 0; i < controller.currentIndex; i++) {
      contents[i].draw(canvas, size, true);      // on-screen layer, untouched, still logical
      contents[i].draw(tempCanvas, size, true);  // cache layer, now scaled correctly
    }
    if (needsLayer) {
      canvas.restore();
    }

    _lastRenderedIndex = controller.currentIndex;
    _lastRenderedSize = size;

    final ui.Picture picture = recorder.endRecording();

    if (width > 0 && height > 0) {
      picture.toImage(width, height).then((ui.Image value) {
        controller.cachedImage = value;
      });
    }
  }

  void _drawCached(Canvas canvas, Size size) {
    final ui.Image img = controller.cachedImage!;
    canvas.drawImageRect(
      img,
      Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
      Offset.zero & size,
      Paint()..filterQuality = FilterQuality.high,
    );
  }

  @override
  bool shouldRepaint(covariant _DeepPainter oldDelegate) => false;
}
