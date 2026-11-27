"""Read polygon ring lengths from an ArcGIS FeatureCollection PBF without decoding coordinates.

Esri's wire schema: https://github.com/Esri/arcgis-pbf/blob/master/proto/FeatureCollection/FeatureCollection.proto
"""

from collections import defaultdict


def varint(data, index):
    value = 0
    for shift in range(0, 70, 7):
        if index >= len(data):
            break
        byte = data[index]
        index += 1
        value |= (byte & 127) << shift
        if byte < 128:
            return value, index
    raise ValueError("Invalid ArcGIS protobuf integer")


def fields(data):
    result = defaultdict(list)
    index = 0
    while index < len(data):
        tag, index = varint(data, index)
        number, wire = divmod(tag, 8)
        if number == 0 or wire not in (0, 1, 2, 5):
            raise ValueError("Invalid ArcGIS protobuf tag")
        if wire == 0:
            value, index = varint(data, index)
        else:
            if wire == 2:
                size, index = varint(data, index)
            else:
                size = 8 if wire == 1 else 4
            if index + size > len(data):
                raise ValueError("Incomplete ArcGIS protobuf")
            value = data[index : index + size]
            index += size
        result[number].append(value)
    return result


def single(message, field):
    values = message.get(field, [])
    if len(values) != 1 or not isinstance(values[0], memoryview):
        raise ValueError(f"Expected one ArcGIS protobuf field {field}")
    return values[0]


def ring_topology(data):
    # FeatureCollection -> QueryResult -> FeatureResult -> Feature -> Geometry.
    collection = fields(memoryview(data))
    if 1 in collection and bytes(single(collection, 1)) != b"1.0":
        raise ValueError("Unsupported ArcGIS protobuf version")
    query = fields(single(collection, 2))
    result = fields(single(query, 1))
    if result.get(7) != [3] or any(result.get(9, [])):
        raise ValueError("Expected a complete ArcGIS polygon result")
    feature = fields(single(result, 15))
    geometry = fields(single(feature, 2))
    # Field 2 is packed uint32 ring lengths. Field 3 contains delta-coded coordinates.
    lengths = single(geometry, 2)
    index = rings = vertices = 0
    while index < len(lengths):
        count, index = varint(lengths, index)
        if count < 4:
            raise ValueError("Incomplete ArcGIS polygon ring")
        rings += 1
        vertices += count
    if not rings:
        raise ValueError("Empty ArcGIS polygon")
    return rings, vertices
