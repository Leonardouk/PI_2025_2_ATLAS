#include <iostream>
#include <regex>
#include <string>
#include <filesystem>
#include <fmt/format.h>

int main() {
    
    for (int current_level = 0; current_level < 10; current_level++) {
        std::filesystem::path path = fmt::format("./Openslide/tiles/001.mrxs/level{}", current_level);
        std::regex correct_images(fmt::format("{}\\\\\\w+_(LQ|HQ).jpg", path.string()));

        for (const auto &file : std::filesystem::directory_iterator(path)) {
            std::string image_name = (file.path()).string();
            if (!std::regex_match(image_name, correct_images)) std::filesystem::remove(file.path());
        }
    }

    return 0;
}