import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

void probe() {
  try {
     sherpa.init(); 
  } catch(e) {}
  
  try {
     sherpa.initBindings();
  } catch(e) {}
  
  try {
     sherpa.SherpaOnnx.init();
  } catch(e) {}

  try {
    sherpa.SherpaOnnxLoader.init();
  } catch(e) {}
}
