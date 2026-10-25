// S3 阶段 mock 数据（仅保留播放引擎 mock 所需；歌单/歌手/合集已接真数据）

import "../models/track.dart";
// 形状 = §3 域模型，S4 换真播放引擎时本文件删除

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

/// 歌词 mock（S1.4 播放卡歌词视图展示用；真歌词链在 S4.4 接入）
const mockLyrics = [
  "仿佛如同一场梦",
  "我们如此短暂地相逢",
  "你像一阵细雨洒落我心底",
  "那感觉如此神秘",
  "我不禁抬起头看着你",
  "而你并不露痕迹",
  "虽然不言不语",
  "叫人难忘记",
];
