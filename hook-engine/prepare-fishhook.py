#!/usr/bin/env python3
"""Build-time BSD fishhook adapter. The original vendored files stay byte-exact."""
from pathlib import Path
import sys
source = (Path(__file__).parent / "vendor/fishhook/fishhook.c").read_text()
start = source.index("          kern_return_t err;")
end = source.index("          goto symbol_loop;", start)
source = source[:start] + """          mirsa_fishhook_store(&indirect_symbol_bindings[i],
              cur->rebindings[j].replacement, cur->rebindings[j].replaced);
""" + source[end:]
source = source.replace('#include "fishhook.h"', '#include "fishhook.h"\nextern void mirsa_fishhook_store(void **slot, void *replacement, void **original);')
needle = "    rebind_symbols_for_image(rebindings_head, (const struct mach_header *) header, slide);"
assert source.count(needle) == 1
source = source.replace(needle, "    if (retval == 0) {\n" + needle + "\n    }")
Path(sys.argv[1]).write_text(source)
