/// Port of `image/Filter.java`.
enum Filter {
  nearestNeighbour,
  bicubic,
  hqx;

  static Filter fromSetting(String text) {
    final t = text.toLowerCase();
    if (t == 'true' || t == 'hqx') return Filter.hqx;
    if (t == 'bicubic') return Filter.bicubic;
    return Filter.nearestNeighbour;
  }
}
