import "../models/playlist.dart";
import "../models/track.dart";

/// S1 阶段 mock 数据（视觉与数量对齐 prototype/style-a-aurora）
/// 形状 = §3 域模型，S3 换 Repository 真数据时整文件删除、页面机械替换

const mockTracks = [
  Track(
    id: "bili:mock_1",
    name: "夜航西飞",
    author: "陈鸿宇",
    duration: 252,
    coverHue: 212,
  ),
  Track(
    id: "bili:mock_2",
    name: "漠河舞厅",
    author: "柳爽",
    duration: 311,
    origin: OriginType.kuwo,
    coverHue: 8,
  ),
  Track(
    id: "bili:mock_3",
    name: "晚风心里吹",
    author: "陈婧霏",
    duration: 238,
    coverHue: 330,
  ),
  Track(
    id: "bili:mock_4",
    name: "起风了",
    author: "买辣椒也用券",
    duration: 325,
    coverHue: 46,
  ),
  Track(
    id: "bili:mock_5",
    name: "光年之外",
    author: "G.E.M. 邓紫棋",
    duration: 235,
    coverHue: 188,
  ),
  Track(
    id: "bili:mock_6",
    name: "句号",
    author: "G.E.M. 邓紫棋",
    duration: 236,
    coverHue: 282,
  ),
  Track(
    id: "kuwo:mock_7",
    name: "失眠飞行",
    author: "接个吻，开一枪",
    duration: 214,
    origin: OriginType.kuwo,
    coverHue: 160,
  ),
  Track(
    id: "local:mock_8",
    name: "白羊",
    author: "徐秉龙 / 沈以诚",
    duration: 266,
    origin: OriginType.local,
    coverHue: 24,
  ),
];

const mockPlaylists = [
  Playlist(id: "pl-1", name: "最近播放", type: PlaylistType.builtIn, count: 37, coverHue: 210),
  Playlist(id: "pl-2", name: "夜色轻电子", type: PlaylistType.custom, count: 23, coverHue: 300),
  Playlist(id: "pl-3", name: "通勤低音量", type: PlaylistType.custom, count: 41, coverHue: 180),
  Playlist(id: "pl-4", name: "翻唱收藏", type: PlaylistType.custom, count: 12, coverHue: 30),
  Playlist(id: "pl-5", name: "雨天钢琴", type: PlaylistType.custom, count: 18, coverHue: 230),
];

/// 自定义歌单（歌单页列表区展示用）
const mockCustomPlaylists = [
  Playlist(id: "pl-2", name: "夜色轻电子", type: PlaylistType.custom, count: 23, coverHue: 300),
  Playlist(id: "pl-3", name: "通勤低音量", type: PlaylistType.custom, count: 41, coverHue: 180),
  Playlist(id: "pl-4", name: "翻唱收藏", type: PlaylistType.custom, count: 12, coverHue: 30),
  Playlist(id: "pl-5", name: "雨天钢琴", type: PlaylistType.custom, count: 18, coverHue: 230),
];

/// 歌手（S1 UI mock；域模型待 S3 搜索功能定义）
class MockSinger {
  final String name;
  final int hue;

  const MockSinger(this.name, this.hue);
}

const mockSingers = [
  MockSinger("陈鸿宇", 212),
  MockSinger("邓紫棋", 282),
  MockSinger("柳爽", 8),
  MockSinger("陈婧霏", 330),
  MockSinger("徐秉龙", 160),
  MockSinger("房东的猫", 200),
];

const mockCollections = [
  Playlist(id: "col-1", name: "华语民谣·深夜电台", type: PlaylistType.collection, count: 128, coverHue: 212),
  Playlist(id: "col-2", name: "国风电子乐集", type: PlaylistType.collection, count: 86, coverHue: 300),
  Playlist(id: "col-3", name: "City Pop 巡游", type: PlaylistType.collection, count: 54, coverHue: 24),
  Playlist(id: "col-4", name: "北欧氛围钢琴", type: PlaylistType.collection, count: 72, coverHue: 230),
];
