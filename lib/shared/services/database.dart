import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

part 'database.g.dart';

/// 视频资源表
class Videos extends Table {
  TextColumn get id => text()();
  TextColumn get title => text()();
  TextColumn get author => text().withDefault(const Constant(''))();
  TextColumn get platform => text().withDefault(const Constant('unknown'))();
  TextColumn get originalUrl => text()();
  TextColumn get localPath => text()();
  TextColumn get thumbnailPath => text().nullable()();
  IntColumn get durationSeconds => integer().withDefault(const Constant(0))();
  IntColumn get fileSizeBytes => integer().withDefault(const Constant(0))();
  DateTimeColumn get downloadedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// 分组表
class Groups extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  DateTimeColumn get createdAt => dateTime()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}

/// 视频-分组关联表（多对多）
class VideoGroups extends Table {
  TextColumn get videoId => text()();
  TextColumn get groupId => text()();

  @override
  Set<Column> get primaryKey => {videoId, groupId};
}

/// 下载任务表
class DownloadTasks extends Table {
  TextColumn get id => text()();
  TextColumn get url => text()();
  TextColumn get title => text().nullable()();
  TextColumn get author => text().nullable()();
  TextColumn get platform => text().nullable()();
  TextColumn get thumbnailUrl => text().nullable()();
  TextColumn get status => text().withDefault(const Constant('pending'))();
  RealColumn get progress => real().withDefault(const Constant(0.0))();
  IntColumn get totalBytes => integer().nullable()();
  IntColumn get receivedBytes => integer().nullable()();
  TextColumn get errorMessage => text().nullable()();
  TextColumn get localPath => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

@DriftDatabase(tables: [Videos, Groups, VideoGroups, DownloadTasks])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 1;

  // ===== Video CRUD =====

  Stream<List<Video>> watchAllVideos() {
    return (select(videos)
          ..orderBy([(t) => OrderingTerm.desc(t.downloadedAt)]))
        .watch();
  }

  Stream<List<Video>> watchVideosByPlatform(String platform) {
    return (select(videos)
          ..where((t) => t.platform.equals(platform))
          ..orderBy([(t) => OrderingTerm.desc(t.downloadedAt)]))
        .watch();
  }

  Stream<List<Video>> watchVideosByGroup(String groupId) {
    final query = select(videos).join([
      innerJoin(videoGroups, videoGroups.videoId.equalsExp(videos.id)),
    ])
      ..where(videoGroups.groupId.equals(groupId))
      ..orderBy([OrderingTerm.desc(videos.downloadedAt)]);

    return query.watch().map((rows) {
      return rows.map((row) => row.readTable(videos)).toList();
    });
  }

  Future<void> insertVideo(VideosCompanion video) => into(videos).insert(video);

  Future<void> deleteVideo(String id) =>
      (delete(videos)..where((t) => t.id.equals(id))).go();

  Future<void> deleteVideos(List<String> ids) =>
      (delete(videos)..where((t) => t.id.isIn(ids))).go();

  Future<Video?> getVideoById(String id) =>
      (select(videos)..where((t) => t.id.equals(id))).getSingleOrNull();

  // ===== Group CRUD =====

  Stream<List<Group>> watchAllGroups() {
    return (select(groups)
          ..orderBy([(t) => OrderingTerm.asc(t.sortOrder)]))
        .watch();
  }

  Future<void> insertGroup(GroupsCompanion group) =>
      into(groups).insert(group);

  Future<void> updateGroupName(String id, String name) =>
      (update(groups)..where((t) => t.id.equals(id)))
          .write(GroupsCompanion(name: Value(name)));

  Future<void> deleteGroup(String id) async {
    await (delete(videoGroups)..where((t) => t.groupId.equals(id))).go();
    await (delete(groups)..where((t) => t.id.equals(id))).go();
  }

  // ===== Video-Group Relation =====

  Future<void> addVideoToGroup(String videoId, String groupId) =>
      into(videoGroups).insert(
        VideoGroupsCompanion(
          videoId: Value(videoId),
          groupId: Value(groupId),
        ),
        onConflict: DoNothing(),
      );

  Future<void> removeVideoFromGroup(String videoId, String groupId) =>
      (delete(videoGroups)
            ..where((t) =>
                t.videoId.equals(videoId) & t.groupId.equals(groupId)))
          .go();

  // ===== Download Task CRUD =====

  Stream<List<DownloadTask>> watchDownloadTasks() {
    return (select(downloadTasks)
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .watch();
  }

  Future<void> insertDownloadTask(DownloadTasksCompanion task) =>
      into(downloadTasks).insert(task);

  Future<void> updateDownloadTask(String id, DownloadTasksCompanion data) =>
      (update(downloadTasks)..where((t) => t.id.equals(id))).write(data);

  Future<void> deleteDownloadTask(String id) =>
      (delete(downloadTasks)..where((t) => t.id.equals(id))).go();

  Future<void> clearCompletedTasks() =>
      (delete(downloadTasks)..where((t) => t.status.equals('completed'))).go();
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'clip_vault.db'));
    return NativeDatabase.createInBackground(file);
  });
}
