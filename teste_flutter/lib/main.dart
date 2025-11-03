import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui show Image;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

class TileCoordinate {
  final int level;
  final int row;
  final int column;

  TileCoordinate(this.level, this.row, this.column);
}

class TileData {
  final File file;

  TileData(this.file);
}

class TileManager {
  String dirPath;
  final int tileSize;
  final Map<TileCoordinate, ui.Image?> loadedTiles = {};

  TileManager({this.dirPath = '', this.tileSize = 512});

  Future<void> setTilesDirectory() async {
    dirPath = (await getApplicationDocumentsDirectory()).path;
  }

  Future<TileData?> getTile(TileCoordinate coord) async {
    final tilePath = '$dirPath\\tiles\\level${coord.level}\\${coord.column}_${coord.row}_HQ.jpg';
    final tileFile = File(tilePath);
    print(tilePath);
    if (!await tileFile.exists()) {
      return null;
    }
    final tile = TileData(tileFile);
    return tile;
  }

  Set<TileCoordinate> updateVisibleTiles(Rect viewPortRect, int level) {
    final tiles = <TileCoordinate>{};

    final startColumn = max(0, (viewPortRect.left / tileSize).floor());    
    final lastColumn = max(0, (viewPortRect.right / tileSize).ceil());
    final startRow = max(0, (viewPortRect.top / tileSize).floor());
    final lastRow = max(0, (viewPortRect.bottom / tileSize).ceil());

    for (int row = startRow; row <= lastRow; row++) {
      for (int column = startColumn; column <= lastColumn; column++) {
        tiles.add(TileCoordinate(level, row, column));
      }
    }

    return tiles;
  }

  Future<void> mapTiles(Set<TileCoordinate> setCoords) async {
    print('\n${"="*6}Entrou em mapTiles${'='*6}');
    for (TileCoordinate coord in setCoords) {
      final TileData? tileFile = await getTile(coord);
      print('O valor do objeto é: $tileFile\nA coordenada do objeto é: ${coord.row}_${coord.column}\n');
      if (tileFile == null) {
        print('arquivo de objeto é nulo');
        loadedTiles[coord] = null;
      } 
      else {
        print('arquivo de objeto não é nulo');
        ui.Image tileImage = await decodeImageFromList(await tileFile.file.readAsBytes());
        loadedTiles[coord] = tileImage;
      }
    }
    print('${"="*6}Saiu de mapTiles${'='*6}\n');
  }

  Future<void> loadTiles(Rect viewPortRect, int level) async {
    loadedTiles.clear(); 
    await mapTiles(updateVisibleTiles(viewPortRect, level));
  }

  void deloadTiles() {
    loadedTiles.clear();
  }
}

class TilePainter extends CustomPainter {
  final Map<TileCoordinate, ui.Image?> loadedTiles;
  final int tileSize;
  final Offset viewportOffset;
  
  TilePainter(this.loadedTiles, this.tileSize, this.viewportOffset);

  @override
  void paint(Canvas canvas, Size size) {
    print('${"="*6}Entrou em paint${'='*6}');
    print('loadedTiles.length = ${loadedTiles.length}, viewportOffset = $viewportOffset');
    final Iterable<MapEntry<TileCoordinate, ui.Image?>> entries = loadedTiles.entries;
    int drawCount = 0;
    for (var entry in entries) {      
      if (entry.value == null) {
        print('valor de objeto é nulo para tile (${entry.key.column}, ${entry.key.row})');
        continue;
      }
      
      double globalX = entry.key.column * tileSize.toDouble();
      double globalY = entry.key.row * tileSize.toDouble();
      double screenX = globalX - viewportOffset.dx;
      double screenY = globalY - viewportOffset.dy;
      
      canvas.drawImage(
        entry.value!, 
        Offset(screenX, screenY), 
        Paint()
      );
      drawCount++;
    }
    print('Desenhadas $drawCount tiles');
    print('${"="*6}Saiu de paint${'='*6}');
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
    startTiles();
  }

  @override
  void dispose() {
    transformationController.dispose();
    super.dispose();
  }

  Future<void> startTiles() async {
    print("startTiles: _viewportOffset = $_viewportOffset");
    Rect telaUsuario = _viewportOffset & const Size(2048, 2048);
    print("startTiles: telaUsuario = $telaUsuario");
    
    await tileManager.setTilesDirectory();
    await tileManager.loadTiles(telaUsuario, 0);

    setState(() {
      _loadedTiles = tileManager.loadedTiles;
      _tileSize = tileManager.tileSize;
      _isLoading = false;
      _initialLoadComplete = true;
    });
    print("Carregou ${tileManager.loadedTiles.length} tiles");
    print("Viewport: $telaUsuario");
    print("_viewportOffset: $_viewportOffset");
  }
  
  void updateVieportCoords() {
    Matrix4 matrix = transformationController.value;
    double viewportX = -matrix.getTranslation().x;
    double viewportY = -matrix.getTranslation().y;

    setState(() {
      _viewportOffset = Offset(viewportX, viewportY);
    });
  }

  Future<void> reloadTilesViewport() async {
    Matrix4 matrix = transformationController.value;
    double scale = matrix.getMaxScaleOnAxis();

    final screenSize = MediaQuery.of(context).size;

    double visibleWidth = screenSize.width / scale;
    double visibleHeight = screenSize.height / scale;

    Rect viewPortRect = Rect.fromLTWH(_viewportOffset.dx, _viewportOffset.dy, visibleWidth, visibleHeight);

    await tileManager.loadTiles(viewPortRect, 0);

    setState(() {
      _loadedTiles = tileManager.loadedTiles;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }
    
    return Scaffold(
        body: Column(
          children: 
          [
            Expanded(
              child: InteractiveViewer(
                transformationController: transformationController,
                minScale: 1,
                maxScale: 3,
                boundaryMargin: const EdgeInsets.all(double.infinity),
                constrained: false,
                alignment: Alignment.topLeft,
                onInteractionUpdate: (details) {
                  updateVieportCoords();
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
                    painter: TilePainter(_loadedTiles, _tileSize, _viewportOffset),
                  ),
                ),
              ),
            ),
            Padding(
              padding: EdgeInsetsGeometry.all(8.0),
              child: Row(
                children: [
                  Text('X: ${_viewportOffset.dx}'),
                  Text('  Y: ${_viewportOffset.dy}')
                ],
              ),
            )
          ]
        ),
    );
  }
}