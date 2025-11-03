import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
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
  @override
  void initState() {
    super.initState();
    loadImages();
  }
  
  // Varíavel para manipular transformação da tela  
  final TransformationController _transformationController = TransformationController();
  // Variáveis para referenciar posição do mouse dentro de container do Widget
  int boxX = 0;
  int boxY = 0;
  // Variáveis para referenciar posição do pixel central da tela utilizado no zoom
  double rectX = 0;
  double rectY = 0;
  // Variáveis de chave utilizadas na análise de posição do mouse
  final GlobalKey _areaKey = GlobalKey();
  final GlobalKey _stackKey = GlobalKey();
  
  // Armazenamos apenas os caminhos dos arquivos
  final List<List<File>> imageRows = [];
  bool isLoading = true;
  
  // Para calcular dimensões
  double? _rowHeight;
  double? _totalWidth;


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
    final RenderBox? stackBox = _stackKey.currentContext?.findRenderObject() as RenderBox?;
    if (stackBox == null) return;

    final viewportSize = stackBox.size;
    final viewportCenterX = viewportSize.width / 2;
    final viewportCenterY = viewportSize.height / 2;

    final Matrix4 currentMatrix = _transformationController.value.clone();
    final currentScale = currentMatrix.getMaxScaleOnAxis();
    final scaleDelta = scale / currentScale;

    final currentTranslationX = currentMatrix.getTranslation().x;
    final currentTranslationY = currentMatrix.getTranslation().y;

    final contentCenterX = (viewportCenterX - currentTranslationX) / currentScale;
    final contentCenterY = (viewportCenterY - currentTranslationY) / currentScale;

    final newTranslationX = viewportCenterX - (contentCenterX * scale);
    final newTranslationY = viewportCenterY - (contentCenterY * scale);

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

  Future<void> loadImages() async {
    setState(() {
      isLoading = true;
    });

    final directory = await getApplicationDocumentsDirectory();
    final imagesDirectory = Directory('${directory.path}/tiles');

    if (!await imagesDirectory.exists()) {
      await imagesDirectory.create();
      setState(() {
        isLoading = false;
      });
      return;
    } 
    
    final levelDirectory = Directory('${imagesDirectory.path}/level0');
    
    if (!await levelDirectory.exists()) {
      setState(() {
        isLoading = false;
      });
      return;
    }
    
    final List<FileSystemEntity> entities = levelDirectory.listSync();
    
    // Armazenamos apenas os arquivos
    final List<File> tempList = [];
    String tempRow = '';
    
    int processedCount = 0;
    
    for (FileSystemEntity entity in entities) {
      if (entity is File) {
        final String entityString = entity.toString();
        final String currentRow = entityString.splitMapJoin(
          RegExp('File:|${RegExp.escape(levelDirectory.path)}\\\\|(_.+)|\''), 
          onMatch: (m) => '', 
          onNonMatch: (n) => n,
        );
        
        if (tempRow == '') tempRow = currentRow;
        
        if (entityString.contains('HQ')) {
          if (currentRow == tempRow) {
            tempList.add(entity);
          } else {
            imageRows.add(List.from(tempList));
            tempList.clear();
            tempList.add(entity);
            tempRow = currentRow;
            
            // Yield a cada 3 linhas
            processedCount++;
            if (processedCount % 3 == 0) {
              await Future.delayed(Duration.zero);
            }
          }
        }
      }
    }
    
    // Adiciona a última linha
    if (tempList.isNotEmpty) {
      imageRows.add(List.from(tempList));
    }
    
    setState(() {
      isLoading = false;
    });
    
    print('Carregamento concluído!');
    print('Total de linhas: ${imageRows.length}');
    print('Total de imagens: ${imageRows.fold(0, (sum, row) => sum + row.length)}');
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          Expanded(
            child: Stack(
              key: _stackKey,
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
                      constraints: BoxConstraints(
                        minHeight: MediaQuery.of(context).size.height, 
                        minWidth: MediaQuery.of(context).size.width
                      ),
                      child: isLoading
                          ? const Center(child: CircularProgressIndicator())
                          : ListView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: imageRows.length,
                              itemBuilder: (context, index) {
                                final rowFiles = imageRows[index];
                                return Row(
                                  children: rowFiles.map((file) => 
                                    Image.file(
                                      file,
                                      scale: 15,
                                      // CRÍTICO: Define limites de cache
                                      cacheWidth: 200,
                                      cacheHeight: 200,
                                      // Libera memória quando fora da tela
                                      gaplessPlayback: false,
                                    )
                                  ).toList(),
                                );
                              },
                            ),
                    ),
                  ),
                ),
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
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () {
                    print('Total de linhas: ${imageRows.length}');
                    print('Total de imagens: ${imageRows.fold(0, (sum, row) => sum + row.length)}');
                    print('Imagens por linha: ${imageRows.map((row) => row.length).take(5).toList()}...');
                  },
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
      ..color = Colors.transparent
      ..style = PaintingStyle.fill;

    final rectWidth = 1.0;
    final rectHeight = 1.0;

    final x = centerX - rectWidth / 2;
    final y = centerY - rectHeight / 2;

    final rect = Rect.fromLTWH(x, y, rectWidth, rectHeight);

    if (onRectDrawn != null) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        onRectDrawn!.call(x, y);
      });
    }

    canvas.drawRect(rect, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return false;
  }
}