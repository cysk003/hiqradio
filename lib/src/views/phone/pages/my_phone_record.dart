import 'dart:io';
import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:hiqradio/src/app/iconfont.dart';
import 'package:hiqradio/src/blocs/app_cubit.dart';
import 'package:hiqradio/src/blocs/record_cubit.dart';
import 'package:hiqradio/src/models/record.dart';
import 'package:hiqradio/src/models/station.dart';
import 'package:hiqradio/src/utils/pair.dart';
import 'package:hiqradio/src/views/components/ink_click.dart';
import 'package:hiqradio/src/views/components/station_placeholder.dart';
import 'package:hiqradio/src/views/phone/components/my_slidable_action.dart';
import 'package:intl/intl.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:oktoast/oktoast.dart';
import 'package:permission_handler/permission_handler.dart';

class MyPhoneRecord extends StatefulWidget {
  const MyPhoneRecord({super.key});

  @override
  State<MyPhoneRecord> createState() => _MyPhoneRecordState();
}

class _MyPhoneRecordState extends State<MyPhoneRecord>
    with AutomaticKeepAliveClientMixin {
  ScrollController scrollController = ScrollController();
  int selectedId = -1;
  @override
  void initState() {
    super.initState();
    context.read<RecordCubit>().loadRecord();
  }

  @override
  void dispose() {
    super.dispose();
    scrollController.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    List<Pair<Station, Record>> records =
        context.select<RecordCubit, List<Pair<Station, Record>>>(
            (value) => value.state.records);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: records.isNotEmpty ? _buildRecord(records) : _empty())
        ],
      ),
    );
  }

  Widget _empty() {
    bool isLoading =
        context.select<RecordCubit, bool>((value) => value.state.isLoading);
    if (isLoading) {
      return Center(
        child: Container(
          height: 40.0,
          width: 40.0,
          padding: const EdgeInsets.all(4.0),
          child: CircularProgressIndicator(
            strokeWidth: 1.0,
            color: Colors.white.withOpacity(0.8),
          ),
        ),
      );
    }
    return Center(
      child: Text(
        // '暂无录音记录',
        AppLocalizations.of(context)!.record_empty,

        style: const TextStyle(
          fontSize: 15.0,
        ),
      ),
    );
  }

  Widget _buildRecord(List<Pair<Station, Record>> records) {
    Record? playingRecord = context.select<AppCubit, Record?>(
      (value) => value.state.playingRecord,
    );

    return ListView.builder(
      itemBuilder: (context, index) {
        Pair<Station, Record> pair = records[index];

        Station station = pair.p1;
        Record record = pair.p2;

        Size winSize = MediaQuery.of(context).size;

        return Slidable(
          key: ValueKey(index),
          endActionPane: ActionPane(
              extentRatio: 1,
              motion: const BehindMotion(),
              children: [
                if (record.file != null)
                  MySlidableAction(
                    isFirst: true,
                    isEnd: false,
                    color: Colors.green,
                    icon: IconFont.quit,
                    onPressed: () async {
                      _exportRecord(record);
                    },
                  ),
                MySlidableAction(
                  isFirst: record.file == null,
                  isEnd: true,
                  color: Colors.red,
                  icon: IconFont.delete,
                  iconSize: 30,
                  onPressed: () {
                    context.read<RecordCubit>().delRecord(record.id!);
                    if (record.file != null) {
                      File input = File(record.file!);
                      input.delete();
                    }
                  },
                ),
              ]),
          child: Container(
            margin: const EdgeInsets.all(3.0),
            padding: const EdgeInsets.all(5.0),
            decoration: BoxDecoration(
                color: Theme.of(context).canvasColor,
                borderRadius: BorderRadius.circular(5.0)),
            child: Row(
              children: [
                GestureDetector(
                  child: StationRecord(
                    onClicked: () {
                      setState(() {
                        selectedId = record.id!;
                      });
                      if (playingRecord != null &&
                          playingRecord.id == record.id) {
                        context.read<AppCubit>().stopPlayRecord();
                      } else {
                        context.read<AppCubit>().playRecord(record);
                      }
                    },
                    width: winSize.width - 68,
                    height: 60.0,
                    station: station,
                    record: record,
                  ),
                  onTap: () {
                    setState(() {
                      selectedId = record.id!;
                    });
                    if (playingRecord != null &&
                        playingRecord.id == record.id) {
                      context.read<AppCubit>().stopPlayRecord();
                    } else {
                      context.read<AppCubit>().playRecord(record);
                    }
                  },
                  onLongPressEnd: (details) {
                    showContextMenu(details.globalPosition, record);
                  },
                ),
                playingRecord != null && playingRecord.id == record.id
                    ? Icon(
                        IconFont.volume,
                        size: 28.0,
                        color: Colors.red.withOpacity(0.8),
                      )
                    : InkClick(
                        onTap: () {},
                        child: Icon(
                          IconFont.volume,
                          size: 28.0,
                          color: Colors.red.withOpacity(0.0),
                        ),
                      )
              ],
            ),
          ),
        );
      },
      itemCount: records.length,
      controller: scrollController,
    );
  }

  void _exportRecord(Record record) async {
    String? selectedDirectory = await FilePicker.platform.getDirectoryPath();

    if (selectedDirectory != null) {
      String file = record.file!;
      int index = file.lastIndexOf(Platform.pathSeparator);
      String fileName = file.substring(index + 1);
      String outFileName =
          '$selectedDirectory${Platform.pathSeparator}$fileName';

      if (await Permission.manageExternalStorage.request().isGranted) {
        File input = File(record.file!);
        File output = File(outFileName);
        if (!await output.exists()) {
          await output.create(recursive: true);
        }
        Uint8List data = await input.readAsBytes();
        await output.writeAsBytes(data.toList());
        showToast(
            '${AppLocalizations.of(context)!.record_export_msg}  $outFileName',
            position: const ToastPosition(
              align: Alignment.bottomCenter,
            ),
            duration: const Duration(seconds: 3));
      }
    }
  }

  void showContextMenu(Offset offset, Record record) {
    showMenu(
        context: context,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(5.0),
        ),
        position: RelativeRect.fromLTRB(
            offset.dx, offset.dy + 5.0, offset.dx, offset.dy),
        items: [
          _popMenuItem(() {
            context.read<RecordCubit>().delRecord(record.id!);
            if (record.file != null) {
              File input = File(record.file!);
              input.delete();
            }
          },
              IconFont.delete,
              // '删除录音'
              AppLocalizations.of(context)!.record_delete),
          if (record.file != null)
            _popMenuItem(() {
              _exportRecord(record);
            }, IconFont.quit, AppLocalizations.of(context)!.record_export),
        ],
        elevation: 8.0);
  }

  PopupMenuItem<Never> _popMenuItem(
      VoidCallback onTap, IconData icon, String text) {
    return PopupMenuItem<Never>(
      mouseCursor: SystemMouseCursors.basic,
      height: 30.0,
      onTap: () => onTap(),
      padding: const EdgeInsets.all(0.0),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6.0, horizontal: 6.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 18.0, right: 12.0),
              child: Icon(
                icon,
                size: 16.0,
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 2.0),
              child: Text(
                text,
                style: const TextStyle(fontSize: 16.0),
              ),
            )
          ],
        ),
      ),
    );
  }

  @override
  bool get wantKeepAlive => true;
}

class StationRecord extends StatelessWidget {
  final VoidCallback? onClicked;
  final double width;
  final double height;
  final Station station;
  final Record record;
  const StationRecord(
      {super.key,
      this.onClicked,
      required this.width,
      required this.height,
      required this.station,
      required this.record});

  @override
  Widget build(BuildContext context) {
    // String sDuration = '';
    // if (record.endTime != null) {
    //   var duration = DateTime.fromMillisecondsSinceEpoch(record.endTime!)
    //       .difference(DateTime.fromMillisecondsSinceEpoch(record.startTime));
    //   sDuration =
    //       "${duration.inHours.toString().padLeft(2, '0')}:${duration.inMinutes.remainder(60).toString().padLeft(2, '0')}:${(duration.inSeconds.remainder(60)).toString().padLeft(2, '0')}";
    // }

    return SizedBox(
      height: height,
      width: width,
      child: Row(
        children: [
          InkClick(
            onTap: () => onClicked?.call(),
            child: SizedBox(
              height: height,
              width: height,
              child: ClipRRect(
                borderRadius: const BorderRadius.all(Radius.circular(5.0)),
                child: station.favicon != null && station.favicon!.isNotEmpty
                    ? CachedNetworkImage(
                        fit: BoxFit.fill,
                        imageUrl: station.favicon!,
                        placeholder: (context, url) {
                          return const StationPlaceholder(
                            height: 60.0,
                            width: 60.0,
                          );
                        },
                        errorWidget: (context, url, error) {
                          return const StationPlaceholder(
                            height: 60.0,
                            width: 60.0,
                          );
                        },
                      )
                    : const StationPlaceholder(
                        height: 60.0,
                        width: 60.0,
                      ),
              ),
            ),
          ),
          const SizedBox(
            width: 8.0,
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Spacer(),
              SizedBox(
                width: width - height - 8.0,
                child: Text(
                  station.name,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 15),
                ),
              ),
              SizedBox(
                width: width - height - 8.0,
                child: Text(
                  '开始: ${DateFormat("yyyy-MM-dd HH:mm:ss").format(
                    DateTime.fromMillisecondsSinceEpoch(record.startTime),
                  )}',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 12, color: Colors.grey.withOpacity(0.8)),
                ),
              ),
              SizedBox(
                width: width - height - 8.0,
                child: Text(
                  record.endTime != null
                      ? '结束: ${DateFormat("yyyy-MM-dd HH:mm:ss").format(
                          DateTime.fromMillisecondsSinceEpoch(record.endTime!),
                        )}'
                      : '',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 12, color: Colors.grey.withOpacity(0.8)),
                ),
              ),
              // SizedBox(
              //   width: width - height - 8.0,
              //   child: Text(
              //     record.endTime != null ? '时长(估): $sDuration' : '',
              //     overflow: TextOverflow.ellipsis,
              //     style: TextStyle(
              //         fontSize: 12, color: Colors.grey.withOpacity(0.8)),
              //   ),
              // ),
              const Spacer(),
            ],
          )
        ],
      ),
    );
  }
}
