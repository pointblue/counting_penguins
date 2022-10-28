//  TiffTiler.cpp
//  Created by Tim DeBenedictis on 10/25/22.

#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <tiffio.h>
#include <jpeglib.h>
#include <setjmp.h>

#include <string>
#include <iostream>

#include "GImage.h"

// To compile this program on MacOS:
// brew install libtiff
// gcc -o tifftiler TiffTiler.cpp -I/opt/homebrew/include -L/opt/homebrew/lib -ltiff  -ljpeg -lstdc++

// To compile this program on Ubuntu Linux:
// sudo apt install libtiff
// gcc -o tifftiler TiffTiler.cpp -I/usr/include  -L/usr/lib -ltiff  -ljpeg -lstdc++

// To run:
// ./tifftiler orthos/croz_2020-11-29_all_col.tif

typedef struct GImage
{
    int     width;              // number of pixels across image horizontally
    int     height;             // number of pixels down image vertically
    int     depth;              // number of bits per pixel: 1, 8, 24, or 32
    size_t  rowsize;            // number of bytes per row in image data
    char    *data;              // pointer to image data buffer
    int     colortable[0x0100]; // RGBA color table for 8-bit images
    int     selectLeft;         // selected rectangle left; 0 < left < width
    int     selectTop;          // selected rectangle top; 0 < top < height
    int     selectRight;        // selected rectangle right; left <= right <= width
    int     selectBottom;       // selected rectangle bottom; top <= bottom <= height
}
GImage;

/*** GCreateImage ****************************************************************/

GImagePtr GCreateImage ( int width, int height, int depth )
{
    GImagePtr    image = NULL;

    image = (GImagePtr) calloc ( 1, sizeof ( GImage ) );
    if ( image == NULL )
        return ( NULL );
    
    image->data = (char *) calloc ( width * height * depth / 8, sizeof ( char ) );
    if ( image->data == NULL )
    {
        free ( image );
        return ( NULL );
    }
    
    image->width = width;
    image->height = height;
    image->depth = depth;
    image->rowsize = width * depth / 8;

    /*** create a simple grayscale color table for the image. ***/
    
    for ( int index = 0; index < 256; index++ )
        GSetImageColorTableEntry ( image, index, index, index, index );
    
    /*** set initial selection rectangle to entire image ***/
    
    image->selectLeft = 0;
    image->selectTop = 0;
    image->selectRight = width;
    image->selectBottom = height;
    
    return ( image );
}

/*** GDeleteImage ****************************************************************/

void GDeleteImage ( GImagePtr image )
{
    if ( image != NULL )
    {
        free ( image->data );
        free ( image );
    }
}

/*** GGetImageWidth **************************************************************/

int GGetImageWidth ( GImagePtr image )
{
    if ( image != NULL )
        return ( image->width );
    else
        return ( 0 );
}

/*** GGetImageHeight **************************************************************/

int GGetImageHeight ( GImagePtr image )
{
    if ( image != NULL )
        return ( image->height );
    else
        return ( 0 );
}

/*** GGetImageDepth ********************************************************/

int GGetImageDepth ( GImagePtr image )
{
    if ( image != NULL )
        return ( image->depth );
    else
        return ( 0 );
}

/*** GGetImageDataRowSize **************************************************/

size_t GGetImageDataRowSize ( GImagePtr image )
{
    if ( image != NULL )
        return ( image->rowsize );
    else
        return ( 0 );
}

/*** GGetImageDataRow ******************************************************/

char *GGetImageDataRow ( GImagePtr image, int row )
{
    if ( image != NULL && row >= 0 && row < image->height )
        return ( image->data + image->rowsize * row );
    else
        return ( NULL );
}

/***  GSetImageColorTableEntry  ****************************************/

void GSetImageColorTableEntry ( GImagePtr image, unsigned char index,
                               unsigned char red, unsigned char green, unsigned char blue )
{
    image->colortable[index] = ( blue << 16L ) | ( green << 8L ) | red;
}

/*** GGetImageColorTableEntry *********************************************/

void GGetImageColorTableEntry ( GImagePtr image, unsigned char index,
                               unsigned char *red, unsigned char *green, unsigned char *blue )
{
    *red   = image->colortable[index] & 0x000000FF;
    *green = ( image->colortable[index] >> 8 ) & 0x000000FF;
    *blue  = ( image->colortable[index] >> 16 ) & 0x000000FF;
}

/*** GCreateSubframeImage **/

GImagePtr GCreateSubframeImage ( GImagePtr image, int subLeft, int subTop, int subWidth, int subHeight )
{
    int width = GGetImageWidth ( image );
    int height = GGetImageHeight ( image );
    int depth = GGetImageDepth ( image );
    
    if ( subLeft < 0 || subLeft + subWidth > width )
        return NULL;
    
    if ( subTop < 0 || subTop + subHeight > height )
        return NULL;
    
    GImagePtr subImage = GCreateImage ( subWidth, subHeight, depth );
    if ( subImage == NULL )
        return NULL;
    
    int subRowSize = GGetImageDataRowSize ( subImage );
    for ( int subRow = 0; subRow < subHeight; subRow++ )
    {
        char *rowPtr = GGetImageDataRow ( image, subTop + subRow );
        char *subRowPtr = GGetImageDataRow ( subImage, subRow );
        memcpy ( subRowPtr, rowPtr + subLeft * depth / 8, subRowSize );
    }

    return subImage;
}

/*** jpeg_std_error_jump ****************************************************/

static jmp_buf    *error_jump_buffer;

void error_jump ( j_common_ptr cinfo )
{
    /*** Clean up the JPEG compression or decompression object,
     then return control to the setjmp point. ***/
    
    jpeg_destroy ( cinfo );
    longjmp ( *error_jump_buffer, 1 );
}

struct jpeg_error_mgr *jpeg_std_error_jump ( struct jpeg_error_mgr *err, jmp_buf *err_jmp_buf )
{
    jpeg_std_error ( err );
    err->error_exit = error_jump;
    error_jump_buffer = err_jmp_buf;
    return ( err );
}

/*** GWriteJPEGImageFile *****************************************************/

int GWriteJPEGImageFile ( GImagePtr image, short quality, FILE *file )
{
    struct jpeg_compress_struct    cinfo;
    struct jpeg_error_mgr        jerr;
    JSAMPROW                    row_pointer[1];
    JDIMENSION                    col;
    int                            row_stride;
    int                            image_width = GGetImageWidth ( image );
    int                            image_height = GGetImageHeight ( image );
    int                            image_depth = GGetImageDepth ( image );
    jmp_buf                        jerr_jmp_buf;
    unsigned char                red, green, blue;
    unsigned char                *image_row;
    
    /*** Set up default JPEG library error handling.  Then override the
     standard error_exit routine (which would quit the program!) with
     our own replacement, which jumps back to context established in
     the call to setjmp() below.  If this happens, the JPEG library
     has signalled a fatal error, so close the file and return FALSE. ***/
    
    cinfo.err = jpeg_std_error_jump ( &jerr, &jerr_jmp_buf );
    if ( setjmp ( jerr_jmp_buf ) )
    {
        return ( FALSE );
    }
    
    /*** Now allocate and initialize the JPEG compression object, and specify
     the file as the data source. */
    
    jpeg_create_compress ( &cinfo );
    jpeg_stdio_dest ( &cinfo, file );
    
    /*** Set parameters for compression.  First we supply a description of the
     input image.  We must set at least cinfo.in_color_space, since the defaults
     depend on the source color space.  Then use the library's routine to set
     default compression parameters.  Finally, we can set any non-default
     parameters we wish to.  Here we just use the quality (quantization table)
     scaling ***/
    
    cinfo.image_width = image_width;
    cinfo.image_height = image_height;
    cinfo.input_components = image_depth == 8 ? 1 : 3;
    cinfo.in_color_space = image_depth == 8 ? JCS_GRAYSCALE : JCS_RGB;
    
    jpeg_set_defaults ( &cinfo);
    jpeg_set_quality ( &cinfo, quality, TRUE );
    
    /*** Start the JPEG compressor. ***/
    
    jpeg_start_compress ( &cinfo, TRUE );
    
    /*** Determine the size, in bytes, of a row in the output buffer,
     then make a one-row-high sample array.  Then write scanlines
     to the output file until there are no more scanlines to be read. ***/
    
    row_stride = image_width * cinfo.input_components;
    row_pointer[0] = (JSAMPLE *) malloc ( row_stride );
    
    while ( cinfo.next_scanline < cinfo.image_height )
    {
        /*** Here we use the library's state variable cinfo.next_scanline
         as the loop counter, so that we don't have to keep track ourselves. ***/
        
        image_row = (JSAMPLE *) GGetImageDataRow ( image, cinfo.next_scanline );
        
        for ( col = 0; col < image_width; col++ )
        {
            /*** Copy the R-G-B color components of the image pixel into the
             corresponding locations in the output row, then write the
             entire row to the file. ***/
            
            if ( image_depth == 8 )
            {
                row_pointer[0][col] = image_row[col];
            }
            else if ( image_depth == 24 )
            {
                row_pointer[0][3 * col]     = image_row[3 * col];        // red
                row_pointer[0][3 * col + 1] = image_row[3 * col + 1];    // green
                row_pointer[0][3 * col + 2] = image_row[3 * col + 2];    // blue
            }
            else if ( image_depth == 32 )
            {
                row_pointer[0][3 * col]     = image_row[4 * col];        // red
                row_pointer[0][3 * col + 1] = image_row[4 * col + 1];    // green
                row_pointer[0][3 * col + 2] = image_row[4 * col + 2];    // blue
            }
        }
        
        jpeg_write_scanlines ( &cinfo, row_pointer, 1 );
    }
    
    free ( row_pointer[0] );
    
    /*** Finish compression, and release the JPEG compression object ***/
    
    jpeg_finish_compress ( &cinfo );
    jpeg_destroy_compress ( &cinfo );
    
    /*** And we're done! ***/
    
    return ( TRUE );
}

/*** TIFFErrorSupressor *****************************************************************/

void TIFFErrorSupressor ( const char *module, const char *fmt, va_list ap )
{
    
}

/*** TIFFClientRead *********************************************************************/

tsize_t TIFFClientRead ( thandle_t handle, tdata_t data, tsize_t size )
{
    FILE *file = (FILE *) handle;
    tsize_t result;
    
    result = fread ( data, size, 1, file );
    
    return ( result * size );
}

/*** TIFFClientWrite *********************************************************************/

tsize_t TIFFClientWrite ( thandle_t handle, tdata_t data, tsize_t size )
{
    FILE *file = (FILE *) handle;
    tsize_t result;
    
    result = fwrite ( data, size, 1, file );
    
    return ( result * size );
}

/*** TIFFClientSeek *********************************************************************/

toff_t TIFFClientSeek ( thandle_t file, toff_t offset, int whence )
{
    if ( fseek ( (FILE *) file, offset, whence ) == 0 )
        return ( ftell ( (FILE *) file ) );
    else
        return ( EOF );
}

/*** TIFFClientClose *********************************************************************/

int TIFFClientClose ( thandle_t file )
{
    return ( fclose ( (FILE *) file ) );
}

/*** TIFFClientSize *********************************************************************/

toff_t TIFFClientSize ( thandle_t file )
{
    long size = -1, offset;
    
    offset = ftell ( (FILE *) file );
    if ( offset > -1 )
    {
        if ( fseek ( (FILE *) file, 0, SEEK_END ) == 0 )
            size = ftell ( (FILE *) file );
        
        fseek ( (FILE *) file, offset, SEEK_SET );
    }
    
    return ( size );
}

/*** TIFFClientMap *********************************************************************/

int TIFFClientMap ( thandle_t file, tdata_t* pbase, toff_t* psize )
{
    return ( 0 );
}

/*** TIFFClientUnmap *********************************************************************/

void TIFFClientUnmap ( thandle_t file, tdata_t base, toff_t size )
{
    
}

/*** GOpenTIFFImage *******************************************************************/

TIFF *GOpenTIFFImage ( const char *filename )
{
    int                row, col, width = 0, height = 0, tilewidth = 0, tileheight = 0;
    unsigned int    *data0, *data1, *data2, value;
    unsigned short    bitspersample = 0, samplesperpixel = 0, planarconfig = 0, photometric = 0;
    unsigned short    compression = 0;
    unsigned short    numcolors, color, *redmap = NULL, *greenmap = NULL, *bluemap = NULL;
    unsigned char    red, green, blue, alpha;
    TIFF            *tiff = NULL;
    
    FILE *file = fopen ( filename, "rb" );
    if ( file == NULL )
        return NULL;
        
    /*** Create a TIFF record in memory.  (Note that we don't actually open the file
     here!)  Note that this automatically reads the first TIFF Image File Directory
     (i.e. all data associated with the first image in the TIFF file) in the file.
     Return an error code on failure. ***/
    
    tiff = TIFFClientOpen ( "", "r", file,
                           TIFFClientRead, TIFFClientWrite, TIFFClientSeek, TIFFClientClose, TIFFClientSize,
                           TIFFClientMap, TIFFClientUnmap );
    
    if ( tiff == NULL )
        return ( NULL );
    
    /*** Obtain the image's dimensions and bit-depth.  The create a new image with the
     corresponding dimensions and bit-depth.  On failure, release memory for the
     TIFF file and return a NULL pointer. ***/
    
    TIFFGetField ( tiff, TIFFTAG_IMAGEWIDTH, &width );
    TIFFGetField ( tiff, TIFFTAG_IMAGELENGTH, &height );
    TIFFGetField ( tiff, TIFFTAG_TILEWIDTH, &tilewidth );
    TIFFGetField ( tiff, TIFFTAG_TILELENGTH, &tileheight );
    TIFFGetField ( tiff, TIFFTAG_SAMPLESPERPIXEL, &samplesperpixel );
    TIFFGetField ( tiff, TIFFTAG_BITSPERSAMPLE, &bitspersample );
    TIFFGetField ( tiff, TIFFTAG_PLANARCONFIG, &planarconfig );
    TIFFGetField ( tiff, TIFFTAG_PHOTOMETRIC, &photometric );
    TIFFGetField ( tiff, TIFFTAG_COMPRESSION, &compression );
    
    printf ( "TIFF width: %d\n", width );
    printf ( "TIFF height: %d\n", height );
    printf ( "TIFF tile width: %d\n", tilewidth );
    printf ( "TIFF tile height: %d\n", tileheight );
    printf ( "TIFF bits per sample: %d\n", bitspersample );
    printf ( "TIFF samples per pixel: %d\n", samplesperpixel );
    printf ( "TIFF planar config: %d\n", planarconfig );
    printf ( "TIFF photometric: %d\n", photometric );
    printf ( "TIFF compression: %d\n", compression );
    printf ( "TIFF scanline size: %lld\n", TIFFScanlineSize ( tiff ) );
    
    return tiff;
}

/*** GReadTIFFImageStrip *******************************************************************/

GImagePtr GReadTIFFImageStrip ( TIFF *tiff, int stripTop, int stripHeight )
{
    int             width = 0, height = 0, tilewidth = 0, tileheight = 0;
    unsigned short  bitspersample = 0, samplesperpixel = 0, planarconfig = 0, photometric = 0;
    GImagePtr       image = NULL;

    /*** Obtain the image's dimensions and bit-depth.  The create a new image with the
         corresponding dimensions and bit-depth.  On failure, release memory for the
         TIFF file and return a NULL pointer. ***/
    
    TIFFGetField ( tiff, TIFFTAG_IMAGEWIDTH, &width );
    TIFFGetField ( tiff, TIFFTAG_IMAGELENGTH, &height );
    TIFFGetField ( tiff, TIFFTAG_TILEWIDTH, &tilewidth );
    TIFFGetField ( tiff, TIFFTAG_TILELENGTH, &tileheight );
    TIFFGetField ( tiff, TIFFTAG_SAMPLESPERPIXEL, &samplesperpixel );
    TIFFGetField ( tiff, TIFFTAG_BITSPERSAMPLE, &bitspersample );
    TIFFGetField ( tiff, TIFFTAG_PLANARCONFIG, &planarconfig );
    TIFFGetField ( tiff, TIFFTAG_PHOTOMETRIC, &photometric );

    /*** If we have a TIFF file which represents an RGB color image,
         we read a horizontal strip out of the TIFF and return it as a GImage.
         NOTE: THIS CODE WILL FAIL TO READ TILED TIFF FILES. ***/
    
    if ( bitspersample <= 8 && tilewidth == 0 && tileheight == 0 && photometric == PHOTOMETRIC_RGB )
    {
        image = GCreateImage ( width, stripHeight, bitspersample * samplesperpixel );
        if ( image == NULL )
        {
            printf ( "Failed to allocate GImage!\n" );
            TIFFClose ( tiff );
            return ( NULL );
        }
                
        /*** For each row in the TIFF file, read image data into the image directly.
             We can get away with this because the data returned by the TIFF library
             is in exactly the same format the we expect for an indexed-color bitmap. ***/
        
        for ( int row = 0; row < stripHeight; row++ )
        {
            TIFFReadScanline ( tiff, GGetImageDataRow ( image, row ), row + stripTop, 0 );
        }
    }
    
    /*** Return a pointer to the image. ***/
    
    return ( image );
}

#define TILEWIDTH 512
#define TILEHEIGHT 256
#define TILEOVERLAP 20

int main ( int argc, char *argv[] )
{
    // Print usage and quit if not enough inputs
    
    if ( argc < 3 )
    {
        printf ( "Usage: %s <tifffile> <tiledir>\n", argv[0] );
        printf ( "tiffile: path to input ortho TIFF file.\n" );
        printf ( "tiledir: path to output tile directory.\n" );
        exit ( -1 );
    }
    
    // Open TIFF file, exit on failure
    
    TIFF *tiff = GOpenTIFFImage ( argv[1] );
    if ( tiff == NULL )
    {
        printf ( "Can't open input TIFF file %s!\n", argv[1] );
        exit ( -1 );
    }
    
    // Get base filename of input ortho TIFF file
    
    printf ( "Opened input TIFF image file %s.\n", argv[1] );
    std::string inpath ( argv[1] );
    size_t start = inpath.find_last_of ( "/" ) + 1;
    size_t end = inpath.find_last_of ( "." );
    std::string basename = inpath.substr ( start, end - start );
    
    // Make sure output directory ends with a slash
    
    std::string outdir ( argv[2] );
    if ( outdir.back() != '/' )
        outdir += '/';
    
    // Get ortho dimensions and compute number of tiles needed
    
    int width = 0, height = 0;
    TIFFGetField ( tiff, TIFFTAG_IMAGEWIDTH, &width );
    TIFFGetField ( tiff, TIFFTAG_IMAGELENGTH, &height );

    int numTilesX = ( width + TILEWIDTH - 1 ) / TILEWIDTH;
    int numTilesY = ( height + TILEHEIGHT - 1 ) / TILEHEIGHT;
    printf ( "Number of tiles x=%d, y=%d, total=%d\n", numTilesX, numTilesY, numTilesX * numTilesY );
    
    // Read horizontal strips out of the TIFF file.

    for ( int strip = 0; strip < numTilesY; strip++ )
    {
        int stripTop    = strip * TILEHEIGHT;
        int stripBottom = stripTop + TILEHEIGHT;
        int stripHeight = stripBottom <= height ? TILEHEIGHT : height - stripTop;
        
        GImagePtr stripImage = GReadTIFFImageStrip ( tiff, stripTop, stripHeight );
        if ( stripImage == NULL )
        {
            printf ( "Failed to read TIFF image strip %d!\n", strip );
            break;
        }
        
        printf ( "Read TIFF image strip %d!\n", strip );
        
        // Extract tiles from the strip, and write each tile to a JPEG file
        
        for ( int tile = 0; tile < numTilesX; tile++ )
        {
            int tileLeft  = tile * TILEWIDTH;
            int tileRight = tileLeft + TILEWIDTH;
            int tileWidth = tileRight <= width ? TILEWIDTH : width - tileLeft;
            
            GImagePtr tileImage = GCreateSubframeImage ( stripImage, tileLeft, 0, tileWidth, stripHeight );
            if ( tileImage == NULL )
            {
                printf ( "Failed to create strip %d tile %d!\n", strip, tile );
                continue;
            }
            
            char tilename[256] = { 0 };
            sprintf ( tilename, "_%03d_%03d.jpg", strip, tile );
            std::string outpath = outdir + basename + tilename;
            
            FILE *outfile = fopen ( outpath.c_str(), "wb" );
            if ( outfile == NULL )
            {
                printf ( "Failed to create file %s!\n", outpath.c_str() );
                GDeleteImage ( tileImage );
                continue;
            }

            if ( GWriteJPEGImageFile ( tileImage, 90, outfile ) )
                printf ( "Wrote tile %s...\n", outpath.c_str() );
            else
                printf ( "Failed to write tile %s...\n", outpath.c_str() );
        
            fclose ( outfile );
            GDeleteImage ( tileImage );
        }
        
        GDeleteImage ( stripImage );
    }

    TIFFClose ( tiff );
}
