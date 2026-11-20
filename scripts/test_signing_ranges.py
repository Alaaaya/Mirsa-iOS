"""Run the actual read-only parser fixtures without iOS FFI dependencies."""
import os, pathlib, subprocess, tempfile
root=pathlib.Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory() as tmp:
    source=pathlib.Path(tmp)/"ranges.rs"
    source.write_text('#[path="'+str(root/'rust-core/src/signature_ranges.rs')+'"] mod ranges;\n')
    binary=pathlib.Path(tmp)/"ranges"
    subprocess.run(["rustc","--edition=2021","--test",str(source),"-o",str(binary)],check=True)
    subprocess.run([str(binary)],check=True)
