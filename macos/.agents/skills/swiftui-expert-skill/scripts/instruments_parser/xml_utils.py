"""Streaming XML helpers for xctrace export output.

Instruments XML deduplicates repeated values with `id`/`ref` attributes that
can span the whole document, so we stream rows with iterparse while keeping
a global id cache for later ref lookups.
"""
from __future__ import annotations

import xml.etree.ElementTree as ET
from collections.abc import Iterator
from dataclasses import dataclass


@dataclass(frozen=True)
class Column:
    mnemonic: str          # e.g. "time", "weight", "stack"
    engineering_type: str  # e.g. "sample-time", "weight", "tagged-backtrace"


# Purge already-parsed children from the row container after this many
# elements, so sibling accumulation never grows with the document.
_PURGE_INTERVAL = 10_000


class RowStream:
    """Iterate <row> elements of a single <table> schema export.

    Yields `dict[str, Element]` keyed by column mnemonic. A yielded row (and
    the elements in it) is only valid until the iterator advances; extract
    values into plain Python types as you go, which every lane parser does.

    Memory: two passes over the bytes keep peak RAM bounded on very large
    exports instead of ≈ document size. Pass one collects the set of ids that
    are actually referenced by `ref` attributes later in the document; pass
    two retains only those id elements in the cache (strong references, so
    periodic purges of the row container cannot drop them) and purges parsed
    children from the container as it streams.
    """

    def __init__(self, xml_bytes: bytes):
        self._xml = xml_bytes
        self.columns: list[Column] = []
        self._id_cache: dict[str, ET.Element] = {}

    def resolve(self, element: ET.Element) -> ET.Element:
        """If the element is a ref, return the referenced element; else self."""
        ref = element.get("ref")
        if ref is None:
            return element
        target = self._id_cache.get(ref)
        if target is None:
            return element  # unresolved; return the ref element itself
        return target

    def __iter__(self) -> Iterator[dict[str, ET.Element]]:
        referenced = self._collect_referenced_ids()
        context = ET.iterparse(_bytes_to_file(self._xml), events=("start", "end"))
        root: ET.Element | None = None
        container: ET.Element | None = None  # <table>: accumulates the rows
        schema_seen = False
        since_purge = 0
        for event, elem in context:
            if event == "start":
                if root is None:
                    root = elem
                elif container is None and elem.tag == "table":
                    container = elem
                continue

            if elem.tag == "schema" and not schema_seen:
                self.columns = _parse_columns(elem)
                schema_seen = True
            elif elem.tag == "row":
                yield _row_dict(elem, self.columns)

            eid = elem.get("id")
            if eid is not None and eid in referenced:
                self._id_cache[eid] = elem

            since_purge += 1
            if since_purge >= _PURGE_INTERVAL:
                if container is not None:
                    container.clear()
                if root is not None:
                    root.clear()
                since_purge = 0
        # Parse finished: the export bytes and the tree are no longer needed.
        self._xml = b""

    def _collect_referenced_ids(self) -> frozenset[str]:
        """First pass: which ids does anything `ref` later in the document."""
        refs: set[str] = set()
        context = ET.iterparse(_bytes_to_file(self._xml), events=("start", "end"))
        root: ET.Element | None = None
        container: ET.Element | None = None
        since_purge = 0
        for event, elem in context:
            if event == "start":
                if root is None:
                    root = elem
                elif container is None and elem.tag == "table":
                    container = elem
                continue
            ref = elem.get("ref")
            if ref is not None:
                refs.add(ref)
            since_purge += 1
            if since_purge >= _PURGE_INTERVAL:
                if container is not None:
                    container.clear()
                if root is not None:
                    root.clear()
                since_purge = 0
        return frozenset(refs)


def _parse_columns(schema_el: ET.Element) -> list[Column]:
    cols: list[Column] = []
    for col in schema_el.findall("col"):
        mnemonic = (col.findtext("mnemonic") or "").strip()
        etype = (col.findtext("engineering-type") or "").strip()
        if mnemonic:
            cols.append(Column(mnemonic=mnemonic, engineering_type=etype))
    return cols


def _row_dict(row_el: ET.Element, cols: list[Column]) -> dict[str, ET.Element]:
    # Row children map positionally to columns. <sentinel/> marks a missing
    # optional value for that column.
    result: dict[str, ET.Element] = {}
    children = list(row_el)
    for idx, child in enumerate(children):
        if idx >= len(cols):
            break
        if child.tag == "sentinel":
            continue
        result[cols[idx].mnemonic] = child
    return result


def _bytes_to_file(data: bytes):
    import io
    return io.BytesIO(data)


# --- Extraction helpers ---------------------------------------------------

def int_text(elem: ET.Element | None) -> int | None:
    if elem is None or elem.text is None:
        return None
    try:
        return int(elem.text)
    except ValueError:
        return None


def str_text(elem: ET.Element | None) -> str | None:
    if elem is None or elem.text is None:
        return None
    return elem.text


def fmt_attr(elem: ET.Element | None) -> str | None:
    """Return the human-readable `fmt` attribute if present."""
    if elem is None:
        return None
    return elem.get("fmt")


def extract_thread(thread_el: ET.Element, stream: RowStream) -> dict:
    """Parse a <thread> element into name, tid, process dict.

    Handles ref-style threads by resolving through the stream's id cache.
    """
    resolved = stream.resolve(thread_el)
    name = resolved.get("fmt", "")
    tid_el = resolved.find("tid")
    process_el = resolved.find("process")
    process = extract_process(process_el, stream) if process_el is not None else None
    return {
        "name": name,
        "tid": int_text(tid_el),
        "process": process,
        "is_main": name.startswith("Main Thread") if name else False,
    }


def extract_process(process_el: ET.Element, stream: RowStream) -> dict:
    resolved = stream.resolve(process_el)
    name = resolved.get("fmt", "")
    pid_el = resolved.find("pid")
    return {
        "name": _clean_process_name(name),
        "pid": int_text(pid_el),
    }


def _clean_process_name(fmt: str) -> str:
    # "NowPlaying Gigs (28401)" -> "NowPlaying Gigs"
    if " (" in fmt and fmt.endswith(")"):
        return fmt.rsplit(" (", 1)[0]
    return fmt


def extract_backtrace(
    bt_el: ET.Element, stream: RowStream, max_frames: int = 20
) -> list[dict]:
    """Return a list of frame dicts from a <tagged-backtrace> or <backtrace>.

    Frames are ordered leaf-first (top of stack first), matching Instruments'
    display order.
    """
    resolved = stream.resolve(bt_el)
    inner = resolved.find("backtrace")
    if inner is None:
        inner = resolved
    frames: list[dict] = []
    for frame_el in inner.findall("frame"):
        f = stream.resolve(frame_el)
        frames.append({
            "name": f.get("name") or "",
            "addr": f.get("addr") or "",
        })
        if len(frames) >= max_frames:
            break
    return frames


def top_symbol(frames: list[dict]) -> str:
    """Pick the leaf symbol, falling back to addr if unsymbolicated."""
    if not frames:
        return "<empty-stack>"
    first = frames[0]
    return first.get("name") or first.get("addr") or "<unknown>"


def first_present(row: dict, *keys: str) -> ET.Element | None:
    """Return the first row column whose key exists.

    `row[key] or row[other_key]` is unsafe here: Element is falsy when it has
    no children (a common case for leaf <event-time>, <start-time>, etc.), so
    `or` short-circuits past valid leaf elements. This walks keys explicitly.
    """
    for key in keys:
        el = row.get(key)
        if el is not None:
            return el
    return None


def in_window(time_ns: int | None, window: tuple[int, int] | None) -> bool:
    """Return True if time_ns is inside [start, end] (inclusive), or window is None."""
    if window is None:
        return True
    if time_ns is None:
        return False
    start, end = window
    return start <= time_ns <= end


def event_overlaps_window(
    start_ns: int, end_ns: int, window: tuple[int, int] | None
) -> bool:
    """Return True if [start, end] overlaps [window.start, window.end]."""
    if window is None:
        return True
    w_start, w_end = window
    return not (end_ns < w_start or start_ns > w_end)
