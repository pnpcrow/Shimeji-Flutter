// Generated from hqx-java (Hq2x.java) - hqx algorithm by
// Maxim Stepin, Java port by Cameron Zemek et al. (LGPL-3.0).
// Do not edit by hand; regenerate with tool/convert_hqx.py.
library;

import 'util.dart';

/// Port of hqx/Hq2x.
class Hq2x {
  /// Java Integer.compareUnsigned(a, b) > 0.
  static bool compareUnsignedGt(int a, int b) =>
      (a & 0xFFFFFFFF) > (b & 0xFFFFFFFF);

  /// Upscales ARGB pixel data by 2x using hq2x.
  static void scale2(List<int> sp, List<int> dp, int xRes, int yRes) {
    scale2Full(sp, dp, xRes, yRes, 48, 7, 6, 0, false, false);
  }

  static void scale2Full(
      List<int> sp, List<int> dp, int xRes, int yRes, int trY, int trU, int trV, int trA, bool wrapX, bool wrapY) {

        int spIdx = 0, dpIdx = 0;
        // Don't shift trA, as it uses shift right instead of a mask for comparisons.
        trY <<= 16;
        trU <<= 8;
        final int dpL = xRes * 2;

        int prevLine, nextLine;
        final List<int> w = List<int>.filled(9, 0);

        //   +----+----+----+
        //   | w0 | w1 | w2 |
        //   +----+----+----+
        //   | w3 | w4 | w5 |
        //   +----+----+----+
        //   | w6 | w7 | w8 |
        //   +----+----+----+

        for (int j = 0; j < yRes; j++) {
            prevLine = j > 0
                    ? -xRes
                    : wrapY
                      ? xRes * (yRes - 1)
                      : 0;
            nextLine = j < yRes - 1
                    ? xRes
                    : wrapY
                      ? -(xRes * (yRes - 1))
                      : 0;
            for (int i = 0; i < xRes; i++) {
                w[1] = sp[spIdx + prevLine];
                w[4] = sp[spIdx];
                w[7] = sp[spIdx + nextLine];

                if (i > 0) {
                    w[0] = sp[spIdx + prevLine - 1];
                    w[3] = sp[spIdx - 1];
                    w[6] = sp[spIdx + nextLine - 1];
                } else {
                    if (wrapX) {
                        w[0] = sp[spIdx + prevLine + xRes - 1];
                        w[3] = sp[spIdx + xRes - 1];
                        w[6] = sp[spIdx + nextLine + xRes - 1];
                    } else {
                        w[0] = w[1];
                        w[3] = w[4];
                        w[6] = w[7];
                    }
                }

                if (i < xRes - 1) {
                    w[2] = sp[spIdx + prevLine + 1];
                    w[5] = sp[spIdx + 1];
                    w[8] = sp[spIdx + nextLine + 1];
                } else {
                    if (wrapX) {
                        w[2] = sp[spIdx + prevLine - xRes + 1];
                        w[5] = sp[spIdx - xRes + 1];
                        w[8] = sp[spIdx + nextLine - xRes + 1];
                    } else {
                        w[2] = w[1];
                        w[5] = w[4];
                        w[8] = w[7];
                    }
                }

                int pattern = 0;
                int flag = 1;

                for (int k = 0; k < w.length; k++) {
                    if (k == 4) {
                        continue;
                    }

                    if (w[k] != w[4]) {
                        if (HqxUtil.diff(w[4], w[k], trY, trU, trV, trA)) {
                            pattern |= flag;
                        }
                    }
                    flag <<= 1;
                }

                switch (pattern) {
                    case 0 || 1 || 4 || 5 || 32 || 33 || 36 || 37 || 128 || 129 || 132 || 133 || 160 || 161 || 164 || 165: {
                        dp[dpIdx] = HqxUtil.mix2To1To1(w[4], w[3], w[1]);
                        dp[dpIdx + 1] = HqxUtil.mix2To1To1(w[4], w[1], w[5]);
                        dp[dpIdx + dpL] = HqxUtil.mix2To1To1(w[4], w[7], w[3]);
                        dp[dpIdx + dpL + 1] = HqxUtil.mix2To1To1(w[4], w[5], w[7]);
                    }
                    case 2 || 34 || 130 || 162: {
                        dp[dpIdx] = HqxUtil.mix2To1To1(w[4], w[0], w[3]);
                        dp[dpIdx + 1] = HqxUtil.mix2To1To1(w[4], w[2], w[5]);
                        dp[dpIdx + dpL] = HqxUtil.mix2To1To1(w[4], w[7], w[3]);
                        dp[dpIdx + dpL + 1] = HqxUtil.mix2To1To1(w[4], w[5], w[7]);
                    }
                    case 16 || 17 || 48 || 49: {
                        dp[dpIdx] = HqxUtil.mix2To1To1(w[4], w[3], w[1]);
                        dp[dpIdx + 1] = HqxUtil.mix2To1To1(w[4], w[2], w[1]);
                        dp[dpIdx + dpL] = HqxUtil.mix2To1To1(w[4], w[7], w[3]);
                        dp[dpIdx + dpL + 1] = HqxUtil.mix2To1To1(w[4], w[8], w[7]);
                    }
                    case 64 || 65 || 68 || 69: {
                        dp[dpIdx] = HqxUtil.mix2To1To1(w[4], w[3], w[1]);
                        dp[dpIdx + 1] = HqxUtil.mix2To1To1(w[4], w[1], w[5]);
                        dp[dpIdx + dpL] = HqxUtil.mix2To1To1(w[4], w[6], w[3]);
                        dp[dpIdx + dpL + 1] = HqxUtil.mix2To1To1(w[4], w[8], w[5]);
                    }
                    case 8 || 12 || 136 || 140: {
                        dp[dpIdx] = HqxUtil.mix2To1To1(w[4], w[0], w[1]);
                        dp[dpIdx + 1] = HqxUtil.mix2To1To1(w[4], w[1], w[5]);
                        dp[dpIdx + dpL] = HqxUtil.mix2To1To1(w[4], w[6], w[7]);
                        dp[dpIdx + dpL + 1] = HqxUtil.mix2To1To1(w[4], w[5], w[7]);
                    }
                    case 3 || 35 || 131 || 163: {
                        dp[dpIdx] = HqxUtil.mix3To1(w[4], w[3]);
                        dp[dpIdx + 1] = HqxUtil.mix2To1To1(w[4], w[2], w[5]);
                        dp[dpIdx + dpL] = HqxUtil.mix2To1To1(w[4], w[7], w[3]);
                        dp[dpIdx + dpL + 1] = HqxUtil.mix2To1To1(w[4], w[5], w[7]);
                    }
                    case 6 || 38 || 134 || 166: {
                        dp[dpIdx] = HqxUtil.mix2To1To1(w[4], w[0], w[3]);
                        dp[dpIdx + 1] = HqxUtil.mix3To1(w[4], w[5]);
                        dp[dpIdx + dpL] = HqxUtil.mix2To1To1(w[4], w[7], w[3]);
                        dp[dpIdx + dpL + 1] = HqxUtil.mix2To1To1(w[4], w[5], w[7]);
                    }
                    case 20 || 21 || 52 || 53: {
                        dp[dpIdx] = HqxUtil.mix2To1To1(w[4], w[3], w[1]);
                        dp[dpIdx + 1] = HqxUtil.mix3To1(w[4], w[1]);
                        dp[dpIdx + dpL] = HqxUtil.mix2To1To1(w[4], w[7], w[3]);
                        dp[dpIdx + dpL + 1] = HqxUtil.mix2To1To1(w[4], w[8], w[7]);
                    }
                    case 144 || 145 || 176 || 177: {
                        dp[dpIdx] = HqxUtil.mix2To1To1(w[4], w[3], w[1]);
                        dp[dpIdx + 1] = HqxUtil.mix2To1To1(w[4], w[2], w[1]);
                        dp[dpIdx + dpL] = HqxUtil.mix2To1To1(w[4], w[7], w[3]);
                        dp[dpIdx + dpL + 1] = HqxUtil.mix3To1(w[4], w[7]);
                    }
                    case 192 || 193 || 196 || 197: {
                        dp[dpIdx] = HqxUtil.mix2To1To1(w[4], w[3], w[1]);
                        dp[dpIdx + 1] = HqxUtil.mix2To1To1(w[4], w[1], w[5]);
                        dp[dpIdx + dpL] = HqxUtil.mix2To1To1(w[4], w[6], w[3]);
                        dp[dpIdx + dpL + 1] = HqxUtil.mix3To1(w[4], w[5]);
                    }
                    case 96 || 97 || 100 || 101: {
                        dp[dpIdx] = HqxUtil.mix2To1To1(w[4], w[3], w[1]);
                        dp[dpIdx + 1] = HqxUtil.mix2To1To1(w[4], w[1], w[5]);
                        dp[dpIdx + dpL] = HqxUtil.mix3To1(w[4], w[3]);
                        dp[dpIdx + dpL + 1] = HqxUtil.mix2To1To1(w[4], w[8], w[5]);
                    }
                    case 40 || 44 || 168 || 172: {
                        dp[dpIdx] = HqxUtil.mix2To1To1(w[4], w[0], w[1]);
                        dp[dpIdx + 1] = HqxUtil.mix2To1To1(w[4], w[1], w[5]);
                        dp[dpIdx + dpL] = HqxUtil.mix3To1(w[4], w[7]);
                        dp[dpIdx + dpL + 1] = HqxUtil.mix2To1To1(w[4], w[5], w[7]);
                    }
                    case 9 || 13 || 137 || 141: {
                        dp[dpIdx] = HqxUtil.mix3To1(w[4], w[1]);
                        dp[dpIdx + 1] = HqxUtil.mix2To1To1(w[4], w[1], w[5]);
                        dp[dpIdx + dpL] = HqxUtil.mix2To1To1(w[4], w[6], w[7]);
                        dp[dpIdx + dpL + 1] = HqxUtil.mix2To1To1(w[4], w[5], w[7]);
                    }
                    case 18 || 50: {
                        dp[dpIdx] = HqxUtil.mix2To1To1(w[4], w[0], w[3]);
                        if (HqxUtil.diff(w[1], w[5], trY, trU, trV, trA)) {
                            dp[dpIdx + 1] = HqxUtil.mix3To1(w[4], w[2]);
                        } else {
                            dp[dpIdx + 1] = HqxUtil.mix2To1To1(w[4], w[1], w[5]);
                        }
                        dp[dpIdx + dpL] = HqxUtil.mix2To1To1(w[4], w[7], w[3]);
                        dp[dpIdx + dpL + 1] = HqxUtil.mix2To1To1(w[4], w[8], w[7]);
                    }
                    case 80 || 81: {
                        dp[dpIdx] = HqxUtil.mix2To1To1(w[4], w[3], w[1]);
                        dp[dpIdx + 1] = HqxUtil.mix2To1To1(w[4], w[2], w[1]);
                        dp[dpIdx + dpL] = HqxUtil.mix2To1To1(w[4], w[6], w[3]);
                        if (HqxUtil.diff(w[5], w[7], trY, trU, trV, trA)) {
                            dp[dpIdx + dpL + 1] = HqxUtil.mix3To1(w[4], w[8]);
                        } else {
                            dp[dpIdx + dpL + 1] = HqxUtil.mix2To1To1(w[4], w[5], w[7]);
                        }
                    }
                    case 72 || 76: {
                        dp[dpIdx] = HqxUtil.mix2To1To1(w[4], w[0], w[1]);
                        dp[dpIdx + 1] = HqxUtil.mix2To1To1(w[4], w[1], w[5]);
                        if (HqxUtil.diff(w[7], w[3], trY, trU, trV, trA)) {
                            dp[dpIdx + dpL] = HqxUtil.mix3To1(w[4], w[6]);
                        } else {
                            dp[dpIdx + dpL] = HqxUtil.mix2To1To1(w[4], w[7], w[3]);
                        }
                        dp[dpIdx + dpL + 1] = HqxUtil.mix2To1To1(w[4], w[8], w[5]);
                    }
                    case 10 || 138: {
                        if (HqxUtil.diff(w[3], w[1], trY, trU, trV, trA)) {
                            dp[dpIdx] = HqxUtil.mix3To1(w[4], w[0]);
                        } else {
                            dp[dpIdx] = HqxUtil.mix2To1To1(w[4], w[3], w[1]);
                        }
                        dp[dpIdx + 1] = HqxUtil.mix2To1To1(w[4], w[2], w[5]);
                        dp[dpIdx + dpL] = HqxUtil.mix2To1To1(w[4], w[6], w[7]);
                        dp[dpIdx + dpL + 1] = HqxUtil.mix2To1To1(w[4], w[5], w[7]);
                    }
                    case 66: {
                        dp[dpIdx] = HqxUtil.mix2To1To1(w[4], w[0], w[3]);
                        dp[dpIdx + 1] = HqxUtil.mix2To1To1(w[4], w[2], w[5]);
                        dp[dpIdx + dpL] = HqxUtil.mix2To1To1(w[4], w[6], w[3]);
                        dp[dpIdx + dpL + 1] = HqxUtil.mix2To1To1(w[4], w[8], w[5]);
                    }
                    case 24: {
                        dp[dpIdx] = HqxUtil.mix2To1To1(w[4], w[0], w[1]);
                        dp[dpIdx + 1] = HqxUtil.mix2To1To1(w[4], w[2], w[1]);
                        dp[dpIdx + dpL] = HqxUtil.mix2To1To1(w[4], w[6], w[7]);
                        dp[dpIdx + dpL + 1] = HqxUtil.mix2To1To1(w[4], w[8], w[7]);
                    }
                    case 7 || 39 || 135 || 167: {
                        dp[dpIdx] = HqxUtil.mix3To1(w[4], w[3]);
                        dp[dpIdx + 1] = HqxUtil.mix3To1(w[4], w[5]);
                        dp[dpIdx + dpL] = HqxUtil.mix2To1To1(w[4], w[7], w[3]);
                        dp[dpIdx + dpL + 1] = HqxUtil.mix2To1To1(w[4], w[5], w[7]);
                    }
                    case 148 || 149 || 180 || 181: {
                        dp[dpIdx] = HqxUtil.mix2To1To1(w[4], w[3], w[1]);
                        dp[dpIdx + 1] = HqxUtil.mix3To1(w[4], w[1]);
                        dp[dpIdx + dpL] = HqxUtil.mix2To1To1(w[4], w[7], w[3]);
                        dp[dpIdx + dpL + 1] = HqxUtil.mix3To1(w[4], w[7]);
                    }
                    case 224 || 225 || 228 || 229: {
                        dp[dpIdx] = HqxUtil.mix2To1To1(w[4], w[3], w[1]);
                        dp[dpIdx + 1] = HqxUtil.mix2To1To1(w[4], w[1], w[5]);
                        dp[dpIdx + dpL] = HqxUtil.mix3To1(w[4], w[3]);
                        dp[dpIdx + dpL + 1] = HqxUtil.mix3To1(w[4], w[5]);
                    }
                    case 41 || 45 || 169 || 173: {
                        dp[dpIdx] = HqxUtil.mix3To1(w[4], w[1]);
                        dp[dpIdx + 1] = HqxUtil.mix2To1To1(w[4], w[1], w[5]);
                        dp[dpIdx + dpL] = HqxUtil.mix3To1(w[4], w[7]);
                        dp[dpIdx + dpL + 1] = HqxUtil.mix2To1To1(w[4], w[5], w[7]);
                    }
                    case 22 || 54: {
                        dp[dpIdx] = HqxUtil.mix2To1To1(w[4], w[0], w[3]);
                        if (HqxUtil.diff(w[1], w[5], trY, trU, trV, trA)) {
                            dp[dpIdx + 1] = w[4];
                        } else {
                            dp[dpIdx + 1] = HqxUtil.mix2To1To1(w[4], w[1], w[5]);
                        }
                        dp[dpIdx + dpL] = HqxUtil.mix2To1To1(w[4], w[7], w[3]);
                        dp[dpIdx + dpL + 1] = HqxUtil.mix2To1To1(w[4], w[8], w[7]);
                    }
                    case 208 || 209: {
                        dp[dpIdx] = HqxUtil.mix2To1To1(w[4], w[3], w[1]);
                        dp[dpIdx + 1] = HqxUtil.mix2To1To1(w[4], w[2], w[1]);
                        dp[dpIdx + dpL] = HqxUtil.mix2To1To1(w[4], w[6], w[3]);
                        if (HqxUtil.diff(w[5], w[7], trY, trU, trV, trA)) {
                            dp[dpIdx + dpL + 1] = w[4];
                        } else {
                            dp[dpIdx + dpL + 1] = HqxUtil.mix2To1To1(w[4], w[5], w[7]);
                        }
                    }
                    case 104 || 108: {
                        dp[dpIdx] = HqxUtil.mix2To1To1(w[4], w[0], w[1]);
                        dp[dpIdx + 1] = HqxUtil.mix2To1To1(w[4], w[1], w[5]);
                        if (HqxUtil.diff(w[7], w[3], trY, trU, trV, trA)) {
                            dp[dpIdx + dpL] = w[4];
                        } else {
                            dp[dpIdx + dpL] = HqxUtil.mix2To1To1(w[4], w[7], w[3]);
                        }
                        dp[dpIdx + dpL + 1] = HqxUtil.mix2To1To1(w[4], w[8], w[5]);
                    }
                    case 11 || 139: {
                        if (HqxUtil.diff(w[3], w[1], trY, trU, trV, trA)) {
                            dp[dpIdx] = w[4];
                        } else {
                            dp[dpIdx] = HqxUtil.mix2To1To1(w[4], w[3], w[1]);
                        }
                        dp[dpIdx + 1] = HqxUtil.mix2To1To1(w[4], w[2], w[5]);
                        dp[dpIdx + dpL] = HqxUtil.mix2To1To1(w[4], w[6], w[7]);
                        dp[dpIdx + dpL + 1] = HqxUtil.mix2To1To1(w[4], w[5], w[7]);
                    }
                    case 19 || 51: {
                        if (HqxUtil.diff(w[1], w[5], trY, trU, trV, trA)) {
                            dp[dpIdx] = HqxUtil.mix3To1(w[4], w[3]);
                            dp[dpIdx + 1] = HqxUtil.mix3To1(w[4], w[2]);
                        } else {
                            dp[dpIdx] = HqxUtil.mix4To2To1(w[4], w[1], w[3]);
                            dp[dpIdx + 1] = HqxUtil.mix2To3To3(w[4], w[1], w[5]);
                        }
                        dp[dpIdx + dpL] = HqxUtil.mix2To1To1(w[4], w[7], w[3]);
                        dp[dpIdx + dpL + 1] = HqxUtil.mix2To1To1(w[4], w[8], w[7]);
                    }
                    case 146 || 178: {
                        dp[dpIdx] = HqxUtil.mix2To1To1(w[4], w[0], w[3]);
                        if (HqxUtil.diff(w[1], w[5], trY, trU, trV, trA)) {
                            dp[dpIdx + 1] = HqxUtil.mix3To1(w[4], w[2]);
                            dp[dpIdx + dpL + 1] = HqxUtil.mix3To1(w[4], w[7]);
                        } else {
                            dp[dpIdx + 1] = HqxUtil.mix2To3To3(w[4], w[1], w[5]);
                            dp[dpIdx + dpL + 1] = HqxUtil.mix4To2To1(w[4], w[5], w[7]);
                        }
                        dp[dpIdx + dpL] = HqxUtil.mix2To1To1(w[4], w[7], w[3]);
                    }
                    case 84 || 85: {
                        dp[dpIdx] = HqxUtil.mix2To1To1(w[4], w[3], w[1]);
                        if (HqxUtil.diff(w[5], w[7], trY, trU, trV, trA)) {
                            dp[dpIdx + 1] = HqxUtil.mix3To1(w[4], w[1]);
                            dp[dpIdx + dpL + 1] = HqxUtil.mix3To1(w[4], w[8]);
                        } else {
                            dp[dpIdx + 1] = HqxUtil.mix4To2To1(w[4], w[5], w[1]);
                            dp[dpIdx + dpL + 1] = HqxUtil.mix2To3To3(w[4], w[5], w[7]);
                        }
                        dp[dpIdx + dpL] = HqxUtil.mix2To1To1(w[4], w[6], w[3]);
                    }
                    case 112 || 113: {
                        dp[dpIdx] = HqxUtil.mix2To1To1(w[4], w[3], w[1]);
                        dp[dpIdx + 1] = HqxUtil.mix2To1To1(w[4], w[2], w[1]);
                        if (HqxUtil.diff(w[5], w[7], trY, trU, trV, trA)) {
                            dp[dpIdx + dpL] = HqxUtil.mix3To1(w[4], w[3]);
                            dp[dpIdx + dpL + 1] = HqxUtil.mix3To1(w[4], w[8]);
                        } else {
                            dp[dpIdx + dpL] = HqxUtil.mix4To2To1(w[4], w[7], w[3]);
                            dp[dpIdx + dpL + 1] = HqxUtil.mix2To3To3(w[4], w[5], w[7]);
                        }
                    }
                    case 200 || 204: {
                        dp[dpIdx] = HqxUtil.mix2To1To1(w[4], w[0], w[1]);
                        dp[dpIdx + 1] = HqxUtil.mix2To1To1(w[4], w[1], w[5]);
                        if (HqxUtil.diff(w[7], w[3], trY, trU, trV, trA)) {
                            dp[dpIdx + dpL] = HqxUtil.mix3To1(w[4], w[6]);
                            dp[dpIdx + dpL + 1] = HqxUtil.mix3To1(w[4], w[5]);
                        } else {
                            dp[dpIdx + dpL] = HqxUtil.mix2To3To3(w[4], w[7], w[3]);
                            dp[dpIdx + dpL + 1] = HqxUtil.mix4To2To1(w[4], w[7], w[5]);
                        }
                    }
                    case 73 || 77: {
                        if (HqxUtil.diff(w[7], w[3], trY, trU, trV, trA)) {
                            dp[dpIdx] = HqxUtil.mix3To1(w[4], w[1]);
                            dp[dpIdx + dpL] = HqxUtil.mix3To1(w[4], w[6]);
                        } else {
                            dp[dpIdx] = HqxUtil.mix4To2To1(w[4], w[3], w[1]);
                            dp[dpIdx + dpL] = HqxUtil.mix2To3To3(w[4], w[7], w[3]);
                        }
                        dp[dpIdx + 1] = HqxUtil.mix2To1To1(w[4], w[1], w[5]);
                        dp[dpIdx + dpL + 1] = HqxUtil.mix2To1To1(w[4], w[8], w[5]);
                    }
                    case 42 || 170: {
                        if (HqxUtil.diff(w[3], w[1], trY, trU, trV, trA)) {
                            dp[dpIdx] = HqxUtil.mix3To1(w[4], w[0]);
                            dp[dpIdx + dpL] = HqxUtil.mix3To1(w[4], w[7]);
                        } else {
                            dp[dpIdx] = HqxUtil.mix2To3To3(w[4], w[3], w[1]);
                            dp[dpIdx + dpL] = HqxUtil.mix4To2To1(w[4], w[3], w[7]);
                        }
                        dp[dpIdx + 1] = HqxUtil.mix2To1To1(w[4], w[2], w[5]);
                        dp[dpIdx + dpL + 1] = HqxUtil.mix2To1To1(w[4], w[5], w[7]);
                    }
                    case 14 || 142: {
                        if (HqxUtil.diff(w[3], w[1], trY, trU, trV, trA)) {
                            dp[dpIdx] = HqxUtil.mix3To1(w[4], w[0]);
                            dp[dpIdx + 1] = HqxUtil.mix3To1(w[4], w[5]);
                        } else {
                            dp[dpIdx] = HqxUtil.mix2To3To3(w[4], w[3], w[1]);
                            dp[dpIdx + 1] = HqxUtil.mix4To2To1(w[4], w[1], w[5]);
                        }
                        dp[dpIdx + dpL] = HqxUtil.mix2To1To1(w[4], w[6], w[7]);
                        dp[dpIdx + dpL + 1] = HqxUtil.mix2To1To1(w[4], w[5], w[7]);
                    }
                    case 67: {
                        dp[dpIdx] = HqxUtil.mix3To1(w[4], w[3]);
                        dp[dpIdx + 1] = HqxUtil.mix2To1To1(w[4], w[2], w[5]);
                        dp[dpIdx + dpL] = HqxUtil.mix2To1To1(w[4], w[6], w[3]);
                        dp[dpIdx + dpL + 1] = HqxUtil.mix2To1To1(w[4], w[8], w[5]);
                    }
                    case 70: {
                        dp[dpIdx] = HqxUtil.mix2To1To1(w[4], w[0], w[3]);
                        dp[dpIdx + 1] = HqxUtil.mix3To1(w[4], w[5]);
                        dp[dpIdx + dpL] = HqxUtil.mix2To1To1(w[4], w[6], w[3]);
                        dp[dpIdx + dpL + 1] = HqxUtil.mix2To1To1(w[4], w[8], w[5]);
                    }
                    case 28: {
                        dp[dpIdx] = HqxUtil.mix2To1To1(w[4], w[0], w[1]);
                        dp[dpIdx + 1] = HqxUtil.mix3To1(w[4], w[1]);
                        dp[dpIdx + dpL] = HqxUtil.mix2To1To1(w[4], w[6], w[7]);
                        dp[dpIdx + dpL + 1] = HqxUtil.mix2To1To1(w[4], w[8], w[7]);
                    }
                    case 152: {
                        dp[dpIdx] = HqxUtil.mix2To1To1(w[4], w[0], w[1]);
                        dp[dpIdx + 1] = HqxUtil.mix2To1To1(w[4], w[2], w[1]);
                        dp[dpIdx + dpL] = HqxUtil.mix2To1To1(w[4], w[6], w[7]);
                        dp[dpIdx + dpL + 1] = HqxUtil.mix3To1(w[4], w[7]);
                    }
                    case 194: {
                        dp[dpIdx] = HqxUtil.mix2To1To1(w[4], w[0], w[3]);
                        dp[dpIdx + 1] = HqxUtil.mix2To1To1(w[4], w[2], w[5]);
                        dp[dpIdx + dpL] = HqxUtil.mix2To1To1(w[4], w[6], w[3]);
                        dp[dpIdx + dpL + 1] = HqxUtil.mix3To1(w[4], w[5]);
                    }
                    case 98: {
                        dp[dpIdx] = HqxUtil.mix2To1To1(w[4], w[0], w[3]);
                        dp[dpIdx + 1] = HqxUtil.mix2To1To1(w[4], w[2], w[5]);
                        dp[dpIdx + dpL] = HqxUtil.mix3To1(w[4], w[3]);
                        dp[dpIdx + dpL + 1] = HqxUtil.mix2To1To1(w[4], w[8], w[5]);
                    }
                    case 56: {
                        dp[dpIdx] = HqxUtil.mix2To1To1(w[4], w[0], w[1]);
                        dp[dpIdx + 1] = HqxUtil.mix2To1To1(w[4], w[2], w[1]);
                        dp[dpIdx + dpL] = HqxUtil.mix3To1(w[4], w[7]);
                        dp[dpIdx + dpL + 1] = HqxUtil.mix2To1To1(w[4], w[8], w[7]);
                    }
                    case 25: {
                        dp[dpIdx] = HqxUtil.mix3To1(w[4], w[1]);
                        dp[dpIdx + 1] = HqxUtil.mix2To1To1(w[4], w[2], w[1]);
                        dp[dpIdx + dpL] = HqxUtil.mix2To1To1(w[4], w[6], w[7]);
                        dp[dpIdx + dpL + 1] = HqxUtil.mix2To1To1(w[4], w[8], w[7]);
                    }
                    case 26 || 31: {
                        if (HqxUtil.diff(w[3], w[1], trY, trU, trV, trA)) {
                            dp[dpIdx] = w[4];
                        } else {
                            dp[dpIdx] = HqxUtil.mix2To1To1(w[4], w[3], w[1]);
                        }
                        if (HqxUtil.diff(w[1], w[5], trY, trU, trV, trA)) {
                            dp[dpIdx + 1] = w[4];
                        } else {
                            dp[dpIdx + 1] = HqxUtil.mix2To1To1(w[4], w[1], w[5]);
                        }
                        dp[dpIdx + dpL] = HqxUtil.mix2To1To1(w[4], w[6], w[7]);
                        dp[dpIdx + dpL + 1] = HqxUtil.mix2To1To1(w[4], w[8], w[7]);
                    }
                    case 82 || 214: {
                        dp[dpIdx] = HqxUtil.mix2To1To1(w[4], w[0], w[3]);
                        if (HqxUtil.diff(w[1], w[5], trY, trU, trV, trA)) {
                            dp[dpIdx + 1] = w[4];
                        } else {
                            dp[dpIdx + 1] = HqxUtil.mix2To1To1(w[4], w[1], w[5]);
                        }
                        dp[dpIdx + dpL] = HqxUtil.mix2To1To1(w[4], w[6], w[3]);
                        if (HqxUtil.diff(w[5], w[7], trY, trU, trV, trA)) {
                            dp[dpIdx + dpL + 1] = w[4];
                        } else {
                            dp[dpIdx + dpL + 1] = HqxUtil.mix2To1To1(w[4], w[5], w[7]);
                        }
                    }
                    case 88 || 248: {
                        dp[dpIdx] = HqxUtil.mix2To1To1(w[4], w[0], w[1]);
                        dp[dpIdx + 1] = HqxUtil.mix2To1To1(w[4], w[2], w[1]);
                        if (HqxUtil.diff(w[7], w[3], trY, trU, trV, trA)) {
                            dp[dpIdx + dpL] = w[4];
                        } else {
                            dp[dpIdx + dpL] = HqxUtil.mix2To1To1(w[4], w[7], w[3]);
                        }
                        if (HqxUtil.diff(w[5], w[7], trY, trU, trV, trA)) {
                            dp[dpIdx + dpL + 1] = w[4];
                        } else {
                            dp[dpIdx + dpL + 1] = HqxUtil.mix2To1To1(w[4], w[5], w[7]);
                        }
                    }
                    case 74 || 107: {
                        if (HqxUtil.diff(w[3], w[1], trY, trU, trV, trA)) {
                            dp[dpIdx] = w[4];
                        } else {
                            dp[dpIdx] = HqxUtil.mix2To1To1(w[4], w[3], w[1]);
                        }
                        dp[dpIdx + 1] = HqxUtil.mix2To1To1(w[4], w[2], w[5]);
                        if (HqxUtil.diff(w[7], w[3], trY, trU, trV, trA)) {
                            dp[dpIdx + dpL] = w[4];
                        } else {
                            dp[dpIdx + dpL] = HqxUtil.mix2To1To1(w[4], w[7], w[3]);
                        }
                        dp[dpIdx + dpL + 1] = HqxUtil.mix2To1To1(w[4], w[8], w[5]);
                    }
                    case 27: {
                        if (HqxUtil.diff(w[3], w[1], trY, trU, trV, trA)) {
                            dp[dpIdx] = w[4];
                        } else {
                            dp[dpIdx] = HqxUtil.mix2To1To1(w[4], w[3], w[1]);
                        }
                        dp[dpIdx + 1] = HqxUtil.mix3To1(w[4], w[2]);
                        dp[dpIdx + dpL] = HqxUtil.mix2To1To1(w[4], w[6], w[7]);
                        dp[dpIdx + dpL + 1] = HqxUtil.mix2To1To1(w[4], w[8], w[7]);
                    }
                    case 86: {
                        dp[dpIdx] = HqxUtil.mix2To1To1(w[4], w[0], w[3]);
                        if (HqxUtil.diff(w[1], w[5], trY, trU, trV, trA)) {
                            dp[dpIdx + 1] = w[4];
                        } else {
                            dp[dpIdx + 1] = HqxUtil.mix2To1To1(w[4], w[1], w[5]);
                        }
                        dp[dpIdx + dpL] = HqxUtil.mix2To1To1(w[4], w[6], w[3]);
                        dp[dpIdx + dpL + 1] = HqxUtil.mix3To1(w[4], w[8]);
                    }
                    case 216: {
                        dp[dpIdx] = HqxUtil.mix2To1To1(w[4], w[0], w[1]);
                        dp[dpIdx + 1] = HqxUtil.mix2To1To1(w[4], w[2], w[1]);
                        dp[dpIdx + dpL] = HqxUtil.mix3To1(w[4], w[6]);
                        if (HqxUtil.diff(w[5], w[7], trY, trU, trV, trA)) {
                            dp[dpIdx + dpL + 1] = w[4];
                        } else {
                            dp[dpIdx + dpL + 1] = HqxUtil.mix2To1To1(w[4], w[5], w[7]);
                        }
                    }
                    case 106: {
                        dp[dpIdx] = HqxUtil.mix3To1(w[4], w[0]);
                        dp[dpIdx + 1] = HqxUtil.mix2To1To1(w[4], w[2], w[5]);
                        if (HqxUtil.diff(w[7], w[3], trY, trU, trV, trA)) {
                            dp[dpIdx + dpL] = w[4];
                        } else {
                            dp[dpIdx + dpL] = HqxUtil.mix2To1To1(w[4], w[7], w[3]);
                        }
                        dp[dpIdx + dpL + 1] = HqxUtil.mix2To1To1(w[4], w[8], w[5]);
                    }
                    case 30: {
                        dp[dpIdx] = HqxUtil.mix3To1(w[4], w[0]);
                        if (HqxUtil.diff(w[1], w[5], trY, trU, trV, trA)) {
                            dp[dpIdx + 1] = w[4];
                        } else {
                            dp[dpIdx + 1] = HqxUtil.mix2To1To1(w[4], w[1], w[5]);
                        }
                        dp[dpIdx + dpL] = HqxUtil.mix2To1To1(w[4], w[6], w[7]);
                        dp[dpIdx + dpL + 1] = HqxUtil.mix2To1To1(w[4], w[8], w[7]);
                    }
                    case 210: {
                        dp[dpIdx] = HqxUtil.mix2To1To1(w[4], w[0], w[3]);
                        dp[dpIdx + 1] = HqxUtil.mix3To1(w[4], w[2]);
                        dp[dpIdx + dpL] = HqxUtil.mix2To1To1(w[4], w[6], w[3]);
                        if (HqxUtil.diff(w[5], w[7], trY, trU, trV, trA)) {
                            dp[dpIdx + dpL + 1] = w[4];
                        } else {
                            dp[dpIdx + dpL + 1] = HqxUtil.mix2To1To1(w[4], w[5], w[7]);
                        }
                    }
                    case 120: {
                        dp[dpIdx] = HqxUtil.mix2To1To1(w[4], w[0], w[1]);
                        dp[dpIdx + 1] = HqxUtil.mix2To1To1(w[4], w[2], w[1]);
                        if (HqxUtil.diff(w[7], w[3], trY, trU, trV, trA)) {
                            dp[dpIdx + dpL] = w[4];
                        } else {
                            dp[dpIdx + dpL] = HqxUtil.mix2To1To1(w[4], w[7], w[3]);
                        }
                        dp[dpIdx + dpL + 1] = HqxUtil.mix3To1(w[4], w[8]);
                    }
                    case 75: {
                        if (HqxUtil.diff(w[3], w[1], trY, trU, trV, trA)) {
                            dp[dpIdx] = w[4];
                        } else {
                            dp[dpIdx] = HqxUtil.mix2To1To1(w[4], w[3], w[1]);
                        }
                        dp[dpIdx + 1] = HqxUtil.mix2To1To1(w[4], w[2], w[5]);
                        dp[dpIdx + dpL] = HqxUtil.mix3To1(w[4], w[6]);
                        dp[dpIdx + dpL + 1] = HqxUtil.mix2To1To1(w[4], w[8], w[5]);
                    }
                    case 29: {
                        dp[dpIdx] = HqxUtil.mix3To1(w[4], w[1]);
                        dp[dpIdx + 1] = HqxUtil.mix3To1(w[4], w[1]);
                        dp[dpIdx + dpL] = HqxUtil.mix2To1To1(w[4], w[6], w[7]);
                        dp[dpIdx + dpL + 1] = HqxUtil.mix2To1To1(w[4], w[8], w[7]);
                    }
                    case 198: {
                        dp[dpIdx] = HqxUtil.mix2To1To1(w[4], w[0], w[3]);
                        dp[dpIdx + 1] = HqxUtil.mix3To1(w[4], w[5]);
                        dp[dpIdx + dpL] = HqxUtil.mix2To1To1(w[4], w[6], w[3]);
                        dp[dpIdx + dpL + 1] = HqxUtil.mix3To1(w[4], w[5]);
                    }
                    case 184: {
                        dp[dpIdx] = HqxUtil.mix2To1To1(w[4], w[0], w[1]);
                        dp[dpIdx + 1] = HqxUtil.mix2To1To1(w[4], w[2], w[1]);
                        dp[dpIdx + dpL] = HqxUtil.mix3To1(w[4], w[7]);
                        dp[dpIdx + dpL + 1] = HqxUtil.mix3To1(w[4], w[7]);
                    }
                    case 99: {
                        dp[dpIdx] = HqxUtil.mix3To1(w[4], w[3]);
                        dp[dpIdx + 1] = HqxUtil.mix2To1To1(w[4], w[2], w[5]);
                        dp[dpIdx + dpL] = HqxUtil.mix3To1(w[4], w[3]);
                        dp[dpIdx + dpL + 1] = HqxUtil.mix2To1To1(w[4], w[8], w[5]);
                    }
                    case 57: {
                        dp[dpIdx] = HqxUtil.mix3To1(w[4], w[1]);
                        dp[dpIdx + 1] = HqxUtil.mix2To1To1(w[4], w[2], w[1]);
                        dp[dpIdx + dpL] = HqxUtil.mix3To1(w[4], w[7]);
                        dp[dpIdx + dpL + 1] = HqxUtil.mix2To1To1(w[4], w[8], w[7]);
                    }
                    case 71: {
                        dp[dpIdx] = HqxUtil.mix3To1(w[4], w[3]);
                        dp[dpIdx + 1] = HqxUtil.mix3To1(w[4], w[5]);
                        dp[dpIdx + dpL] = HqxUtil.mix2To1To1(w[4], w[6], w[3]);
                        dp[dpIdx + dpL + 1] = HqxUtil.mix2To1To1(w[4], w[8], w[5]);
                    }
                    case 156: {
                        dp[dpIdx] = HqxUtil.mix2To1To1(w[4], w[0], w[1]);
                        dp[dpIdx + 1] = HqxUtil.mix3To1(w[4], w[1]);
                        dp[dpIdx + dpL] = HqxUtil.mix2To1To1(w[4], w[6], w[7]);
                        dp[dpIdx + dpL + 1] = HqxUtil.mix3To1(w[4], w[7]);
                    }
                    case 226: {
                        dp[dpIdx] = HqxUtil.mix2To1To1(w[4], w[0], w[3]);
                        dp[dpIdx + 1] = HqxUtil.mix2To1To1(w[4], w[2], w[5]);
                        dp[dpIdx + dpL] = HqxUtil.mix3To1(w[4], w[3]);
                        dp[dpIdx + dpL + 1] = HqxUtil.mix3To1(w[4], w[5]);
                    }
                    case 60: {
                        dp[dpIdx] = HqxUtil.mix2To1To1(w[4], w[0], w[1]);
                        dp[dpIdx + 1] = HqxUtil.mix3To1(w[4], w[1]);
                        dp[dpIdx + dpL] = HqxUtil.mix3To1(w[4], w[7]);
                        dp[dpIdx + dpL + 1] = HqxUtil.mix2To1To1(w[4], w[8], w[7]);
                    }
                    case 195: {
                        dp[dpIdx] = HqxUtil.mix3To1(w[4], w[3]);
                        dp[dpIdx + 1] = HqxUtil.mix2To1To1(w[4], w[2], w[5]);
                        dp[dpIdx + dpL] = HqxUtil.mix2To1To1(w[4], w[6], w[3]);
                        dp[dpIdx + dpL + 1] = HqxUtil.mix3To1(w[4], w[5]);
                    }
                    case 102: {
                        dp[dpIdx] = HqxUtil.mix2To1To1(w[4], w[0], w[3]);
                        dp[dpIdx + 1] = HqxUtil.mix3To1(w[4], w[5]);
                        dp[dpIdx + dpL] = HqxUtil.mix3To1(w[4], w[3]);
                        dp[dpIdx + dpL + 1] = HqxUtil.mix2To1To1(w[4], w[8], w[5]);
                    }
                    case 153: {
                        dp[dpIdx] = HqxUtil.mix3To1(w[4], w[1]);
                        dp[dpIdx + 1] = HqxUtil.mix2To1To1(w[4], w[2], w[1]);
                        dp[dpIdx + dpL] = HqxUtil.mix2To1To1(w[4], w[6], w[7]);
                        dp[dpIdx + dpL + 1] = HqxUtil.mix3To1(w[4], w[7]);
                    }
                    case 58: {
                        if (HqxUtil.diff(w[3], w[1], trY, trU, trV, trA)) {
                            dp[dpIdx] = HqxUtil.mix3To1(w[4], w[0]);
                        } else {
                            dp[dpIdx] = HqxUtil.mix6To1To1(w[4], w[3], w[1]);
                        }
                        if (HqxUtil.diff(w[1], w[5], trY, trU, trV, trA)) {
                            dp[dpIdx + 1] = HqxUtil.mix3To1(w[4], w[2]);
                        } else {
                            dp[dpIdx + 1] = HqxUtil.mix6To1To1(w[4], w[1], w[5]);
                        }
                        dp[dpIdx + dpL] = HqxUtil.mix3To1(w[4], w[7]);
                        dp[dpIdx + dpL + 1] = HqxUtil.mix2To1To1(w[4], w[8], w[7]);
                    }
                    case 83: {
                        dp[dpIdx] = HqxUtil.mix3To1(w[4], w[3]);
                        if (HqxUtil.diff(w[1], w[5], trY, trU, trV, trA)) {
                            dp[dpIdx + 1] = HqxUtil.mix3To1(w[4], w[2]);
                        } else {
                            dp[dpIdx + 1] = HqxUtil.mix6To1To1(w[4], w[1], w[5]);
                        }
                        dp[dpIdx + dpL] = HqxUtil.mix2To1To1(w[4], w[6], w[3]);
                        if (HqxUtil.diff(w[5], w[7], trY, trU, trV, trA)) {
                            dp[dpIdx + dpL + 1] = HqxUtil.mix3To1(w[4], w[8]);
                        } else {
                            dp[dpIdx + dpL + 1] = HqxUtil.mix6To1To1(w[4], w[5], w[7]);
                        }
                    }
                    case 92: {
                        dp[dpIdx] = HqxUtil.mix2To1To1(w[4], w[0], w[1]);
                        dp[dpIdx + 1] = HqxUtil.mix3To1(w[4], w[1]);
                        if (HqxUtil.diff(w[7], w[3], trY, trU, trV, trA)) {
                            dp[dpIdx + dpL] = HqxUtil.mix3To1(w[4], w[6]);
                        } else {
                            dp[dpIdx + dpL] = HqxUtil.mix6To1To1(w[4], w[7], w[3]);
                        }
                        if (HqxUtil.diff(w[5], w[7], trY, trU, trV, trA)) {
                            dp[dpIdx + dpL + 1] = HqxUtil.mix3To1(w[4], w[8]);
                        } else {
                            dp[dpIdx + dpL + 1] = HqxUtil.mix6To1To1(w[4], w[5], w[7]);
                        }
                    }
                    case 202: {
                        if (HqxUtil.diff(w[3], w[1], trY, trU, trV, trA)) {
                            dp[dpIdx] = HqxUtil.mix3To1(w[4], w[0]);
                        } else {
                            dp[dpIdx] = HqxUtil.mix6To1To1(w[4], w[3], w[1]);
                        }
                        dp[dpIdx + 1] = HqxUtil.mix2To1To1(w[4], w[2], w[5]);
                        if (HqxUtil.diff(w[7], w[3], trY, trU, trV, trA)) {
                            dp[dpIdx + dpL] = HqxUtil.mix3To1(w[4], w[6]);
                        } else {
                            dp[dpIdx + dpL] = HqxUtil.mix6To1To1(w[4], w[7], w[3]);
                        }
                        dp[dpIdx + dpL + 1] = HqxUtil.mix3To1(w[4], w[5]);
                    }
                    case 78: {
                        if (HqxUtil.diff(w[3], w[1], trY, trU, trV, trA)) {
                            dp[dpIdx] = HqxUtil.mix3To1(w[4], w[0]);
                        } else {
                            dp[dpIdx] = HqxUtil.mix6To1To1(w[4], w[3], w[1]);
                        }
                        dp[dpIdx + 1] = HqxUtil.mix3To1(w[4], w[5]);
                        if (HqxUtil.diff(w[7], w[3], trY, trU, trV, trA)) {
                            dp[dpIdx + dpL] = HqxUtil.mix3To1(w[4], w[6]);
                        } else {
                            dp[dpIdx + dpL] = HqxUtil.mix6To1To1(w[4], w[7], w[3]);
                        }
                        dp[dpIdx + dpL + 1] = HqxUtil.mix2To1To1(w[4], w[8], w[5]);
                    }
                    case 154: {
                        if (HqxUtil.diff(w[3], w[1], trY, trU, trV, trA)) {
                            dp[dpIdx] = HqxUtil.mix3To1(w[4], w[0]);
                        } else {
                            dp[dpIdx] = HqxUtil.mix6To1To1(w[4], w[3], w[1]);
                        }
                        if (HqxUtil.diff(w[1], w[5], trY, trU, trV, trA)) {
                            dp[dpIdx + 1] = HqxUtil.mix3To1(w[4], w[2]);
                        } else {
                            dp[dpIdx + 1] = HqxUtil.mix6To1To1(w[4], w[1], w[5]);
                        }
                        dp[dpIdx + dpL] = HqxUtil.mix2To1To1(w[4], w[6], w[7]);
                        dp[dpIdx + dpL + 1] = HqxUtil.mix3To1(w[4], w[7]);
                    }
                    case 114: {
                        dp[dpIdx] = HqxUtil.mix2To1To1(w[4], w[0], w[3]);
                        if (HqxUtil.diff(w[1], w[5], trY, trU, trV, trA)) {
                            dp[dpIdx + 1] = HqxUtil.mix3To1(w[4], w[2]);
                        } else {
                            dp[dpIdx + 1] = HqxUtil.mix6To1To1(w[4], w[1], w[5]);
                        }
                        dp[dpIdx + dpL] = HqxUtil.mix3To1(w[4], w[3]);
                        if (HqxUtil.diff(w[5], w[7], trY, trU, trV, trA)) {
                            dp[dpIdx + dpL + 1] = HqxUtil.mix3To1(w[4], w[8]);
                        } else {
                            dp[dpIdx + dpL + 1] = HqxUtil.mix6To1To1(w[4], w[5], w[7]);
                        }
                    }
                    case 89: {
                        dp[dpIdx] = HqxUtil.mix3To1(w[4], w[1]);
                        dp[dpIdx + 1] = HqxUtil.mix2To1To1(w[4], w[2], w[1]);
                        if (HqxUtil.diff(w[7], w[3], trY, trU, trV, trA)) {
                            dp[dpIdx + dpL] = HqxUtil.mix3To1(w[4], w[6]);
                        } else {
                            dp[dpIdx + dpL] = HqxUtil.mix6To1To1(w[4], w[7], w[3]);
                        }
                        if (HqxUtil.diff(w[5], w[7], trY, trU, trV, trA)) {
                            dp[dpIdx + dpL + 1] = HqxUtil.mix3To1(w[4], w[8]);
                        } else {
                            dp[dpIdx + dpL + 1] = HqxUtil.mix6To1To1(w[4], w[5], w[7]);
                        }
                    }
                    case 90: {
                        if (HqxUtil.diff(w[3], w[1], trY, trU, trV, trA)) {
                            dp[dpIdx] = HqxUtil.mix3To1(w[4], w[0]);
                        } else {
                            dp[dpIdx] = HqxUtil.mix6To1To1(w[4], w[3], w[1]);
                        }
                        if (HqxUtil.diff(w[1], w[5], trY, trU, trV, trA)) {
                            dp[dpIdx + 1] = HqxUtil.mix3To1(w[4], w[2]);
                        } else {
                            dp[dpIdx + 1] = HqxUtil.mix6To1To1(w[4], w[1], w[5]);
                        }
                        if (HqxUtil.diff(w[7], w[3], trY, trU, trV, trA)) {
                            dp[dpIdx + dpL] = HqxUtil.mix3To1(w[4], w[6]);
                        } else {
                            dp[dpIdx + dpL] = HqxUtil.mix6To1To1(w[4], w[7], w[3]);
                        }
                        if (HqxUtil.diff(w[5], w[7], trY, trU, trV, trA)) {
                            dp[dpIdx + dpL + 1] = HqxUtil.mix3To1(w[4], w[8]);
                        } else {
                            dp[dpIdx + dpL + 1] = HqxUtil.mix6To1To1(w[4], w[5], w[7]);
                        }
                    }
                    case 23 || 55: {
                        if (HqxUtil.diff(w[1], w[5], trY, trU, trV, trA)) {
                            dp[dpIdx] = HqxUtil.mix3To1(w[4], w[3]);
                            dp[dpIdx + 1] = w[4];
                        } else {
                            dp[dpIdx] = HqxUtil.mix4To2To1(w[4], w[1], w[3]);
                            dp[dpIdx + 1] = HqxUtil.mix2To3To3(w[4], w[1], w[5]);
                        }
                        dp[dpIdx + dpL] = HqxUtil.mix2To1To1(w[4], w[7], w[3]);
                        dp[dpIdx + dpL + 1] = HqxUtil.mix2To1To1(w[4], w[8], w[7]);
                    }
                    case 150 || 182: {
                        dp[dpIdx] = HqxUtil.mix2To1To1(w[4], w[0], w[3]);
                        if (HqxUtil.diff(w[1], w[5], trY, trU, trV, trA)) {
                            dp[dpIdx + 1] = w[4];
                            dp[dpIdx + dpL + 1] = HqxUtil.mix3To1(w[4], w[7]);
                        } else {
                            dp[dpIdx + 1] = HqxUtil.mix2To3To3(w[4], w[1], w[5]);
                            dp[dpIdx + dpL + 1] = HqxUtil.mix4To2To1(w[4], w[5], w[7]);
                        }
                        dp[dpIdx + dpL] = HqxUtil.mix2To1To1(w[4], w[7], w[3]);
                    }
                    case 212 || 213: {
                        dp[dpIdx] = HqxUtil.mix2To1To1(w[4], w[3], w[1]);
                        if (HqxUtil.diff(w[5], w[7], trY, trU, trV, trA)) {
                            dp[dpIdx + 1] = HqxUtil.mix3To1(w[4], w[1]);
                            dp[dpIdx + dpL + 1] = w[4];
                        } else {
                            dp[dpIdx + 1] = HqxUtil.mix4To2To1(w[4], w[5], w[1]);
                            dp[dpIdx + dpL + 1] = HqxUtil.mix2To3To3(w[4], w[5], w[7]);
                        }
                        dp[dpIdx + dpL] = HqxUtil.mix2To1To1(w[4], w[6], w[3]);
                    }
                    case 240 || 241: {
                        dp[dpIdx] = HqxUtil.mix2To1To1(w[4], w[3], w[1]);
                        dp[dpIdx + 1] = HqxUtil.mix2To1To1(w[4], w[2], w[1]);
                        if (HqxUtil.diff(w[5], w[7], trY, trU, trV, trA)) {
                            dp[dpIdx + dpL] = HqxUtil.mix3To1(w[4], w[3]);
                            dp[dpIdx + dpL + 1] = w[4];
                        } else {
                            dp[dpIdx + dpL] = HqxUtil.mix4To2To1(w[4], w[7], w[3]);
                            dp[dpIdx + dpL + 1] = HqxUtil.mix2To3To3(w[4], w[5], w[7]);
                        }
                    }
                    case 232 || 236: {
                        dp[dpIdx] = HqxUtil.mix2To1To1(w[4], w[0], w[1]);
                        dp[dpIdx + 1] = HqxUtil.mix2To1To1(w[4], w[1], w[5]);
                        if (HqxUtil.diff(w[7], w[3], trY, trU, trV, trA)) {
                            dp[dpIdx + dpL] = w[4];
                            dp[dpIdx + dpL + 1] = HqxUtil.mix3To1(w[4], w[5]);
                        } else {
                            dp[dpIdx + dpL] = HqxUtil.mix2To3To3(w[4], w[7], w[3]);
                            dp[dpIdx + dpL + 1] = HqxUtil.mix4To2To1(w[4], w[7], w[5]);
                        }
                    }
                    case 105 || 109: {
                        if (HqxUtil.diff(w[7], w[3], trY, trU, trV, trA)) {
                            dp[dpIdx] = HqxUtil.mix3To1(w[4], w[1]);
                            dp[dpIdx + dpL] = w[4];
                        } else {
                            dp[dpIdx] = HqxUtil.mix4To2To1(w[4], w[3], w[1]);
                            dp[dpIdx + dpL] = HqxUtil.mix2To3To3(w[4], w[7], w[3]);
                        }
                        dp[dpIdx + 1] = HqxUtil.mix2To1To1(w[4], w[1], w[5]);
                        dp[dpIdx + dpL + 1] = HqxUtil.mix2To1To1(w[4], w[8], w[5]);
                    }
                    case 43 || 171: {
                        if (HqxUtil.diff(w[3], w[1], trY, trU, trV, trA)) {
                            dp[dpIdx] = w[4];
                            dp[dpIdx + dpL] = HqxUtil.mix3To1(w[4], w[7]);
                        } else {
                            dp[dpIdx] = HqxUtil.mix2To3To3(w[4], w[3], w[1]);
                            dp[dpIdx + dpL] = HqxUtil.mix4To2To1(w[4], w[3], w[7]);
                        }
                        dp[dpIdx + 1] = HqxUtil.mix2To1To1(w[4], w[2], w[5]);
                        dp[dpIdx + dpL + 1] = HqxUtil.mix2To1To1(w[4], w[5], w[7]);
                    }
                    case 15 || 143: {
                        if (HqxUtil.diff(w[3], w[1], trY, trU, trV, trA)) {
                            dp[dpIdx] = w[4];
                            dp[dpIdx + 1] = HqxUtil.mix3To1(w[4], w[5]);
                        } else {
                            dp[dpIdx] = HqxUtil.mix2To3To3(w[4], w[3], w[1]);
                            dp[dpIdx + 1] = HqxUtil.mix4To2To1(w[4], w[1], w[5]);
                        }
                        dp[dpIdx + dpL] = HqxUtil.mix2To1To1(w[4], w[6], w[7]);
                        dp[dpIdx + dpL + 1] = HqxUtil.mix2To1To1(w[4], w[5], w[7]);
                    }
                    case 124: {
                        dp[dpIdx] = HqxUtil.mix2To1To1(w[4], w[0], w[1]);
                        dp[dpIdx + 1] = HqxUtil.mix3To1(w[4], w[1]);
                        if (HqxUtil.diff(w[7], w[3], trY, trU, trV, trA)) {
                            dp[dpIdx + dpL] = w[4];
                        } else {
                            dp[dpIdx + dpL] = HqxUtil.mix2To1To1(w[4], w[7], w[3]);
                        }
                        dp[dpIdx + dpL + 1] = HqxUtil.mix3To1(w[4], w[8]);
                    }
                    case 203: {
                        if (HqxUtil.diff(w[3], w[1], trY, trU, trV, trA)) {
                            dp[dpIdx] = w[4];
                        } else {
                            dp[dpIdx] = HqxUtil.mix2To1To1(w[4], w[3], w[1]);
                        }
                        dp[dpIdx + 1] = HqxUtil.mix2To1To1(w[4], w[2], w[5]);
                        dp[dpIdx + dpL] = HqxUtil.mix3To1(w[4], w[6]);
                        dp[dpIdx + dpL + 1] = HqxUtil.mix3To1(w[4], w[5]);
                    }
                    case 62: {
                        dp[dpIdx] = HqxUtil.mix3To1(w[4], w[0]);
                        if (HqxUtil.diff(w[1], w[5], trY, trU, trV, trA)) {
                            dp[dpIdx + 1] = w[4];
                        } else {
                            dp[dpIdx + 1] = HqxUtil.mix2To1To1(w[4], w[1], w[5]);
                        }
                        dp[dpIdx + dpL] = HqxUtil.mix3To1(w[4], w[7]);
                        dp[dpIdx + dpL + 1] = HqxUtil.mix2To1To1(w[4], w[8], w[7]);
                    }
                    case 211: {
                        dp[dpIdx] = HqxUtil.mix3To1(w[4], w[3]);
                        dp[dpIdx + 1] = HqxUtil.mix3To1(w[4], w[2]);
                        dp[dpIdx + dpL] = HqxUtil.mix2To1To1(w[4], w[6], w[3]);
                        if (HqxUtil.diff(w[5], w[7], trY, trU, trV, trA)) {
                            dp[dpIdx + dpL + 1] = w[4];
                        } else {
                            dp[dpIdx + dpL + 1] = HqxUtil.mix2To1To1(w[4], w[5], w[7]);
                        }
                    }
                    case 118: {
                        dp[dpIdx] = HqxUtil.mix2To1To1(w[4], w[0], w[3]);
                        if (HqxUtil.diff(w[1], w[5], trY, trU, trV, trA)) {
                            dp[dpIdx + 1] = w[4];
                        } else {
                            dp[dpIdx + 1] = HqxUtil.mix2To1To1(w[4], w[1], w[5]);
                        }
                        dp[dpIdx + dpL] = HqxUtil.mix3To1(w[4], w[3]);
                        dp[dpIdx + dpL + 1] = HqxUtil.mix3To1(w[4], w[8]);
                    }
                    case 217: {
                        dp[dpIdx] = HqxUtil.mix3To1(w[4], w[1]);
                        dp[dpIdx + 1] = HqxUtil.mix2To1To1(w[4], w[2], w[1]);
                        dp[dpIdx + dpL] = HqxUtil.mix3To1(w[4], w[6]);
                        if (HqxUtil.diff(w[5], w[7], trY, trU, trV, trA)) {
                            dp[dpIdx + dpL + 1] = w[4];
                        } else {
                            dp[dpIdx + dpL + 1] = HqxUtil.mix2To1To1(w[4], w[5], w[7]);
                        }
                    }
                    case 110: {
                        dp[dpIdx] = HqxUtil.mix3To1(w[4], w[0]);
                        dp[dpIdx + 1] = HqxUtil.mix3To1(w[4], w[5]);
                        if (HqxUtil.diff(w[7], w[3], trY, trU, trV, trA)) {
                            dp[dpIdx + dpL] = w[4];
                        } else {
                            dp[dpIdx + dpL] = HqxUtil.mix2To1To1(w[4], w[7], w[3]);
                        }
                        dp[dpIdx + dpL + 1] = HqxUtil.mix2To1To1(w[4], w[8], w[5]);
                    }
                    case 155: {
                        if (HqxUtil.diff(w[3], w[1], trY, trU, trV, trA)) {
                            dp[dpIdx] = w[4];
                        } else {
                            dp[dpIdx] = HqxUtil.mix2To1To1(w[4], w[3], w[1]);
                        }
                        dp[dpIdx + 1] = HqxUtil.mix3To1(w[4], w[2]);
                        dp[dpIdx + dpL] = HqxUtil.mix2To1To1(w[4], w[6], w[7]);
                        dp[dpIdx + dpL + 1] = HqxUtil.mix3To1(w[4], w[7]);
                    }
                    case 188: {
                        dp[dpIdx] = HqxUtil.mix2To1To1(w[4], w[0], w[1]);
                        dp[dpIdx + 1] = HqxUtil.mix3To1(w[4], w[1]);
                        dp[dpIdx + dpL] = HqxUtil.mix3To1(w[4], w[7]);
                        dp[dpIdx + dpL + 1] = HqxUtil.mix3To1(w[4], w[7]);
                    }
                    case 185: {
                        dp[dpIdx] = HqxUtil.mix3To1(w[4], w[1]);
                        dp[dpIdx + 1] = HqxUtil.mix2To1To1(w[4], w[2], w[1]);
                        dp[dpIdx + dpL] = HqxUtil.mix3To1(w[4], w[7]);
                        dp[dpIdx + dpL + 1] = HqxUtil.mix3To1(w[4], w[7]);
                    }
                    case 61: {
                        dp[dpIdx] = HqxUtil.mix3To1(w[4], w[1]);
                        dp[dpIdx + 1] = HqxUtil.mix3To1(w[4], w[1]);
                        dp[dpIdx + dpL] = HqxUtil.mix3To1(w[4], w[7]);
                        dp[dpIdx + dpL + 1] = HqxUtil.mix2To1To1(w[4], w[8], w[7]);
                    }
                    case 157: {
                        dp[dpIdx] = HqxUtil.mix3To1(w[4], w[1]);
                        dp[dpIdx + 1] = HqxUtil.mix3To1(w[4], w[1]);
                        dp[dpIdx + dpL] = HqxUtil.mix2To1To1(w[4], w[6], w[7]);
                        dp[dpIdx + dpL + 1] = HqxUtil.mix3To1(w[4], w[7]);
                    }
                    case 103: {
                        dp[dpIdx] = HqxUtil.mix3To1(w[4], w[3]);
                        dp[dpIdx + 1] = HqxUtil.mix3To1(w[4], w[5]);
                        dp[dpIdx + dpL] = HqxUtil.mix3To1(w[4], w[3]);
                        dp[dpIdx + dpL + 1] = HqxUtil.mix2To1To1(w[4], w[8], w[5]);
                    }
                    case 227: {
                        dp[dpIdx] = HqxUtil.mix3To1(w[4], w[3]);
                        dp[dpIdx + 1] = HqxUtil.mix2To1To1(w[4], w[2], w[5]);
                        dp[dpIdx + dpL] = HqxUtil.mix3To1(w[4], w[3]);
                        dp[dpIdx + dpL + 1] = HqxUtil.mix3To1(w[4], w[5]);
                    }
                    case 230: {
                        dp[dpIdx] = HqxUtil.mix2To1To1(w[4], w[0], w[3]);
                        dp[dpIdx + 1] = HqxUtil.mix3To1(w[4], w[5]);
                        dp[dpIdx + dpL] = HqxUtil.mix3To1(w[4], w[3]);
                        dp[dpIdx + dpL + 1] = HqxUtil.mix3To1(w[4], w[5]);
                    }
                    case 199: {
                        dp[dpIdx] = HqxUtil.mix3To1(w[4], w[3]);
                        dp[dpIdx + 1] = HqxUtil.mix3To1(w[4], w[5]);
                        dp[dpIdx + dpL] = HqxUtil.mix2To1To1(w[4], w[6], w[3]);
                        dp[dpIdx + dpL + 1] = HqxUtil.mix3To1(w[4], w[5]);
                    }
                    case 220: {
                        dp[dpIdx] = HqxUtil.mix2To1To1(w[4], w[0], w[1]);
                        dp[dpIdx + 1] = HqxUtil.mix3To1(w[4], w[1]);
                        if (HqxUtil.diff(w[7], w[3], trY, trU, trV, trA)) {
                            dp[dpIdx + dpL] = HqxUtil.mix3To1(w[4], w[6]);
                        } else {
                            dp[dpIdx + dpL] = HqxUtil.mix6To1To1(w[4], w[7], w[3]);
                        }
                        if (HqxUtil.diff(w[5], w[7], trY, trU, trV, trA)) {
                            dp[dpIdx + dpL + 1] = w[4];
                        } else {
                            dp[dpIdx + dpL + 1] = HqxUtil.mix2To1To1(w[4], w[5], w[7]);
                        }
                    }
                    case 158: {
                        if (HqxUtil.diff(w[3], w[1], trY, trU, trV, trA)) {
                            dp[dpIdx] = HqxUtil.mix3To1(w[4], w[0]);
                        } else {
                            dp[dpIdx] = HqxUtil.mix6To1To1(w[4], w[3], w[1]);
                        }
                        if (HqxUtil.diff(w[1], w[5], trY, trU, trV, trA)) {
                            dp[dpIdx + 1] = w[4];
                        } else {
                            dp[dpIdx + 1] = HqxUtil.mix2To1To1(w[4], w[1], w[5]);
                        }
                        dp[dpIdx + dpL] = HqxUtil.mix2To1To1(w[4], w[6], w[7]);
                        dp[dpIdx + dpL + 1] = HqxUtil.mix3To1(w[4], w[7]);
                    }
                    case 234: {
                        if (HqxUtil.diff(w[3], w[1], trY, trU, trV, trA)) {
                            dp[dpIdx] = HqxUtil.mix3To1(w[4], w[0]);
                        } else {
                            dp[dpIdx] = HqxUtil.mix6To1To1(w[4], w[3], w[1]);
                        }
                        dp[dpIdx + 1] = HqxUtil.mix2To1To1(w[4], w[2], w[5]);
                        if (HqxUtil.diff(w[7], w[3], trY, trU, trV, trA)) {
                            dp[dpIdx + dpL] = w[4];
                        } else {
                            dp[dpIdx + dpL] = HqxUtil.mix2To1To1(w[4], w[7], w[3]);
                        }
                        dp[dpIdx + dpL + 1] = HqxUtil.mix3To1(w[4], w[5]);
                    }
                    case 242: {
                        dp[dpIdx] = HqxUtil.mix2To1To1(w[4], w[0], w[3]);
                        if (HqxUtil.diff(w[1], w[5], trY, trU, trV, trA)) {
                            dp[dpIdx + 1] = HqxUtil.mix3To1(w[4], w[2]);
                        } else {
                            dp[dpIdx + 1] = HqxUtil.mix6To1To1(w[4], w[1], w[5]);
                        }
                        dp[dpIdx + dpL] = HqxUtil.mix3To1(w[4], w[3]);
                        if (HqxUtil.diff(w[5], w[7], trY, trU, trV, trA)) {
                            dp[dpIdx + dpL + 1] = w[4];
                        } else {
                            dp[dpIdx + dpL + 1] = HqxUtil.mix2To1To1(w[4], w[5], w[7]);
                        }
                    }
                    case 59: {
                        if (HqxUtil.diff(w[3], w[1], trY, trU, trV, trA)) {
                            dp[dpIdx] = w[4];
                        } else {
                            dp[dpIdx] = HqxUtil.mix2To1To1(w[4], w[3], w[1]);
                        }
                        if (HqxUtil.diff(w[1], w[5], trY, trU, trV, trA)) {
                            dp[dpIdx + 1] = HqxUtil.mix3To1(w[4], w[2]);
                        } else {
                            dp[dpIdx + 1] = HqxUtil.mix6To1To1(w[4], w[1], w[5]);
                        }
                        dp[dpIdx + dpL] = HqxUtil.mix3To1(w[4], w[7]);
                        dp[dpIdx + dpL + 1] = HqxUtil.mix2To1To1(w[4], w[8], w[7]);
                    }
                    case 121: {
                        dp[dpIdx] = HqxUtil.mix3To1(w[4], w[1]);
                        dp[dpIdx + 1] = HqxUtil.mix2To1To1(w[4], w[2], w[1]);
                        if (HqxUtil.diff(w[7], w[3], trY, trU, trV, trA)) {
                            dp[dpIdx + dpL] = w[4];
                        } else {
                            dp[dpIdx + dpL] = HqxUtil.mix2To1To1(w[4], w[7], w[3]);
                        }
                        if (HqxUtil.diff(w[5], w[7], trY, trU, trV, trA)) {
                            dp[dpIdx + dpL + 1] = HqxUtil.mix3To1(w[4], w[8]);
                        } else {
                            dp[dpIdx + dpL + 1] = HqxUtil.mix6To1To1(w[4], w[5], w[7]);
                        }
                    }
                    case 87: {
                        dp[dpIdx] = HqxUtil.mix3To1(w[4], w[3]);
                        if (HqxUtil.diff(w[1], w[5], trY, trU, trV, trA)) {
                            dp[dpIdx + 1] = w[4];
                        } else {
                            dp[dpIdx + 1] = HqxUtil.mix2To1To1(w[4], w[1], w[5]);
                        }
                        dp[dpIdx + dpL] = HqxUtil.mix2To1To1(w[4], w[6], w[3]);
                        if (HqxUtil.diff(w[5], w[7], trY, trU, trV, trA)) {
                            dp[dpIdx + dpL + 1] = HqxUtil.mix3To1(w[4], w[8]);
                        } else {
                            dp[dpIdx + dpL + 1] = HqxUtil.mix6To1To1(w[4], w[5], w[7]);
                        }
                    }
                    case 79: {
                        if (HqxUtil.diff(w[3], w[1], trY, trU, trV, trA)) {
                            dp[dpIdx] = w[4];
                        } else {
                            dp[dpIdx] = HqxUtil.mix2To1To1(w[4], w[3], w[1]);
                        }
                        dp[dpIdx + 1] = HqxUtil.mix3To1(w[4], w[5]);
                        if (HqxUtil.diff(w[7], w[3], trY, trU, trV, trA)) {
                            dp[dpIdx + dpL] = HqxUtil.mix3To1(w[4], w[6]);
                        } else {
                            dp[dpIdx + dpL] = HqxUtil.mix6To1To1(w[4], w[7], w[3]);
                        }
                        dp[dpIdx + dpL + 1] = HqxUtil.mix2To1To1(w[4], w[8], w[5]);
                    }
                    case 122: {
                        if (HqxUtil.diff(w[3], w[1], trY, trU, trV, trA)) {
                            dp[dpIdx] = HqxUtil.mix3To1(w[4], w[0]);
                        } else {
                            dp[dpIdx] = HqxUtil.mix6To1To1(w[4], w[3], w[1]);
                        }
                        if (HqxUtil.diff(w[1], w[5], trY, trU, trV, trA)) {
                            dp[dpIdx + 1] = HqxUtil.mix3To1(w[4], w[2]);
                        } else {
                            dp[dpIdx + 1] = HqxUtil.mix6To1To1(w[4], w[1], w[5]);
                        }
                        if (HqxUtil.diff(w[7], w[3], trY, trU, trV, trA)) {
                            dp[dpIdx + dpL] = w[4];
                        } else {
                            dp[dpIdx + dpL] = HqxUtil.mix2To1To1(w[4], w[7], w[3]);
                        }
                        if (HqxUtil.diff(w[5], w[7], trY, trU, trV, trA)) {
                            dp[dpIdx + dpL + 1] = HqxUtil.mix3To1(w[4], w[8]);
                        } else {
                            dp[dpIdx + dpL + 1] = HqxUtil.mix6To1To1(w[4], w[5], w[7]);
                        }
                    }
                    case 94: {
                        if (HqxUtil.diff(w[3], w[1], trY, trU, trV, trA)) {
                            dp[dpIdx] = HqxUtil.mix3To1(w[4], w[0]);
                        } else {
                            dp[dpIdx] = HqxUtil.mix6To1To1(w[4], w[3], w[1]);
                        }
                        if (HqxUtil.diff(w[1], w[5], trY, trU, trV, trA)) {
                            dp[dpIdx + 1] = w[4];
                        } else {
                            dp[dpIdx + 1] = HqxUtil.mix2To1To1(w[4], w[1], w[5]);
                        }
                        if (HqxUtil.diff(w[7], w[3], trY, trU, trV, trA)) {
                            dp[dpIdx + dpL] = HqxUtil.mix3To1(w[4], w[6]);
                        } else {
                            dp[dpIdx + dpL] = HqxUtil.mix6To1To1(w[4], w[7], w[3]);
                        }
                        if (HqxUtil.diff(w[5], w[7], trY, trU, trV, trA)) {
                            dp[dpIdx + dpL + 1] = HqxUtil.mix3To1(w[4], w[8]);
                        } else {
                            dp[dpIdx + dpL + 1] = HqxUtil.mix6To1To1(w[4], w[5], w[7]);
                        }
                    }
                    case 218: {
                        if (HqxUtil.diff(w[3], w[1], trY, trU, trV, trA)) {
                            dp[dpIdx] = HqxUtil.mix3To1(w[4], w[0]);
                        } else {
                            dp[dpIdx] = HqxUtil.mix6To1To1(w[4], w[3], w[1]);
                        }
                        if (HqxUtil.diff(w[1], w[5], trY, trU, trV, trA)) {
                            dp[dpIdx + 1] = HqxUtil.mix3To1(w[4], w[2]);
                        } else {
                            dp[dpIdx + 1] = HqxUtil.mix6To1To1(w[4], w[1], w[5]);
                        }
                        if (HqxUtil.diff(w[7], w[3], trY, trU, trV, trA)) {
                            dp[dpIdx + dpL] = HqxUtil.mix3To1(w[4], w[6]);
                        } else {
                            dp[dpIdx + dpL] = HqxUtil.mix6To1To1(w[4], w[7], w[3]);
                        }
                        if (HqxUtil.diff(w[5], w[7], trY, trU, trV, trA)) {
                            dp[dpIdx + dpL + 1] = w[4];
                        } else {
                            dp[dpIdx + dpL + 1] = HqxUtil.mix2To1To1(w[4], w[5], w[7]);
                        }
                    }
                    case 91: {
                        if (HqxUtil.diff(w[3], w[1], trY, trU, trV, trA)) {
                            dp[dpIdx] = w[4];
                        } else {
                            dp[dpIdx] = HqxUtil.mix2To1To1(w[4], w[3], w[1]);
                        }
                        if (HqxUtil.diff(w[1], w[5], trY, trU, trV, trA)) {
                            dp[dpIdx + 1] = HqxUtil.mix3To1(w[4], w[2]);
                        } else {
                            dp[dpIdx + 1] = HqxUtil.mix6To1To1(w[4], w[1], w[5]);
                        }
                        if (HqxUtil.diff(w[7], w[3], trY, trU, trV, trA)) {
                            dp[dpIdx + dpL] = HqxUtil.mix3To1(w[4], w[6]);
                        } else {
                            dp[dpIdx + dpL] = HqxUtil.mix6To1To1(w[4], w[7], w[3]);
                        }
                        if (HqxUtil.diff(w[5], w[7], trY, trU, trV, trA)) {
                            dp[dpIdx + dpL + 1] = HqxUtil.mix3To1(w[4], w[8]);
                        } else {
                            dp[dpIdx + dpL + 1] = HqxUtil.mix6To1To1(w[4], w[5], w[7]);
                        }
                    }
                    case 186: {
                        if (HqxUtil.diff(w[3], w[1], trY, trU, trV, trA)) {
                            dp[dpIdx] = HqxUtil.mix3To1(w[4], w[0]);
                        } else {
                            dp[dpIdx] = HqxUtil.mix6To1To1(w[4], w[3], w[1]);
                        }
                        if (HqxUtil.diff(w[1], w[5], trY, trU, trV, trA)) {
                            dp[dpIdx + 1] = HqxUtil.mix3To1(w[4], w[2]);
                        } else {
                            dp[dpIdx + 1] = HqxUtil.mix6To1To1(w[4], w[1], w[5]);
                        }
                        dp[dpIdx + dpL] = HqxUtil.mix3To1(w[4], w[7]);
                        dp[dpIdx + dpL + 1] = HqxUtil.mix3To1(w[4], w[7]);
                    }
                    case 115: {
                        dp[dpIdx] = HqxUtil.mix3To1(w[4], w[3]);
                        if (HqxUtil.diff(w[1], w[5], trY, trU, trV, trA)) {
                            dp[dpIdx + 1] = HqxUtil.mix3To1(w[4], w[2]);
                        } else {
                            dp[dpIdx + 1] = HqxUtil.mix6To1To1(w[4], w[1], w[5]);
                        }
                        dp[dpIdx + dpL] = HqxUtil.mix3To1(w[4], w[3]);
                        if (HqxUtil.diff(w[5], w[7], trY, trU, trV, trA)) {
                            dp[dpIdx + dpL + 1] = HqxUtil.mix3To1(w[4], w[8]);
                        } else {
                            dp[dpIdx + dpL + 1] = HqxUtil.mix6To1To1(w[4], w[5], w[7]);
                        }
                    }
                    case 93: {
                        dp[dpIdx] = HqxUtil.mix3To1(w[4], w[1]);
                        dp[dpIdx + 1] = HqxUtil.mix3To1(w[4], w[1]);
                        if (HqxUtil.diff(w[7], w[3], trY, trU, trV, trA)) {
                            dp[dpIdx + dpL] = HqxUtil.mix3To1(w[4], w[6]);
                        } else {
                            dp[dpIdx + dpL] = HqxUtil.mix6To1To1(w[4], w[7], w[3]);
                        }
                        if (HqxUtil.diff(w[5], w[7], trY, trU, trV, trA)) {
                            dp[dpIdx + dpL + 1] = HqxUtil.mix3To1(w[4], w[8]);
                        } else {
                            dp[dpIdx + dpL + 1] = HqxUtil.mix6To1To1(w[4], w[5], w[7]);
                        }
                    }
                    case 206: {
                        if (HqxUtil.diff(w[3], w[1], trY, trU, trV, trA)) {
                            dp[dpIdx] = HqxUtil.mix3To1(w[4], w[0]);
                        } else {
                            dp[dpIdx] = HqxUtil.mix6To1To1(w[4], w[3], w[1]);
                        }
                        dp[dpIdx + 1] = HqxUtil.mix3To1(w[4], w[5]);
                        if (HqxUtil.diff(w[7], w[3], trY, trU, trV, trA)) {
                            dp[dpIdx + dpL] = HqxUtil.mix3To1(w[4], w[6]);
                        } else {
                            dp[dpIdx + dpL] = HqxUtil.mix6To1To1(w[4], w[7], w[3]);
                        }
                        dp[dpIdx + dpL + 1] = HqxUtil.mix3To1(w[4], w[5]);
                    }
                    case 201 || 205: {
                        dp[dpIdx] = HqxUtil.mix3To1(w[4], w[1]);
                        dp[dpIdx + 1] = HqxUtil.mix2To1To1(w[4], w[1], w[5]);
                        if (HqxUtil.diff(w[7], w[3], trY, trU, trV, trA)) {
                            dp[dpIdx + dpL] = HqxUtil.mix3To1(w[4], w[6]);
                        } else {
                            dp[dpIdx + dpL] = HqxUtil.mix6To1To1(w[4], w[7], w[3]);
                        }
                        dp[dpIdx + dpL + 1] = HqxUtil.mix3To1(w[4], w[5]);
                    }
                    case 46 || 174: {
                        if (HqxUtil.diff(w[3], w[1], trY, trU, trV, trA)) {
                            dp[dpIdx] = HqxUtil.mix3To1(w[4], w[0]);
                        } else {
                            dp[dpIdx] = HqxUtil.mix6To1To1(w[4], w[3], w[1]);
                        }
                        dp[dpIdx + 1] = HqxUtil.mix3To1(w[4], w[5]);
                        dp[dpIdx + dpL] = HqxUtil.mix3To1(w[4], w[7]);
                        dp[dpIdx + dpL + 1] = HqxUtil.mix2To1To1(w[4], w[5], w[7]);
                    }
                    case 147 || 179: {
                        dp[dpIdx] = HqxUtil.mix3To1(w[4], w[3]);
                        if (HqxUtil.diff(w[1], w[5], trY, trU, trV, trA)) {
                            dp[dpIdx + 1] = HqxUtil.mix3To1(w[4], w[2]);
                        } else {
                            dp[dpIdx + 1] = HqxUtil.mix6To1To1(w[4], w[1], w[5]);
                        }
                        dp[dpIdx + dpL] = HqxUtil.mix2To1To1(w[4], w[7], w[3]);
                        dp[dpIdx + dpL + 1] = HqxUtil.mix3To1(w[4], w[7]);
                    }
                    case 116 || 117: {
                        dp[dpIdx] = HqxUtil.mix2To1To1(w[4], w[3], w[1]);
                        dp[dpIdx + 1] = HqxUtil.mix3To1(w[4], w[1]);
                        dp[dpIdx + dpL] = HqxUtil.mix3To1(w[4], w[3]);
                        if (HqxUtil.diff(w[5], w[7], trY, trU, trV, trA)) {
                            dp[dpIdx + dpL + 1] = HqxUtil.mix3To1(w[4], w[8]);
                        } else {
                            dp[dpIdx + dpL + 1] = HqxUtil.mix6To1To1(w[4], w[5], w[7]);
                        }
                    }
                    case 189: {
                        dp[dpIdx] = HqxUtil.mix3To1(w[4], w[1]);
                        dp[dpIdx + 1] = HqxUtil.mix3To1(w[4], w[1]);
                        dp[dpIdx + dpL] = HqxUtil.mix3To1(w[4], w[7]);
                        dp[dpIdx + dpL + 1] = HqxUtil.mix3To1(w[4], w[7]);
                    }
                    case 231: {
                        dp[dpIdx] = HqxUtil.mix3To1(w[4], w[3]);
                        dp[dpIdx + 1] = HqxUtil.mix3To1(w[4], w[5]);
                        dp[dpIdx + dpL] = HqxUtil.mix3To1(w[4], w[3]);
                        dp[dpIdx + dpL + 1] = HqxUtil.mix3To1(w[4], w[5]);
                    }
                    case 126: {
                        dp[dpIdx] = HqxUtil.mix3To1(w[4], w[0]);
                        if (HqxUtil.diff(w[1], w[5], trY, trU, trV, trA)) {
                            dp[dpIdx + 1] = w[4];
                        } else {
                            dp[dpIdx + 1] = HqxUtil.mix2To1To1(w[4], w[1], w[5]);
                        }
                        if (HqxUtil.diff(w[7], w[3], trY, trU, trV, trA)) {
                            dp[dpIdx + dpL] = w[4];
                        } else {
                            dp[dpIdx + dpL] = HqxUtil.mix2To1To1(w[4], w[7], w[3]);
                        }
                        dp[dpIdx + dpL + 1] = HqxUtil.mix3To1(w[4], w[8]);
                    }
                    case 219: {
                        if (HqxUtil.diff(w[3], w[1], trY, trU, trV, trA)) {
                            dp[dpIdx] = w[4];
                        } else {
                            dp[dpIdx] = HqxUtil.mix2To1To1(w[4], w[3], w[1]);
                        }
                        dp[dpIdx + 1] = HqxUtil.mix3To1(w[4], w[2]);
                        dp[dpIdx + dpL] = HqxUtil.mix3To1(w[4], w[6]);
                        if (HqxUtil.diff(w[5], w[7], trY, trU, trV, trA)) {
                            dp[dpIdx + dpL + 1] = w[4];
                        } else {
                            dp[dpIdx + dpL + 1] = HqxUtil.mix2To1To1(w[4], w[5], w[7]);
                        }
                    }
                    case 125: {
                        if (HqxUtil.diff(w[7], w[3], trY, trU, trV, trA)) {
                            dp[dpIdx] = HqxUtil.mix3To1(w[4], w[1]);
                            dp[dpIdx + dpL] = w[4];
                        } else {
                            dp[dpIdx] = HqxUtil.mix4To2To1(w[4], w[3], w[1]);
                            dp[dpIdx + dpL] = HqxUtil.mix2To3To3(w[4], w[7], w[3]);
                        }
                        dp[dpIdx + 1] = HqxUtil.mix3To1(w[4], w[1]);
                        dp[dpIdx + dpL + 1] = HqxUtil.mix3To1(w[4], w[8]);
                    }
                    case 221: {
                        dp[dpIdx] = HqxUtil.mix3To1(w[4], w[1]);
                        if (HqxUtil.diff(w[5], w[7], trY, trU, trV, trA)) {
                            dp[dpIdx + 1] = HqxUtil.mix3To1(w[4], w[1]);
                            dp[dpIdx + dpL + 1] = w[4];
                        } else {
                            dp[dpIdx + 1] = HqxUtil.mix4To2To1(w[4], w[5], w[1]);
                            dp[dpIdx + dpL + 1] = HqxUtil.mix2To3To3(w[4], w[5], w[7]);
                        }
                        dp[dpIdx + dpL] = HqxUtil.mix3To1(w[4], w[6]);
                    }
                    case 207: {
                        if (HqxUtil.diff(w[3], w[1], trY, trU, trV, trA)) {
                            dp[dpIdx] = w[4];
                            dp[dpIdx + 1] = HqxUtil.mix3To1(w[4], w[5]);
                        } else {
                            dp[dpIdx] = HqxUtil.mix2To3To3(w[4], w[3], w[1]);
                            dp[dpIdx + 1] = HqxUtil.mix4To2To1(w[4], w[1], w[5]);
                        }
                        dp[dpIdx + dpL] = HqxUtil.mix3To1(w[4], w[6]);
                        dp[dpIdx + dpL + 1] = HqxUtil.mix3To1(w[4], w[5]);
                    }
                    case 238: {
                        dp[dpIdx] = HqxUtil.mix3To1(w[4], w[0]);
                        dp[dpIdx + 1] = HqxUtil.mix3To1(w[4], w[5]);
                        if (HqxUtil.diff(w[7], w[3], trY, trU, trV, trA)) {
                            dp[dpIdx + dpL] = w[4];
                            dp[dpIdx + dpL + 1] = HqxUtil.mix3To1(w[4], w[5]);
                        } else {
                            dp[dpIdx + dpL] = HqxUtil.mix2To3To3(w[4], w[7], w[3]);
                            dp[dpIdx + dpL + 1] = HqxUtil.mix4To2To1(w[4], w[7], w[5]);
                        }
                    }
                    case 190: {
                        dp[dpIdx] = HqxUtil.mix3To1(w[4], w[0]);
                        if (HqxUtil.diff(w[1], w[5], trY, trU, trV, trA)) {
                            dp[dpIdx + 1] = w[4];
                            dp[dpIdx + dpL + 1] = HqxUtil.mix3To1(w[4], w[7]);
                        } else {
                            dp[dpIdx + 1] = HqxUtil.mix2To3To3(w[4], w[1], w[5]);
                            dp[dpIdx + dpL + 1] = HqxUtil.mix4To2To1(w[4], w[5], w[7]);
                        }
                        dp[dpIdx + dpL] = HqxUtil.mix3To1(w[4], w[7]);
                    }
                    case 187: {
                        if (HqxUtil.diff(w[3], w[1], trY, trU, trV, trA)) {
                            dp[dpIdx] = w[4];
                            dp[dpIdx + dpL] = HqxUtil.mix3To1(w[4], w[7]);
                        } else {
                            dp[dpIdx] = HqxUtil.mix2To3To3(w[4], w[3], w[1]);
                            dp[dpIdx + dpL] = HqxUtil.mix4To2To1(w[4], w[3], w[7]);
                        }
                        dp[dpIdx + 1] = HqxUtil.mix3To1(w[4], w[2]);
                        dp[dpIdx + dpL + 1] = HqxUtil.mix3To1(w[4], w[7]);
                    }
                    case 243: {
                        dp[dpIdx] = HqxUtil.mix3To1(w[4], w[3]);
                        dp[dpIdx + 1] = HqxUtil.mix3To1(w[4], w[2]);
                        if (HqxUtil.diff(w[5], w[7], trY, trU, trV, trA)) {
                            dp[dpIdx + dpL] = HqxUtil.mix3To1(w[4], w[3]);
                            dp[dpIdx + dpL + 1] = w[4];
                        } else {
                            dp[dpIdx + dpL] = HqxUtil.mix4To2To1(w[4], w[7], w[3]);
                            dp[dpIdx + dpL + 1] = HqxUtil.mix2To3To3(w[4], w[5], w[7]);
                        }
                    }
                    case 119: {
                        if (HqxUtil.diff(w[1], w[5], trY, trU, trV, trA)) {
                            dp[dpIdx] = HqxUtil.mix3To1(w[4], w[3]);
                            dp[dpIdx + 1] = w[4];
                        } else {
                            dp[dpIdx] = HqxUtil.mix4To2To1(w[4], w[1], w[3]);
                            dp[dpIdx + 1] = HqxUtil.mix2To3To3(w[4], w[1], w[5]);
                        }
                        dp[dpIdx + dpL] = HqxUtil.mix3To1(w[4], w[3]);
                        dp[dpIdx + dpL + 1] = HqxUtil.mix3To1(w[4], w[8]);
                    }
                    case 233 || 237: {
                        dp[dpIdx] = HqxUtil.mix3To1(w[4], w[1]);
                        dp[dpIdx + 1] = HqxUtil.mix2To1To1(w[4], w[1], w[5]);
                        if (HqxUtil.diff(w[7], w[3], trY, trU, trV, trA)) {
                            dp[dpIdx + dpL] = w[4];
                        } else {
                            dp[dpIdx + dpL] = HqxUtil.mix14To1To1(w[4], w[7], w[3]);
                        }
                        dp[dpIdx + dpL + 1] = HqxUtil.mix3To1(w[4], w[5]);
                    }
                    case 47 || 175: {
                        if (HqxUtil.diff(w[3], w[1], trY, trU, trV, trA)) {
                            dp[dpIdx] = w[4];
                        } else {
                            dp[dpIdx] = HqxUtil.mix14To1To1(w[4], w[3], w[1]);
                        }
                        dp[dpIdx + 1] = HqxUtil.mix3To1(w[4], w[5]);
                        dp[dpIdx + dpL] = HqxUtil.mix3To1(w[4], w[7]);
                        dp[dpIdx + dpL + 1] = HqxUtil.mix2To1To1(w[4], w[5], w[7]);
                    }
                    case 151 || 183: {
                        dp[dpIdx] = HqxUtil.mix3To1(w[4], w[3]);
                        if (HqxUtil.diff(w[1], w[5], trY, trU, trV, trA)) {
                            dp[dpIdx + 1] = w[4];
                        } else {
                            dp[dpIdx + 1] = HqxUtil.mix14To1To1(w[4], w[1], w[5]);
                        }
                        dp[dpIdx + dpL] = HqxUtil.mix2To1To1(w[4], w[7], w[3]);
                        dp[dpIdx + dpL + 1] = HqxUtil.mix3To1(w[4], w[7]);
                    }
                    case 244 || 245: {
                        dp[dpIdx] = HqxUtil.mix2To1To1(w[4], w[3], w[1]);
                        dp[dpIdx + 1] = HqxUtil.mix3To1(w[4], w[1]);
                        dp[dpIdx + dpL] = HqxUtil.mix3To1(w[4], w[3]);
                        if (HqxUtil.diff(w[5], w[7], trY, trU, trV, trA)) {
                            dp[dpIdx + dpL + 1] = w[4];
                        } else {
                            dp[dpIdx + dpL + 1] = HqxUtil.mix14To1To1(w[4], w[5], w[7]);
                        }
                    }
                    case 250: {
                        dp[dpIdx] = HqxUtil.mix3To1(w[4], w[0]);
                        dp[dpIdx + 1] = HqxUtil.mix3To1(w[4], w[2]);
                        if (HqxUtil.diff(w[7], w[3], trY, trU, trV, trA)) {
                            dp[dpIdx + dpL] = w[4];
                        } else {
                            dp[dpIdx + dpL] = HqxUtil.mix2To1To1(w[4], w[7], w[3]);
                        }
                        if (HqxUtil.diff(w[5], w[7], trY, trU, trV, trA)) {
                            dp[dpIdx + dpL + 1] = w[4];
                        } else {
                            dp[dpIdx + dpL + 1] = HqxUtil.mix2To1To1(w[4], w[5], w[7]);
                        }
                    }
                    case 123: {
                        if (HqxUtil.diff(w[3], w[1], trY, trU, trV, trA)) {
                            dp[dpIdx] = w[4];
                        } else {
                            dp[dpIdx] = HqxUtil.mix2To1To1(w[4], w[3], w[1]);
                        }
                        dp[dpIdx + 1] = HqxUtil.mix3To1(w[4], w[2]);
                        if (HqxUtil.diff(w[7], w[3], trY, trU, trV, trA)) {
                            dp[dpIdx + dpL] = w[4];
                        } else {
                            dp[dpIdx + dpL] = HqxUtil.mix2To1To1(w[4], w[7], w[3]);
                        }
                        dp[dpIdx + dpL + 1] = HqxUtil.mix3To1(w[4], w[8]);
                    }
                    case 95: {
                        if (HqxUtil.diff(w[3], w[1], trY, trU, trV, trA)) {
                            dp[dpIdx] = w[4];
                        } else {
                            dp[dpIdx] = HqxUtil.mix2To1To1(w[4], w[3], w[1]);
                        }
                        if (HqxUtil.diff(w[1], w[5], trY, trU, trV, trA)) {
                            dp[dpIdx + 1] = w[4];
                        } else {
                            dp[dpIdx + 1] = HqxUtil.mix2To1To1(w[4], w[1], w[5]);
                        }
                        dp[dpIdx + dpL] = HqxUtil.mix3To1(w[4], w[6]);
                        dp[dpIdx + dpL + 1] = HqxUtil.mix3To1(w[4], w[8]);
                    }
                    case 222: {
                        dp[dpIdx] = HqxUtil.mix3To1(w[4], w[0]);
                        if (HqxUtil.diff(w[1], w[5], trY, trU, trV, trA)) {
                            dp[dpIdx + 1] = w[4];
                        } else {
                            dp[dpIdx + 1] = HqxUtil.mix2To1To1(w[4], w[1], w[5]);
                        }
                        dp[dpIdx + dpL] = HqxUtil.mix3To1(w[4], w[6]);
                        if (HqxUtil.diff(w[5], w[7], trY, trU, trV, trA)) {
                            dp[dpIdx + dpL + 1] = w[4];
                        } else {
                            dp[dpIdx + dpL + 1] = HqxUtil.mix2To1To1(w[4], w[5], w[7]);
                        }
                    }
                    case 252: {
                        dp[dpIdx] = HqxUtil.mix2To1To1(w[4], w[0], w[1]);
                        dp[dpIdx + 1] = HqxUtil.mix3To1(w[4], w[1]);
                        if (HqxUtil.diff(w[7], w[3], trY, trU, trV, trA)) {
                            dp[dpIdx + dpL] = w[4];
                        } else {
                            dp[dpIdx + dpL] = HqxUtil.mix2To1To1(w[4], w[7], w[3]);
                        }
                        if (HqxUtil.diff(w[5], w[7], trY, trU, trV, trA)) {
                            dp[dpIdx + dpL + 1] = w[4];
                        } else {
                            dp[dpIdx + dpL + 1] = HqxUtil.mix14To1To1(w[4], w[5], w[7]);
                        }
                    }
                    case 249: {
                        dp[dpIdx] = HqxUtil.mix3To1(w[4], w[1]);
                        dp[dpIdx + 1] = HqxUtil.mix2To1To1(w[4], w[2], w[1]);
                        if (HqxUtil.diff(w[7], w[3], trY, trU, trV, trA)) {
                            dp[dpIdx + dpL] = w[4];
                        } else {
                            dp[dpIdx + dpL] = HqxUtil.mix14To1To1(w[4], w[7], w[3]);
                        }
                        if (HqxUtil.diff(w[5], w[7], trY, trU, trV, trA)) {
                            dp[dpIdx + dpL + 1] = w[4];
                        } else {
                            dp[dpIdx + dpL + 1] = HqxUtil.mix2To1To1(w[4], w[5], w[7]);
                        }
                    }
                    case 235: {
                        if (HqxUtil.diff(w[3], w[1], trY, trU, trV, trA)) {
                            dp[dpIdx] = w[4];
                        } else {
                            dp[dpIdx] = HqxUtil.mix2To1To1(w[4], w[3], w[1]);
                        }
                        dp[dpIdx + 1] = HqxUtil.mix2To1To1(w[4], w[2], w[5]);
                        if (HqxUtil.diff(w[7], w[3], trY, trU, trV, trA)) {
                            dp[dpIdx + dpL] = w[4];
                        } else {
                            dp[dpIdx + dpL] = HqxUtil.mix14To1To1(w[4], w[7], w[3]);
                        }
                        dp[dpIdx + dpL + 1] = HqxUtil.mix3To1(w[4], w[5]);
                    }
                    case 111: {
                        if (HqxUtil.diff(w[3], w[1], trY, trU, trV, trA)) {
                            dp[dpIdx] = w[4];
                        } else {
                            dp[dpIdx] = HqxUtil.mix14To1To1(w[4], w[3], w[1]);
                        }
                        dp[dpIdx + 1] = HqxUtil.mix3To1(w[4], w[5]);
                        if (HqxUtil.diff(w[7], w[3], trY, trU, trV, trA)) {
                            dp[dpIdx + dpL] = w[4];
                        } else {
                            dp[dpIdx + dpL] = HqxUtil.mix2To1To1(w[4], w[7], w[3]);
                        }
                        dp[dpIdx + dpL + 1] = HqxUtil.mix2To1To1(w[4], w[8], w[5]);
                    }
                    case 63: {
                        if (HqxUtil.diff(w[3], w[1], trY, trU, trV, trA)) {
                            dp[dpIdx] = w[4];
                        } else {
                            dp[dpIdx] = HqxUtil.mix14To1To1(w[4], w[3], w[1]);
                        }
                        if (HqxUtil.diff(w[1], w[5], trY, trU, trV, trA)) {
                            dp[dpIdx + 1] = w[4];
                        } else {
                            dp[dpIdx + 1] = HqxUtil.mix2To1To1(w[4], w[1], w[5]);
                        }
                        dp[dpIdx + dpL] = HqxUtil.mix3To1(w[4], w[7]);
                        dp[dpIdx + dpL + 1] = HqxUtil.mix2To1To1(w[4], w[8], w[7]);
                    }
                    case 159: {
                        if (HqxUtil.diff(w[3], w[1], trY, trU, trV, trA)) {
                            dp[dpIdx] = w[4];
                        } else {
                            dp[dpIdx] = HqxUtil.mix2To1To1(w[4], w[3], w[1]);
                        }
                        if (HqxUtil.diff(w[1], w[5], trY, trU, trV, trA)) {
                            dp[dpIdx + 1] = w[4];
                        } else {
                            dp[dpIdx + 1] = HqxUtil.mix14To1To1(w[4], w[1], w[5]);
                        }
                        dp[dpIdx + dpL] = HqxUtil.mix2To1To1(w[4], w[6], w[7]);
                        dp[dpIdx + dpL + 1] = HqxUtil.mix3To1(w[4], w[7]);
                    }
                    case 215: {
                        dp[dpIdx] = HqxUtil.mix3To1(w[4], w[3]);
                        if (HqxUtil.diff(w[1], w[5], trY, trU, trV, trA)) {
                            dp[dpIdx + 1] = w[4];
                        } else {
                            dp[dpIdx + 1] = HqxUtil.mix14To1To1(w[4], w[1], w[5]);
                        }
                        dp[dpIdx + dpL] = HqxUtil.mix2To1To1(w[4], w[6], w[3]);
                        if (HqxUtil.diff(w[5], w[7], trY, trU, trV, trA)) {
                            dp[dpIdx + dpL + 1] = w[4];
                        } else {
                            dp[dpIdx + dpL + 1] = HqxUtil.mix2To1To1(w[4], w[5], w[7]);
                        }
                    }
                    case 246: {
                        dp[dpIdx] = HqxUtil.mix2To1To1(w[4], w[0], w[3]);
                        if (HqxUtil.diff(w[1], w[5], trY, trU, trV, trA)) {
                            dp[dpIdx + 1] = w[4];
                        } else {
                            dp[dpIdx + 1] = HqxUtil.mix2To1To1(w[4], w[1], w[5]);
                        }
                        dp[dpIdx + dpL] = HqxUtil.mix3To1(w[4], w[3]);
                        if (HqxUtil.diff(w[5], w[7], trY, trU, trV, trA)) {
                            dp[dpIdx + dpL + 1] = w[4];
                        } else {
                            dp[dpIdx + dpL + 1] = HqxUtil.mix14To1To1(w[4], w[5], w[7]);
                        }
                    }
                    case 254: {
                        dp[dpIdx] = HqxUtil.mix3To1(w[4], w[0]);
                        if (HqxUtil.diff(w[1], w[5], trY, trU, trV, trA)) {
                            dp[dpIdx + 1] = w[4];
                        } else {
                            dp[dpIdx + 1] = HqxUtil.mix2To1To1(w[4], w[1], w[5]);
                        }
                        if (HqxUtil.diff(w[7], w[3], trY, trU, trV, trA)) {
                            dp[dpIdx + dpL] = w[4];
                        } else {
                            dp[dpIdx + dpL] = HqxUtil.mix2To1To1(w[4], w[7], w[3]);
                        }
                        if (HqxUtil.diff(w[5], w[7], trY, trU, trV, trA)) {
                            dp[dpIdx + dpL + 1] = w[4];
                        } else {
                            dp[dpIdx + dpL + 1] = HqxUtil.mix14To1To1(w[4], w[5], w[7]);
                        }
                    }
                    case 253: {
                        dp[dpIdx] = HqxUtil.mix3To1(w[4], w[1]);
                        dp[dpIdx + 1] = HqxUtil.mix3To1(w[4], w[1]);
                        if (HqxUtil.diff(w[7], w[3], trY, trU, trV, trA)) {
                            dp[dpIdx + dpL] = w[4];
                        } else {
                            dp[dpIdx + dpL] = HqxUtil.mix14To1To1(w[4], w[7], w[3]);
                        }
                        if (HqxUtil.diff(w[5], w[7], trY, trU, trV, trA)) {
                            dp[dpIdx + dpL + 1] = w[4];
                        } else {
                            dp[dpIdx + dpL + 1] = HqxUtil.mix14To1To1(w[4], w[5], w[7]);
                        }
                    }
                    case 251: {
                        if (HqxUtil.diff(w[3], w[1], trY, trU, trV, trA)) {
                            dp[dpIdx] = w[4];
                        } else {
                            dp[dpIdx] = HqxUtil.mix2To1To1(w[4], w[3], w[1]);
                        }
                        dp[dpIdx + 1] = HqxUtil.mix3To1(w[4], w[2]);
                        if (HqxUtil.diff(w[7], w[3], trY, trU, trV, trA)) {
                            dp[dpIdx + dpL] = w[4];
                        } else {
                            dp[dpIdx + dpL] = HqxUtil.mix14To1To1(w[4], w[7], w[3]);
                        }
                        if (HqxUtil.diff(w[5], w[7], trY, trU, trV, trA)) {
                            dp[dpIdx + dpL + 1] = w[4];
                        } else {
                            dp[dpIdx + dpL + 1] = HqxUtil.mix2To1To1(w[4], w[5], w[7]);
                        }
                    }
                    case 239: {
                        if (HqxUtil.diff(w[3], w[1], trY, trU, trV, trA)) {
                            dp[dpIdx] = w[4];
                        } else {
                            dp[dpIdx] = HqxUtil.mix14To1To1(w[4], w[3], w[1]);
                        }
                        dp[dpIdx + 1] = HqxUtil.mix3To1(w[4], w[5]);
                        if (HqxUtil.diff(w[7], w[3], trY, trU, trV, trA)) {
                            dp[dpIdx + dpL] = w[4];
                        } else {
                            dp[dpIdx + dpL] = HqxUtil.mix14To1To1(w[4], w[7], w[3]);
                        }
                        dp[dpIdx + dpL + 1] = HqxUtil.mix3To1(w[4], w[5]);
                    }
                    case 127: {
                        if (HqxUtil.diff(w[3], w[1], trY, trU, trV, trA)) {
                            dp[dpIdx] = w[4];
                        } else {
                            dp[dpIdx] = HqxUtil.mix14To1To1(w[4], w[3], w[1]);
                        }
                        if (HqxUtil.diff(w[1], w[5], trY, trU, trV, trA)) {
                            dp[dpIdx + 1] = w[4];
                        } else {
                            dp[dpIdx + 1] = HqxUtil.mix2To1To1(w[4], w[1], w[5]);
                        }
                        if (HqxUtil.diff(w[7], w[3], trY, trU, trV, trA)) {
                            dp[dpIdx + dpL] = w[4];
                        } else {
                            dp[dpIdx + dpL] = HqxUtil.mix2To1To1(w[4], w[7], w[3]);
                        }
                        dp[dpIdx + dpL + 1] = HqxUtil.mix3To1(w[4], w[8]);
                    }
                    case 191: {
                        if (HqxUtil.diff(w[3], w[1], trY, trU, trV, trA)) {
                            dp[dpIdx] = w[4];
                        } else {
                            dp[dpIdx] = HqxUtil.mix14To1To1(w[4], w[3], w[1]);
                        }
                        if (HqxUtil.diff(w[1], w[5], trY, trU, trV, trA)) {
                            dp[dpIdx + 1] = w[4];
                        } else {
                            dp[dpIdx + 1] = HqxUtil.mix14To1To1(w[4], w[1], w[5]);
                        }
                        dp[dpIdx + dpL] = HqxUtil.mix3To1(w[4], w[7]);
                        dp[dpIdx + dpL + 1] = HqxUtil.mix3To1(w[4], w[7]);
                    }
                    case 223: {
                        if (HqxUtil.diff(w[3], w[1], trY, trU, trV, trA)) {
                            dp[dpIdx] = w[4];
                        } else {
                            dp[dpIdx] = HqxUtil.mix2To1To1(w[4], w[3], w[1]);
                        }
                        if (HqxUtil.diff(w[1], w[5], trY, trU, trV, trA)) {
                            dp[dpIdx + 1] = w[4];
                        } else {
                            dp[dpIdx + 1] = HqxUtil.mix14To1To1(w[4], w[1], w[5]);
                        }
                        dp[dpIdx + dpL] = HqxUtil.mix3To1(w[4], w[6]);
                        if (HqxUtil.diff(w[5], w[7], trY, trU, trV, trA)) {
                            dp[dpIdx + dpL + 1] = w[4];
                        } else {
                            dp[dpIdx + dpL + 1] = HqxUtil.mix2To1To1(w[4], w[5], w[7]);
                        }
                    }
                    case 247: {
                        dp[dpIdx] = HqxUtil.mix3To1(w[4], w[3]);
                        if (HqxUtil.diff(w[1], w[5], trY, trU, trV, trA)) {
                            dp[dpIdx + 1] = w[4];
                        } else {
                            dp[dpIdx + 1] = HqxUtil.mix14To1To1(w[4], w[1], w[5]);
                        }
                        dp[dpIdx + dpL] = HqxUtil.mix3To1(w[4], w[3]);
                        if (HqxUtil.diff(w[5], w[7], trY, trU, trV, trA)) {
                            dp[dpIdx + dpL + 1] = w[4];
                        } else {
                            dp[dpIdx + dpL + 1] = HqxUtil.mix14To1To1(w[4], w[5], w[7]);
                        }
                    }
                    case 255: {
                        if (HqxUtil.diff(w[3], w[1], trY, trU, trV, trA)) {
                            dp[dpIdx] = w[4];
                        } else {
                            dp[dpIdx] = HqxUtil.mix14To1To1(w[4], w[3], w[1]);
                        }
                        if (HqxUtil.diff(w[1], w[5], trY, trU, trV, trA)) {
                            dp[dpIdx + 1] = w[4];
                        } else {
                            dp[dpIdx + 1] = HqxUtil.mix14To1To1(w[4], w[1], w[5]);
                        }
                        if (HqxUtil.diff(w[7], w[3], trY, trU, trV, trA)) {
                            dp[dpIdx + dpL] = w[4];
                        } else {
                            dp[dpIdx + dpL] = HqxUtil.mix14To1To1(w[4], w[7], w[3]);
                        }
                        if (HqxUtil.diff(w[5], w[7], trY, trU, trV, trA)) {
                            dp[dpIdx + dpL + 1] = w[4];
                        } else {
                            dp[dpIdx + dpL + 1] = HqxUtil.mix14To1To1(w[4], w[5], w[7]);
                        }
                    }
                }
                spIdx++;
                dpIdx += 2;
            }
            dpIdx += dpL;
        }
    }
}
