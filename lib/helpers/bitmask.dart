import 'dart:math';

class BitmaskHelper {
  static bool nthBit(number, n) => number & pow(2, n - 1) != 0;
  static int toggleBit(number, n) => (number ^ pow(2, n - 1));
}
