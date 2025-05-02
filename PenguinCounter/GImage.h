#ifndef GIMAGE_H
#define GIMAGE_H

#ifdef __cplusplus
extern "C" {
#endif

#include <stdio.h>

#define GUILIB_API
#define RGB_TO_LUMINANCE(r,g,b) ((0.3*(r))+(0.6*(g))+(0.1*(b)))

#ifndef TRUE
#define TRUE 1
#define FALSE 0
#endif

typedef struct GImage *GImagePtr;

/*** GCreateImage ********************************************************
 
	Creates a new image.  An image is a rectangular array of pixel data
	that can be manipulated in memory and read from/written to file.
 
	GImagePtr GCreateImage ( int width, int height, int depth )
 
	(width):  number of pixel across image horizontally.
	(height): number of pixels down image vertically.
	(depth):  number of bits per pixel in image data.
 
	If successful, this function returns a pointer to a new image record.
	On failure, the function returns NULL.
 
	To dispose of the image record returned by this function, call GDeleteImage().
 
	The image data array will be initialized to zero. To obtain pointers to image
	data rows, whose contents you can modify directly, use GGetImageDataRow().
 
	Valid values for the depth are 8, 24, and 32.  An 8-bit image is an indexed
	256-color image with a color table.  A 24-bit image stores RGB color data
	with 8 bits per pixel.  A 32-bit image stores RGBA image data with an alpha
	(transparency) channel.

	The color table will be initialized to a simple grayscale color table
	where 0 = black, 255 = white. To get the RGB color components that correspond
	to each color table entry, use GGetImageColorTableEntry(); to modify them,
	use GSetImageColorTableEntry().

	The image's selected rectangle for image processing operations will initially
	contain the entire image, i.e. (left,top,right,bottom) = (0,0,width,height).
	
******************************************************************************/

GUILIB_API GImagePtr GCreateImage ( int width, int height, int depth );

/***  GDeleteImage **********************************************************
 
 Destroys and releases memory occupied by an image record.
 
 void GDeleteImage ( GImagePtr image )
 
 (image): pointer to an image record, as returned by GCreateImage().
 
****************************************************************************/

GUILIB_API void GDeleteImage ( GImagePtr );

/****  GGetImageWidth  ****************************************************
 
 Obtains the number of pixels across an image horizontally.
 
 int GGetImageWidth ( GImagePtr image )
 
 (image): pointer to an image record, as returned by GCreateImage().
 
 This function returns the width of the image, in pixels.
 
**************************************************************************/

GUILIB_API int GGetImageWidth ( GImagePtr );

/***  GGetImageHeight  *****************************************************
 
	Obtains the number of pixels across an image vertically.
 
	int GGetImageHeight ( GImagePtr image )
 
	(image): pointer to an image record, as returned by GCreateImage().
 
	This function returns the height of the image, in pixels.
 
****************************************************************************/

GUILIB_API int GGetImageHeight ( GImagePtr );

/***  GGetImageDepth  ******************************************************
 
	Obtains the bit-depth of an image.
 
	int GGetImageDepth ( GImagePtr image )
 
	(image): pointer to an image record, as returned by GCreateImage().
 
	This function returns the number of bits per pixel in an image,
	either 1, 8, or 32.  See GCreateImage().
 
****************************************************************************/

GUILIB_API int GGetImageDepth ( GImagePtr );

/***  GSetImageColorTableEntry  ********************************************

	Sets the R-G-B components of an entry in an image color table.

	void GSetImageColorTableEntry ( GImagePtr image, unsigned char index,
	     unsigned char red, unsigned char green, unsigned char blue )

	(image): pointer to an image record, as returned by GCreateImage().
	(index): index of color table entry to modify, from 0-255.
	(red):   red color component, from 0-255.
	(green): green color compoenent, from 0-255.
	(blue):  blue color component, from 0-255.
	
	This function returns nothing.
		
****************************************************************************/

GUILIB_API void GSetImageColorTableEntry ( GImagePtr, unsigned char, unsigned char, unsigned char, unsigned char );

/***  GGetImageColorTableEntry  ********************************************

	Obtains the R-G-B color components of an entry in an image color table.

	void GGetImageColorTableEntry ( GImagePtr image, unsigned char index,
	     unsigned char *red, unsigned char *green, unsigned char *blue )

	(image): pointer to an image record, as returned by GCreateImage().
	(index): index of color table entry to obtain, from 0-255.
	(red):   receives red color component, from 0-255.
	(green): receives green color compoenent, from 0-255.
	(blue):  receives blue color component, from 0-255.
	
	This function returns nothing.
		
****************************************************************************/

GUILIB_API void GGetImageColorTableEntry ( GImagePtr, unsigned char, unsigned char *, unsigned char *, unsigned char * );

/***  GGetImageDataRow  *****************************************************
 
	Returns a pointer to the start of a row of an image's pixel data.
 
	char *GGetImageDataRow ( GImagePtr image, int row )
 
	(image): pointer to an image record, as returned by GCreateImage().
	(row):   row number.
 
	The function returns a pointer to the start of the image data row.
 
	The row number (row) must range from zero (for the top row of the image)
	to the total number of rows in the image minus one (for the bottom row);
	see GGetImageHeight() to determine the number of rows in the image.
 
*****************************************************************************/

GUILIB_API char *GGetImageDataRow ( GImagePtr, int );

/***  GGetImageDataRowSize  **************************************************
 
	Returns the number of bytes per row in the image's pixel data.
 
	size_t GGetImageDataRowSize ( GImagePtr image )
 
	(image): pointer to an image record, as returned by GCreateImage().
 
	The function returns the number of bytes per row in the image data.
	On Windows, this value will be negative because image data rows are
	stored "upside down", with the topmost row at the end of the buffer.
 
*****************************************************************************/

GUILIB_API size_t GGetImageDataRowSize ( GImagePtr );

/*** GGetImagePixelColor ***************************************************

	Returns the RGBA color components of a pixel in an image.
	
	void GGetImagePixelColor ( GImagePtr image, int col, int row,
	     unsigned char *red, unsigned char *green, unsigned char *blue,
		 unsigned char *alpha )
	
	(image): pointer to an image record, as returned by GCreateImage().
	(col,row): horizontal, vertical location of a particular pixel.
	(red):   recieves red component of the pixel color.
	(green): recieves green component of the pixel color.
	(blue):  recieves blue component of the pixel color.
	(alpha): recieves alpha (transparency) component of pixel color.
	
	The function returns nothing.  The RGBA color components of the pixel
	value are returned in (red), (green), (blue), and (alpha) respectively.
	
	For an 8-bit indexed-color image, this function simply looks up the RGB
	color components corresponding to this pixel in the image's color table.
	The alpha values for indexed-color images are always zero.
	
	For a 24- or 32-bit color image, a pixel value represents an actual color.
	This function parses the R, G, B, and A color components from this value.
	Alpha values run from 0 (completely opaque) to 255 (completely transparent).
	
	NOTE: This is a relatively slow function.  If you're processing many
	different pixels in an image, it's faster to get a pointer to individual
	image rows (see GGetImageDataRow(), then operate on each row pointer.
	
*****************************************************************************/

GUILIB_API void GGetImagePixelColor ( GImagePtr image, int col, int row,
unsigned char *red, unsigned char *green, unsigned char *blue, unsigned char *alpha );

/*** GSetImagePixelColor ***************************************************

	Modifies the RGBA color components of a pixel in an image.
	
	void GSetImagePixelColor ( GImagePtr image, int col, int row,
	     unsigned char red, unsigned char green, unsigned char blue,
		 unsigned char alpha )
	
	(image): pointer to an image record, as returned by GCreateImage().
	(col,row): horizontal, vertical location of a particular pixel.
	(red):   desired red component of the pixel color, 0 - 255.
	(green): desired green component of the pixel color, 0 - 255.
	(blue):  desired blue component of the pixel color, 0 - 255.
	(alpha): desired alpha (transparency) component of pixel color.
	
	The function returns nothing.
	
	For an 8-bit indexed-color image, this function computes the equivalent
	grayscale value corresponding to (red,green,blue) and stores that in the
	pixel value.  The alpha value for indexed-color images is ignored.
	
	For a 24- or 32-bit color image, this function stores the R, G, B, and A
	color components in the pixel.  For 24-bit images, alpha is ignored.
	Alpha values run from 0 (completely opaque) to 255 (completely transparent).
	
	NOTE: This is a relatively slow function.  If you're processing many
	different pixels in an image, it's faster to get a pointer to individual
	image rows (see GGetImageDataRow(), then operate on each row pointer.
	
*****************************************************************************/

GUILIB_API void GSetImagePixelColor ( GImagePtr image, int row, int col,
unsigned char red, unsigned char green, unsigned char blue, unsigned char alpha );

/*** GReadImage ************************************************************

	Attempts to read an image in any supported format.

	GUILIB_API GImagePtr GReadImage ( const char *filename );

	(filename): path to image file to read.
	
	If successful the function returns a pointer to a GImage structure
	containing the input image data from the file.  On failure, the function
	returns NULL.  (Reasons: invalid file path or unsupported format.)
	
****************************************************************************/

GUILIB_API GImagePtr GReadImage ( const char *filename );

/*** GReadImageFile ********************************************************

	Attempts to read an image file in any supported format.

	GUILIB_API GImagePtr GReadImageFile ( FILE *file );

	(file): pointer to image file, opened for reading in binary mode.
	
	If successful the function returns a pointer to a GImage structure
	containing the input image data from the file.  On failure, the function
	returns NULL.  (Invalid file path, or unsupported format.)
	
****************************************************************************/

GUILIB_API GImagePtr GReadImageFile ( FILE *file );

/*** GWriteImage ************************************************************
	 
	Attempts to write an image in the format corresponding to its filename
	extension (.jpg, .png, etc.)
	 
	GUILIB_API GImagePtr GWriteImage ( GImagePtr image, const char *filename );
	 
	(filename): path to image file to write.
	 
	If successful the function returns TRUE.  On failure, the function
	returns FALSE.  (Reasons: invalid file path or unsupported format.)
 
	For individual image file formats, parameters set to default values:
	JPEG quality = 90; PNG interlacing = FALSE.
 
	More control over individual file format parameters is possible with
	format-specific image-writing functions (GWriteJPEGImageFile(), etc.)

****************************************************************************/
	
GUILIB_API int GWriteImage ( GImagePtr image, const char *filename );

/*** GReadJPEGImageFile *****************************************************
 
	Creates a new image and reads image data from a JPEG file into it.
 
	GImagePtr GReadJPEGImageFile ( FILE *file )
 
	(file): pointer to the file from which the JPEG image should be read.
 
	The function returns a pointer to the image that was read from the file,
	if successful, or NULL on failure.
 
	The file must be opened for reading in binary mode.  See GOpenFile().
 
	If successful, the function returns a pointer to an initialized image
	structure containing the data read from the JPEG file.  If the JPEG file
	contains grayscale data (i.e. one color channel per pixel), the image
	returned by this function will be an 8-bit indexed-color bitmap with a
	simple grayscale color table (i.e. color index 0 corresponds to black;
	color index 255 corresponds to white).  If the JPEG file contains color
	data (i.e. 3 color components per pixel), the image returned by this
	function will have 24-bit pixels containing RGB color data.
 
*****************************************************************************/

GUILIB_API GImagePtr GReadJPEGImageFile ( FILE *fp );

/*** GWriteJPEGImageFile *****************************************************
 
	Writes data from an image in memory to a JPEG image file.
 
	int GWriteJPEGImageFile ( GImagePtr image, short quality, FILE *file )
 
	(image):   pointer to image which should be written to the file.
	(quality): quality factor, indicating degree of image compression.
	(file):    pointer to the file to which the JPEG image should be written.
 
	The function returns TRUE if successful, or FALSE on failure.
 
	The file must be opened for writing in binary mode.  See GOpenFile().
 
	The quality factor may vary from 0 (maximum compression) to 100
	(no compression).
	
	The input image may have a depth of 8, 24, or 32 bits per pixel.
	
	If 8-bit, the output file will be a simple grayscale JPEG; its color
	table will be ignored, since the JPEG format does not support them.
	
	If 24- or 32-bit, the output file will be an RGB JPEG.  If 32-bit,
	the image's alpha values will be ignored, since JPEG does not support
	transparency.

*****************************************************************************/

GUILIB_API int GWriteJPEGImageFile ( GImagePtr image, short quality, FILE *file );

/*** GReadPNGImageFile *****************************************************
 
	Creates a new image and reads image data from a PNG file into it.
 
	GImagePtr GReadPNGImageFile ( FILE *file )
 
	(file): pointer to the file from which the PNG image should be read.
 
	The function returns a pointer to the image that was read from the file,
	if successful, or NULL on failure.
 
	The file must be opened for reading in binary mode.  See GOpenFile().
 
	If successful, the function returns a pointer to an initialized image
	structure containing the data read from the PNG file.  If the file
	contains grayscale data (i.e. one color channel per pixel), the image
	returned by this function will be an 8-bit grayscale bitmap with a
	simple grayscale color table (i.e. color index 0 corresponds to black;
	color index 255 corresponds to white).  If the PNG file contains color
	data (i.e. 3 color components per pixel), the image returned by this
	function will be a 24-bit color image containing RGB color data.
	If the PNG file contains color + transparency, the returned image will
	be a 32-bit color image with RGBA pixel data.
 
*****************************************************************************/

GUILIB_API GImagePtr GReadPNGImageFile ( FILE *file );

/*** GWritePNGImageFile *****************************************************
 
	Writes data from an image in memory to a PNG image file.
 
	int GWritePNGImageFile ( GImagePtr image, bool interlaced, FILE *file )
 
	(image):      pointer to image which should be written to the file.
	(interlaced): true or false flag indicating whether rows should be interlaced.
	(file):       pointer to the file to which the JPEG image should be written.
 
	The function returns TRUE if successful, or FALSE on failure.
 
	The file must be opened for writing in binary mode.
	
	This function can write 8-, 24, and 32-bit images.  For 8-bit images,
	the color table is written to the PNG palette.  For 24- and 32-bit images,
	RGB color pixel values are written, including alpha values for 32-bit images.
 
*****************************************************************************/

GUILIB_API int GWritePNGImageFile ( GImagePtr image, bool interlaced, FILE *file );

/*** GReadTIFFImageFile *****************************************************
	 
	Creates a new image and reads image data from a TIFF file into it.
	 
	GImagePtr GReadTIFFImageFile ( FILE *file )
	 
	(file): pointer to the file from which the TIFF image should be read.
	 
	The function returns a pointer to the image that was read from the file,
	if successful, or NULL on failure.
	 
	The file must be opened for reading in binary mode.  See GOpenFile().
	
	The returned image may be 8-bit (indexed color with color table),
	or 32-bit (RGBA color, with transparency) depending on the contents
	of the TIFF file.  Although the TIFF format also supports 24-bit (RGB)
	images, such files will be returned by this function as 32-bit RGBA
	images, with the alpha channel set to 0% transparency (i.e. 100% opaque).

*****************************************************************************/
	
GUILIB_API GImagePtr GReadTIFFImageFile ( FILE *file );

/*** GWriteTIFFImageFile *****************************************************
	 
	Writes data from an image in memory to a TIFF image file.
	 
	int GWriteTIFFImageFile ( GImagePtr image, char *name, FILE *file )
	 
	(image): pointer to image which should be written to the file.
	(name):  pointer to ASCII NUL-terminated file name string.
	(file):  pointer to the file to which the TIFF image should be written.
	 
	The function returns TRUE if successful, or FALSE on failure.
	 
	The file must be opened for writing in binary mode.  See GOpenFile().
	The file name argument (name) is simply a tag stored in the TIFF file.
	The actual name of the file on the local filesystem will be determined
	by whatever was passed to the function which created and opened the
	file pointer (file).

	This function can write 8-, 24-, and 32-bit images.  For 8-bit images,
	the color table is written to the PNG palette.  For 24- and 32-bit images,
	RGB color pixel values are written, including alpha values for 32-bit images.
		
*****************************************************************************/
	
GUILIB_API int GWriteTIFFImageFile ( GImagePtr image, const char *name, FILE *file );

/*** GReadGIFImageFile *****************************************************
	 
	Creates a new image and reads imaeg data from a GIF file into it.
	 
	GImagePtr GReadGIFImageFile ( FILE *file )
	 
	(file): pointer to the file from which the GIF image should be read.
	 
	The function returns a pointer to the image that was read from the file,
	if successful, or NULL on failure.
	 
	The file must be opened for reading in binary mode.  See GOpenFile().
	 
	The image returned by this function will always be an 8-bit, indexed-
	color image, regardless of the bit depth of the GIF file.  (The GIF
	library returns data in an 8-bits-per-pixel buffer, which makes it
	difficult to create an image with any other bit depth.)  However,
	pixel values and color table values stored in the image will be
	exactly the same as stored in the GIF file.
	 
	In a multi-image GIF file (e.g. an animated GIF), only the first image
	in the file will be returned.  This function ignores all GIF extensions,
	including transparency codes, etc.
 
*****************************************************************************/
	
GUILIB_API GImagePtr GReadGIFImageFile ( FILE *file );
	
/*** GWriteGIFImageFile *****************************************************
	 
	Writes data from an image in memory to a GIF image file.
	 
	int GWriteGIFImageFile ( GImagePtr image, FILE *file )
	 
	(image): pointer to image which should be written to the file.
	(file):  pointer to the file to which the GIF image should be written.
	 
	The function returns TRUE if successful, or FALSE on failure.
	 
	The file must be opened for writing in binary mode.
	 
	This function can only write GIF files from images of any bit depth.
	However, 24- or 32-bit RGB images will be written as 8-bit grayscale
	GIF files, because the GIF format does not support > 8 bits per channel.
	If the image is an 8-bit indexed-color image, the image color table
	will be written to the output GIF file.
	 
	GIF files written by this function will contain only a single GIF image,
	and no extensions, in GIF87a format (e.g. the simplest possible GIF format).
	 
*********************************************************************************/
	
GUILIB_API int GWriteGIFImageFile ( GImagePtr image, FILE *file );

/*** GReadBMPImageFile *******************************************************

	Reads a Windows BMP file to an image.
	
	GImagePtr GReadBMPImageFile ( FILE *file )
	
	(file):  pointer to file, opened for reading in binary mode.
	
	The function returns a pointer to the image, if successful, or NULL on
	failure.
	
	This function can read 8-bit indexed-color BMP files, as well as 24-
	and 32-bit RGB/RGBA color BMPs.  It cannot read compressed BMP files,
	nor BMP files with multiple color planes.

*****************************************************************************/

GUILIB_API GImagePtr GReadBMPImageFile ( FILE *pFile );

/*** GWriteBMPImageFile *******************************************************

	Writes an image to a Winows BMP file.
	
	int GWriteImageFile ( GImagePtr image, FILE *file )
	
	(image): pointer to image.
	(file):  pointer to file, opened for writing in binary mode.
	
	The function returns TRUE, if successful, or FALSE on failure.
	
	The function writes both indexed-color (<= 8-bit) and 24- and 32-bit
	bitmaps (RGB, RGBA).  Bitmap data is not compressed.
	
*****************************************************************************/

GUILIB_API int GWriteBMPImageFile ( GImagePtr pImage, FILE *pFile );

/*** GFlipImage ***************************************************************

	Flips the ordering of an image's rows or columns.
 
	GUILIB_API void GFlipImageHorizontal ( GImagePtr image );
	GUILIB_API void GFlipImageVertical ( GImagePtr image );

	These functions return nothing.  The flip the image data in place.

	GFlipImageHorizontal() reverses the order of pixels within each row.
	GFlipImageVertical() reverses the order of rows within the image.
 
*******************************************************************************/
	
GUILIB_API void GFlipImageHorizontal ( GImagePtr image );
GUILIB_API void GFlipImageVertical ( GImagePtr image );

/*** GCloneImage *******************************************************************

	Creates a new image which is an exact copy of an existing image.
	
	GImagePtr GCloneImage ( GImagePtr image )
	
	(image): pointer to an existing image.
	
	If successful, the function returns a pointer to the clone.
	On failure, the function returns NULL.
	
************************************************************************************/

GUILIB_API GImagePtr GCloneImage ( GImagePtr image );

/*** GResizeImage ******************************************************************
	 
	Creates a new image that is a resized copy of an existing image.
	 
	GUILIB_API GImagePtr GResizeImage ( GImagePtr image, int width, int height );

	(width): desired new image width, in pixels.
 	)height): desired new image height, in pixels.
 
	If successful, the function returns a pointer to the new image; on failure,
	it returns NULL.  The new image has the same depth (bits-per-pixel) and pixel
	format as the old image.
 
	This function uses the simplest possible "nearest-pixel" method for choosing
	data values in the new image.  It does not do any (bicubic, etc.) interpolation.
	Expect the returned image to look very "pixellated" if you resize it dramatically.
 
***********************************************************************************/
	
GUILIB_API GImagePtr GResizeImage ( GImagePtr image, int width, int height );

/*** GResampleImage ***************************************************************
	 
	Creates a new image that is a resamped copy of an existing image.
	 
	GUILIB_API GImagePtr GResampleImage ( GImagePtr image, int depth );
	 
	(depth): desired new image depth, in bits per pixel; either 8 or 32.
 
	If successful, the function returns a pointer to the new image; on failure,
	it returns NULL.  The new image has the same dimensions (width x height) but
	has the new pixel bits-per-pixel depth value specified.
	 
	If changing 32-bit (RGBA color) to 8-bit (grayscale), luminance values
	for each pixel will be computed and any alpha channel (transparency) will
	be ignored.
 
	If changing grayscale (8-bit) to RGBA color (32-bit), all RGB channels will
 	be set to the grayscale value of each pixel, and the alpha channel will be
	set to 100% opacity (0% transparency).
 
************************************************************************************/
	
GUILIB_API GImagePtr GResampleImage ( GImagePtr image, int depth );

/*** GGetImageSelection ************************************************************

	Returns an image's current selection rectangle boundaries.  This is the area
	in which image processing operations take place.
	
	void GGetImageSelection ( GImage *pImage, int *pLeft, int *pTop, int *pRight, int *pBottom )

	(pImage): pointer to image.
	(pLeft): recieves rectangle left boundary.
	(pTop): recieves rectangle top boundary.
	(pRight): recieves rectangle right boundary.
	(pBottom): recieves rectangle bottom boundary.

	The function returns nothing.  If the entire image area is selected,
	(left,top) is (0,0) and (right,bottom) is (width,height).
	
************************************************************************************/

GUILIB_API void GGetImageSelection ( GImage *pImage, int *pLeft, int *pTop, int *pRight, int *pBottom );

/*** GSetImageSelection ************************************************************

	Sets an image's selection rectangle.  This is the area in which image processing
	operations take place.
	
	void GSetImageSelection ( GImage *pImage, int left, int top, int right, int bottom )

	(pImage): pointer to image.
	(left): recieves rectangle left boundary.
	(top): recieves rectangle top boundary.
	(right): recieves rectangle right boundary.
	(bottom): recieves rectangle bottom boundary.

	The function returns nothing.  If the entire image area is selected,
	(left,top) is (0,0) and (right,bottom) is (width,height).  An image is
	entirely selected when it is first created or resized.
	
	For image processing functions like GCombineImageWithColor() or GProcessImage(),
	the selection rectangle defines the area affected.  Pixels outside the rectangle
	will not be affected by any image processing operation. A pixel at (row,col) is
	inside the rectangle if top <= row < bottom and left <= col < right.  If top and
	bottom are equal, or left and right are equal, the rectangle is zero pixels tall
	(or wide) and no pixels will be affected by any image processing operation.
	
************************************************************************************/

GUILIB_API void GSetImageSelection ( GImage *pImage, int left, int top, int right, int bottom );

/*** GColorFunc *********************************************************************

	GColorFunc is a pointer to a user-supplied callback function which combines one
	RGBA color with another, or transforms an RGBA color.

	typedef void (*GColorFunc) ( float pDstRGBA[4], float pSrcRGBA[4] );

	(pDstRGBA): pointer to array containing detination RBBA color components.
	(pSrcRGBA): pointer to array containing source RGBA color components.
	
	The function returns nothing.
	
	Note that RGBA values are floating point, in the range 0.0 to 255.0.
	When stored in a GImage, results are converted to unsigned char;
	truncated to the nearest integer and clipped to the range 0 - 255. 
 
	For GCombineImageWithColor() and GCombineImageWithImage(), this function is
	called for every pixel in the image(s) selected rectangle.  Several built-in
	functions are available for common color operations:
	
	GCopyColor(): overwrites destination RGBA with source RGBA.
	GBlendColor(): blends destination RGBA with source RGBA using source alpha.
	GInvertColor(): inverts destination RGBA; ignores source RGBA.
	GAddColor(): adds source RGBA to destination RGBA.
	GSubtractColor(): subtracts source RGBA from destination RGBA.
	GMultiplyColor(): multiples destination RGBA by source RGBA.
	GDivideColor(): divides destination RGBA by source RGBA.
	GPowerColor(): raises destination RGBA to power of source RGBA.
	GRootColor(): takes source RGBA root of destination RGBA.
	
	More specifically, for each RGBA color component in dst and src, the
	mathematical operations performed by each function are as follows:
	
	GCopyColor: dst = src
	GBlendColor: dst = dst * ( 1 - alpha / 255 ) + src * ( alpha / 255 )
	GInvertColor: dst = 255 - dst
	GAddColor: dst = dst + src; brightens color
	GSubtractColor: dst = dst - src; darkens color
	GMultiplyColor: dst = dst * src / 255; reduces contrast
	GDivideColor: dst = 255 * dst / src; increases contrast
	GPowerColor: dst = 255 * ( dst / 255 ) ^ ( 1 + src / 255 ); darkens bright areas.
	GRootColor: dst = 255 * ( dst / 255 ) ^ ( 1/ ( 1 + src / 255 ) ); brightens dark areas.

	These functions can be used for basic image processing operations like
	changing brightness, contrast, white balance, and bright/dark areas.
	
*************************************************************************************/

typedef void (*GColorFunc) ( float pDstRGBA[4], float pSrcRGBA[4] );

void GCopyColor ( float dstRGBA[4], float srcRGBA[4] );
void GBlendColor ( float dstRGBA[4], float srcRGBA[4] );
void GInvertColor ( float dstRGBA[4], float srcRGBA[4] );
void GAddColor ( float dstRGBA[4], float srcRGBA[4] );
void GSubtractColor ( float dstRGBA[4], float srcRGBA[4] );
void GMultiplyColor ( float dstRGBA[4], float srcRGBA[4] );
void GDivideColor ( float dstRGBA[4], float srcRGBA[4] );
void GPowerColor ( float dstRGBA[4], float srcRGBA[4] );
void GRootColor ( float dstRGBA[4], float srcRGBA[4] );

/*** GCombineImageWithColor **********************************************************

	Combines each pixel in an image's selected rectangle with a constant color.

	void GCombineImageWithColor ( GImagePtr pImage, float colorRGBA[4], GColorFunc pFunc )

	(pImage): pointer to image whose pixels you wish to combine with the color.
	(colorRGBA): pointer to array containing RGBA color values to combine with pixels.
	(pFunc): pointer to function to perform the color combination operation.
	
	The function returns nothing.  See GColorFunc() for a description of the
	available color combination operations, and a template for wriing your own.

	This function can be used for basic image processing operations like
	changing brightness, contrast, white balance, and bright/dark areas.
	
	For example, this function call brightens each pixel in pImage's selected
	rectanngle by 10 (red), 20 (green), and 30 (blue):
	
		float rgba[4] = { 10, 20, 30, 0 };
		GCombineImageWithColor ( pImage, rgba, GAddColor );
	
	This call darkens each pixel's RGB color component by 32
	and sets alpha to zero:

		float rgba[4] = { 32, 32, 32, 255 };
		GCombineImageWithColor ( pImage, rgba, GSubtractColor );
	
	This function call reduces contrast for pixel RGB color components by 50%,
	while leaving alpha values unchanged:
	
		float rgba[4] = { 127, 127, 127, 255 };
		GCombineImageWithColor ( pImage, rgba, GMultiplyColor );

	This call changes white balance so that RGB (230,240,250) becomes white:

		float rgba[4] = { 230, 240, 250, 255 };
		GCombineImageWithColor ( pImage, rgba, GDivideColor );
	
	This call paints the image's selected rectangle to 50% transparent yellow:
	
		float rgba[4] = { 127, 127, 0, 127 };
		GCombineImageWithColor ( pImage, rgba, GCopyColor );
	
*************************************************************************************/
	
GUILIB_API void GCombineImageWithColor ( GImagePtr pImage, float colorRGBA[4], GColorFunc pFunc );
GUILIB_API void GProcessImage ( GImagePtr pImage, GColorFunc pFunc, float *pParams );

/*** GCombineImageWithImage **********************************************************

	Combines each pixel in an image's selected rectangle with the corresponding pixel
	in another image's selected rectangle.

	void GCombineImageWithImage ( GImagePtr pDstImage, GImagePtr pSrcImage, GColorFunc pFunc )

	(pDstImage): pointer to image whose pixels to combine with those in another image.
	(pSrcImage): pointer to other image; will not be affected by combination.
	(pFunc): pointer to function to perform pixel color combination operation.
	
	The function returns nothing.  See GColorFunc() for a description of the
	available color combination operations, and a template for wriing your own.
	
	If the images are different sizes, only their overlapping rows and columns
	will be combined.  If pDstImage's selected rectangle has a different (left,top)
	corner than pSrcImage's selected rectangle, then pixels in pDstImage will be
	offset from pixels in pSrcImage by the difference between their (left,top) values.
	
	For example, suppose pDstImage has a selection rectangle of (10,10,20,20) and
	pSrcImage has a selection rectangle of (0,0,800,600).  Then calling:
	
	GCombineImageWithImage ( pDstImage, pSrcImage, GCopyColor )
	
	will overwrite a 10x10 pixel square in pDstImage (from 10,10 to 20,20)
	with a 10x10 pixel square in the top left corner of pSrcImage (from 0,0 to 10,10).
	
	This is a powerful function which has many uses:
	
	- to copy an area from one image to another;
	- to stamp "sprites" from one image onto another;
	- to remove thermal noise by subtracting a dark frame from an image;
	- to remove vignetting by dividing an image by a flat-field calibration frame.
	
*************************************************************************************/

void GCombineImageWithImage ( GImagePtr pDstImage, GImagePtr pSrcImage, GColorFunc pFunc );

typedef struct GColorStats
{
	unsigned long	n;				// total number of values
	unsigned long	sum;			// sum of color values
	unsigned char	min;			// minimum color value
	unsigned char	max;			// maximum color value
	unsigned char	median;			// median color value
	unsigned char	mode;			// mode (most common) color value
	float			mean;			// average color value
	float			stdev;			// standard deviation of color values
	unsigned long	histogram[256];	// histogram of color values
}
GColorStats;

/*** GGetImageColorStatistics ********************************************************

	Obtains color statistics on pixels inside an image's selected rectangle.
	
	void GGetImageColorStatistics ( GImagePtr pImage, int nColors, GColorStats pStats[4] )

	(pImage): pointer to image on which to obtain color statistics.
	(nColors): number of RGBA color components to obtain statistics on, up to 4.
	(pStats): pointer to array of nColors GColorStats structs.
	
	The function returns nothing.  On return, the array of pColorStats structs
	will be filled with statistics on the corresponding RGBA color component(s)
	of the pixels within the image's selected rectangle.  For example, if nStats = 3,
	then pStats[0], pStats[1], and pStats[2] will be filled with statistics on the
	red, green, and blue components (respectively); alpha will be ignored, and pStats
	must point to an array of at least 3 GColorStat structs.
	
**************************************************************************************/

GUILIB_API void GGetImageColorStatistics ( GImagePtr pImage, int nColors, GColorStats pStats[4] );

/*** GConvertRGBToHSL ***************************************************

	Converts red, green, blue to hue, saturation, lightness.
	
	void GConvertRGBToHSL ( float rgb[3], float hsl[3] )
	
	(rgb): input red, green, blue color components
	(hsl): receieves output hue, saturation, lightness.
	
	Input values of red, green, blue must all be in the range 0.0 to 255.0.
	Output hue is 0.0 to 360.0 with 0.0 = red, 60.0 = yellow, 120.0 = green,
	180.0 = cyan, 240.0 = blue, 300.0 = magenta.
	Output saturation is 0.0 to 255.0 (pure white to pure color)
	Output lightness value is 0.0 to 255.0 (black - white)

************************************************************************/

GUILIB_API void GConvertRGBToHSL ( float rgb[3], float hsl[3] );

/*** GConvertHSLToRGB **************************************************

	Converts hue, saturation, lightness to red, green, blue.
	
	void GConvertHSLToRGB ( float hsl[3], float rgb[3] );

	(hsl): input hue, saturation, lightness
	(rgb): recieves output red, green, blue
	
	Input hue is 0.0 to 360.0 with 0.0 = red, 60.0 = yellow, 120.0 = green,
	180.0 = cyan, 240.0 = blue, 300.0 = magenta.
	Input saturation is 0.0 to 255.0 (pure white to pure color).
	Input lightness value is 0.0 - 255.0 (black - white).
	Output values of red, green, blue will all be in the range 0.0 - 255.0

************************************************************************/

GUILIB_API void GConvertHSLToRGB ( float hsl[3], float rgb[3] );

/*** EVERYTHING BELOW THIS LINE IS EXPERIMENTAL AND/OR IN DEVELOPMENT ******/

GUILIB_API void GAdjustHueSaturationLightness ( float rgba[3], float hsl[3] );
GUILIB_API void GAdjustBrightessContrast ( float rgba[3], float bc[2] );
GUILIB_API void	GAdjustImageHueSaturationLightness ( GImagePtr pImage, float hue, float saturation, float lightness );
GUILIB_API void	GAdjustImageBrightnessContrast ( GImagePtr pImage, float brightness, float contrast );
GUILIB_API void GFilterImage ( GImagePtr pImage, float *pFilter, int filterWidth, int filterHeight );
GUILIB_API GImagePtr GScaleImage ( GImagePtr oldImage, int newWidth, int newHeight );
GUILIB_API GImagePtr GDownscaleImage ( GImagePtr oldImage, int newWidth, int newHeight );

#include <tiffio.h>

GImagePtr GCreateSubImage ( GImagePtr image, int subLeft, int subTop, int subWidth, int subHeight );
TIFF *GOpenTIFFImage ( const char *filename );
GUILIB_API int GReadTIFFImageStrip ( TIFF *tiff, int stripTop, int stripHeight, GImagePtr image, int imageTop );
void GGetAverageColor ( GImagePtr image, int left, int top, int width, int height, float rgba[4] );

#ifdef __cplusplus
}
#endif

#endif
