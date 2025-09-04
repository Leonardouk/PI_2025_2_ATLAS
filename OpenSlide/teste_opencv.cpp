#include <opencv2/opencv.hpp>
#include <iostream>

using namespace cv;
using namespace std;

int main() {
    cout << "Iniciando programa..." << endl;
    
    // Cria uma imagem preta 300x300
    Mat img = Mat::zeros(300, 300, CV_8UC3);
    
    cout << "Imagem criada: " << img.rows << "x" << img.cols << " pixels" << endl;
    
    // Em vez de mostrar na tela, salva a imagem
    bool saved = imwrite("imagem_preta.png", img);
    
    if (saved) {
        cout << "Imagem salva como 'imagem_preta.png'" << endl;
        cout << "Abra o arquivo para visualizar!" << endl;
    } else {
        cout << "Erro ao salvar imagem" << endl;
        return -1;
    }
    
    cout << "Programa finalizado com sucesso!" << endl;
    
    // Pausa para você ver as mensagens (equivalente ao waitKey)
    cout << "Pressione Enter para sair...";
    cin.get();
    
    return 0;
}