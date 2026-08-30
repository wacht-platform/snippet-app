import 'package:open_filex/open_filex.dart';
import 'package:url_launcher/url_launcher.dart';

import 'platform.dart';

/// Open a downloaded local file with the platform's default application.
/// open_filex has no macOS or Windows implementation, so those use the OS
/// file-URI handler (Launch Services / ShellExecute) via launchUrl instead.
Future<bool> openLocalFile(String path) async {
  if (kMacOS || kWindows) {
    return launchUrl(Uri.file(path), mode: LaunchMode.externalApplication);
  }
  final result = await OpenFilex.open(path);
  return result.type == ResultType.done;
}
