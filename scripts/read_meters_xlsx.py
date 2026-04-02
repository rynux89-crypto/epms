import json
import posixpath
import sys
import zipfile
from xml.etree import ElementTree as ET

NS = {
    "main": "http://schemas.openxmlformats.org/spreadsheetml/2006/main",
    "rel": "http://schemas.openxmlformats.org/package/2006/relationships",
}


def col_to_index(ref: str) -> int:
    letters = []
    for ch in ref:
        if ch.isalpha():
            letters.append(ch.upper())
        else:
            break
    idx = 0
    for ch in letters:
        idx = idx * 26 + (ord(ch) - ord("A") + 1)
    return max(idx - 1, 0)


def normalize_header(value: str) -> str:
    return (value or "").strip().lower()


def text_or_empty(node):
    return "" if node is None else "".join(node.itertext())


def load_shared_strings(zf: zipfile.ZipFile):
    if "xl/sharedStrings.xml" not in zf.namelist():
        return []
    root = ET.fromstring(zf.read("xl/sharedStrings.xml"))
    values = []
    for si in root.findall("main:si", NS):
        values.append("".join(si.itertext()))
    return values


def get_first_sheet_path(zf: zipfile.ZipFile):
    workbook = ET.fromstring(zf.read("xl/workbook.xml"))
    rels = ET.fromstring(zf.read("xl/_rels/workbook.xml.rels"))
    rel_map = {}
    for rel in rels.findall("rel:Relationship", NS):
        rel_id = rel.attrib.get("Id")
        target = rel.attrib.get("Target")
        if rel_id and target:
            rel_map[rel_id] = target

    sheets = workbook.find("main:sheets", NS)
    if sheets is None:
        raise RuntimeError("No worksheet found in workbook.")

    for sheet in sheets.findall("main:sheet", NS):
        rel_id = sheet.attrib.get("{http://schemas.openxmlformats.org/officeDocument/2006/relationships}id")
        if not rel_id:
            continue
        target = rel_map.get(rel_id)
        if not target:
            continue
        return posixpath.normpath(posixpath.join("xl", target))
    raise RuntimeError("No worksheet target found in workbook.")


def cell_value(cell, shared_strings):
    cell_type = cell.attrib.get("t")
    if cell_type == "inlineStr":
        return text_or_empty(cell.find("main:is", NS)).strip()

    value_node = cell.find("main:v", NS)
    if value_node is None:
        return ""
    raw = text_or_empty(value_node).strip()
    if cell_type == "s":
        try:
            return shared_strings[int(raw)].strip()
        except Exception:
            return raw
    return raw


def read_rows(path: str):
    with zipfile.ZipFile(path, "r") as zf:
        shared_strings = load_shared_strings(zf)
        sheet_path = get_first_sheet_path(zf)
        root = ET.fromstring(zf.read(sheet_path))

    sheet_data = root.find("main:sheetData", NS)
    if sheet_data is None:
        return []

    rows = []
    headers = []
    for row in sheet_data.findall("main:row", NS):
        values = {}
        max_idx = -1
        for cell in row.findall("main:c", NS):
            ref = cell.attrib.get("r", "")
            idx = col_to_index(ref)
            max_idx = max(max_idx, idx)
            values[idx] = cell_value(cell, shared_strings)

        ordered = [values.get(i, "") for i in range(max_idx + 1)]
        if not headers:
            headers = [normalize_header(v) for v in ordered]
            continue

        item = {}
        non_empty = False
        for i, header in enumerate(headers):
            if not header:
                continue
            value = ordered[i] if i < len(ordered) else ""
            if isinstance(value, str):
                value = value.strip()
            if value not in ("", None):
                non_empty = True
            item[header] = value
        if non_empty:
            rows.append(item)
    return rows


def main():
    if len(sys.argv) < 2:
        raise RuntimeError("xlsx path is required")
    rows = read_rows(sys.argv[1])
    sys.stdout.write(json.dumps(rows, ensure_ascii=False))


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        sys.stderr.write(str(exc))
        sys.exit(1)
