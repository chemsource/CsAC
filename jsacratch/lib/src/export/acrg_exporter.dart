import '../models/project.dart';
import 'acr_exporter.dart';

/// Export a project with multiple scripts as .acrg format.
/// .acrg is multiple JS scripts in one file with separators and markers.
String exportAcrg(JsacratchProject project) {
  final buf = StringBuffer();
  buf.writeln('/// @acrg-project');
  buf.writeln('/// @name ${project.name}');
  buf.writeln('/// @generated-by jsacratch');
  buf.writeln();

  for (var i = 0; i < project.scripts.length; i++) {
    final script = project.scripts[i];
    buf.writeln('/// === SCRIPT_BEGIN: ${script.name} ===');
    buf.writeln('/// @acr-script');
    buf.writeln('/// @name ${script.name}');
    buf.writeln('/// @index $i');
    buf.writeln();

    if (script.blocks.isNotEmpty) {
      buf.write(generateCodeFromBlocks(script.blocks));
    } else if (script.code.isNotEmpty) {
      buf.writeln(script.code);
    }

    buf.writeln();
    buf.writeln('/// === SCRIPT_END: ${script.name} ===');
    buf.writeln();
  }

  return buf.toString();
}
