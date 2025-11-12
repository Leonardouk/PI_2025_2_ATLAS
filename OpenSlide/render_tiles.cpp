// Comando para compilação:  g++ -o render.exe render_tiles.cpp `pkg-config --cflags --libs opencv4` -lopenslide -lfmt
// Para executar, baixar opencv, openslide e fmt

#include <iostream>
#include <opencv2/opencv.hpp>
#include <openslide/openslide.h>
#include <cmath>
#include <vector>
#include <fmt/format.h>
#include <filesystem> 
#include <chrono>

namespace fs = std::filesystem;

// Essa função serve para conferir se o tile lido está majoritamente vazio
bool is_tile_empty(const std::vector<uint32_t> &buffer, double limit = .8, int white_level = 240) {
    int white_pixels = 0;
    int total_pixels = buffer.size();

    for (int pixel_channels : buffer) {
        int r = (pixel_channels >> 16) & 0xFF;
        int g = (pixel_channels >> 8) & 0xFF;
        int b = pixel_channels & 0xFF;

        if (r >= white_level && g >= white_level && b >= white_level) {
            white_pixels++;
        }
    }

    double frac_white = static_cast<double>(white_pixels) / total_pixels;
    return frac_white >= limit;
}

int main() {
    std::chrono::steady_clock::time_point begin = std::chrono::steady_clock::now();

    std::string file = "001.mrxs";
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

    // Checa se existe diretório para tiles e o cria se necessáo
    fs::path out_root = fs::path(std::getenv("USERPROFILE")) / "Documents" / "tiles";

    // Checa se existe diretório referente ao arquivo sendo lido e cria se necessário
    fs::path file_dir = fmt::format("{}", file);

    // Informações básicas
    int level_count = openslide_get_level_count(slide);
    std::cout << "Níveis disponíveis: " << level_count << std::endl;

    // int64_t width0, height0;
    // openslide_get_level0_dimensions(slide, &width0, &height0);
    int16_t tile_size = 512;
    
    // Renderização dos tiles por cada nível (0 até máximo)
    for (int current_level = 0; current_level < level_count; ++current_level) {
        int64_t level_width, level_height;
        openslide_get_level_dimensions(slide, current_level, &level_width, &level_height);
        
        // Essas variáveis determinam o tamanho em tiles dos dois eixos da imagem
        int tiles_x = (level_width + tile_size - 1) / tile_size;
        int tiles_y = (level_height + tile_size - 1) / tile_size;
        
        // Impressão para debug  
        // std::cout << "Nível " << current_level << std::endl;
        // std::cout << "Largura do nível: " << level_width << " | Altura do nível: " << level_height << std::endl;
        // std::cout << "tiles x: " << tiles_x << " | tilrs y: " << tiles_y << '\n' << std::endl;
        
        // Conferindo o downsample, quantos pixels em nível 0 corresponde no nível atual
        double downsample = openslide_get_level_downsample(slide, current_level);
        
        std::cout << "Level " << current_level << ": " << level_width << " x " << level_height << " (downsample: " << downsample << ")" << std::endl;
        // Reserva espaço no buffer para armazenar tiles
        std::vector<uint32_t> buffer; 
        buffer.reserve(tile_size * tile_size); // tamanho do buffer é exatamente quantos pixels existem em um tile

        // Cria diretório para armazenar tiles por nível se não existir
        fs::path level_dir = fmt::format("level{}", current_level);

        // Lendo informação por tile
        for (int y = 0; y < tiles_y; y++) {
            for (int x = 0; x < tiles_x; x++) {
                // Confirma se o tile está no limite do eixo
                int64_t tile_w = std::min<int64_t>(tile_size, level_width - x * tile_size);
                int64_t tile_h = std::min<int64_t>(tile_size, level_height - y * tile_size);
                if (tile_w <= 0 || tile_h <= 0) continue;

                // Ajustando as coordenadas para o nível atual
                int x0 = std::llround(x * tile_size * downsample);
                int y0 = std::llround(y * tile_size * downsample);
                
                // Redimensiona o buffer para a quantidade exata que o tile vai usar
                buffer.assign(tile_w * tile_h, 0);

                // Usamos o OpenSlide para ler tiles por tamanho
                openslide_read_region(slide, buffer.data(), x0, y0, current_level, tile_w, tile_h);

                // Verificando se dados foram encontrados no tile
                bool has_data = false;
                for (int pixel : buffer) {
                    if (pixel != 0) {
                        has_data = true;
                        break;
                    }
                }

                // Verificando se o tile é majoritamente vazio
                bool empty_tile = is_tile_empty(buffer);

                // Renderiza e salva tile se ele possuir e dados e não for "vazio"
                if (has_data && !empty_tile) {
                    std::cout << "Nível " << current_level << ": " << "tile " << x << "_" << y << " --> valido\n"; // Para debug
                    
                    // Renderizando a imagem
                    // 1- Cria matriz BGRA
                    cv::Mat img_bgra(tile_h, tile_w, CV_8UC4, buffer.data());
                    // 2- Separa os canais de cor
                    std::vector<cv::Mat> ch;
                    cv::split(img_bgra, ch);
                    // 3- Cria matriz para o canal alfa e a normaliza
                    cv::Mat alpha_f;
                    ch[3].convertTo(alpha_f, CV_32F, 1.0f / 255.0f);
                    std::vector<cv::Mat> out_ch(3);
                    // 4- Compondo os outro canais com alfa
                        for (int c = 0; c < 3; ++c) {
                        cv::Mat comp_f;
                        ch[c].convertTo(comp_f, CV_32F);
                        // out = rgb * alpha + 255*(1-alpha)
                        cv::Mat out_f = comp_f.mul(alpha_f) + 255.0f * (1.0f - alpha_f);
                        out_f.convertTo(out_ch[c], CV_8U);
                    }
                    cv::Mat out_bgr;
                    cv::merge(out_ch, out_bgr);
                    
                    // Define o diretório de saída final
                    fs::path out_dir = out_root/ file_dir / level_dir;
                    fs::create_directories(out_dir);
                    fs::path out_file_LQ = out_root/ file_dir / level_dir / fmt::format("{}_{}_LQ.jpg", x, y);
                    fs::path out_file_HQ = out_root/ file_dir / level_dir / fmt::format("{}_{}_HQ.png", x, y);
                    
                    // Salva o arquivo da imagem
                    cv::imwrite(out_file_LQ.string(), out_bgr, {cv::IMWRITE_JPEG_QUALITY, 5});
                    cv::imwrite(out_file_HQ.string(), out_bgr, {cv::IMWRITE_PNG_COMPRESSION, 9});
                } else {
                    std::cout << "Nível " << current_level << ": " << "tile " << x << "_" << y << " --> invalido\n"; // Para debug
                }
            }
        }
    }

    openslide_close(slide);
    std::chrono::steady_clock::time_point end = std::chrono::steady_clock::now();
    std::cout << "Tempo de execução: " << std::chrono::duration_cast<std::chrono::seconds>(end-begin).count() << " [s]" << std::endl;
    return 0;
}