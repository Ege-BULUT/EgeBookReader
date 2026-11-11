cmake_minimum_required(VERSION 3.22)
project(ebr_native C CXX)

# libarchive (BSD-2-Clause) reads CBR and CB7 files. Only the parts needed for RAR and 7z are switched on.
include(FetchContent)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

# liblzma from xz (0BSD) decodes LZMA and LZMA2, the usual 7z methods. Built static and handed to libarchive's
# FindLibLZMA through its cache variables, because the library does not exist yet when libarchive is configured.
FetchContent_Declare(xz
  URL https://github.com/tukaani-project/xz/releases/download/v5.8.1/xz-5.8.1.tar.gz
  URL_HASH SHA256=507825b599356c10dca1cd720c9d0d0c9d5400b9de300af00e4d1ea150795543)
FetchContent_GetProperties(xz)
if(NOT xz_POPULATED)
  FetchContent_Populate(xz)
  set(XZ_NLS OFF CACHE BOOL "" FORCE)
  set(XZ_DOC OFF CACHE BOOL "" FORCE)
  set(BUILD_SHARED_LIBS OFF)
  add_subdirectory(${xz_SOURCE_DIR} ${xz_BINARY_DIR} EXCLUDE_FROM_ALL)
  unset(BUILD_SHARED_LIBS)
endif()
set(LIBLZMA_INCLUDE_DIR ${xz_SOURCE_DIR}/src/liblzma/api CACHE PATH "" FORCE)
set(LIBLZMA_LIBRARY liblzma CACHE STRING "" FORCE)
foreach(check AUTO_DECODER EASY_ENCODER LZMA_PRESET)
  set(LIBLZMA_HAS_${check} 1 CACHE INTERNAL "")
endforeach()

set(ENABLE_TEST OFF CACHE BOOL "" FORCE)
set(ENABLE_COVERAGE OFF CACHE BOOL "" FORCE)
set(ENABLE_TAR OFF CACHE BOOL "" FORCE)
set(ENABLE_CPIO OFF CACHE BOOL "" FORCE)
set(ENABLE_CAT OFF CACHE BOOL "" FORCE)
set(ENABLE_UNZIP OFF CACHE BOOL "" FORCE)
set(ENABLE_INSTALL OFF CACHE BOOL "" FORCE)
foreach(option OPENSSL MBEDTLS NETTLE LIBB2 LZ4 LZO ZSTD BZip2 LIBXML2 EXPAT PCREPOSIX PCRE2POSIX CNG ACL XATTR ICONV LibGCC)
  set(ENABLE_${option} OFF CACHE BOOL "" FORCE)
endforeach()
set(ENABLE_LZMA ON CACHE BOOL "" FORCE)
set(ENABLE_ZLIB ON CACHE BOOL "" FORCE)
FetchContent_Declare(libarchive
  URL https://github.com/libarchive/libarchive/releases/download/v3.8.11/libarchive-3.8.11.tar.gz
  URL_HASH SHA256=900fe9fc7237c2b04f090f3c3648de8fe597525771f5035016537ce2d667d12b)
FetchContent_MakeAvailable(libarchive)
set_target_properties(archive PROPERTIES OUTPUT_NAME ebr_archive)

# DjVuLibre (GPL-2.0-or-later, usable under the app's AGPL-3.0) opens DjVu books. Only libdjvu is built, with a
# hand-written config.h, plus ebr_djvu.cpp, a small C face for Dart FFI.
FetchContent_Declare(djvulibre
  URL https://downloads.sourceforge.net/project/djvu/DjVuLibre/3.5.28/djvulibre-3.5.28.tar.gz
  URL_HASH SHA256=fcd009ea7654fde5a83600eb80757bd3a76998e47d13c66b54c8db849f8f2edc)
FetchContent_GetProperties(djvulibre)
if(NOT djvulibre_POPULATED)
  FetchContent_Populate(djvulibre)
endif()
set(DJVU ${djvulibre_SOURCE_DIR}/libdjvu)
add_library(ebr_djvu SHARED djvu/ebr_djvu.cpp
  ${DJVU}/Arrays.cpp ${DJVU}/BSByteStream.cpp ${DJVU}/BSEncodeByteStream.cpp ${DJVU}/ByteStream.cpp ${DJVU}/DataPool.cpp
  ${DJVU}/DjVmDir.cpp ${DJVU}/DjVmDir0.cpp ${DJVU}/DjVmDoc.cpp ${DJVU}/DjVmNav.cpp ${DJVU}/DjVuAnno.cpp
  ${DJVU}/DjVuDocEditor.cpp ${DJVU}/DjVuDocument.cpp ${DJVU}/DjVuDumpHelper.cpp ${DJVU}/DjVuErrorList.cpp ${DJVU}/DjVuFile.cpp
  ${DJVU}/DjVuFileCache.cpp ${DJVU}/DjVuGlobal.cpp ${DJVU}/DjVuGlobalMemory.cpp ${DJVU}/DjVuImage.cpp ${DJVU}/DjVuInfo.cpp
  ${DJVU}/DjVuMessage.cpp ${DJVU}/DjVuMessageLite.cpp ${DJVU}/DjVuNavDir.cpp ${DJVU}/DjVuPalette.cpp ${DJVU}/DjVuPort.cpp
  ${DJVU}/DjVuText.cpp ${DJVU}/DjVuToPS.cpp ${DJVU}/GBitmap.cpp ${DJVU}/GContainer.cpp ${DJVU}/GException.cpp
  ${DJVU}/GIFFManager.cpp ${DJVU}/GMapAreas.cpp ${DJVU}/GOS.cpp ${DJVU}/GPixmap.cpp ${DJVU}/GRect.cpp ${DJVU}/GScaler.cpp
  ${DJVU}/GSmartPointer.cpp ${DJVU}/GString.cpp ${DJVU}/GThreads.cpp ${DJVU}/GURL.cpp ${DJVU}/GUnicode.cpp
  ${DJVU}/IFFByteStream.cpp ${DJVU}/IW44EncodeCodec.cpp ${DJVU}/IW44Image.cpp ${DJVU}/JB2EncodeCodec.cpp ${DJVU}/JB2Image.cpp
  ${DJVU}/JPEGDecoder.cpp ${DJVU}/MMRDecoder.cpp ${DJVU}/MMX.cpp ${DJVU}/UnicodeByteStream.cpp ${DJVU}/XMLParser.cpp
  ${DJVU}/XMLTags.cpp ${DJVU}/ZPCodec.cpp ${DJVU}/atomic.cpp ${DJVU}/ddjvuapi.cpp ${DJVU}/debug.cpp ${DJVU}/miniexp.cpp)
target_include_directories(ebr_djvu PRIVATE djvu ${DJVU})
target_compile_definitions(ebr_djvu PRIVATE HAVE_CONFIG_H=1 DDJVUAPI= MINILISPAPI= DIR_DATADIR="\"\"")
target_compile_options(ebr_djvu PRIVATE -fexceptions -frtti -w)
set_target_properties(ebr_djvu PROPERTIES CXX_STANDARD 11)
