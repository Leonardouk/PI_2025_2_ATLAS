#include <iostream>
#include <opencv2/opencv.hpp>
#include <openslide/openslide.h>
#include <vector>

int main() {
    const char* filename = "C:/Users/leona/Pictures/001.mrxs";
    
    openslide_t* slide = openslide_open(filename);
    if (slide == nullptr) {
        std::cerr << "Erro: arquivo não encontrado" << std::endl;
        return -1;
    }
    
    const char* error = openslide_get_error(slide);
    if (error != nullptr) {
        std::cerr << "Erro OpenSlide: " << error << std::endl;
        openslide_close(slide);
        return -1;
    }
    
    // Informações básicas
    int32_t level_count = openslide_get_level_count(slide);
    std::cout << "Níveis disponíveis: " << level_count << std::endl;
    
    // Tentar vários níveis
    for (int level = 0; level < level_count; level++) {
        int64_t w, h;
        openslide_get_level_dimensions(slide, level, &w, &h);
        std::cout << "Nível " << level << ": " << w << "x" << h << std::endl;
        
        // // Pular níveis muito grandes
        // if (w > 50000 || h > 50000) {
        //     std::cout << "  -> Pulando (muito grande)" << std::endl;
        //     continue;
        // }
        
        // Testar uma pequena região
        int width = 512;
        int height = 512;        
        // Várias posições para testar
        std::vector<std::pair<int64_t, int64_t>> positions = {
            {w/4, h/4},     // Quadrante 1
            {w/2, h/2},     // Centro
            {3*w/4, h/4},   // Quadrante 2
            {w/4, 3*h/4},   // Quadrante 3
            {3*w/4, 3*h/4}, // Quadrante 4
            {0, 0}          // Canto
        };
        
        for (size_t pos = 0; pos < positions.size(); pos++) {
            int64_t x = std::min(positions[pos].first, w - width);
            int64_t y = std::min(positions[pos].second, h - height);
            
            std::cout << "x: " << positions[pos].first << "|" << w << '-' << width << " y: " << positions[pos].second << "|" << h << '-' << height;
            
            std::vector<uint32_t> buffer(width * height, 0);
            openslide_read_region(slide, buffer.data(), x, y, level, width, height);
            
            // Verificar se obtivemos dados
            bool has_data = false;
            uint32_t non_zero_pixels = 0;
            for (const auto& pixel : buffer) {
                if (pixel != 0) {
                    has_data = true;
                    non_zero_pixels++;
                }
            }
            
            if (has_data) {
                std::cout << "  -> Dados encontrados na posição " << pos 
                         << " (x=" << x << ", y=" << y << ") - " 
                         << non_zero_pixels << " pixels não-zero" << std::endl;
                
                // Criar imagem OpenCV - método mais direto
                cv::Mat img(height, width, CV_8UC4, buffer.data());
                cv::Mat img_bgr;
                cv::cvtColor(img, img_bgr, cv::COLOR_RGBA2BGR);
                
                std::string filename = "debug_nivel" + std::to_string(level) + 
                                     "_pos" + std::to_string(pos) + ".png";
                cv::imwrite(filename, img_bgr);
                std::cout << "  -> Salvo: " << filename << std::endl;
                
                // Também tentar conversão manual
                cv::Mat manual_img(height, width, CV_8UC3);
                for (int i = 0; i < height; i++) {
                    for (int j = 0; j < width; j++) {
                        uint32_t pixel = buffer[i * width + j];
                        std::cout << pixel << std::endl;
                        uint8_t a = (pixel >> 24) & 0xFF;
                        uint8_t r = (pixel >> 16) & 0xFF;
                        uint8_t g = (pixel >> 8) & 0xFF;
                        uint8_t b = pixel & 0xFF;
                        
                        // Se transparente, usar cinza
                        if (a == 0) {
                            manual_img.at<cv::Vec3b>(i, j) = cv::Vec3b(128, 128, 128);
                        } else {
                            manual_img.at<cv::Vec3b>(i, j) = cv::Vec3b(b, g, r);
                        }
                    }
                }
                
                std::string manual_filename = "manual_nivel" + std::to_string(level) + 
                                            "_pos" + std::to_string(pos) + ".png";
                cv::imwrite(manual_filename, manual_img);
                std::cout << "  -> Salvo (manual): " << manual_filename << std::endl;
                
                // Parar após encontrar a primeira região com dados
                if (non_zero_pixels > 1000) { // Se tem bastante conteúdo
                    openslide_close(slide);
                    return 0;
                }
            } else {
                std::cout << "  -> Posição " << pos << " vazia" << std::endl;
            }
        }
    }
    
    std::cout << "Nenhuma região com conteúdo foi encontrada!" << std::endl;
    openslide_close(slide);
    return 0;
}