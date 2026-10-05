# Sourced by markdown-tables.sh and ui-captures-markdown.sh so both render the same assets: a 12 px dot, a 160 by 40 picture, a 400 by 40 one wider than the narrow column, 500 rows of three cells, 60 rows of 12 long words that chunk and overflow, and a pair of tables of which only one fits a very wide pane.
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
solid(root + '/huge.png', 400, 40)
rows = ''.join('| row %d | a plain cell number %d | %d |\n' % (i, i, i * 7) for i in range(500))
open(root + '/rows500.md', 'w').write('# Rows\n\n| Name | Cell | Number |\n| --- | --- | ---: |\n' + rows)
# Sixty rows is three chunks of the table, and twelve long whole words a row overflow both panes.
words = ['Categorization', 'Initialization', 'Configuration', 'Authentication', 'Synchronization', 'Normalization', 'Serialization', 'Optimization', 'Customization', 'Virtualization', 'Orchestration', 'Documentation']
wide = '| ' + ' | '.join(words) + ' |\n| ' + ' | '.join(['---'] * len(words)) + ' |\n'
wide += ''.join('| ' + ' | '.join('%s%d' % (w[:6].lower(), i) for w in words) + ' |\n' for i in range(60))
open(root + '/chunkwide.md', 'w').write('# Chunked\n\n' + wide)
# Two tables: twelve long words that fit a 4000 px pane, then forty that overflow even that, so a widened pane drops the first scroll and keeps the second.
many = (words * 4)[:40]
def table(cols):
    return '| ' + ' | '.join(c + str(i) for i, c in enumerate(cols)) + ' |\n| ' + ' | '.join(['---'] * len(cols)) + ' |\n| ' + ' | '.join(['x'] * len(cols)) + ' |\n'
open(root + '/pair.md', 'w').write('# Pair\n\n' + table(words) + '\n' + table(many))
PY
}
