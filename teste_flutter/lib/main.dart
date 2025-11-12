import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui show Image;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:vector_math/vector_math_64.dart' as vm;

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

/*
==============================
Gerenciamento de zoom e níveis
==============================
*/
class ZoomLevelController {
  int zoomLevel = 0;
  int maxZoomLevel = 0;
  double minScale = 0.5;
  double maxScale = 2.0;
  
  // Store min/max scale for each level
  Map<int, Map<String, double>> levelScaleRanges = {};

  void setMaxZoomLevel(int highestLevel) {
    maxZoomLevel = highestLevel;
  }

  bool isMaxZoom() {
    return zoomLevel == maxZoomLevel;
  }
  
  void initializeLevelScaleRanges(Map<int, Map<String, int>> levelDimensions) {
    // Calculate appropriate scale ranges for each level
    // Each level should have a comfortable range around scale 1.0
    for (int level = 0; level <= maxZoomLevel; level++) {
      levelScaleRanges[level] = {
        'min': 0.5,
        'max': 2.0,
      };
    }
  }
  
  void setScaleRangeForLevel(int level) {
    if (levelScaleRanges.containsKey(level)) {
      minScale = levelScaleRanges[level]!['min']!;
      maxScale = levelScaleRanges[level]!['max']!;
    }
  }

  int getLevelForScale(double currentScale) {
    // Determine what level we should be at based on current scale
    // Only move ONE level at a time since we reset to 1.0 after each transition
    if (currentScale >= maxScale - .01 && zoomLevel < maxZoomLevel) {
      return zoomLevel + 1;
    }
    if (currentScale <= minScale + .01 && zoomLevel > 0) {
      return zoomLevel - 1;
    }
    return zoomLevel;
  }

  void updateScaleLevel(Matrix4 matrix) {
    final currentScale = matrix.getMaxScaleOnAxis();
    if (currentScale >= maxScale - .01 && !isMaxZoom()) {
      zoomLevel += 1;
      setScaleRangeForLevel(zoomLevel);
    }
    if (currentScale <= minScale + .01 && zoomLevel != 0) {
      zoomLevel -= 1;
      setScaleRangeForLevel(zoomLevel);
    }
  }
}

/*
=======================
Gerenciamento de tiles
=======================
*/
/// A classe TileManager é responsável por gerenciar a construção, posicionamento e atualização de informações de cache e visualização de todos os tiles que formam a tela do usuário.
/// Ela possui todos os atributos e métodos básicos necessários para se criar a manipulação de tiles da forma que for mais adequada do sistema de tiling para o programa.
class TileManager {
  String dirPath;
  String imageFileName = '001.mrxs';
  int currentLevel = 0;
  int maxLevel = 0;
  int tileSize;
  final Map<TileCoordinate, ui.Image?> loadedTiles = {};
  final Map<int, Map<String, int>> levelDimensions = {}; // Store actual canvas width/height per level
  
  TileManager({this.dirPath = '', this.tileSize = 512});

  Future<void> setTilesDirectory() async {
    var documentsPath = (await getApplicationDocumentsDirectory()).path;
    dirPath = '$documentsPath\\tiles\\$imageFileName';
  }

  Future<void> getHighestLevel() async {
    maxLevel = Directory(dirPath).listSync().length - 1;
    currentLevel = maxLevel;
    await setActualLevelDimensions();
  }

  Future<void> setActualLevelDimensions() async {
    // Actual canvas dimensions from OpenSlide for each pyramid level
    levelDimensions[0] = {'width': 94600, 'height': 220936};
    levelDimensions[1] = {'width': 47300, 'height': 110468};
    levelDimensions[2] = {'width': 23650, 'height': 55234};
    levelDimensions[3] = {'width': 11825, 'height': 27617};
    levelDimensions[4] = {'width': 5912, 'height': 13808};
    levelDimensions[5] = {'width': 2956, 'height': 6904};
    levelDimensions[6] = {'width': 1478, 'height': 3452};
    levelDimensions[7] = {'width': 739, 'height': 1726};
    levelDimensions[8] = {'width': 369, 'height': 863};
    levelDimensions[9] = {'width': 184, 'height': 431};
  }

  Future<TileData?> getTile(TileCoordinate coord) async {
    final tilePath = '$dirPath\\level${coord.level}\\${coord.column}_${coord.row}_HQ.jpg';
    final tileFile = File(tilePath);
    if (!await tileFile.exists()) {
      return null;
    }
    final tile = TileData(tileFile);
    return tile;
  }

  Set<TileCoordinate> updateVisibleTiles(Rect viewPortRect) {
    final tiles = <TileCoordinate>{};

    // Calculate which tiles we need based on viewport
    final startColumn = max(0, (viewPortRect.left / tileSize).floor());
    final lastColumn = max(0, (viewPortRect.right / tileSize).ceil());
    final startRow = max(0, (viewPortRect.top / tileSize).floor());
    final lastRow = max(0, (viewPortRect.bottom / tileSize).ceil());

    for (int row = startRow; row <= lastRow; row++) {
      for (int column = startColumn; column <= lastColumn; column++) {
        tiles.add(TileCoordinate(currentLevel, row, column));
      }
    }

    return tiles;
  }

  Future<void> mapTiles(Set<TileCoordinate> setCoords) async {
    for (TileCoordinate coord in setCoords) {
      if (loadedTiles.containsKey(coord)) {
        continue;
      }
      final TileData? tileFile = await getTile(coord);
      if (tileFile == null) {
        loadedTiles[coord] = null;
      } 
      else {
        ui.Image tileImage = await decodeImageFromList(
          await tileFile.file.readAsBytes(),
        ); 
        loadedTiles[coord] = tileImage;
      }
    }
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
  final TileManager tileManager;

  TilePainter(this.loadedTiles, this.tileSize, this.tileManager);

  @override
  void paint(Canvas canvas, Size size) {
    final dims = tileManager.levelDimensions[tileManager.currentLevel] ?? {'width': 512, 'height': 512};
    final double canvasWidth = dims['width']!.toDouble();
    final double canvasHeight = dims['height']!.toDouble();
    
    for (var entry in loadedTiles.entries) {
      if (entry.value == null) continue;

      double globalX = entry.key.column * tileManager.tileSize.toDouble();
      double globalY = entry.key.row * tileManager.tileSize.toDouble();
      
      // Clip tiles to actual canvas size (handles edge tiles)
      double tileWidth = min(tileManager.tileSize.toDouble(), canvasWidth - globalX);
      double tileHeight = min(tileManager.tileSize.toDouble(), canvasHeight - globalY);
      
      if (tileWidth <= 0 || tileHeight <= 0) continue;

      canvas.drawImageRect(
        entry.value!, 
        Rect.fromLTWH(0, 0, tileWidth, tileHeight),
        Rect.fromLTWH(globalX, globalY, tileWidth, tileHeight),
        Paint()
      );
    }
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
  bool _isLoading = true;
  bool _initialLoadComplete = false;
  Offset _viewportOffset = Offset.zero;
  bool _levelChangeInProgress = false; // Flag to prevent viewport updates during level transitions
  TileManager tileManager = TileManager();
  ZoomLevelController zoomLevelController = ZoomLevelController();
  late TransformationController transformationController;

  @override
  void initState() {
    super.initState();
    transformationController = TransformationController();
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
    final screenSize = MediaQuery.of(context).size;
    Rect initialViewport = _viewportOffset & screenSize;
    
    await tileManager.setTilesDirectory();
    await tileManager.getHighestLevel();
    zoomLevelController.setMaxZoomLevel(tileManager.maxLevel);
    
    // Initialize scale ranges for each level
    zoomLevelController.initializeLevelScaleRanges(tileManager.levelDimensions);
    zoomLevelController.setScaleRangeForLevel(tileManager.currentLevel);
    
    await tileManager.loadTiles(initialViewport);
    
    setState(() {
      _isLoading = false;
      _initialLoadComplete = true;
    });
  }

  void updateViewportCoords() {
    // Skip viewport updates if a level change is in progress
    if (_levelChangeInProgress) {
      return;
    }
    
    Matrix4 matrix = transformationController.value;
    double scale = matrix.getMaxScaleOnAxis();

    double viewportX = -matrix.getTranslation().x;
    double viewportY = -matrix.getTranslation().y;

    // World coordinates = canvas pixel position / scale
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

    if(mounted) {
      setState(() {});
    }
  }

  void zoomToCenter(double num) async {
    final viewportSize = MediaQuery.of(context).size;
    final viewportCenterX = viewportSize.width / 2;
    final viewportCenterY = viewportSize.height / 2;

    final Matrix4 originalMatrix = transformationController.value.clone();
    final currentScale = originalMatrix.getMaxScaleOnAxis();
    final originalTranslationX = originalMatrix.getTranslation().x;
    final originalTranslationY = originalMatrix.getTranslation().y;
    final int oldLevel = tileManager.currentLevel;
    
    double newScale = currentScale + num;
    
    bool levelChanged = false;
    int newZoomLevel = oldLevel;
    
    // Check if we should change level based on zoom direction
    if (num > 0 && oldLevel > 0) {
      // Zooming in - go to more detailed level (lower number)
      newZoomLevel = oldLevel - 1;
      levelChanged = true;
    } else if (num < 0 && oldLevel < zoomLevelController.maxZoomLevel) {
      // Zooming out - go to less detailed level (higher number)
      newZoomLevel = oldLevel + 1;
      levelChanged = true;
    }

    if (levelChanged) {
      final worldCenterX_oldLevel = (viewportCenterX - originalTranslationX) / currentScale;
      final worldCenterY_oldLevel = (viewportCenterY - originalTranslationY) / currentScale;
      
      double finalWorldCenterX = worldCenterX_oldLevel;
      double finalWorldCenterY = worldCenterY_oldLevel;
      
      _levelChangeInProgress = true;
      
      final oldDims = tileManager.levelDimensions[oldLevel] ?? {'width': 512, 'height': 512};
      final newDims = tileManager.levelDimensions[newZoomLevel] ?? {'width': 512, 'height': 512};
      
      final double scaleFactorX = newDims['width']!.toDouble() / oldDims['width']!.toDouble();
      final double scaleFactorY = newDims['height']!.toDouble() / oldDims['height']!.toDouble();
      
      finalWorldCenterX = worldCenterX_oldLevel * scaleFactorX;
      finalWorldCenterY = worldCenterY_oldLevel * scaleFactorY;
      
      print('Level change: $oldLevel -> $newZoomLevel');
      
      tileManager.currentLevel = newZoomLevel;
      
      // Set the scale range for the new level
      zoomLevelController.setScaleRangeForLevel(newZoomLevel);
      
      // Reset scale to 1.0 (native resolution) when changing levels
      newScale = 1.0;
        
      double visibleWidth = viewportSize.width / newScale;
      double visibleHeight = viewportSize.height / newScale;
      
      Rect viewPortRect = Rect.fromLTWH(
        finalWorldCenterX - visibleWidth / 2,
        finalWorldCenterY - visibleHeight / 2,
        visibleWidth,
        visibleHeight,
      );
      
      Set<TileCoordinate> visibleCoords = tileManager.updateVisibleTiles(viewPortRect);
      tileManager.deloadTiles(visibleCoords);
      await tileManager.mapTiles(visibleCoords);
      
      final newTranslationX = viewportCenterX - (finalWorldCenterX * newScale);
      final newTranslationY = viewportCenterY - (finalWorldCenterY * newScale);

      final Matrix4 matrix = Matrix4.identity()
        ..row0 = vm.Vector4(newScale, 0.0, 0.0, newTranslationX)
        ..row1 = vm.Vector4(0.0, newScale, 0.0, newTranslationY)
        ..row2 = vm.Vector4(0.0, 0.0, 1.0, 0.0)
        ..row3 = vm.Vector4(0.0, 0.0, 0.0, 1.0);
      
      transformationController.value = matrix;
      
      setState(() {});
      
      Future.delayed(Duration(milliseconds: 100), () {
        setState(() {
          _levelChangeInProgress = false;
        });
        updateViewportCoords();
      });
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
            child: Stack(
              children: [
                InteractiveViewer(
                  transformationController: transformationController,
                  scaleEnabled: true,
                  minScale: zoomLevelController.minScale,
                  maxScale: zoomLevelController.maxScale,
                  boundaryMargin: const EdgeInsets.all(double.infinity),
                  constrained: false,
                  alignment: Alignment.topLeft,
                  onInteractionUpdate: (details) {
                    // Just update viewport during gesture - don't change levels yet
                    updateViewportCoords();
                  },
                  onInteractionEnd: (details) async {
                    if (_levelChangeInProgress) {
                      // Already processing a level change, ignore
                      return;
                    }
                    
                    // Check if we should change levels after gesture completes
                    final currentScale = transformationController.value.getMaxScaleOnAxis();
                    
                    // If we just reset to 1.0, don't trigger another transition
                    if ((currentScale - 1.0).abs() < 0.01) {
                      // We're at native scale, just reload tiles
                      if (_initialLoadComplete && !_isLoading) {
                        reloadTilesViewport();
                      }
                      return;
                    }
                    
                    final desiredZoomLevel = zoomLevelController.getLevelForScale(currentScale);
                    final currentZoomLevel = zoomLevelController.maxZoomLevel - desiredZoomLevel;
                    
                    if (tileManager.currentLevel != currentZoomLevel) {
                      _levelChangeInProgress = true;
                      
                      int oldLevel = tileManager.currentLevel;
                      
                      print('Pinch level change: $oldLevel -> $currentZoomLevel (scale: ${currentScale.toStringAsFixed(2)})');
                      
                      // Update the zoom level controller's internal state FIRST
                      zoomLevelController.zoomLevel = desiredZoomLevel;
                      zoomLevelController.setScaleRangeForLevel(currentZoomLevel);

                      final oldDims = tileManager.levelDimensions[oldLevel] ?? {'width': 512, 'height': 512};
                      final newDims = tileManager.levelDimensions[currentZoomLevel] ?? {'width': 512, 'height': 512};
                      
                      final double scaleFactorX = newDims['width']!.toDouble() / oldDims['width']!.toDouble();
                      final double scaleFactorY = newDims['height']!.toDouble() / oldDims['height']!.toDouble();
                      
                      Matrix4 currentMatrix = transformationController.value.clone();

                      final viewportSize = MediaQuery.of(context).size;
                      final viewportCenterX = viewportSize.width / 2;
                      final viewportCenterY = viewportSize.height / 2;

                      double currentTranslationX = currentMatrix.getTranslation().x;
                      double currentTranslationY = currentMatrix.getTranslation().y;

                      double worldCenterX = (viewportCenterX - currentTranslationX) / currentScale;
                      double worldCenterY = (viewportCenterY - currentTranslationY) / currentScale;
                      
                      worldCenterX *= scaleFactorX;
                      worldCenterY *= scaleFactorY;
                      
                      // Reset scale to 1.0 (native resolution) when changing levels
                      double newScale = 1.0;
                      
                      double newTranslationX = viewportCenterX - (worldCenterX * newScale);
                      double newTranslationY = viewportCenterY - (worldCenterY * newScale);
                      
                      // Load tiles for the new level before updating the view
                      tileManager.currentLevel = currentZoomLevel;
                      
                      double visibleWidth = viewportSize.width / newScale;
                      double visibleHeight = viewportSize.height / newScale;
                      
                      Rect viewPortRect = Rect.fromLTWH(
                        worldCenterX - visibleWidth / 2,
                        worldCenterY - visibleHeight / 2,
                        visibleWidth,
                        visibleHeight,
                      );
                      
                      Set<TileCoordinate> visibleCoords = tileManager.updateVisibleTiles(viewPortRect);
                      tileManager.deloadTiles(visibleCoords);
                      await tileManager.mapTiles(visibleCoords);
                      
                      final Matrix4 newMatrix = Matrix4.identity()
                        ..row0 = vm.Vector4(newScale, 0.0, 0.0, newTranslationX)
                        ..row1 = vm.Vector4(0.0, newScale, 0.0, newTranslationY)
                        ..row2 = vm.Vector4(0.0, 0.0, 1.0, 0.0)
                        ..row3 = vm.Vector4(0.0, 0.0, 0.0, 1.0);
                      
                      transformationController.value = newMatrix;
                      
                      setState(() {});
                      
                      Future.delayed(Duration(milliseconds: 300), () {
                        _levelChangeInProgress = false;
                      });
                    } else if (_initialLoadComplete && !_isLoading) {
                      // No level change - just reload tiles for current level
                      reloadTilesViewport();
                    }
                  },
                  child: Container(
                    width: MediaQuery.of(context).size.width,
                    height: MediaQuery.of(context).size.height,
                    child: CustomPaint(
                      painter: TilePainter(
                        tileManager.loadedTiles,
                        tileManager.tileSize,
                        tileManager
                      ),
                    ),
                  ),
                ),
                // Center marker - fixed position overlay
                Positioned.fill(
                  child: Center(
                    child: Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.7),
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.all(8.0),
            child: Row(
              children: [
                Text('Level: ${tileManager.currentLevel}  |  '),
                ElevatedButton(
                  onPressed: () {
                    Matrix4 matrix = transformationController.value;
                    print('Matrix: $matrix');
                    print('Viewport offset: $_viewportOffset');
                    print('Scale: ${matrix.getMaxScaleOnAxis()}');
                  },
                  child: Text('Debug Info'),
                ),
                SizedBox(width: 8),
                ElevatedButton(onPressed: () {zoomToCenter(1);}, child: Text('Zoom +')),
                SizedBox(width: 8),
                ElevatedButton(onPressed: () {zoomToCenter(-1);}, child: Text('Zoom -')),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
