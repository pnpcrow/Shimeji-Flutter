/// XML helpers mirroring the Java `Entry` class (namespace-aware child
/// selection by local name).
library;

import 'package:xml/xml.dart';

/// Java-style attribute helpers: getAttribute returns '' for missing
/// attributes, hasAttribute mirrors Entry.hasAttribute.
extension XmlJavaCompat on XmlElement {
  String attr(String localName) => getAttribute(localName) ?? '';
  bool hasAttr(String localName) => getAttribute(localName) != null;
}

extension XmlChildSelection on XmlElement {
  /// Direct child elements with the given local name.
  Iterable<XmlElement> namedChildren(String localName) =>
      childElements.where((e) => e.name.local == localName);

  bool isNamed(String localName) => name.local == localName;

  /// First direct child element with the given local name.
  XmlElement? namedChild(String localName) {
    for (final child in childElements) {
      if (child.name.local == localName) return child;
    }
    return null;
  }

  /// Concatenated text of all descendant text nodes.
  String get textContent => innerText;
}
