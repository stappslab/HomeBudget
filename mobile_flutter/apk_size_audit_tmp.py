from collections import defaultdict
from pathlib import Path
from zipfile import ZipFile
import hashlib
import sys

path = Path(sys.argv[1])
groups = defaultdict(lambda: [0, 0, 0])
libs = defaultdict(lambda: [0, 0, 0])
entries = []
with ZipFile(path) as archive:
    identical = defaultdict(list)
    for item in archive.infolist():
        if item.is_dir():
            continue
        name = item.filename
        if name.startswith('lib/'):
            group = 'lib/' + name.split('/')[1]
            libs[name] = [item.compress_size, item.file_size, item.compress_type]
        elif name.startswith('assets/flutter_assets/'):
            group = 'assets/flutter_assets'
        elif name.startswith('res/'):
            group = 'res/'
        elif name.startswith('META-INF/'):
            group = 'META-INF/'
        elif name.startswith('kotlin/'):
            group = 'kotlin/'
        elif name.endswith('.dex'):
            group = 'DEX'
        else:
            group = name.split('/')[0]
        groups[group][0] += item.compress_size
        groups[group][1] += item.file_size
        groups[group][2] += 1
        entries.append((item.compress_size, item.file_size, name))
        if name.startswith('res/') and item.file_size >= 20000:
            identical[hashlib.sha256(archive.read(item)).hexdigest()].append(
                (name, item.compress_size))

def mb(size):
    return f'{size / 1_000_000:.2f}'

print('FILE', path)
print('APK_BYTES', path.stat().st_size, 'APK_MB', mb(path.stat().st_size))
print('UNCOMPRESSED_MB', mb(sum(value[1] for value in groups.values())))
print('GROUPS (compressed MB, raw MB, count)')
for name, value in sorted(groups.items(), key=lambda pair: -pair[1][0]):
    print(name, mb(value[0]), mb(value[1]), value[2])
print('LARGEST ENTRIES (compressed MB, raw MB)')
for compressed, raw, name in sorted(entries, reverse=True)[:35]:
    print(mb(compressed), mb(raw), name)
print('IDENTICAL_RESOURCE_GROUPS (potential duplicate compressed MB, copies)')
for matches in sorted((values for values in identical.values() if len(values) > 1),
    key=lambda values: -sum(size for _, size in values[1:]))[:15]:
    print(mb(sum(size for _, size in matches[1:])), len(matches),
      ', '.join(name for name, _ in matches))
