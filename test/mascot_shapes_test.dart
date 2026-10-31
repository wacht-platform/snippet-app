import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/mochi.dart';
import 'package:snippet/models.dart';

void main() {
  test('shape names map to shapes and fall back to mochi', () {
    expect(mascotShapeNamed('bunny'), MascotShape.bunny);
    expect(mascotShapeNamed('onigiri'), MascotShape.onigiri);
    expect(mascotShapeNamed('nope'), MascotShape.mochi);
    expect(mascotShapeNamed(null), MascotShape.mochi);
  });

  test('agents carry their shape and the remembered map drives the mascot', () {
    final a = CoordinationAgent.fromJson({'id': 'ada', 'shape': 'cat'});
    expect(a.shape, 'cat');
    rememberAgentShapes([('ada', a.shape)]);
    expect(mascotShapeFor('ada'), MascotShape.cat);
    setRememberedAgentShape('ada', null);
    expect(mascotShapeFor('ada'), MascotShape.mochi);
    rememberAgentShapes(const []);
  });
}
