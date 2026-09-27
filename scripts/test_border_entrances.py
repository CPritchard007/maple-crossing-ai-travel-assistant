import unittest
from import_border_entrances import enrich


class EntranceImportTest(unittest.TestCase):
    def test_road_filter_lane_grouping_and_no_boundary_fallback(self):
        data = {'crossings': [
            {'id': 'one', 'type': 'road', 'latitude': 49, 'longitude': -100},
            {'id': 'two', 'type': 'road', 'latitude': 49, 'longitude': -110},
        ], 'limitations': []}
        nodes = {'elements': [
            {'id': i, 'lat': lat, 'lon': -100, 'tags': {'barrier': 'border_control'}}
            for i, lat in [(1, 49.001), (2, 49.0011), (3, 48.999), (4, 49.01)]
        ]}
        roads = {'elements': [{'tags': {'highway': 'service'}, 'nodes': [1, 2, 3]}]}
        result = enrich(data, nodes, roads)
        entrances = result['crossings'][0]['entrances']
        self.assertEqual(len(entrances), 2)
        self.assertEqual(sorted(len(p['lane_node_ids']) for p in entrances), [1, 2])
        self.assertEqual(result['crossings'][1]['entrances'], [])
        self.assertTrue(all(p['latitude'] != 49 for p in entrances))

    def test_partial_response_rejected(self):
        with self.assertRaises(ValueError):
            enrich({}, {'remark': 'timeout'}, {})


if __name__ == '__main__':
    unittest.main()
