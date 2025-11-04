import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui show Image;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:vector_math/vector_math_64.dart';

/*
O código abaixo foi para criar os algoritmos que permitem a visualização das imagens do projeto do atlas de imagens de microscópio eletrônico da FMABC.
As imagens são divididas em pedaços menores para garantir que elas possam ser renderizadas com velocidade, precisão e com garantia que não seja necessário capacidades muito
exigentes de memória e processamento. Para visualizar essas "pedaços" de imagem organizados nas posições corretas, foi utilizado um sistema de visualização baseado em tiles, baseado
em coordenadas de linhas (eixo Y) e colunas (eixo X). Cada tile ocupa, na escala orginal das imagens, 512 pixels, ou seja, a cada tile, são ocupados 512 pixels em cada eixo.
*/

/*
=======================
Estruturação de tiles
=======================
*/
/// TileCoordinate é uma classe que serve para a estruturação dos tiles, a classe é formada por apenas os atributos de posição que cada tile deve receber para ser posicionado:
/// level, row e column.
class TileCoordinate {
  final int level;
  final int row;
  final int column;

  TileCoordinate(this.level, this.row, this.column);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! TileCoordinate) return false;
    return other.level == level && other.row == row && other.column == column;
  }

  @override
  int get hashCode => Object.hash(level, row, column);
}

/// TileData é uma classe que serve para a estruturação dos tiles, a classe é formada por apenas um atributo de tipo arquivo, o qual é o arquivo da imagem recebida e que será
/// posicionada na tela do usuário.
class TileData {
  final File file;

  TileData(this.file);
}

/// A classe TileManager é responsável por gerenciar a construção, posicionamento e atualização de informações de cache e visualização de todos os tiles que formam a tela do usuário.
/// Ela possui todos os atributos e métodos básicos necessários para se criar a manipulação de tiles da forma que for mais adequada do sistema de tiling para o programa.
class TileManager {
  String dirPath;
  String imageFileName = '001.mrxs';
  int ?currentLevel;
  final int tileSize;
  final Map<TileCoordinate, ui.Image?> loadedTiles = {};

  TileManager({this.dirPath = '', this.tileSize = 512});

  Future<void> setTilesDirectory() async {
    var documentsPath = (await getApplicationDocumentsDirectory()).path;
    dirPath = '$documentsPath\\tiles\\$imageFileName';
  }

  Future<void> setCurrentLevelHighest() async {
    currentLevel = Directory(dirPath).listSync().length - 2;
  }

  Future<TileData?> getTile(TileCoordinate coord) async {
    final tilePath = '$dirPath\\level${coord.level}\\${coord.column}_${coord.row}_HQ.jpg';
    final tileFile = File(tilePath);
    // print(tilePath);
    if (!await tileFile.exists()) {
      return null;
    }
    final tile = TileData(tileFile);
    return tile;
  }

  Set<TileCoordinate> updateVisibleTiles(Rect viewPortRect) {
    final tiles = <TileCoordinate>{};

    final startColumn = max(0, (viewPortRect.left / tileSize).floor());
    final lastColumn = max(0, (viewPortRect.right / tileSize).ceil());
    final startRow = max(0, (viewPortRect.top / tileSize).floor());
    final lastRow = max(0, (viewPortRect.bottom / tileSize).ceil());

    for (int row = startRow; row <= lastRow; row++) {
      for (int column = startColumn; column <= lastColumn; column++) {
        tiles.add(TileCoordinate(currentLevel!, row, column));
      }
    }

    return tiles;
  }

  Future<void> mapTiles(Set<TileCoordinate> setCoords) async {
    // print('\n${"=" * 6}Entrou em mapTiles${'=' * 6}');
    for (TileCoordinate coord in setCoords) {
      final TileData? tileFile = await getTile(coord);
      // print('O valor do objeto é: $tileFile\nA coordenada do objeto é: ${coord.column}_${coord.row}\n');
      if (tileFile == null) {
        // print('arquivo de objeto é nulo');
        loadedTiles[coord] = null;
      } else {
        // print('arquivo de objeto não é nulo');
        ui.Image tileImage = await decodeImageFromList(
          await tileFile.file.readAsBytes(),
        );
        if (loadedTiles.containsKey(coord)) {
          continue;
        } else {
          loadedTiles[coord] = tileImage;
        }
      }
    }
    // print('${"=" * 6}Saiu de mapTiles${'=' * 6}\n');
  }

  Future<void> loadTiles(Rect viewPortRect) async {
    Set<TileCoordinate> visibleCoords = updateVisibleTiles(viewPortRect);
    deloadTiles(visibleCoords);
    await mapTiles(visibleCoords);
  }

  void deloadTiles(Set<TileCoordinate> visibleCoords) {
    loadedTiles.removeWhere((coord, image) => !visibleCoords.contains(coord));
  }
}

class TilePainter extends CustomPainter {
  final Map<TileCoordinate, ui.Image?> loadedTiles;
  final int tileSize;
  final Offset viewportOffset;

  TilePainter(this.loadedTiles, this.tileSize, this.viewportOffset);

  @override
  void paint(Canvas canvas, Size size) {
    // print('${"="*6}Entrou em paint${'='*6}');
    // print('loadedTiles.length = ${loadedTiles.length}, viewportOffset = $viewportOffset');
    final Iterable<MapEntry<TileCoordinate, ui.Image?>> entries =
        loadedTiles.entries;
    // int drawCount = 0;
    for (var entry in entries) {
      if (entry.value == null) {
        // print('valor de objeto é nulo para tile (${entry.key.column}, ${entry.key.row})');
        continue;
      }

      double globalX = entry.key.column * tileSize.toDouble();
      double globalY = entry.key.row * tileSize.toDouble();

      canvas.drawImage(entry.value!, Offset(globalX, globalY), Paint());
      // drawCount++;
    }
    // print('Desenhadas $drawCount tiles');
    // print('${"="*6}Saiu de paint${'='*6}');
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return true;
  }
}

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
  Map<TileCoordinate, ui.Image?> _loadedTiles = {};
  int _tileSize = 512;
  bool _isLoading = true;
  bool _initialLoadComplete = false;
  Offset _viewportOffset = Offset.zero;
  TileManager tileManager = TileManager();
  late TransformationController transformationController;

  @override
  void initState() {
    super.initState();
    transformationController = TransformationController();
    _viewportOffset = Offset(0, 0);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    startTiles();
  }

  @override
  void dispose() {
    transformationController.dispose();
    super.dispose();
  }

  Future<void> startTiles() async {
    // print("startTiles: _viewportOffset = $_viewportOffset");
    Rect telaUsuario =
        _viewportOffset &
        Size(
          MediaQuery.of(context).size.width,
          MediaQuery.of(context).size.height,
        );
    // print("startTiles: telaUsuario = $telaUsuario");

    await tileManager.setTilesDirectory();
    await tileManager.setCurrentLevelHighest();
    await tileManager.loadTiles(telaUsuario);

    setState(() {
      _loadedTiles = tileManager.loadedTiles;
      _tileSize = tileManager.tileSize;
      _isLoading = false;
      _initialLoadComplete = true;
    });
    // print("Carregou ${tileManager.loadedTiles.length} tiles");
    // print("Viewport: $telaUsuario");
    // print("_viewportOffset: $_viewportOffset");
  }

  void updateViewportCoords() {
    Matrix4 matrix = transformationController.value;
    double scale = matrix.getMaxScaleOnAxis();

    double viewportX = -matrix.getTranslation().x;
    double viewportY = -matrix.getTranslation().y;

    double worldX = viewportX / scale;
    double worldY = viewportY / scale;

    setState(() {
      _viewportOffset = Offset(worldX, worldY);
    });
  }

  Future<void> reloadTilesViewport() async {
    Matrix4 matrix = transformationController.value;
    double scale = matrix.getMaxScaleOnAxis();

    double visibleWidth = MediaQuery.of(context).size.width / scale;
    double visibleHeight = MediaQuery.of(context).size.height / scale;

    Rect viewPortRect = Rect.fromLTWH(
      _viewportOffset.dx,
      _viewportOffset.dy,
      visibleWidth,
      visibleHeight,
    );

    await tileManager.loadTiles(viewPortRect);

    setState(() {
      _loadedTiles = tileManager.loadedTiles;
    });
  }

  void zoomToCenter(double num) {
    final viewportSize = MediaQuery.of(context).size;
    final viewportCenterX = viewportSize.width / 2;
    final viewportCenterY = viewportSize.height / 2;

    final Matrix4 currentMatrix = transformationController.value.clone();
    final currentScale = currentMatrix.getMaxScaleOnAxis();
    final scale = currentScale + num;

    if (scale >= 1) {
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
      
      transformationController.value = matrix;
    }  
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      body: Column(
        children: [
          Expanded(
            child: InteractiveViewer(
              transformationController: transformationController,
              scaleEnabled: true,
              minScale: 1,
              maxScale: 3,
              boundaryMargin: const EdgeInsets.all(double.infinity),
              constrained: false,
              alignment: Alignment.topLeft,
              onInteractionUpdate: (details) {
                updateViewportCoords();
              },
              onInteractionEnd: (details) {
                if (_initialLoadComplete && !_isLoading) {
                  reloadTilesViewport();
                }
              },
              child: Container(
                width: MediaQuery.of(context).size.width,
                height: MediaQuery.of(context).size.height,
                child: CustomPaint(
                  painter: TilePainter(
                    _loadedTiles,
                    _tileSize,
                    _viewportOffset,
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsetsGeometry.all(8.0),
            child: Row(
              children: [
                Text('X: ${(_viewportOffset.dx.toInt() / 512).floor()}'),
                Text('  Y: ${(_viewportOffset.dy.toInt() / 512).floor()}'),
                ElevatedButton(
                  onPressed: () {
                    Matrix4 matrix = transformationController.value;
                    print(matrix);
                    print(_viewportOffset);
                  },
                  child: Text('Print valores de matriz'),
                ),
                ElevatedButton(onPressed: () {zoomToCenter(1);}, child: Text('Zoom +')),
                ElevatedButton(onPressed: () {zoomToCenter(-1);}, child: Text('Zoom -')),
                // ElevatedButton(
                //   onPressed: () async {
                //     setState(() {
                //       _viewportOffset = Offset(512 * 63, 512 * 215);
                //       Matrix4 matrix = Matrix4.identity();
                //       matrix.setTranslationRaw(-63.0 * 512, -215.0 * 512, 0);
                //       transformationController.value = matrix;
                //     });
                    
                //     await Future.delayed(const Duration(milliseconds: 50));
                //     await reloadTilesViewport();
                //   },
                //   child: Text('63, 215'),
                // ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
