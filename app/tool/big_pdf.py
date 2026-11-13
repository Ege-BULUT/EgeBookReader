#!/usr/bin/env python3
"""Writes a text PDF with many pages, for checking a big PDF on the emulator. Standard library only.
Usage: python3 tool/big_pdf.py 2000 /tmp/big.pdf"""
import sys

pages, out = int(sys.argv[1]), sys.argv[2]
line = 'Page {n}. The quick brown fox jumps over the lazy dog; a long line of text that fills the width.'
objects = ['<< /Type /Catalog /Pages 2 0 R >>', None, '<< /Type /Font /Subtype /Type1 /BaseFont /Times-Roman >>']
kids = []
for n in range(1, pages + 1):
    text = ''.join(f'BT /F1 11 Tf 56 {780 - 15 * i} Td ({line.format(n=n)}) Tj ET\n' for i in range(48))
    objects.append(f'<< /Length {len(text)} >>\nstream\n{text}endstream')
    objects.append(f'<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Resources << /Font << /F1 3 0 R >> >> '
                   f'/Contents {len(objects)} 0 R >>')
    kids.append(f'{len(objects)} 0 R')
objects[1] = f'<< /Type /Pages /Kids [{" ".join(kids)}] /Count {pages} >>'
data, offsets = bytearray(b'%PDF-1.4\n'), []
for i, o in enumerate(objects, 1):
    offsets.append(len(data))
    data += f'{i} 0 obj\n{o}\nendobj\n'.encode('latin-1')
xref = len(data)
data += f'xref\n0 {len(objects) + 1}\n0000000000 65535 f \n'.encode()
data += b''.join(f'{o:010d} 00000 n \n'.encode() for o in offsets)
data += f'trailer\n<< /Size {len(objects) + 1} /Root 1 0 R >>\nstartxref\n{xref}\n%%EOF\n'.encode()
open(out, 'wb').write(data)
print(f'{out}: {pages} pages, {len(data) // 1024} KB')
