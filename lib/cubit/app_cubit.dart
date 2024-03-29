import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:crop_your_image/crop_your_image.dart';
import 'package:dio/dio.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:gallery_saver/gallery_saver.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';
import 'package:path_provider/path_provider.dart';

import '../../../generated/l10n.dart';

part 'app_state.dart';

class AppCubit extends Cubit<AppState> {
  AppCubit() : super(AppInitial());

  static AppCubit get(context) => BlocProvider.of(context);
  dynamic user;
  int bodyIndex = 0;
  bool cameraInitiated = false;
  late List<CameraDescription> cameras;
  late double maxZoom, minZoom, zoomLevel;
  late CameraController controller;
  final _firebaseStorage = FirebaseStorage.instance;
  final dbRef = FirebaseDatabase.instance.ref().child('users');
  final String apiHeroku = "https://screye.herokuapp.com/api/v3/";
  final String apiAzure =
      "https://screyeapi.azurewebsites.net/api/screyeapiv1/";
  String test_result = "";
  double sliderVal = 1.0;

  void ChangeBodyIndex(idx) {
    bodyIndex = idx;
    emit(ChangedBodyIndex());
  }

  void updateZoomLevel(val) async {
    await controller.setZoomLevel(val);
    sliderVal = val;
    emit(ZoomLevelChanged());
  }

  bool isOnline = false;

  Future<void> saveImage(String imageName, String imageUrl, context) async {
    try {
      // Download the image
      Response response = await Dio()
          .get(imageUrl, options: Options(responseType: ResponseType.bytes));

      // Get the local storage directory
      Directory? appDocDir = await getApplicationDocumentsDirectory();

      if (appDocDir != null) {
        // Save the image to local storage

        final name = imageName.replaceAll("-", "_");

        File file = File('${appDocDir.path}/IMG_${name}.jpg');
        await file.writeAsBytes(response.data);
        await GallerySaver.saveImage(file.path, albumName: "ScrEye");
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(S.of(context).img_saved_later),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(S.of(context).unknownError),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<bool> checkInternetConnectivity() async {
    var connectivityResult = await Connectivity().checkConnectivity();
    isOnline = connectivityResult == ConnectivityResult.wifi ||
        connectivityResult == ConnectivityResult.mobile;
    return isOnline;
  }

  void startCamera() async {
    cameras = await availableCameras();
    controller =
        CameraController(cameras[0], ResolutionPreset.high, enableAudio: false);
    controller.initialize().then((_) {
      cameraInitiated = true;
      _setZooms();
      controller.setFlashMode(FlashMode.off);
    }).catchError((Object e) {
      if (e is CameraException) {
        switch (e.code) {
          case 'CameraAccessDenied':
            debugPrint('User denied camera access.');
            break;
          default:
            debugPrint('Handle other errors.');
            break;
        }
      }
    });
  }

  void _setZooms() async {
    minZoom = await controller.getMinZoomLevel();
    zoomLevel = minZoom;
    maxZoom = await controller.getMaxZoomLevel();
  }

  void setUser(User) {
    user = User;
  }

  Future<void> ShowCropWidget(
      BuildContext context, Uint8List capturedImage) async {
    final _controller = CropController();
    Uint8List outputimg = capturedImage;
    notLoading();

    await showDialog(
      useSafeArea: false,
      context: context,
      builder: (context) {
        return Scaffold(
          appBar: AppBar(
            title: Text(S.of(context).your_img),
          ),
          body: Stack(
            children: [
              Crop(
                fixArea: true,
                baseColor: Theme.of(context).listTileTheme.tileColor!,
                initialAreaBuilder: (rect) => Rect.fromLTRB(rect.left + 110.w,
                    rect.top + 160.h, rect.right - 110.w, rect.bottom - 370.h),
                controller: _controller,
                image: capturedImage,
                onCropped: (crop) {
                  outputimg = crop;
                },
              ),
              Align(
                alignment: Alignment.bottomCenter,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () async {
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          backgroundColor: const Color(0xFFCE772F),
                          content: Text(S.of(context).img_discarded),
                        ));
                      },
                      icon: const Icon(Icons.delete),
                      label: Text(S.of(context).discard),
                    ),
                    OutlinedButton.icon(
                      onPressed: () async {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          backgroundColor:
                              Theme.of(context).appBarTheme.backgroundColor!,
                          content: Text(S.of(context).loading),
                        ));

                        _controller.crop();

                        await Future.delayed(
                            const Duration(milliseconds: 1500));
                        final tempDir = await getTemporaryDirectory();
                        final now = DateTime.now();
                        final name =
                            '${now.day}-${now.month}-${now.year}-${now.hour}-${now.minute}-${now.second}';
                        final file = await File('${tempDir.path}/${name}.jpg')
                            .writeAsBytes(outputimg);
                        await GallerySaver.saveImage(file.path,
                            albumName: "ScrEye");
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          behavior: SnackBarBehavior.floating,
                          backgroundColor: const Color(0xFF29C469),
                          content: Text(S.of(context).img_saved_later),
                        ));
                      },
                      icon: const Icon(Icons.save_alt),
                      label: Text(S.of(context).save),
                    ),
                    state is! Uploading
                        ? OutlinedButton.icon(
                            label: Text(S.of(context).upload),
                            icon: const Icon(Icons.upload),
                            onPressed: () async {
                              ScaffoldMessenger.of(context)
                                  .showSnackBar(SnackBar(
                                backgroundColor: Theme.of(context)
                                    .appBarTheme
                                    .backgroundColor!,
                                content: Text(S.of(context).loading),
                              ));
                              _controller.crop();
                              await Future.delayed(
                                  const Duration(milliseconds: 1500));
                              uploadImage(image: outputimg).then((data) async {
                                getTest(
                                    imgname: data[0],
                                    token: data[1],
                                    url: data[2]);
                                Navigator.pop(context);
                              });
                            },
                          )
                        : OutlinedButton(
                            onPressed: null,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                LoadingAnimationWidget.threeArchedCircle(
                                    color: Theme.of(context)
                                        .textTheme
                                        .subtitle2!
                                        .color!,
                                    size: 20),
                                SizedBox(width: 10.h),
                                Text(S.of(context).loading)
                              ],
                            ),
                          ),
                  ],
                ),
              )
            ],
          ),
        );
      },
    );

    // stop periodic internet connectivity checks
  }

  void startConnectivityTimer() {
    connectivityTimer = Timer.periodic(Duration(seconds: 3), (timer) async {
      var connectivityResult = await Connectivity().checkConnectivity();
      isOnline = connectivityResult == ConnectivityResult.wifi ||
          connectivityResult == ConnectivityResult.mobile;
    });
  }

  late Timer connectivityTimer;

  void stopConnectivityTimer() {
    connectivityTimer.cancel();
  }

  void loading() async {
    emit(Loading());
  }

  void notLoading() async {
    emit(NotLoading());
  }

  void uploading() async {
    emit(Uploading());
  }

  void doneUploading() async {
    emit(DoneUploading());
  }

  Future<List> uploadImage({
    required dynamic image,
  }) async {
    notLoading();
    uploading();

    try {
      final tempDir = await getTemporaryDirectory();
      final now = DateTime.now();
      final name =
          '${now.day}-${now.month}-${now.year}-${now.hour}-${now.minute}-${now.second}';
      File file = await File('${tempDir.path}/image.jpg').create();

      if (image.runtimeType == XFile) {
        file = File(image.path);
      } else {
        file.writeAsBytesSync(image);
      }
      if (await checkInternetConnectivity()) {
        if (image != null) {
          final snapshot = await uploadFileToFirebase(file, name);
          final downloadUrl = await getDownloadUrl(snapshot);
          final token = parseTokenFromUrl(downloadUrl);

          print('url= $downloadUrl');
          doneUploading();
          return [name, token, downloadUrl];
        }
      }

      doneUploading();
      return ["name", "token"];
    } catch (e) {
      //debugPrint("**"+e.toString());
      doneUploading();
      return ["name", "token"];
    }
  }

  Future<dynamic> uploadFileToFirebase(File file, String name) async {
    return await _firebaseStorage
        .ref()
        .child('images/${user.uid}/$name')
        .putFile(file);
  }

  Future<String> getDownloadUrl(dynamic snapshot) async {
    return await snapshot.ref.getDownloadURL();
  }

  String parseTokenFromUrl(String downloadUrl) {
    const startWord = "token=";
    final startIndex = downloadUrl.indexOf(startWord);
    final endIndex = downloadUrl.length;
    return downloadUrl.substring(startIndex + startWord.length, endIndex);
  }

  void getTest({
    required String imgname,
    required String token,
    required String url,
  }) async {
    bodyIndex = 2;
    emit(WaitingResult());

    try {
      final res = await getApiRequest(imgname: imgname, token: token);
      test_result = res;
      final now = DateTime.now().millisecondsSinceEpoch;

      final imageData = {
        'name': imgname,
        'url': url,
        'result': res,
        'time': now,
      };
      await writeImageDataToDatabase(imageData, now.toString());

      emit(TestDone());
    } catch (e) {
      print(e.toString());
      emit(TestError());
    }
  }

  Future<void> writeImageDataToDatabase(
      Map<String, dynamic> imageData, String key) async {
    await dbRef.child(user.uid).child("images").child(key).set(imageData);
  }

  String buildUrl({
    required String baseUrl,
    required String imgname,
    required String token,
    required String uid,
  }) =>
      "$baseUrl?id=$imgname&token=$token&uid=$uid";

  Future<String> getApiRequest({
    required String imgname,
    required String token,
  }) async {
    final String url = buildUrl(
      baseUrl: apiHeroku,
      imgname: imgname,
      token: token,
      uid: user.uid,
    );
    print("api url=:$url");
    final dio = Dio();
    try {
      final response = await dio.get(url);
      print(response.data);
      return response.data;
    } on DioError catch (e) {
      print(e.message);
      rethrow;
    }
  }
}
