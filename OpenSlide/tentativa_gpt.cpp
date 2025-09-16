#include <iostream>
#include <opencv2/opencv.hpp>
#include <openslide/openslide.h>
#include <cmath>
#include <vector>
#include <fmt/format.h>
#include <filesystem>   // para criar diretórios

namespace fs = std::filesystem;

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
    int level_count = openslide_get_level_count(slide);
    std::cout << "Níveis disponíveis: " << level_count << std::endl;

    int64_t width0, height0;
    openslide_get_level0_dimensions(slide, &width0, &height0);
    int16_t tile_size = 256;
    
    // Renderização dos tiles por cada nível (0 até máximo)
    for (int current_level = 0; current_level < level_count; ++current_level) {
        int64_t level_width, level_height;
        openslide_get_level_dimensions(slide, current_level, &level_width, &level_height);
        
        double factor = pow(2.0, (level_count - 1 - current_level));
        
        int tiles_x = (level_width + tile_size - 1) / tile_size;
        int tiles_y = (level_height + tile_size - 1) / tile_size;

        // Cria diretório automaticamente
        std::string level_dir = fmt::format("tiles/level{}", current_level);
        fs::create_directories(level_dir);

        for (int ty = 0; ty < tiles_y; ++ty) {
            for (int tx = 0; tx < tiles_x; ++tx) {
                int64_t x0 = (int64_t)tx * tile_size * (int64_t)factor;
                int64_t y0 = (int64_t)ty * tile_size * (int64_t)factor;

                // largura/altura reais do tile no nível 0
                int64_t tile_w = std::min<int64_t>(tile_size * factor, width0 - x0);
                int64_t tile_h = std::min<int64_t>(tile_size * factor, height0 - y0);

                int32_t best = openslide_get_best_level_for_downsample(slide, factor);
                double ds_best = openslide_get_level_downsample(slide, best);

                int read_w = (int)std::ceil((double)tile_w / ds_best);
                int read_h = (int)std::ceil((double)tile_h / ds_best);

                // segurança contra tiles inválidos
                if (read_w <= 0 || read_h <= 0 || 
                    (int64_t)read_w * (int64_t)read_h > 100000000) {
                    std::cerr << "Tile inválido em level " << current_level 
                              << " (" << tx << "," << ty << ") -> "
                              << "read_w=" << read_w << " read_h=" << read_h << std::endl;
                    continue;
                }

                std::vector<uint32_t> buf((size_t)read_w * (size_t)read_h);
                openslide_read_region(slide, buf.data(), x0, y0, best, read_w, read_h);

                // converte premultiplied ARGB -> BGR
                cv::Mat tmp(read_h, read_w, CV_8UC4, buf.data());
                cv::Mat rgba;
                tmp.copyTo(rgba);

                cv::Mat bgr(read_h, read_w, CV_8UC3);
                for (int y = 0; y < read_h; ++y) {
                    for (int x = 0; x < read_w; ++x) {
                        cv::Vec4b px = rgba.at<cv::Vec4b>(y, x);
                        uint8_t b = px[0], g = px[1], r = px[2], a = px[3];
                        if (a == 0) { 
                            bgr.at<cv::Vec3b>(y, x) = cv::Vec3b(255, 255, 255); 
                        } else if (a == 255) { 
                            bgr.at<cv::Vec3b>(y, x) = cv::Vec3b(b, g, r); 
                        } else {
                            float inv = 255.0f / (float)a;
                            uint8_t rr = (uint8_t)std::min(255, (int)std::round(r * inv));
                            uint8_t gg = (uint8_t)std::min(255, (int)std::round(g * inv));
                            uint8_t bb = (uint8_t)std::min(255, (int)std::round(b * inv));
                            bgr.at<cv::Vec3b>(y, x) = cv::Vec3b(bb, gg, rr);
                        }
                    }
                }

                // redimensiona para tile_size x tile_size
                cv::Mat tile;
                cv::resize(bgr, tile, cv::Size(tile_size, tile_size),
                           0, 0, cv::INTER_LANCZOS4);

                // salvar JPG
                std::vector<int> params = {cv::IMWRITE_JPEG_QUALITY, 90};
                std::string name = fmt::format("{}/{}_{}.jpg", level_dir, tx, ty);

                std::cout << "Salvando: " << name 
                          << " (" << read_w << "x" << read_h << ")" << std::endl;

                cv::imwrite(name, tile, params);
            }
        }
    }

    openslide_close(slide);
    return 0;
}
