import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:path/path.dart' as path;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_uploader/flutter_uploader.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:upflutter/Model/ListItem.dart';
import 'package:upflutter/Widgets/HistoryItem.dart';
import 'package:upflutter/Widgets/UploadItem.dart';
import 'dart:convert';
import 'Widgets/Detail.dart';
import 'main.dart';

class UploadPage extends State<MyHomePage> {
  final Color primary = Color(0xff456990);
  final Color primaryDark = Color(0xff3c5c80);
  final Color primaryTwo = Color(0xff3d546e);
  final Color green = Color(0xff49BEAA);

  File file;
  String selectedFile;
  double progress;
  String key;
  String link;
  List<ListItem> historyItems = new List<ListItem>();
  SharedPreferences prefs;
  final url = "https://up.snet.ovh/";
  final uploader = FlutterUploader();
  StreamSubscription _intentDataStreamSubscription;
  String _sharedText;

  String get _fileName {
    return file.path.split("/").last;
  }

  /// Initialize app
  @override
  void initState() {
    super.initState();
    // Init history
    SharedPreferences.getInstance().then((SharedPreferences sp) {
      prefs = sp;
      setState(() {
        List<dynamic> map = jsonDecode(prefs.get("history"));
        historyItems.clear();
        map.forEach((value) {
          historyItems.add(ListItem.fromJson(value));
        });
      });
    });
    // clean of outdated files
    new Timer.periodic(
        Duration(seconds: 1),
        (Timer t) => setState(() {
              while (historyItems.first.endMilisecond <=
                  DateTime.now().millisecondsSinceEpoch)
                historyItems.removeAt(0);
            }));
    // For sharing images coming from outside the app while the app is in the memory
    _intentDataStreamSubscription =
        ReceiveSharingIntent.getMediaStream().listen((List<SharedMediaFile> value) {
          setState(() {
            file = new File(value[0].path);
            selectedFile = path.basename(file.path);
            uploadFile(file);
          });
        }, onError: (err) {
          print("getIntentDataStream error: $err");
        });

    // For sharing images coming from outside the app while the app is closed
    ReceiveSharingIntent.getInitialMedia().then((List<SharedMediaFile> value) {
      setState(() {
        file = new File(value[0].path);
        selectedFile = path.basename(file.path);
        uploadFile(file);
      });
    });

    // For sharing or opening urls/text coming from outside the app while the app is in the memory
    _intentDataStreamSubscription =
        ReceiveSharingIntent.getTextStream().listen((value) {
          setState(() {
            String _sharedText = value;
          });
        }, onError: (err) {
          print("getLinkStream error: $err");
        });

    // For sharing or opening urls/text coming from outside the app while the app is closed
    ReceiveSharingIntent.getInitialText().then((String value) {
      setState(() {
        String sharedText = value;
      });
    });
  }

  @override
  void dispose() {
    _intentDataStreamSubscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
          title: Text(
            "UP - file hosting",
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          backgroundColor: primaryDark,
        ),
        floatingActionButton: Padding(
          padding: EdgeInsets.fromLTRB(0, 0, 20, 20),
          child: FloatingActionButton(
            backgroundColor: primaryTwo,
            child: Icon(
              Icons.add,
              color: green,
            ),
            onPressed: selectFile,
          ),
        ),
        body: CustomScrollView(
          slivers: <Widget>[
            SliverList(
              delegate: SliverChildListDelegate([
                Visibility(
                  visible: selectedFile != null,
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(15, 10, 20, 10),
                    child: UploadItem(
                      progress: progress,
                      fileName: selectedFile,
                      onCancel: cancel,
                    ),
                  ),
                ),
                Visibility(
                  visible: historyItems.length == 0,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(0, 20, 0, 0),
                      child: Opacity(
                        opacity: 0.4,
                        child: Text(
                          'Click "+" to upload file',
                          style: TextStyle(
                              color: primaryTwo,
                              fontWeight: FontWeight.bold,
                              fontSize: 20),
                        ),
                      ),
                    ),
                  ),
                )
              ]),
            ),
            SliverList(
              delegate: SliverChildBuilderDelegate((context, i) {
                return InkWell(
                    focusColor: primaryTwo,
                    onTap: () =>
                        showShare(historyItems[historyItems.length - i - 1]),
                    child: HistoryItem(
                        listItem: historyItems[historyItems.length - i - 1]));
              }, childCount: historyItems.length),
            )
          ],
        ),
        backgroundColor: primary);
  }

  void showShare(ListItem item) {
    showModalBottomSheet<void>(
        backgroundColor: Color(0x00000000),
        context: context,
        builder: (BuildContext context) {
          return Detail(
            item: item,
          );
        });
  }

  /// selecting file
  Future<void> selectFile() async {
    file = await FilePicker.getFile();
    setState(() {
      selectedFile = path.basename(file.path);
    });
    uploadFile(file);
  }

  /// Upload file
  Future<void> uploadFile(File fileToUpload) async {
    // Listen to progress of upload
    uploader.progress.listen((progress) {
      setState(() {
        this.progress = progress.progress.toDouble() / 100;
      });
    });
    String path = fileToUpload.path;
    await uploader.enqueue(
      url: url + "api/upload",
      files: [
        FileItem(
            filename: path.split("/").last,
            savedDir:
                path.substring(0, path.length - path.split("/").last.length),
            fieldname: "file")
      ],
      method: UploadMethod.POST,
      showNotification: true,
      tag: "upload",
    );
    // listen to result of upload
    uploader.result.listen((result) {
      setState(() async {
        Map<String, dynamic> json = jsonDecode(result.response);
        key = json["key"];
        link = url + "u/" + key;
        if (selectedFile != null) {
          ListItem historyItem = new ListItem(selectedFile,
              DateTime.now().millisecondsSinceEpoch, json["toDelete"], link);
          historyItems.add(historyItem);
        }
        selectedFile = null;
        SharedPreferences prefs = await SharedPreferences.getInstance();
        prefs.setString("history", jsonEncode(historyItems));
      });
    }, onError: (ex, stacktrace) {
      Fluttertoast.showToast(
          msg: "Something went wrong :/",
          toastLength: Toast.LENGTH_SHORT,
          gravity: ToastGravity.TOP,
          timeInSecForIosWeb: 1,
          backgroundColor: Colors.grey,
          textColor: Colors.white,
          fontSize: 16.0);
    });
  }

  /// Cancel uploading
  void cancel() {
    selectedFile = null;
    uploader.cancelAll();
  }
}
