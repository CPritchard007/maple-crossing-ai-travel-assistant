"""Enrich the crossing snapshot with road checkpoints from Overpass JSON.

Usage: python3 scripts/import_border_entrances.py crossings.json nodes.json [roads.json]
Nodes must be barrier=border_control; optional roads validate highway membership.
Preserves original crossing coordinates for reference, never uses them as entrances.
"""
import json
import math
import sys
from datetime import datetime, timezone


def distance(a, b):
    lat1, lat2 = map(math.radians, (a['latitude'], b['latitude']))
    dlat = lat2 - lat1
    dlon = math.radians(b['longitude'] - a['longitude'])
    h = math.sin(dlat / 2)**2 + math.cos(lat1)*math.cos(lat2)*math.sin(dlon / 2)**2
    return 6371000 * 2 * math.asin(min(1, math.sqrt(h)))


def enrich(data, nodes, roads=None):
    if nodes.get('remark') or (roads and roads.get('remark')):
        raise ValueError('Incomplete Overpass response; keep the previous snapshot')
    if not nodes.get('elements') or (roads is not None and not roads.get('elements')):
        raise ValueError('Empty checkpoint response; keep the previous snapshot')
    allowed = set()
    for way in (roads or {}).get('elements', []):
        tags = way.get('tags', {})
        if tags.get('highway') not in {'footway', 'path', 'steps', 'corridor', 'cycleway', 'construction', 'proposed'}:
            allowed.update(way.get('nodes', []))
    crossings = data['crossings']
    candidates = [r for r in crossings if r['type'] in {'road', 'unstaffed_road'}]
    prior_directions = {e['osm_node_id']: {k: e[k] for k in ('destination_country', 'direction_basis') if k in e}
                        for r in crossings for e in r.get('entrances', [])}
    for r in crossings:
        r['entrances'] = []
    matched = {r['id']: [] for r in candidates}
    for node in nodes['elements']:
        tags = node.get('tags', {})
        if ((roads is not None and node['id'] not in allowed)
                or tags.get('barrier') != 'border_control'
                or 'level' in tags or tags.get('indoor') == 'yes'
                or tags.get('motor_vehicle') == 'no'
                or tags.get('abandoned') == 'yes'):
            continue
        point = {'latitude': node['lat'], 'longitude': node['lon'], 'osm_node_id': node['id']}
        nearest = min(candidates, key=lambda r: distance(r, point))
        # Northern inspection stations can be many kilometres inland.
        limit = 35000 if nearest['latitude'] > 59 else 5000
        if distance(nearest, point) <= limit:
            matched[nearest['id']].append(point)
    for r in candidates:
        remaining = sorted(matched[r['id']], key=lambda p: p['osm_node_id'])
        groups = []
        while remaining:
            group = [remaining.pop(0)]
            for member in group:
                neighbors = [p for p in remaining if distance(member, p) <= 60]
                group.extend(neighbors)
                remaining = [p for p in remaining if p not in neighbors]
            groups.append(group)
        for group in groups:
            # Select a real checkpoint node, not an invented midpoint in a road gap.
            point = min(group, key=lambda p: sum(distance(p, q) for q in group))
            r['entrances'].append({
                **point,
                **prior_directions.get(point['osm_node_id'], {}),
                'source_url': f"https://www.openstreetmap.org/node/{point['osm_node_id']}",
                'kind': 'inspection_checkpoint',
                'road_link_verified': roads is not None,
                'lane_node_ids': [p['osm_node_id'] for p in group],
            })
        r['entrance_coverage'] = 'mapped_checkpoints_not_exhaustive' if groups else 'unmapped'
    data['schema_version'] = 2
    data['entrance_source'] = {
        'attribution': '© OpenStreetMap contributors',
        'url': 'https://www.openstreetmap.org/copyright',
        'license': 'ODbL 1.0',
        'retrieved_at': datetime.now(timezone.utc).isoformat(),
        'osm_timestamp': nodes.get('osm3s', {}).get('timestamp_osm_base'),
        'road_links_verified': roads is not None,
        'method': 'Border-control nodes (excluding tagged indoor and motor-vehicle-prohibited nodes) matched to nearest listed road crossing within 5 km (35 km north of 59°). Adjacent lanes grouped within 60 m; marker uses a real node. Both sides included where mapped; side labels and completeness are not verified.',
    }
    data['limitations'] = [s for s in data['limitations'] if not s.startswith(('Entrance markers:', 'Road-link lookup'))]
    data['limitations'].append('Entrance markers: mapped road inspection checkpoints, not approach-road turnoffs. Coverage may be incomplete on either side. Unmapped, rail and closed crossings have no entrance markers. Nearby-crossing associations are proximity-based and require review.')
    if roads is None:
        data['limitations'].append('Road-link lookup was unavailable for this snapshot. Checkpoints are matched by proximity; road access and exact approach entrances have not been verified.')
    return data


if __name__ == '__main__':
    path, nodes_path = sys.argv[1:3]
    roads = json.load(open(sys.argv[3])) if len(sys.argv) > 3 else None
    data = enrich(json.load(open(path)), json.load(open(nodes_path)), roads)
    with open(path, 'w') as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
        f.write('\n')
    print(sum(len(r['entrances']) for r in data['crossings']), 'entrance markers at', sum(bool(r['entrances']) for r in data['crossings']), 'crossings')
