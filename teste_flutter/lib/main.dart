import 'package:flutter/material.dart';

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
  // coordenadas que mostramos
  int boxX = 0;
  int boxY = 0;

  // chave para referenciar o widget cuja coordenada local queremos
  final GlobalKey _areaKey = GlobalKey();

  void _updateLoc(PointerEvent event) {
    // pega a RenderBox do widget com a chave
    final box = _areaKey.currentContext?.findRenderObject() as RenderBox?;

    int localX, localY;
    if (box != null) {
      // converte posição global para coordenada local do box
      final local = box.globalToLocal(event.position);
      localX = local.dx.floor();
      localY = local.dy.floor();
    } else {
      // fallback: usa event.localPosition (relativa ao alvo do evento)
      localX = event.localPosition.dx.floor();
      localY = event.localPosition.dy.floor();
    }

    // atualiza estado só se mudou
    if (boxX != localX || boxY != localY) {
      setState(() {
        boxX = localX;
        boxY = localY;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        // MouseRegion aqui pega eventos enquanto o mouse estiver dentro do child (Container)
        child: MouseRegion(
          onHover: _updateLoc,
          child: Container(
            key: _areaKey,    
            width: MediaQuery.of(context).size.width,
            height: MediaQuery.of(context).size.height,
            child: Row(
              children: [
                Column(children: [Image.asset('assets/001/level0/63_221.jpg', scale: 1.6), Image.asset('assets/001/level0/63_222.jpg', scale: 1.6)]), 
                Column(children: [Image.asset('assets/001/level0/64_221.jpg', scale: 1.6), Image.asset('assets/001/level0/64_222.jpg', scale: 1.6)],),
                Column(children: [Image.asset('assets/001/level0/65_221.jpg', scale: 1.6), Image.asset('assets/001/level0/65_222.jpg', scale: 1.6)],),
              ],
              )
            ),
          ),
        ),
      );
  }
}
