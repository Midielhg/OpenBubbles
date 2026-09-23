"""Remove exact-duplicate `impl SseEncode/SseDecode for T` blocks from rust/src/frb_generated.rs.

flutter_rust_bridge_codegen 2.3.0 emits some encoders twice (e.g. Option<i64>, Option<u64>,
(String, u64)) when the same Rust type is reached both with and without #[frb(type_64bit_int)].
The copies are byte-identical, so keeping the first one is behaviour-preserving.
Run after `flutter_rust_bridge_codegen generate`.
"""
import re
import sys
from pathlib import Path

path = Path(__file__).resolve().parent.parent / "rust" / "src" / "frb_generated.rs"
src = path.read_text(encoding="utf-8")
lines = src.split("\n")

header = re.compile(r"^impl (SseEncode|SseDecode) for (.+) \{$")
out, seen, removed, i = [], set(), 0, 0
while i < len(lines):
    m = header.match(lines[i])
    if m:
        # a top-level impl block ends at the next line that is exactly "}"
        j = i
        while lines[j] != "}":
            j += 1
        block = "\n".join(lines[i:j + 1])
        key = (m.group(1), m.group(2))
        if key in seen:
            removed += 1
            i = j + 1
            if i < len(lines) and lines[i] == "":
                i += 1
            continue
        seen.add(key)
        out.extend(lines[i:j + 1])
        i = j + 1
        continue
    out.append(lines[i])
    i += 1

path.write_text("\n".join(out), encoding="utf-8")
print(f"removed {removed} duplicate impl blocks")
sys.exit(0)
