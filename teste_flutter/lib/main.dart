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

  // Ambos os overrides abaixo têm como intuito podemos fazer comparações diretas entre instâncias desta classe. Por exemplo, comparar se o conteúdo de um TileCoordinate é igual a
  // outro
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
/// ZoomLevelController é uma classe que existe com o intuito de gerenciar acompanhar as manipulações de zoom da visualização de um sistema de tiling piramidal, ela também possui
/// funções para tratar parte da lógica de transição de níveis de zoom.
class ZoomLevelController {
  int zoomLevel = 0;
  int maxZoomLevel = 0;
  double minScale = 0.5;
  double maxScale = 2.0;
  
  /// É um atributo Map que tem como intuito armazenar os valores mínimo e máximo que cada nível de zoom deve possuir. Foi pensado para interação com o Widget InteractiveViewer.
  Map<int, Map<String, double>> levelScaleRanges = {};

  /// Define a partir de parâmetro o maior nível de zoom possível de ser alcançado.
  void setMaxZoomLevel(int highestLevel) {
    maxZoomLevel = highestLevel;
  }
  
  /// Retorna se o nível atual de zoom é o máximo possível.
  bool isMaxZoom() {
    return zoomLevel == maxZoomLevel;
  }
  
  /// Calcula intervalos apropriados para escalas de zoom. Cada nível deve possuir uma escala confortável ao redor da escala base de 1.0.
  void initializeLevelScaleRanges(Map<int, Map<String, int>> levelDimensions) {
    for (int level = 0; level <= maxZoomLevel; level++) {
      levelScaleRanges[level] = {
        'min': 0.5,
        'max': 2.0,
      };
    }
  }
  
  /// Mapeia para cada nível o valor mínimo e máximo de seu intervalo de zoom.
  void setScaleRangeForLevel(int level) {
    if (levelScaleRanges.containsKey(level)) {
      minScale = levelScaleRanges[level]!['min']!;
      maxScale = levelScaleRanges[level]!['max']!;
    }
  }

  /// Retorna em qual nível de zoom a visualização deve se encontrar baseado na escala atual. Move apenas um nível por vez, uma vez que resetamos a escala para 1.0 a cada transição 
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

  /// Atualiza o valor de zoom de nível interno baseado na escala atual do zoom da visualização.
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
  String imageFileName = '001.mrxs'; // ESTE VALOR NECESSITA SER ALTERADO PARA RECEBER O VALOR DINÂMICO DO BANCO DE DADOS
  int currentLevel = 0;
  int maxLevel = 0;
  int tileSize;
  /// O atributo loadedTiles é um map que tem como chave, um objeto TileCoordinate, e como valor, uma imagem. Ele serve como um cachê de imagens que foram carregadas
  /// a visualização.
  final Map<TileCoordinate, ui.Image?> loadedTiles = {};
  /// O atributo levelDimensions é um map que tem como chave, uma string representando largura ou altura do nível de zoom da imagem, e como valor, um int representando
  /// o tamanho em pixels de uma das unidades de chave. Ela tem como intuito representar o tamanho de Canvas para cada nível de zoom, para podemos posicionar tiles
  /// e transicionar entre posições dentro de níveis, corretamente. 
  final Map<int, Map<String, int>> levelDimensions = {};
  
  TileManager({this.dirPath = '', this.tileSize = 512});
  
  /// A função tem como intuito definir o diretório do arquivo de imagem correto de onde as imagens que formam os tiles virão.
  Future<void> setTilesDirectory() async {
    var documentsPath = (await getApplicationDocumentsDirectory()).path;
    dirPath = '$documentsPath\\tiles\\$imageFileName';
  }

  /// A função tem como intuito definir o maior valor de nível possível da imagem sendo lida.
  Future<void> getHighestLevel() async {
    maxLevel = Directory(dirPath).listSync().length - 1;
    currentLevel = maxLevel;
    await setActualLevelDimensions();
  }

  /// A função tem como intuito definir as dimensões do Canvas de cada nível de zoom possível da imagem
  /// Atualmente, os valores estão definidos estáticamente no código, no entanto para o seu funcionamento correto, deve-se de alguma forma trazer esse valores do código render_tiles.cpp.
  /// Para assim, podemos desenvolver uma função que define as dimensões para cada nível possível de maneira verdadeiramente dinâmica.
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

  /// A função tem com intuito, a partir de um valor de coordenada, recuperar o arquivo de imagem correto para as coordenadas de tile apresentadas pelo objeto.
  /// Caso não exista valor e arquivo válido para aquele valor de coordenada, retorna um valor nulo.
  Future<TileData?> getTile(TileCoordinate coord) async {
    final tilePath = '$dirPath\\level${coord.level}\\${coord.column}_${coord.row}_HQ.png';
    final tileFile = File(tilePath);
    if (!await tileFile.exists()) {
      return null;
    }
    final tile = TileData(tileFile);
    return tile;
  }

  /// A partir do tamanho da visualização da janela do usuário, define quantos e quais tiles estão visíveis e retorna os seus valores de coordenada como um Set.
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

  /// A função tem como intuito receber um Set com valores de coordenada e os mapear para o valores de imagem válidos ou nulos para aquele conjunto de atributos de TileCoordinate.
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

  /// Dispara o carregamento dos tiles que devem aparecer na visão do usuário a partir da interação entre as diferentes funções presentes em TileManager.
  Future<void> loadTiles(Rect viewPortRect) async {
    Set<TileCoordinate> visibleCoords = updateVisibleTiles(viewPortRect);
    deloadTiles(visibleCoords);
    await mapTiles(visibleCoords);
  }

  /// Descarrega do cachê de tiles, todos aqueles que não estão mais presentes na tela do usuário.
  void deloadTiles(Set<TileCoordinate> visibleCoords) {
    loadedTiles.removeWhere((coord, image) => !visibleCoords.contains(coord));
  }
}

/*
====================
Desenhando os tiles
====================
*/
/// A classe TilePainter tem como intuito desenhar os tiles em suas posições corretas, baseando-se no tamanho real das dimensões dos seus respectivos níveis de zoom, ou até eles
/// alcançarem o valor de 512x512 pixels por tile. Ele também escalona as imagens de seus tamanhos reais ao tamanho correto para preencher o espaço do tile por nível de zoom.
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
  bool _isLoading = true; // Flag que existe enquanto todos os tiles iniciais possam ser carregados para tela do usuário. 
  bool _initialLoadComplete = false; // Flag que existe para que todos os atrivutos da instância tileManger tenham sido definidos corretamente.
  Offset _viewportOffset = Offset.zero; // Variável privada que carrega o offset de viewport do usuário para o centro da tela, é importante para posicionar a tela do usuário no canvas.
  bool _levelChangeInProgress = false; // Flag que existe para evitar o update do viewport do usuário enquanto ocorre a transição de níveis de zoom.
  TileManager tileManager = TileManager(); // instância da classe TileManager
  ZoomLevelController zoomLevelController = ZoomLevelController(); // instância da classe ZoomLevelController
  late TransformationController transformationController; // Variável que carregará instância da classe TransformationController, a qual usamos para a manipulação de toda a
                                                          // movimentação da nossa interface.

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

  /// Instancia e define todas as variáveis e atributos necessários para carregar os primeiros tiles na tela do usuário.
  Future<void> startTiles() async {
    final screenSize = MediaQuery.of(context).size;
    Rect initialViewport = _viewportOffset & screenSize;
    
    await tileManager.setTilesDirectory();
    await tileManager.getHighestLevel();
    zoomLevelController.setMaxZoomLevel(tileManager.maxLevel);
    
    zoomLevelController.initializeLevelScaleRanges(tileManager.levelDimensions);
    zoomLevelController.setScaleRangeForLevel(tileManager.currentLevel);
    
    await tileManager.loadTiles(initialViewport);
    
    setState(() {
      _isLoading = false;
      _initialLoadComplete = true;
    });
  }

  /// Faz update das coordenadas do viewport do usuário, baseado no canto superior esquerdo. Posiciona o viewport no mundo virtual.
  void updateViewportCoords() {
    if (_levelChangeInProgress) {
      return;
    }
    
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

  /// Carrega os tiles a medida que o viewport do usuário vai se movendo pelo mundo virtual.
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

  /// Executa um zoom no centro da tela do usuário a partir do clicar de um botão.
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
    
    if (num > 0 && oldLevel > 0) {
      newZoomLevel = oldLevel - 1;
      levelChanged = true;
    } else if (num < 0 && oldLevel < zoomLevelController.maxZoomLevel) {
      newZoomLevel = oldLevel + 1;
      levelChanged = true;
    }

    if (levelChanged) {
      final worldCenterXOldLevel = (viewportCenterX - originalTranslationX) / currentScale;
      final worldCenterYOldLevel = (viewportCenterY - originalTranslationY) / currentScale;
      
      double finalWorldCenterX = worldCenterXOldLevel;
      double finalWorldCenterY = worldCenterYOldLevel;
      
      _levelChangeInProgress = true;
      
      final oldDims = tileManager.levelDimensions[oldLevel] ?? {'width': 512, 'height': 512};
      final newDims = tileManager.levelDimensions[newZoomLevel] ?? {'width': 512, 'height': 512};
      
      final double scaleFactorX = newDims['width']!.toDouble() / oldDims['width']!.toDouble();
      final double scaleFactorY = newDims['height']!.toDouble() / oldDims['height']!.toDouble();
      
      finalWorldCenterX = worldCenterXOldLevel * scaleFactorX;
      finalWorldCenterY = worldCenterYOldLevel * scaleFactorY;
      
      print('Level change: $oldLevel -> $newZoomLevel');
      
      tileManager.currentLevel = newZoomLevel;
      
      zoomLevelController.setScaleRangeForLevel(newZoomLevel);
      
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
                    updateViewportCoords();
                  },
                  onInteractionEnd: (details) async {
                    if (_levelChangeInProgress) {
                      return;
                    }
                    
                    final currentScale = transformationController.value.getMaxScaleOnAxis();
                    
                    if ((currentScale - 1.0).abs() < 0.01) {
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
                      
                      double newScale = 1.0;
                      
                      double newTranslationX = viewportCenterX - (worldCenterX * newScale);
                      double newTranslationY = viewportCenterY - (worldCenterY * newScale);
                      
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
                // Positioned.fill(
                //   child: Center(
                //     child: Container(
                //       width: 20,
                //       height: 20,
                //       decoration: BoxDecoration(
                //         color: Colors.red.withOpacity(0.7),
                //         border: Border.all(color: Colors.white, width: 2),
                //       ),
                //     ),
                //   ),
                // ),
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
