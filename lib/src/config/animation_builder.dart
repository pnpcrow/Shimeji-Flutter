/// Port of `config/AnimationBuilder.java`.
///
/// Pose loading is asynchronous (image decoding); the constructed poses are
/// then reusable synchronously.
library;

import 'package:xml/xml.dart';

import '../animation/animation.dart';
import '../image/image_pairs.dart';
import '../script/variable_map.dart';
import '../settings.dart';
import '../sound/sounds.dart';
import 'exceptions.dart';
import 'configuration.dart';
import 'xml_util.dart';

class AnimationBuilder {
  final Configuration configuration;
  final String imageSet;
  final String? condition;
  late final List<Pose> poses;
  final List<Hotspot> hotspots = [];
  final bool turn;
  late final int duration;

  AnimationBuilder(this.configuration, XmlElement animationNode, this.imageSet)
      : condition = _parseCondition(animationNode.attr(configuration.schema.get('Condition'))),
        turn = animationNode.attr(configuration.schema.get('IsTurn')) == 'true' {
    final schema = configuration.schema;
    if (condition != null) {
      try {
        Variable.parse(condition);
      } on VariableException catch (e) {
        throw ConfigurationException('Failed to parse condition', e);
      }
    }

    final poseNodes =
        animationNode.findElements(schema.get('Pose')).toList();
    if (poseNodes.isEmpty) {
      throw ConfigurationException('No poses in animation');
    }
    // Poses are loaded asynchronously by [loadPoses] before first use.
    poses = [];
    _poseNodes = poseNodes;

    final hotspotNodes =
        animationNode.findElements(schema.get('Hotspot')).toList();
    for (final hotspotNode in hotspotNodes) {
      hotspots.add(_loadHotspot(hotspotNode));
    }
  }

  List<XmlElement>? _poseNodes;
  bool _loaded = false;

  static String? _parseCondition(String text) => text.isEmpty ? null : text;

  /// Asynchronously loads all pose images (called during config load).
  Future<void> loadPoses(Settings settings) async {
    if (_loaded) return;
    _loaded = true;
    for (final poseNode in _poseNodes!) {
      poses.add(await _loadPose(poseNode, settings));
    }
    duration = poses.fold(0, (sum, pose) => sum + pose.duration);
  }

  Future<Pose> _loadPose(XmlElement poseNode, Settings settings) async {
    final schema = configuration.schema;
    final scaling = settings.scaling;

    String? imageKey;
    if (poseNode.hasAttr(schema.get('Image'))) {
      final imagePath = '$imageSet/${poseNode.attr(schema.get('Image'))}';
      final imageRightText = poseNode.attr(schema.get('ImageRight'));
      final imageRightPath =
          imageRightText.isEmpty ? null : '$imageSet/$imageRightText';
      final anchorText = poseNode.attr(schema.get('ImageAnchor'));
      if (anchorText.isEmpty) {
        throw ConfigurationException('Missing ImageAnchor attribute');
      }
      final anchorCoordinates = anchorText.split(',');
      final anchorX = int.parse(anchorCoordinates[0]);
      final anchorY = int.parse(anchorCoordinates[1]);
      final filter = settings.filter;
      try {
        imageKey = await ImagePairs.load(
            imagePath, imageRightPath, anchorX, anchorY, scaling, filter);
        ImagePairs.addUsage(imageKey, imageSet);
      } catch (e) {
        throw ConfigurationException('Failed to load image: $imagePath', e);
      }
    }

    final velocityText = poseNode.attr(schema.get('Velocity'));
    if (velocityText.isEmpty) {
      throw ConfigurationException('Missing Velocity attribute');
    }
    final velocityCoordinates = velocityText.split(',');
    final dx = int.parse(velocityCoordinates[0]);
    final dy = int.parse(velocityCoordinates[1]);
    var scaledDx = javaRound(dx * scaling);
    var scaledDy = javaRound(dy * scaling);
    // Prevent the mascot from being unable to move.
    if (dx != 0 && scaledDx == 0) scaledDx = dx < 0 ? -1 : 1;
    if (dy != 0 && scaledDy == 0) scaledDy = dy < 0 ? -1 : 1;

    final durationText = poseNode.attr(schema.get('Duration'));
    if (durationText.isEmpty) {
      throw ConfigurationException('Missing Duration attribute');
    }
    final duration = int.parse(durationText);

    String? soundKey;
    final soundText = poseNode.attr(schema.get('Sound'));
    if (soundText.isNotEmpty) {
      try {
        final soundPath = configuration.resolveSoundPath(imageSet, soundText);
        final volumeText = poseNode.attr(schema.get('Volume'));
        final volume = volumeText.isEmpty ? 0.0 : double.parse(volumeText);
        soundKey = await Sounds.load(soundPath, volume);
        Sounds.addUsage(soundKey, imageSet);
      } catch (e) {
        throw ConfigurationException('Failed to load sound: $soundText', e);
      }
    }

    return Pose(
      imageKey: imageKey,
      dx: scaledDx,
      dy: scaledDy,
      duration: duration,
      soundKey: soundKey,
    );
  }

  Hotspot _loadHotspot(XmlElement hotspotNode) {
    final schema = configuration.schema;
    final shapeText = hotspotNode.attr(schema.get('Shape'));
    if (shapeText.isEmpty) {
      throw ConfigurationException('Missing Shape attribute');
    }
    final originText = hotspotNode.attr(schema.get('Origin'));
    if (originText.isEmpty) {
      throw ConfigurationException('Missing Origin attribute');
    }
    final sizeText = hotspotNode.attr(schema.get('Size'));
    if (sizeText.isEmpty) {
      throw ConfigurationException('Missing Size attribute');
    }
    final behaviourText = hotspotNode.attr(schema.get('Behaviour'));
    final scaling = configuration.settings.scaling;
    final originCoordinates = originText.split(',');
    final sizeCoordinates = sizeText.split(',');
    final originX = javaRound(int.parse(originCoordinates[0]) * scaling);
    final originY = javaRound(int.parse(originCoordinates[1]) * scaling);
    final width = javaRound(int.parse(sizeCoordinates[0]) * scaling);
    final height = javaRound(int.parse(sizeCoordinates[1]) * scaling);

    return Hotspot(
      shape: shapeText.toLowerCase(),
      originX: originX,
      originY: originY,
      width: width,
      height: height,
      behaviour: behaviourText.isEmpty ? null : behaviourText,
    );
  }

  void validate() {
    for (final hotspot in hotspots) {
      final behavior = hotspot.behaviour;
      if (behavior != null &&
          !configuration.behaviorBuilders.containsKey(behavior)) {
        throw ConfigurationException('No behavior found: $behavior');
      }
    }
  }

  Animation buildAnimation() {
    try {
      return Animation(
        condition: condition == null ? null : Variable.parse(condition),
        poses: poses,
        hotspots: hotspots,
        turn: turn,
        duration: duration,
      );
    } on VariableException {
      throw AnimationInstantiationException('Failed to parse condition');
    }
  }
}
