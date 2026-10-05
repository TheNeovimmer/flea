# Sourced by markdown-tables.sh and ui-captures-markdown.sh so both render the same assets: a 12 px dot, a 160 by 40 picture, 500 rows of three cells.
markdown_tables_assets_write() {
    python3 - "$1" <<'PY' || return 1
import struct, sys, zlib
root = sys.argv[1]
def chunk(tag, body):
    return struct.pack('>I', len(body)) + tag + body + struct.pack('>I', zlib.crc32(tag + body) & 0xffffffff)
def solid(path, width, height):
    png = b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 2, 0, 0, 0))
    png += chunk(b'IDAT', zlib.compress((b'\0' + b'\x40\x80\xc0' * width) * height)) + chunk(b'IEND', b'')
    open(path, 'wb').write(png)
solid(root + '/dot.png', 12, 12)
solid(root + '/wide.png', 160, 40)
rows = ''.join('| row %d | a plain cell number %d | %d |\n' % (i, i, i * 7) for i in range(500))
open(root + '/rows500.md', 'w').write('# Rows\n\n| Name | Cell | Number |\n| --- | --- | ---: |\n' + rows)
PY
}
