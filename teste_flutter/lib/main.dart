import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;
import 'package:path_provider/path_provider.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) => const MaterialApp(home: ImageCanvas());
}

class ImageCanvas extends StatefulWidget {
  const ImageCanvas({super.key});
  @override
  State<ImageCanvas> createState() => _ImageCanvasState();
}

class _ImageCanvasState extends State<ImageCanvas> {
  final TransformationController _transformationController =
      TransformationController();

  int boxX = 0;
  int boxY = 0;
  double rectX = 0;
  double rectY = 0;

  // Lista de linhas
  final List<Widget> colunasImagem = [];

  final GlobalKey _areaKey = GlobalKey();
  final GlobalKey _stackKey = GlobalKey(); // Add key for Stack
  
  void _updateLoc(PointerEvent event) {
    final box = _areaKey.currentContext?.findRenderObject() as RenderBox?;

    int localX, localY;
    if (box != null) {
      final local = box.globalToLocal(event.position);
      localX = local.dx.floor();
      localY = local.dy.floor();
    } else {
      localX = event.localPosition.dx.floor();
      localY = event.localPosition.dy.floor();
    }

    if (boxX != localX || boxY != localY) {
      setState(() {
        boxX = localX;
        boxY = localY;
      });
    }
  }

  void _zoomToCenter(double scale) {
  // Pega o tamanho da área visível (Stack/InteractiveViewer)
  final RenderBox? stackBox = _stackKey.currentContext?.findRenderObject() as RenderBox?;
  if (stackBox == null) return;

  final viewportSize = stackBox.size;
  final viewportCenterX = viewportSize.width / 2;
  final viewportCenterY = viewportSize.height / 2;

  // Pega a transformação atual
  final Matrix4 currentMatrix = _transformationController.value.clone();

  // Calcula a escala atual
  final currentScale = currentMatrix.getMaxScaleOnAxis();

  // Calcula o fator de mudança de escala
  final scaleDelta = scale / currentScale;

  final currentTranslationX = currentMatrix.getTranslation().x;
  final currentTranslationY = currentMatrix.getTranslation().y;

  // Calcula qual ponto do CONTEÚDO está no centro da viewport atualmente
  final contentCenterX = (viewportCenterX - currentTranslationX) / currentScale;
  final contentCenterY = (viewportCenterY - currentTranslationY) / currentScale;

  // Calcula a nova translação para manter esse mesmo ponto do conteúdo no centro
  final newTranslationX = viewportCenterX - (contentCenterX * scale);
  final newTranslationY = viewportCenterY - (contentCenterY * scale);

  // Aplica zoom mantendo o centro da tela fixo
  final Matrix4 matrix = Matrix4.identity()
    ..row0 = Vector4(scale, 0.0, 0.0, newTranslationX)
    ..row1 = Vector4(0.0, scale, 0.0, newTranslationY)
    ..row2 = Vector4(0.0, 0.0, 1.0, 0.0)
    ..row3 = Vector4(0.0, 0.0, 0.0, 1.0);

  _transformationController.value = matrix;

  print('Viewport: ${viewportSize.width} x ${viewportSize.height}');
  print('Viewport Center: ($viewportCenterX, $viewportCenterY)');
  print('Content point at center: ($contentCenterX, $contentCenterY)');
  print('Scale: $currentScale -> $scale (delta: $scaleDelta)');
  print('Translation: ($currentTranslationX, $currentTranslationY) -> ($newTranslationX, $newTranslationY)');
  print('Matrix: $matrix\n');
}

  void printMatrix() {
    final Matrix4 currentMatrix = _transformationController.value.clone();
    print(currentMatrix);
  }

  // Future<void> addCollumn() async {
  //   final String imagesDirectoryPath = './assets/level0';
  //   final Directory imagesDirectory = Directory(imagesDirectoryPath);

  //   if (await imagesDirectory.exists()) {
  //     print("Rolou")
  //   }
  // }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          Expanded(
            child: Stack(
              key: _stackKey, // Add key here
              children: [
                MouseRegion(
                  onHover: _updateLoc,
                  child: InteractiveViewer(
                    transformationController: _transformationController,
                    minScale: 1,
                    maxScale: 6,
                    boundaryMargin: const EdgeInsets.all(double.infinity),
                    constrained: false,
                    alignment: Alignment.topLeft,
                    child: Container(
                      key: _areaKey,
                      width: MediaQuery.of(context).size.width,
                      height: MediaQuery.of(context).size.height,
                      child: Row(
                        children: [
                          Column(
                            children: [
                              Image.asset(
                                'assets/level0/63_221_HQ.jpg',
                                scale: 1.6,
                              ),
                              Image.asset(
                                'assets/level0/63_222_HQ.jpg',
                                scale: 1.6,
                              ),
                            ],
                          ),
                          Column(
                            children: [
                              Image.asset(
                                'assets/level0/64_221_HQ.jpg',
                                scale: 1.6,
                              ),
                              Image.asset(
                                'assets/level0/64_222_HQ.jpg',
                                scale: 1.6,
                              ),
                            ],
                          ),
                          Column(
                            children: [
                              Image.asset(
                                'assets/level0/65_221_HQ.jpg',
                                scale: 1.6,
                              ),
                              Image.asset(
                                'assets/level0/65_222_HQ.jpg',
                                scale: 1.6,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                // Fixed: Use LayoutBuilder to get size
                IgnorePointer(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return CustomPaint(
                        size: Size(constraints.maxWidth, constraints.maxHeight),
                        painter: RectanglePainter(
                          constraints.maxWidth / 2,
                          constraints.maxHeight / 2,
                          onRectDrawn: (x, y) {
                            setState(() {
                              rectX = x;
                              rectY = y;
                            });
                          }
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton(
                  onPressed: () => _zoomToCenter(1.0),
                  child: const Text('Reset'),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () => _zoomToCenter(2.0),
                  child: const Text('Zoom 2x'),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () => _zoomToCenter(3.0),
                  child: const Text('Zoom 3x'),
                ),
                ElevatedButton(
                  onPressed: () => printMatrix(),
                  child: const Text('Print'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class RectanglePainter extends CustomPainter {
  double centerX = 0;
  double centerY = 0;
  final Function(double x, double y)? onRectDrawn;

  RectanglePainter(this.centerX, this.centerY, {this.onRectDrawn});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.blue
      ..style = PaintingStyle.fill;

    final rectWidth = 1.0;
    final rectHeight = 1.0;

    final x = centerX - rectWidth / 2;
    final y = centerY - rectHeight / 2;

    final rect = Rect.fromLTWH(x, y, rectWidth, rectHeight);

    // Report the coordinates
    onRectDrawn?.call(x, y);

    canvas.drawRect(rect, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return false;
  }
}