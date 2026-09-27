"""Build the local crossing snapshot from a downloaded Wikipedia HTML file.
Usage: python import_border_crossings.py input.html output.json
Requires beautifulsoup4. Coordinates are factual source data, not live status.
"""
import json
import re
import sys
from datetime import datetime, timezone
from bs4 import BeautifulSoup

SOURCE = 'https://en.wikipedia.org/wiki/List_of_Canada%E2%80%93United_States_border_crossings'
soup = BeautifulSoup(open(sys.argv[1], encoding='utf-8').read(), 'html.parser')
records = []
missing = []
sections = {'Land ports of entry': 'road', 'Unstaffed road crossings': 'unstaffed_road', 'Rail crossings': 'rail', 'Closed land ports of entry': 'closed_road'}
for table in soup.select('table.wikitable'):
    heading = table.find_previous(['h2', 'h3']).get_text(' ', strip=True).replace('[edit]', '').strip()
    if heading not in sections:
        continue
    region = ''
    for row in table.select('tr'):
        cells = row.find_all(['th', 'td'], recursive=False)
        geos = row.select('.geo')
        if len(cells) == 1 and not geos:
            region = cells[0].get_text(' ', strip=True)
        if not geos:
            continue
        texts = [re.sub(r'\[\s*\d+\s*\]', '', c.get_text(' ', strip=True)).strip() for c in cells]
        mode = sections[heading]
        if mode == 'road':
            name = texts[0]
        elif mode in ('unstaffed_road', 'closed_road'):
            name = texts[0] + ' – ' + texts[3]
        else:
            name = texts[0] + ' – ' + texts[2] + ' (rail)'
        row_text = row.get_text(' ', strip=True).lower()
        historical = mode == 'closed_road' or 'closed' in row_text or 'abandoned' in row_text or '#f99' in str(row.get('style', '')).lower()
        for index, geo in enumerate(geos):
            lat, lon = map(float, geo.get_text().split(';'))
            assert 24 <= lat <= 72 and -170 <= lon <= -50, (name, lat, lon)
            records.append({
                'id': f'{mode}-{len(records)+1:03d}', 'name': name,
                'type': mode, 'region': region,
                'latitude': lat, 'longitude': lon,
                'status': 'historical_or_restricted_review_required' if historical else 'not_live_verified',
                'source_url': SOURCE + '#' + heading.replace(' ', '_'),
            })
# Ferries have no coordinates in the source: retain an explicit coverage gap.
result = {
    'schema_version': 1,
    'retrieved_at': datetime.now(timezone.utc).isoformat(),
    'source': {'title': 'List of Canada–United States border crossings', 'url': SOURCE,
               'attribution': 'Wikipedia contributors', 'license': 'CC BY-SA 4.0',
               'license_url': 'https://creativecommons.org/licenses/by-sa/4.0/'},
    'coordinate_system': 'WGS84 (EPSG:4326)',
    'coverage': 'All coordinate-bearing entries in the source land, unstaffed road, rail, and closed land crossing tables, including Alaska. Not an authoritative or guaranteed exhaustive inventory.',
    'limitations': ['Ferry crossings are not included: the source ferry table has no coordinates.', 'Includes historical, closed, restricted, and seasonal locations. Markers do not indicate permission to cross or current operating status.', 'Coordinates represent the source crossing location, not necessarily each inspection booth.'],
    'crossings': records,
}
with open(sys.argv[2], 'w', encoding='utf-8') as f:
    json.dump(result, f, ensure_ascii=False, indent=2)
    f.write('\n')
from collections import Counter
print(len(records), Counter(x['type'] for x in records))
