import 'package:image_picker/image_picker.dart';

class MyImagePicker {
  final ImagePicker _picker = ImagePicker();

  Future<XFile?> pickFromGallery() async {
    return _picker.pickImage(source: ImageSource.gallery);
  }

  Future<XFile?> pickFromCamera() async {
    return _picker.pickImage(source: ImageSource.camera);
  }
}