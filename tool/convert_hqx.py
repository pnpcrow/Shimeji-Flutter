#!/usr/bin/env python3
"""One-off Java -> Dart converter for the hqx package sources."""
import io
import re

DELEGATING = re.compile(
    r"public static void %s\(\s*final (?:List<int>|int\[\]) sp, "
    r"final (?:List<int>|int\[\]) dp,\s*final int xRes, final int yRes\s*\)\s*\{"
    r"\s*%s\(sp, dp, xRes, yRes, ([^;]+?)\);" % ("%s", "%s"))


def convert_method_bodies(src: str) -> str:
    s = src
    # Block-arrow cases -> Dart or-pattern cases with block bodies.
    s = re.sub(r"case ([^\n{]*?) -> \{", r"case \1 {", s)

    # Expression-arrow cases (Hq4x style): case A, B -> call(...);
    def expr_arrow(m):
        labels = " || ".join(x.strip() for x in m.group(1).split(","))
        return "case %s: { %s }" % (labels, m.group(2))

    s = re.sub(r"case ([^\n{]+?) -> ([^;\n]+;)", expr_arrow, s)
    s = s.replace("default -> {", "default {")

    # caseN helper methods: private static void caseN(final int[] dp, ...)
    s = re.sub(
        r"private static void (case\d+)\(final int\[\] dp, final int dpIdx, "
        r"final int dpL, final int\[\] w\)",
        r"static void \1(List<int> dp, int dpIdx, int dpL, List<int> w)", s)

    s = s.replace("Integer.compareUnsigned", "compareUnsigned")
    s = s.replace("Util.", "HqxUtil.")
    s = re.sub(r"for \(final int (\w+) = 0; (\w+) < (\w+); (\w+)\+\+\)",
               r"for (var \1 = 0; \2 < \3; \4++)", s)
    s = s.replace("final int[] w = new int[9];",
                  "final List<int> w = List<int>.filled(9, 0);")
    s = s.replace("final int[] w = new int[5];",
                  "final List<int> w = List<int>.filled(5, 0);")
    return s


def find_matching_brace(src, open_idx):
    depth = 0
    i = open_idx
    while i < len(src):
        c = src[i]
        if c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0:
                return i
        i += 1
    raise ValueError("unbalanced braces")


def convert_file(java_path, class_name, scale_name, out_path):
    src = io.open(java_path, encoding="utf-8").read()
    src = re.sub(r"/\*.*?\*/", "", src, flags=re.S)

    pattern = DELEGATING.pattern % (scale_name, scale_name)
    m = re.search(pattern, src)
    assert m, "delegating overload not found in " + java_path
    defaults = m.group(1).strip()

    big_idx = src.find("public static void %s(" % scale_name, m.end())
    assert big_idx > 0, "big overload not found"
    body_open = src.find("{", big_idx)
    body_close = find_matching_brace(src, body_open)
    body = src[body_open + 1:body_close]
    body = convert_method_bodies(body)

    params = ["List<int> sp", "List<int> dp", "int xRes", "int yRes",
              "int trY", "int trU", "int trV", "int trA",
              "bool wrapX", "bool wrapY"]

    out = f"""// Generated from hqx-java ({class_name}.java) - hqx algorithm by
// Maxim Stepin, Java port by Cameron Zemek et al. (LGPL-3.0).
// Do not edit by hand; regenerate with tool/convert_hqx.py.
library;

import 'util.dart';

/// Port of hqx/{class_name}.
class {class_name} {{
  /// Java Integer.compareUnsigned(a, b) > 0.
  static bool compareUnsignedGt(int a, int b) =>
      (a & 0xFFFFFFFF) > (b & 0xFFFFFFFF);

  /// Upscales ARGB pixel data by {scale_name[5]}x using hq{scale_name[5]}x.
  static void {scale_name}(List<int> sp, List<int> dp, int xRes, int yRes) {{
    {scale_name}Full(sp, dp, xRes, yRes, {defaults});
  }}

  static void {scale_name}Full(
      {", ".join(params)}) {{
{body}}}
}}
"""
    io.open(out_path, "w", encoding="utf-8", newline="\n").write(out)
    print(f"wrote {out_path} ({len(out)} bytes)")


if __name__ == "__main__":
    base = r"C:\Develop\Repositories\Shimeji-Desktop\src\main\java\hqx"
    convert_file(base + r"\Hq2x.java", "Hq2x", "scale2", r"lib\src\image\hqx\hq2x.dart")
    convert_file(base + r"\Hq3x.java", "Hq3x", "scale3", r"lib\src\image\hqx\hq3x.dart")
    convert_file(base + r"\Hq4x.java", "Hq4x", "scale4", r"lib\src\image\hqx\hq4x.dart")
