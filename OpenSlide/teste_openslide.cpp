#include <openslide/openslide.h>
#include <stddef.h>
#include <stdint.h>
#include <stdbool.h>
#include <iostream>
#include <limits>
#include <filesystem>
#include <string>

using namespace std;

// Filesystem variables
filesystem::path filePath = "C:/Users/leona/Pictures/001.mrxs";
uintmax_t fileSize = filesystem::file_size(filePath);
openslide_t* slide;

int main() {
    // Checking the size of the slide
    cout << "File size = " << fileSize << endl;
    
    // Opening the slide while avoiding undesirable situations
    try{
        slide = openslide_open("C:/Users/leona/Pictures/001.mrxs");
        if (slide == NULL) {
            cout << "O arquivo é nulo ou inválido.";
        } 
    } catch(const runtime_error e) {
        cout << e.what() << endl;
    }
    
    // Dimensions of slide
    int64_t w, h;
    openslide_get_level0_dimensions(slide, &w, &h);
    const char* mpp_x = openslide_get_property_value(slide, OPENSLIDE_PROPERTY_NAME_MPP_X);
    const char* mpp_y = openslide_get_property_value(slide, OPENSLIDE_PROPERTY_NAME_MPP_Y);
    double mpp_xd = stod(mpp_x);
    double mpp_yd = stod(mpp_y);
    cout << "Largura do slide (pixels): " << w << "\nAltura do slide (pixels): " << h << endl;
    cout << "Largura do slide: (micrometros): " << mpp_xd * w << "\nAltura do slide: (micrometros): " << mpp_yd * h << endl;

    // Slide information
    const char* slide_info_vendor = openslide_get_property_value(slide, OPENSLIDE_PROPERTY_NAME_VENDOR);
    cout << slide_info_vendor << endl;

    
    
    openslide_close(slide);

    // Waiting for user input to end the program
    cout << "Aperte Enter para encerrar o programa..." << endl; 
    // cin.ignore(numeric_limits<streamsize>::max(), '\n'); // Clears input buffer
    cin.get();
    return 0;
}