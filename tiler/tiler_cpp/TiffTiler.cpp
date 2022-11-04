//  TiffTiler.cpp
//  Created by Tim DeBenedictis (timd@southernstars.com) on 10/25/22.
//  This program subdivides a large ortho TIFF file - much larger than will fit
//  into physical RAM - into many small JPEG tiles. Zero-contrast tiles
//  are discarded. A tile summary file in CSV format is written.
//  Things still needed to do:
//  - See TODO in code below.

#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <tiffio.h>
#include <jpeglib.h>
#include <gdal_priv.h>
#include <math.h>
#include <setjmp.h>

#include <string>
#include <iostream>

#include "GImage.h"

// To compile this program on MacOS:
// brew install libtiff gdal
// gcc -std=c++11 -o tifftiler TiffTiler.cpp -I/opt/homebrew/include -L/opt/homebrew/lib -ltiff  -ljpeg -lgdal -lstdc++

// To compile this program on Ubuntu Linux:
// sudo apt install libtiff-dev libgdal-dev
// gcc -std=c++11 -o tifftiler TiffTiler.cpp -I/usr/include/gdal -L/usr/lib -ltiff -ljpeg  -lgdal -lm -lstdc++

// To run:
// ./tifftiler orthos/croz_2020-11-29_all_col.tif tiles1

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

/*** GGetPixelColor ************************************************************/

void GGetPixelColor ( GImagePtr pImage, unsigned char *pPixel, float pRGBA[4] )
{
    if ( pImage->depth == 32 )
    {
        pRGBA[0] = pPixel[0];
        pRGBA[1] = pPixel[1];
        pRGBA[2] = pPixel[2];
        pRGBA[3] = pPixel[3];
    }
    else if ( pImage->depth == 24 )
    {
        pRGBA[0] = pPixel[0];
        pRGBA[1] = pPixel[1];
        pRGBA[2] = pPixel[2];
        pRGBA[3] = 0;
    }
    else
    {
        unsigned char red, green, blue;
        
        GGetImageColorTableEntry ( pImage, *pPixel, &red, &green, &blue );
        
        pRGBA[0] = red;
        pRGBA[1] = green;
        pRGBA[2] = blue;
        pRGBA[3] = 0;
    }
}

/*** GSetPixelColor ************************************************************/

void GSetPixelColor ( GImagePtr pImage, unsigned char *pPixel, float pRGBA[4] )
{
    if ( pImage->depth == 32 )
    {
        pPixel[0] = pRGBA[0] < 0 ? 0 : pRGBA[0] > 255 ? 255 : pRGBA[0];
        pPixel[1] = pRGBA[1] < 0 ? 0 : pRGBA[1] > 255 ? 255 : pRGBA[1];
        pPixel[2] = pRGBA[2] < 0 ? 0 : pRGBA[2] > 255 ? 255 : pRGBA[2];
        pPixel[3] = pRGBA[3] < 0 ? 0 : pRGBA[3] > 255 ? 255 : pRGBA[3];
    }
    else if ( pImage->depth == 24 )
    {
        pPixel[0] = pRGBA[0] < 0 ? 0 : pRGBA[0] > 255 ? 255 : pRGBA[0];
        pPixel[1] = pRGBA[1] < 0 ? 0 : pRGBA[1] > 255 ? 255 : pRGBA[1];
        pPixel[2] = pRGBA[2] < 0 ? 0 : pRGBA[2] > 255 ? 255 : pRGBA[2];
    }
    else
    {
        float    f = RGB_TO_LUMINANCE ( pRGBA[0], pRGBA[1], pRGBA[2] );
        
        pPixel[0] = f < 0 ? 0 : f > 255 ? 255 : f;
    }
}

/*** GCopyImageData ********************************************************************/

void GCopyImageData ( GImagePtr pDstImage, int dstLeft, int dstTop, GImagePtr pSrcImage, int srcLeft, int srcTop, int width, int height )
{
    unsigned char    *pSrcPixel, *pDstPixel;
    float            srcRGBA[4], dstRGBA[4];
    int                row, col;
    
    if ( pSrcImage->depth != pDstImage->depth )
        return;
    
    if ( srcTop + height > pSrcImage->height )
        height = pSrcImage->height - srcTop;

    if ( dstTop + height > pDstImage->height )
        height = pDstImage->height - dstTop;

    if ( srcLeft + width > pSrcImage->width )
        width = pSrcImage->width - srcLeft;
        
    if ( dstLeft + width > pDstImage->width )
        width = pDstImage->width - dstLeft;

    for ( row = 0; row < height; row++ )
    {
        pSrcPixel = (unsigned char *) GGetImageDataRow ( pSrcImage, row + srcTop ) + srcLeft * pSrcImage->depth / 8;
        pDstPixel = (unsigned char *) GGetImageDataRow ( pDstImage, row + dstTop ) + dstLeft * pDstImage->depth / 8;
        memcpy ( pDstPixel, pSrcPixel, width * pDstImage->depth / 8 );
    }
}

/*** GCreateSubImage **/

GImagePtr GCreateSubImage ( GImagePtr image, int subLeft, int subTop, int subWidth, int subHeight )
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

#if 1
    GCopyImageData ( subImage, 0, 0, image, subLeft, subTop, subWidth, subHeight );
#else
    int subRowSize = GGetImageDataRowSize ( subImage );
    for ( int subRow = 0; subRow < subHeight; subRow++ )
    {
        char *rowPtr = GGetImageDataRow ( image, subTop + subRow );
        char *subRowPtr = GGetImageDataRow ( subImage, subRow );
        memcpy ( subRowPtr, rowPtr + subLeft * depth / 8, subRowSize );
    }
#endif
    return subImage;
}

/*** GResampleImage ******************************************************/

GImagePtr GResampleImage ( GImagePtr oldImage, int newDepth )
{
    int                row, col;
    int                width = (int) GGetImageWidth ( oldImage );
    int                height = (int) GGetImageHeight ( oldImage );
    int                oldDepth = (int) GGetImageDepth ( oldImage );
    unsigned char    red, green, blue, *newData = NULL, *oldData = NULL;

    // Sanity check input parameters.
    
    if ( oldImage == NULL || ( newDepth != 8 && newDepth != 24 && newDepth != 32 ) )
        return ( NULL );
    
    // Create new image with new desired bits-per-pixel
    
    GImagePtr    newImage = GCreateImage ( width, height, newDepth );
    if ( newImage == NULL )
        return ( NULL );
        
    // Copy color table from old to new image
    
    for ( int index = 0; index < 256; index++ )
        newImage->colortable[index] = oldImage->colortable[index];

    for ( row = 0; row < height; row++ )
    {
        oldData = (unsigned char *) GGetImageDataRow ( oldImage, row );
        newData = (unsigned char *) GGetImageDataRow ( newImage, row );
        
        if ( newDepth == oldDepth )
        {
            memcpy ( newData, oldData, GGetImageDataRowSize ( oldImage ) );
        }
        else if ( newDepth == 8 )
        {
            if ( oldDepth == 24 )
            {
                for ( col = 0; col < width; col++ )
                {
                    red   = oldData[3 * col];
                    green = oldData[3 * col + 1];
                    blue  = oldData[3 * col + 2];
                    newData[ col ] = RGB_TO_LUMINANCE ( red, green, blue );
                }
            }
            else if ( oldDepth == 32 )
            {
                for ( col = 0; col < width; col++ )
                {
                    red   = oldData[4 * col];
                    green = oldData[4 * col + 1];
                    blue  = oldData[4 * col + 2];
                    newData[ col ] = RGB_TO_LUMINANCE ( red, green, blue );
                }
            }
        }
        else if ( newDepth == 24 )
        {
            if ( oldDepth == 8 )
            {
                for ( col = 0; col < width; col++ )
                {
                    GGetImageColorTableEntry ( oldImage, oldData[col], &red, &green, &blue );
                    newData[3 * col]     = red;
                    newData[3 * col + 1] = green;
                    newData[3 * col + 2] = blue;
                }
            }
            else if ( oldDepth == 32 )
            {
                for ( col = 0; col < width; col++ )
                {
                    newData[3 * col]     = oldData[4 * col];
                    newData[3 * col + 1] = oldData[4 * col + 1];
                    newData[3 * col + 2] = oldData[4 * col + 2];
                }
            }
        }
        else if ( newDepth == 32 )
        {
            if ( oldDepth == 8 )
            {
                for ( col = 0; col < width; col++ )
                {
                    GGetImageColorTableEntry ( oldImage, oldData[col], &red, &green, &blue );
                    newData[4 * col]     = red;
                    newData[4 * col + 1] = green;
                    newData[4 * col + 2] = blue;
                    newData[4 * col + 3] = 255;
                }
            }
            else if ( oldDepth == 24 )
            {
                for ( col = 0; col < width; col++ )
                {
                    newData[4 * col]     = oldData[3 * col];
                    newData[4 * col + 1] = oldData[3 * col + 1];
                    newData[4 * col + 2] = oldData[3 * col + 2];
                    newData[4 * col + 3] = 255;
                }
            }
        }
    }
    
    return ( newImage );
}

/*** GImageSwapRGBA ***/

void GImageSwapRGBA ( GImagePtr image )
{
    int width = GGetImageWidth ( image );
    int height = GGetImageHeight ( image );
    int depth = GGetImageDepth ( image );

    if ( depth < 24 )
        return;
    
    printf ( "Swapping RGBA...\n" );
    for ( int row = 0; row < height; row++ )
    {
        char *data = GGetImageDataRow ( image, row );
        for ( int col = 0; col < width; col++ )
        {
            if ( depth == 32 )
            {
                char r = data[0];
                char g = data[1];
                char b = data[2];
                char a = data[3];

                data[0] = a;
                data[1] = r;
                data[2] = g;
                data[3] = b;

                data += 4;
            }
            else if ( depth == 24 )
            {
                char r = data[0];
                char g = data[1];
                char b = data[2];
                
                data[0] = b;
                data[1] = g;
                data[2] = r;
                
                data += 3;
            }
        }
    }
}

/*** GGetImageColorStatistics ********************************************************/

void GGetImageColorStatistics ( GImagePtr pImage, int nColors, GColorStats pStats[4] )
{
    unsigned char    *pPixel = NULL;
    float            rgba[4];
    int                row, col, i, j;
    
    // initialization
    
    pPixel = (unsigned char *) GGetImageDataRow ( pImage, pImage->selectTop )
           + pImage->selectLeft * pImage->depth / 8;
    GGetPixelColor ( pImage, pPixel, rgba );
    
    for ( i = 0; i < nColors; i++ )
    {
        memset ( &pStats[i], 0, sizeof ( pStats[i] ) );
        pStats[i].min = pStats[i].max = rgba[i];
    }
    
    // Process pixels inside selected rectangle
    
    for ( row = pImage->selectTop; row < pImage->selectBottom; row++ )
    {
        pPixel = (unsigned char *) GGetImageDataRow ( pImage, row ) + pImage->selectLeft * pImage->depth / 8;
        for ( col = pImage->selectLeft; col < pImage->selectRight; col++ )
        {
            GGetPixelColor ( pImage, pPixel, rgba );
            for ( i = 0; i < nColors; i++ )
            {
                pStats[i].n++;
                pStats[i].sum += rgba[i];
                pStats[i].stdev += rgba[i] * rgba[i];
                
                if ( rgba[i] < pStats[i].min )
                    pStats[i].min = rgba[i];
                    
                if ( rgba[i] > pStats[i].max )
                    pStats[i].max = rgba[i];
                    
                pStats[i].histogram[ (int) rgba[i] ]++;
            }
            
            pPixel += pImage->depth / 8;
        }
    }
    
    // Finalization
    
    for ( i = 0; i < nColors; i++ )
    {
        pStats[i].mean = (float) pStats[i].sum / pStats[i].n;
        pStats[i].stdev = pStats[i].stdev / pStats[i].n - pStats[i].mean * pStats[i].mean;
        pStats[i].stdev = pStats[i].stdev > 0.0 ? sqrt ( pStats[i].stdev ) : 0.0;
        
        unsigned long sum = 0, max = 0;

        for ( j = 0; j < 256; j++ )
        {
            sum += pStats[i].histogram[j];
            if ( sum < pStats[i].n / 2 )
                pStats[i].median = j;
        
            if ( pStats[i].histogram[j] > max )
            {
                max = pStats[i].histogram[j];
                pStats[i].mode = j;
            }
        }
    }
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

int GWriteJPEGImage ( GImagePtr image, short quality, const char *filepath )
{
    FILE *outfile = fopen ( filepath, "wb" );
    if ( outfile == NULL )
        return FALSE;
    
    int result = GWriteJPEGImageFile ( image, quality, outfile );
    fclose ( outfile );
    return result;
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
    printf ( "TIFF scanline size: %ld\n", (long) TIFFScanlineSize ( tiff ) );
    
    return tiff;
}

/*** GReadTIFFImageStrip *******************************************************************/

int GReadTIFFImageStrip ( TIFF *tiff, int stripTop, int stripHeight, GImagePtr image, int imageTop )
{
    int             width = 0, height = 0, tilewidth = 0, tileheight = 0;
    unsigned short  bitspersample = 0, samplesperpixel = 0, planarconfig = 0, photometric = 0;

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

    // Ensure image is large enough to store the requested number of TIFF scanlines.
    
    if ( GGetImageWidth ( image ) < width || GGetImageHeight ( image ) + imageTop < stripHeight )
    {
        printf ( "imageHeight = %d, imageTop = %d, stripHeight = %d\n", GGetImageHeight ( image ), imageTop, stripHeight );
        return 0;
    }
    
    // Ensure image format is same as TIFF format.
    
    if ( GGetImageDepth ( image ) != samplesperpixel * bitspersample )
        return 0;
    
    /*** If we have a TIFF file which represents an RGB color image,
         we read a horizontal strip out of the TIFF into the specified GImage.
         NOTE: THIS CODE WILL FAIL TO READ TILED TIFF FILES. ***/
    
    int row = 0;
    if ( bitspersample <= 8 && tilewidth == 0 && tileheight == 0 && photometric == PHOTOMETRIC_RGB )
    {
        /*** For each row in the TIFF file, read image data into the image directly.
             We can get away with this because the data returned by the TIFF library
             is in exactly the same format the we expect for an indexed-color bitmap. ***/
        
        for ( row = 0; row < stripHeight; row++ )
        {
            char *imageRow = GGetImageDataRow ( image, row + imageTop );
            if ( TIFFReadScanline ( tiff, imageRow, row + stripTop, 0 ) < 1 )
                break;
        }
    }
    
    /*** Return number of rows read. ***/
    
    return ( row );
}

/*** GWriteTIFFImageFile *******************************************************************/

int GWriteTIFFImageFile ( GImagePtr image, const char *filename, FILE *file )
{
    unsigned int    width, height, depth, value, row, col;
    unsigned char    *data, *scanline, red, green, blue, alpha;
    unsigned short    *colormap = NULL, numcolors, color;
    TIFF            *tiff = NULL;
    
    /*** Create a TIFF record in memory.  (Note that we don't actually open the file
         here!)  Return an error code on failure. ***/
    
    tiff = TIFFClientOpen ( filename, "w", file,
                           TIFFClientRead, TIFFClientWrite, TIFFClientSeek, TIFFClientClose, TIFFClientSize,
                           TIFFClientMap, TIFFClientUnmap );
    
    if ( tiff == NULL )
        return ( FALSE );
    
    /*** Obtain the image dimensions and depth, and set the corresponding TIFF tags. ***/
    
    width = GGetImageWidth ( image );
    height = GGetImageHeight ( image );
    depth = GGetImageDepth ( image );
    
    TIFFSetField ( tiff, TIFFTAG_IMAGEWIDTH, width );
    TIFFSetField ( tiff, TIFFTAG_IMAGELENGTH, height );
    TIFFSetField ( tiff, TIFFTAG_PLANARCONFIG, PLANARCONFIG_CONTIG );    /* component values for each pixel are stored contiguously */
    TIFFSetField ( tiff, TIFFTAG_COMPRESSION, COMPRESSION_NONE );         /* no compression */
    
    if ( depth <= 8 )
    {
        /*** For an indexed-color image, set the appropriate TIFF tags to indicate
             that we have a 1 color sample of up to the bit depth of the image. ***/
        
        TIFFSetField ( tiff, TIFFTAG_BITSPERSAMPLE, depth );
        TIFFSetField ( tiff, TIFFTAG_SAMPLESPERPIXEL, 1 );
        
        /*** If we have a 1-bit bitmap, we don't write any color table; we just indicate
         that value zero is white and value 1 is black.  If we have an image with at
         least 4 or 8 bits per pixel, extract the color table from the bitmap and
         write it to the TIFF file. ***/
        
        if ( depth == 1 )
        {
            TIFFSetField ( tiff, TIFFTAG_PHOTOMETRIC, PHOTOMETRIC_MINISWHITE );
        }
        else
        {
            TIFFSetField ( tiff, TIFFTAG_PHOTOMETRIC, PHOTOMETRIC_PALETTE );
            
            /*** Compute the number of colors in the image's color table, and allocate
                 an array of short integers big enough to hold R-G-B color components
                 for each entry in the color table.  On failure, free the TIFF record
                 and return a NULL pointer. ***/
            
            numcolors = 1 << depth;
            colormap = (unsigned short *) malloc ( sizeof ( unsigned short ) * 3 * numcolors );
            if ( colormap == NULL )
            {
                TIFFClose ( tiff );
                return ( FALSE );
            }
            
            /*** For each entry in the image's color table, copy the red components into
                 the TIFF color map first, followed by the blue components, then the green.
                 Scale them to the range 0-65535. ***/
            
            for ( color = 0; color < numcolors; color++ )
            {
                GGetImageColorTableEntry ( image, color, &red, &green, &blue );
                
                colormap[ color                 ] = red * 257L;
                colormap[ color + numcolors     ] = green * 257L;
                colormap[ color + numcolors * 2 ] = blue * 257L;
            }
            
            TIFFSetField ( tiff, TIFFTAG_COLORMAP, &colormap[0], &colormap[ numcolors ], &colormap[ 2 * numcolors ] );
        }
        
        /*** Now, for each row of data in the image, write the pixel values in the row
             (which represent indices into the color table) to the TIFF file.  When done,
             free memory for the TIFF colormap. ***/
        
        for ( row = 0; row < height; row++ )
        {
            data = (unsigned char *) GGetImageDataRow ( image, row );
            TIFFWriteScanline ( tiff, data, row, 0 );
        }
        
        if ( colormap != NULL )
            free ( colormap );
    }
    else
    {
        /*** For direct-color images, we set the appropriate TIFF tags to indicate
             that we have eight-bit color samples per pixel, and that they should
             be interpreted as RGB or RGBA color values. ***/
        
        TIFFSetField ( tiff, TIFFTAG_BITSPERSAMPLE, 8 );
        TIFFSetField ( tiff, TIFFTAG_SAMPLESPERPIXEL, depth == 24 ? 3 : 4 );
        TIFFSetField ( tiff, TIFFTAG_PHOTOMETRIC, PHOTOMETRIC_RGB );
        
        /*** Allocate a buffer to hold a single scanline of TIFF RGB or RGBA image file data;
         close the file and return an error code on failure. ***/
        
        size_t size = sizeof ( unsigned char ) * width * ( depth == 24 ? 3 : 4 );
        scanline = (unsigned char *) malloc ( size );
        if ( scanline == NULL )
        {
            TIFFClose ( tiff );
            return ( FALSE );
        }
        
        /*** For each row in the image, store the RGBA values in each pixel into the TIFF
             scanline, then write the scanline to the TIFF file. ***/
        
        for ( row = 0; row < height; row++ )
        {
            memcpy ( scanline, GGetImageDataRow ( image, row ), size );
            TIFFWriteScanline ( tiff, scanline, row, 0 );
        }
        
        /*** Free memory for the TIFF scanline buffer. ***/
        
        free ( scanline );
    }
    
    /*** Close the TIFF file and return a successful result code. ***/
    
    TIFFClose ( tiff );
    return ( TRUE );
}

int GWriteTIFFImage ( GImagePtr image, const char *filepath )
{
    std::string filename ( filepath );
    size_t pos = filename.find_last_of ( '/' );
    if ( pos != std::string::npos )
        filename = filename.substr ( pos + 1, filename.length() - pos - 1 );
    
    FILE *outfile = fopen ( filepath, "wb" );
    if ( outfile == NULL )
        return FALSE;

    int result = GWriteTIFFImageFile ( image, filename.c_str(), outfile );
    fclose ( outfile );
    return result;
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
    
    // Use GDAL to extract the geotransform from the TIFF file.
    
    double geotransform[6] = { 0 };
    GDALAllRegister();
    GDALDataset *fin = (GDALDataset*) GDALOpen ( argv[1], GA_ReadOnly );
    if ( fin == NULL )
        printf ( "Could not open %s with GDAL!\n", argv[1] );
    else if ( fin->GetGeoTransform ( geotransform ) != CE_None )
    {
        printf ( "Could not get geotransform from %s!\n", argv[1] );
        GDALClose ( fin );
    }
    else
    {
        printf ( "GDAL Geotransform:\n%f, %e, %e\n%f, %e, %e\n",
                geotransform[0], geotransform[1], geotransform[2],
                geotransform[3], geotransform[4], geotransform[5] );
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
    
    int width = 0, height = 0, bitspersample = 0, samplesperpixel = 0;
    TIFFGetField ( tiff, TIFFTAG_IMAGEWIDTH, &width );
    TIFFGetField ( tiff, TIFFTAG_IMAGELENGTH, &height );
    TIFFGetField ( tiff, TIFFTAG_SAMPLESPERPIXEL, &samplesperpixel );
    TIFFGetField ( tiff, TIFFTAG_BITSPERSAMPLE, &bitspersample );

    int tileNonOverlapWidth = TILEWIDTH - TILEOVERLAP;
    int tileNonOverlapHeight = TILEHEIGHT - TILEOVERLAP;
    int numTilesX = ( width + tileNonOverlapWidth - 1 ) / tileNonOverlapWidth;
    int numTilesY = ( height + tileNonOverlapHeight - 1 ) / tileNonOverlapHeight;
    int totalTiles = numTilesX * numTilesY;
    printf ( "Number of tiles x=%d, y=%d, total=%d\n", numTilesX, numTilesY, totalTiles );
    
    // create summary CSV file
    
    std::string summaryPath = outdir + basename + "_tilesGeorefTable.csv";
    FILE *summaryFile = fopen ( summaryPath.c_str(), "w" );
    if ( summaryFile == NULL )
        printf ( "Can't create summary CSV file %s!\n", summaryPath.c_str() );
    else
        fprintf ( summaryFile, "tileName,pixelX,pixelY,easting,northng,min,max,mean,stdDev\n" );

    // Read horizontal strips out of the TIFF file and generate tiles from each strip.

    totalTiles = 0;
    GImagePtr prevStrip = NULL;
    for ( int strip = 0; strip < numTilesY; strip++ )
    {
        int stripTop = strip > 0 ? TILEHEIGHT + tileNonOverlapHeight * ( strip - 1 ) : 0;
        int stripBottom = strip > 0 ? stripTop + tileNonOverlapHeight : TILEHEIGHT;
        int stripHeight = stripBottom <= height ? TILEHEIGHT : height - stripTop;
        
        // Allocate image to store current strip
        
        GImagePtr stripImage = GCreateImage ( width, stripHeight, bitspersample * samplesperpixel );
        if ( stripImage == NULL )
        {
            printf ( "Failed to allocate strip %d!\n", strip );
            break;
        }
        
        // Coopy the bottom of the previous strip into the top of the current strip
        
        if ( prevStrip )
            GCopyImageData ( stripImage, 0, 0, prevStrip, 0, tileNonOverlapHeight, width, TILEOVERLAP );
        
        // Read rows from TIFF file into bottom of current strip
        
        int rowsToRead = prevStrip ? stripHeight - TILEOVERLAP : stripHeight;
        int tileTopRow = prevStrip ? TILEOVERLAP : 0;
        if ( GReadTIFFImageStrip ( tiff, stripTop, rowsToRead, stripImage, tileTopRow ) < rowsToRead )
        {
            printf ( "Failed to read TIFF image strip %d!\n", strip );
            break;
        }
        
        printf ( "Read TIFF image strip %d!\n", strip );
#if 0
        char stripname[256] = { 0 };
        sprintf ( stripname, "_%d.tif", strip );
        std::string outpath = outdir + basename + stripname;

        GImagePtr newImage = GResampleImage ( stripImage, 24 );
        if ( newImage == NULL )
        {
            printf ( "Failed to resample TIFF image strip %d!\n", strip );
            GDeleteImage ( stripImage );
            break;
        }
        GDeleteImage ( stripImage );
        stripImage = newImage;

        //GImageSwapRGBA ( stripImage );
        //if ( ! GWriteTIFFImage ( stripImage, outpath.c_str() ) )
        //    printf ( "Failed to write strip %s...\n", outpath.c_str() );

#endif

        // Extract tiles from the strip, and write each tile to a JPEG file
        
        int numTilesWritten = 0;
        int numTilesDiscarded = 0;
        
        for ( int tile = 0; tile < numTilesX; tile++ )
        {
            int tileLeft  = tile * tileNonOverlapWidth;
            int tileRight = tileLeft + TILEWIDTH;
            int tileWidth = tileRight <= width ? TILEWIDTH : width - tileLeft;
            
            // Extract tile from strip
            
            GImagePtr tileImage = GCreateSubImage ( stripImage, tileLeft, 0, tileWidth, stripHeight );
            if ( tileImage == NULL )
            {
                printf ( "Failed to create tile %d in strip %d!\n", tile, strip );
                continue;
            }
            
            // Resample tile to grayscale, and compute statistics
            
            GImagePtr grayTile = GResampleImage ( tileImage, 8 );
            if ( grayTile == NULL )
            {
                printf ( "Can't resample tile %d in strip %d to grayscale, discarding tile!\n", tile, strip );
                numTilesDiscarded++; // printf ( "Discarding all-white tile %d in strip %d.\n", tile, strip );
                GDeleteImage ( tileImage );
                continue;
            }
            
            // Compute grayscale tile color statistics. If tile contrast is zero, discard tile.
            
            GColorStats stats;
            GGetImageColorStatistics ( grayTile, 1, &stats );
            GDeleteImage ( grayTile );
            if ( stats.max == stats.min )
            {
                numTilesDiscarded++; // printf ( "Discarding all-white tile %d in strip %d.\n", tile, strip );
                GDeleteImage ( tileImage );
                continue;
            }
            
            // Save tile as JPEG file in output directory.
            
            char tilename[256] = { 0 };
            sprintf ( tilename, "_%d_%d.jpg", tile, strip );
            std::string outpath = outdir + basename + tilename;
            if ( ! GWriteJPEGImage ( tileImage, 90, outpath.c_str() ) )
            {
                printf ( "Failed to write tile %s...\n", outpath.c_str() );
                GDeleteImage ( tileImage );
                continue;
            }
            
            numTilesWritten++; // printf ( "Wrote tile %s...\n", outpath.c_str() );
            GDeleteImage ( tileImage );
            
            // If we have a summary file, write tile summary, statistics, and geo-reference to the file.
            // TODO: adding TILEOVERLAP is a hack to make our output match Leo's. Who has the bug? Fix!
            
            if ( summaryFile )
            {
                double x = tileLeft, y = stripTop - TILEOVERLAP;
                double lon = geotransform[0] + x * geotransform[1] + y * geotransform[2];
                double lat = geotransform[3] + x * geotransform[4] + y * geotransform[5];
                std::string tileName = basename + tilename;
                fprintf ( summaryFile, "%s,%d,%d,%.12f,%.12f,%d,%d,%f,%f\n",
                         tileName.c_str(), (int) x, (int) y,
                         lon, lat,
                         (int) stats.min, (int) stats.max, stats.mean, stats.stdev );
            }
        }

        totalTiles += numTilesWritten;
        printf ( "Wrote %d tiles; discarded %d tiles.\n", numTilesWritten, numTilesDiscarded );
        
        // Delete the previous strip (if we have one); current strip becomes previous
        
        if ( prevStrip != NULL )
            GDeleteImage ( prevStrip );
        prevStrip = stripImage;
    }

    printf ( "Finished! Grand total %d tiles written.\n", totalTiles );
    if ( summaryFile )
        fclose ( summaryFile );
    
    TIFFClose ( tiff );
}
