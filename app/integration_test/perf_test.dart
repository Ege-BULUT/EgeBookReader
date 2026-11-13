// The 10,000-book limits of test/perf_test.dart, measured on the device: its printed numbers give the phone multiplier.
import 'package:integration_test/integration_test.dart';

import '../test/perf_test.dart' as perf;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  perf.main();
}
