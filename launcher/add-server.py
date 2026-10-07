#!/usr/bin/env python3
"""Add (or update) a server in a Minecraft servers.dat multiplayer list.

Usage: add-server.py <path/to/servers.dat> <name> <address>

servers.dat is an uncompressed NBT file. This reads and writes the full NBT
format so any servers already in the list are kept exactly as they were.
"""

import os
import struct
import sys

END, BYTE, SHORT, INT, LONG, FLOAT, DOUBLE, BYTE_ARRAY, STRING, LIST, COMPOUND, INT_ARRAY, LONG_ARRAY = range(13)


class Reader:
    def __init__(self, data):
        self.data, self.pos = data, 0

    def take(self, fmt):
        size = struct.calcsize(fmt)
        value = struct.unpack_from(fmt, self.data, self.pos)
        self.pos += size
        return value[0]

    def string(self):
        length = self.take(">H")
        value = self.data[self.pos:self.pos + length].decode("utf-8")
        self.pos += length
        return value

    def payload(self, tag):
        simple = {BYTE: ">b", SHORT: ">h", INT: ">i", LONG: ">q", FLOAT: ">f", DOUBLE: ">d"}
        if tag in simple:
            return self.take(simple[tag])
        if tag == STRING:
            return self.string()
        if tag in (BYTE_ARRAY, INT_ARRAY, LONG_ARRAY):
            item = {BYTE_ARRAY: ">b", INT_ARRAY: ">i", LONG_ARRAY: ">q"}[tag]
            return [self.take(item) for _ in range(self.take(">i"))]
        if tag == LIST:
            item_tag = self.take(">b")
            return (item_tag, [self.payload(item_tag) for _ in range(self.take(">i"))])
        if tag == COMPOUND:
            entries = []
            while True:
                child = self.take(">b")
                if child == END:
                    return entries
                entries.append((child, self.string(), self.payload(child)))
        raise ValueError(f"unknown NBT tag {tag}")


def write_string(out, value):
    raw = value.encode("utf-8")
    out += struct.pack(">H", len(raw)) + raw


def write_payload(out, tag, value):
    simple = {BYTE: ">b", SHORT: ">h", INT: ">i", LONG: ">q", FLOAT: ">f", DOUBLE: ">d"}
    if tag in simple:
        out += struct.pack(simple[tag], value)
    elif tag == STRING:
        write_string(out, value)
    elif tag in (BYTE_ARRAY, INT_ARRAY, LONG_ARRAY):
        item = {BYTE_ARRAY: ">b", INT_ARRAY: ">i", LONG_ARRAY: ">q"}[tag]
        out += struct.pack(">i", len(value))
        for v in value:
            out += struct.pack(item, v)
    elif tag == LIST:
        item_tag, items = value
        out += struct.pack(">bi", item_tag, len(items))
        for v in items:
            write_payload(out, item_tag, v)
    elif tag == COMPOUND:
        for child, name, v in value:
            out += struct.pack(">b", child)
            write_string(out, name)
            write_payload(out, child, v)
        out += struct.pack(">b", END)


def main():
    if len(sys.argv) != 4:
        sys.exit(__doc__)
    path, name, address = sys.argv[1:]

    if os.path.exists(path) and os.path.getsize(path) > 0:
        reader = Reader(open(path, "rb").read())
        reader.take(">b")
        root_name = reader.string()
        root = reader.payload(COMPOUND)
    else:
        root_name, root = "", []

    servers = next((v for t, n, v in root if n == "servers" and t == LIST), None)
    if servers is None:
        servers = (COMPOUND, [])
        root.append((LIST, "servers", servers))
    elif servers[0] == END:
        servers = (COMPOUND, servers[1])
        root[:] = [(t, n, servers if n == "servers" else v) for t, n, v in root]

    for entry in servers[1]:
        fields = {n: v for t, n, v in entry}
        if fields.get("name") == name or fields.get("ip") == address:
            entry[:] = [e for e in entry if e[1] not in ("name", "ip")]
            entry[:0] = [(STRING, "name", name), (STRING, "ip", address)]
            action = "Updated"
            break
    else:
        servers[1].insert(0, [(STRING, "name", name), (STRING, "ip", address)])
        action = "Added"

    out = bytearray(struct.pack(">b", COMPOUND))
    write_string(out, root_name)
    write_payload(out, COMPOUND, root)
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    with open(path, "wb") as f:
        f.write(out)
    print(f"  {action} '{name}' ({address}) in {path}")


if __name__ == "__main__":
    main()
