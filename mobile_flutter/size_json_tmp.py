import json
import sys

data = json.load(open(sys.argv[1], encoding='utf-8'))
print('TOP_KEYS', list(data))
for key, value in data.items():
    if isinstance(value, dict):
        print('DICT', key, list(value)[:15])
    elif isinstance(value, list):
        print('LIST', key, len(value), value[0] if value else None)
    else:
        print('VALUE', key, value)
