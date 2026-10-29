import "package:dio/dio.dart";
import "package:shared_preferences/shared_preferences.dart";

import "bili_api_error.dart";
import "ticket.dart";
import "types.dart";

const _cacheCreatedAtKey = "bili_catch_created_at";
const _signImgKey = "bili_sign_img_key";
const _signSubKey = "bili_sign_sub_key";
const _ticketKey = "bili_ticket";
const _spiB3 = "bili_spi_b3";
const _spiB4 = "bili_spi_b4";
const _cacheVersionKey = "bili_cache_version";
const _cacheVersionValue = "4";
const _bNutKey = "bili_b_nut";
const _buvid3Key = "bili_buvid3";
const _bNutCreatedAtKey = "bili_b_nut_created_at";

/// 鉴权材料按实际时间过期；普通初始化和风控重刷都合并并发请求。
class BiliAuth {
  final Dio _dio;
  final DateTime Function() _now;
  final Duration cacheTtl;

  SignData? signData;
  SpiData? spiData;
  String? ticket;
  String? bNut;

  BiliBNut? _bNutCache;
  DateTime? _bNutExpiresAt;
  DateTime? _expiresAt;
  Future<void>? _inFlight;

  BiliAuth({
    Dio? dio,
    DateTime Function()? now,
    this.cacheTtl = const Duration(hours: 24),
  })  : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 15),
            )),
        _now = now ?? DateTime.now {
    _dio.options.headers["User-Agent"] =
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36";
    _dio.options.headers["Referer"] = "https://www.bilibili.com/";
  }

  bool get _ready =>
      signData != null &&
      spiData != null &&
      ticket?.isNotEmpty == true &&
      _expiresAt != null &&
      _now().isBefore(_expiresAt!);

  Future<void> ensure() => _start(force: false);

  /// 风控后跳过旧持久缓存，只做一次完整重刷，不在 SDK 内循环重试。
  Future<void> refresh() => _start(force: true);

  Future<void> _start({required bool force}) =>
      _inFlight ??= _doEnsure(force: force).whenComplete(() {
        _inFlight = null;
      });

  bool _fresh(int? createdAt) {
    if (createdAt == null) return false;
    final age = _now().difference(
      DateTime.fromMillisecondsSinceEpoch(createdAt),
    );
    return !age.isNegative && age < cacheTtl;
  }

  Future<void> _doEnsure({required bool force}) async {
    if (!force && _ready) return;
    final prefs = await SharedPreferences.getInstance();
    if (force) {
      // 失效材料不能在重刷失败后又从 prefs 还原回来。
      await prefs.remove(_cacheCreatedAtKey);
      await prefs.remove(_bNutCreatedAtKey);
      _bNutCache = null;
      _bNutExpiresAt = null;
    }
    _expiresAt = null;
    signData = null;
    spiData = null;
    ticket = null;
    bNut = null;

    BiliBNut? bnut;
    try {
      bnut = await _loadOrFetchBNut(prefs);
    } catch (e) {
      // 主页 cookie 为补充材料；主页暂不可达时仍可用 spi 完成匿名鉴权。
      print("B 站主页指纹获取失败，尝试 spi：$e");
    }
    bNut = bnut?.bNut;
    if (!force && _restoreFromCache(prefs, bnut)) return;

    try {
      final results = await Future.wait<Object>([
        _getSignData(),
        _getSpiData(),
        getBiliTicket("", dio: _dio),
      ]);
      final sign = results[0] as SignData;
      final spi = results[1] as SpiData;
      final fetchedTicket = results[2] as String;
      if (sign.imgKey.isEmpty ||
          sign.subKey.isEmpty ||
          spi.b3.isEmpty ||
          fetchedTicket.isEmpty) {
        throw const BiliAuthError("鉴权响应缺少必要材料");
      }
      final now = _now();
      signData = sign;
      spiData = SpiData(
        b3: bnut?.b3.isNotEmpty == true ? bnut!.b3 : spi.b3,
        b4: spi.b4,
      );
      ticket = fetchedTicket;
      await Future.wait([
        prefs.setString(_cacheVersionKey, _cacheVersionValue),
        prefs.setInt(_cacheCreatedAtKey, now.millisecondsSinceEpoch),
        prefs.setString(_ticketKey, fetchedTicket),
        prefs.setString(_signImgKey, sign.imgKey),
        prefs.setString(_signSubKey, sign.subKey),
        prefs.setString(_spiB3, spiData!.b3),
        prefs.setString(_spiB4, spi.b4),
      ]);
      _expiresAt = now.add(cacheTtl);
    } on BiliApiError {
      rethrow;
    } catch (e) {
      throw BiliAuthError("鉴权材料获取失败", cause: e);
    }
  }

  String? cookieHeader() {
    final parts = <String>[];
    void add(String key, String? value) {
      if (value?.isNotEmpty == true) parts.add("$key=$value;");
    }

    add("buvid4", spiData?.b4);
    add("buvid3", spiData?.b3);
    add("bili_ticket", ticket);
    add("b_nut", bNut);
    return parts.isEmpty ? null : parts.join(" ");
  }

  Future<BiliBNut?> _loadOrFetchBNut(SharedPreferences prefs) async {
    if (_bNutCache != null &&
        _bNutExpiresAt != null &&
        _now().isBefore(_bNutExpiresAt!)) {
      return _bNutCache;
    }
    final createdAt = prefs.getInt(_bNutCreatedAtKey);
    final cachedNut = prefs.getString(_bNutKey);
    if (_fresh(createdAt) && cachedNut?.isNotEmpty == true) {
      _bNutExpiresAt =
          DateTime.fromMillisecondsSinceEpoch(createdAt!).add(cacheTtl);
      return _bNutCache = BiliBNut(
        bNut: cachedNut!,
        b3: prefs.getString(_buvid3Key) ?? "",
      );
    }
    final response = await _dio.get("https://www.bilibili.com/");
    String pick(String name) {
      final cookie = response.headers["set-cookie"]
          ?.where((item) => item.startsWith("$name="))
          .firstOrNull;
      if (cookie == null) return "";
      final pair = cookie.split(";").first;
      return pair.substring(pair.indexOf("=") + 1);
    }

    final fetched = BiliBNut(bNut: pick("b_nut"), b3: pick("buvid3"));
    final now = _now();
    _bNutCache = fetched;
    _bNutExpiresAt = now.add(cacheTtl);
    await Future.wait([
      prefs.setString(_bNutKey, fetched.bNut),
      prefs.setString(_buvid3Key, fetched.b3),
      prefs.setInt(_bNutCreatedAtKey, now.millisecondsSinceEpoch),
    ]);
    return fetched;
  }

  bool _restoreFromCache(SharedPreferences prefs, BiliBNut? bnut) {
    final createdAt = prefs.getInt(_cacheCreatedAtKey);
    if (!_fresh(createdAt) ||
        prefs.getString(_cacheVersionKey) != _cacheVersionValue) {
      return false;
    }
    final img = prefs.getString(_signImgKey);
    final sub = prefs.getString(_signSubKey);
    final b3 = prefs.getString(_spiB3);
    final b4 = prefs.getString(_spiB4);
    final cachedTicket = prefs.getString(_ticketKey);
    if (img?.isNotEmpty != true ||
        sub?.isNotEmpty != true ||
        b3?.isNotEmpty != true ||
        b4 == null ||
        cachedTicket?.isNotEmpty != true) {
      return false;
    }
    signData = SignData(imgKey: img!, subKey: sub!);
    spiData = SpiData(
      b3: bnut?.b3.isNotEmpty == true ? bnut!.b3 : b3!,
      b4: b4,
    );
    ticket = cachedTicket;
    _expiresAt = DateTime.fromMillisecondsSinceEpoch(createdAt!).add(cacheTtl);
    return true;
  }

  Future<SignData> _getSignData() async {
    try {
      final response =
          await _dio.get("https://api.bilibili.com/x/web-interface/nav");
      return SignData.fromJson(response.data);
    } catch (e) {
      throw BiliAuthError("WBI 密钥获取失败", cause: e);
    }
  }

  Future<SpiData> _getSpiData() async {
    try {
      final response =
          await _dio.get("https://api.bilibili.com/x/frontend/finger/spi");
      if (response.data["code"] != 0) {
        throw const BiliAuthError("spi 指纹请求被拒绝");
      }
      return SpiData.fromJson(response.data);
    } catch (e) {
      throw BiliAuthError("spi 指纹获取失败", cause: e);
    }
  }
}
