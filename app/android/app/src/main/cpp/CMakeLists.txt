cmake_minimum_required(VERSION 3.22)
project(ebr_archive C)

# libarchive (BSD-2-Clause) reads CBR files. Only the parts needed for RAR are switched on.
include(FetchContent)
set(ENABLE_TEST OFF CACHE BOOL "" FORCE)
set(ENABLE_COVERAGE OFF CACHE BOOL "" FORCE)
set(ENABLE_TAR OFF CACHE BOOL "" FORCE)
set(ENABLE_CPIO OFF CACHE BOOL "" FORCE)
set(ENABLE_CAT OFF CACHE BOOL "" FORCE)
set(ENABLE_UNZIP OFF CACHE BOOL "" FORCE)
set(ENABLE_INSTALL OFF CACHE BOOL "" FORCE)
foreach(option OPENSSL MBEDTLS NETTLE LIBB2 LZ4 LZO LZMA ZSTD ZLIB BZip2 LIBXML2 EXPAT PCREPOSIX PCRE2POSIX CNG ACL XATTR ICONV LibGCC)
  set(ENABLE_${option} OFF CACHE BOOL "" FORCE)
endforeach()
FetchContent_Declare(libarchive
  URL https://github.com/libarchive/libarchive/releases/download/v3.8.11/libarchive-3.8.11.tar.gz
  URL_HASH SHA256=900fe9fc7237c2b04f090f3c3648de8fe597525771f5035016537ce2d667d12b)
FetchContent_MakeAvailable(libarchive)
set_target_properties(archive PROPERTIES OUTPUT_NAME ebr_archive)
