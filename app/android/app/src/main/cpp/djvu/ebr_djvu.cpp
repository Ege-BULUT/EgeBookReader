// A small C face over DjVuLibre's ddjvuapi for Dart FFI: open, count, measure, render to RGBA, close.
// Calls on one document must not overlap; the Dart side queues them.
#include "ddjvuapi.h"
#include <string.h>

#define EXPORT extern "C" __attribute__((visibility("default")))

struct Doc {
  ddjvu_context_t *ctx;
  ddjvu_document_t *doc;
};

static void drain(ddjvu_context_t *ctx) {
  while (ddjvu_message_peek(ctx)) ddjvu_message_pop(ctx);
}

EXPORT void ebr_djvu_close(Doc *d) {
  if (!d) return;
  if (d->doc) ddjvu_document_release(d->doc);
  ddjvu_context_release(d->ctx);
  delete d;
}

EXPORT Doc *ebr_djvu_open(const char *path) {
  ddjvu_context_t *ctx = ddjvu_context_create("egebookreader");
  if (!ctx) return nullptr;
  Doc *d = new Doc{ctx, ddjvu_document_create_by_filename_utf8(ctx, path, 1)};
  if (!d->doc) {
    ebr_djvu_close(d);
    return nullptr;
  }
  while (!ddjvu_document_decoding_done(d->doc)) {
    ddjvu_message_wait(ctx);
    drain(ctx);
  }
  if (ddjvu_document_decoding_error(d->doc)) {
    ebr_djvu_close(d);
    return nullptr;
  }
  return d;
}

EXPORT int ebr_djvu_pages(Doc *d) { return ddjvu_document_get_pagenum(d->doc); }

// Writes the page's width and height in pixels at its own resolution; returns 0, or -1 on error.
EXPORT int ebr_djvu_size(Doc *d, int page, int *size) {
  ddjvu_pageinfo_t info;
  ddjvu_status_t r;
  while ((r = ddjvu_document_get_pageinfo(d->doc, page, &info)) < DDJVU_JOB_OK) {
    ddjvu_message_wait(d->ctx);
    drain(d->ctx);
  }
  if (r != DDJVU_JOB_OK) return -1;
  // A page rotated by 90 or 270 degrees is shown with its sides swapped.
  bool turned = info.rotation & 1;
  size[0] = turned ? info.height : info.width;
  size[1] = turned ? info.width : info.height;
  return 0;
}

// Renders the whole page scaled to width x height into rgba (4 bytes a pixel, rows top to bottom). Returns 0, or -1.
EXPORT int ebr_djvu_render(Doc *d, int page, int width, int height, unsigned char *rgba) {
  ddjvu_page_t *p = ddjvu_page_create_by_pageno(d->doc, page);
  if (!p) return -1;
  while (!ddjvu_page_decoding_done(p)) {
    ddjvu_message_wait(d->ctx);
    drain(d->ctx);
  }
  int result = -1;
  if (!ddjvu_page_decoding_error(p)) {
    // Byte order in memory is R, G, B, A; the fourth entry is xored in, which makes alpha opaque.
    unsigned int masks[4] = {0x000000ff, 0x0000ff00, 0x00ff0000, 0xff000000};
    ddjvu_format_t *format = ddjvu_format_create(DDJVU_FORMAT_RGBMASK32, 4, masks);
    ddjvu_format_set_row_order(format, 1);
    ddjvu_format_set_y_direction(format, 1);
    ddjvu_rect_t rect = {0, 0, (unsigned)width, (unsigned)height};
    // A page with nothing to draw (blank) renders as white paper.
    if (!ddjvu_page_render(p, DDJVU_RENDER_COLOR, &rect, &rect, format, width * 4, (char *)rgba))
      memset(rgba, 0xff, (size_t)width * height * 4);
    ddjvu_format_release(format);
    result = 0;
  }
  ddjvu_page_release(p);
  return result;
}
