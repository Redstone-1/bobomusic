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

/// 缓存版本：改签名/票据算法时递增即可让全量用户重刷材料（继承旧版机制，当前值不变）
const _cacheVersionValue = "4";

/// b_nut/buvid3 持久化键（S2.2：与鉴权三件套同级持久化，消灭每次调用的主页请求）
const _bNutKey = "bili_b_nut";
const _buvid3Key = "bili_buvid3";
const _bNutCreatedAtKey = "bili_b_nut_created_at";

/// 鉴权生命周期（S2.1 拆分）：WBI 密钥 + spi 指纹 + bili_ticket + b_nut
/// - [ensure] 幂等且并发去重；材料来自缓存或网络，失败抛 [BiliAuthError]
/// - [cookieHeader] 供 API 层拦截器注入（playurl 路径不带 cookie 的特判在 API 层）
class BiliAuth {
  final Dio _dio;

  SignData? signData;
  SpiData? spiData;
  String? ticket;
  String? bNut;

  // b_nut 会话内缓存（取过一次本会话不再请求主页）
  BiliBNut? _bNutCache;
  Future<void>? _inFlight;

  BiliAuth({Dio? dio}) : _dio = dio ?? Dio() {
    _dio.options.headers["User-Agent"] =
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36";
    _dio.options.headers["Referer"] = "https://www.bilibili.com/";
  }

  bool get _ready =>
      signData != null &&
      spiData != null &&
      ticket != null &&
      ticket!.isNotEmpty;

  /// 确保鉴权材料就绪：已就绪直接返回；并发调用共享同一次自举
  Future<void> ensure() => _inFlight ??= _doEnsure().whenComplete(() {
        _inFlight = null;
      });

  Future<void> _doEnsure() async {
    if (_ready) return;
    final prefs = await SharedPreferences.getInstance();

    // 1) b_nut/buvid3（持久缓存 → 会话缓存 → 主页请求）
    final bnut = await _loadOrFetchBNut(prefs);
    bNut = bnut?.bNut;

    // 2) 三件套未过期 → 从缓存还原，不发网络请求
    if (await _restoreFromCache(prefs, bnut)) return;

    // 3) 拉取三件套（任一失败 → 类型化上抛，不再静默 print）
    try {
      final results = await Future.wait([
        _getSignData(),
        _getSpiData(),
        getBiliTicket("", dio: _dio),
      ]);
      signData = results[0] as SignData;
      spiData = results[1] as SpiData;
      ticket = results[2] as String;
      // buvid3 以主页 Set-Cookie 为准（与旧版行为一致）
      if (bnut != null && bnut.b3.isNotEmpty && spiData!.b3.isNotEmpty) {
        spiData = SpiData(b3: bnut.b3, b4: spiData!.b4);
      }

      final now = DateTime.now().millisecondsSinceEpoch;
      await prefs.setString(_cacheVersionKey, _cacheVersionValue);
      await prefs.setInt(_cacheCreatedAtKey, now);
      if (ticket != null && ticket!.isNotEmpty) {
        await prefs.setString(_ticketKey, ticket!);
      }
      if (signData != null) {
        await prefs.setString(_signImgKey, signData!.imgKey);
        await prefs.setString(_signSubKey, signData!.subKey);
      }
      if (spiData != null) {
        await prefs.setString(_spiB3, spiData!.b3);
        await prefs.setString(_spiB4, spiData!.b4);
      }
      // b_nut 与三件套同级持久化
      if (bNut != null && bNut!.isNotEmpty) {
        await prefs.setString(_bNutKey, bNut!);
      }
      if (bnut != null && bnut.b3.isNotEmpty) {
        await prefs.setString(_buvid3Key, bnut.b3);
      }
      await prefs.setInt(_bNutCreatedAtKey, now);
    } on BiliApiError {
      rethrow;
    } catch (e) {
      throw BiliAuthError("鉴权材料获取失败", cause: e);
    }
  }

  /// 组装 cookie 头；空值一律跳过（b_nut 为空不写 cookie）。无可用材料返回 null
  String? cookieHeader() {
    final parts = <String>[];
    final b4 = spiData?.b4;
    final b3 = spiData?.b3;
    final tk = ticket;
    final nut = bNut;
    if (b4 != null && b4.isNotEmpty) parts.add("buvid4=$b4;");
    if (b3 != null && b3.isNotEmpty) parts.add("buvid3=$b3;");
    if (tk != null && tk.isNotEmpty) parts.add("bili_ticket=$tk;");
    if (nut != null && nut.isNotEmpty) parts.add("b_nut=$nut;");
    return parts.isEmpty ? null : parts.join(" ");
  }

  // ---- 内部 ----

  Future<BiliBNut?> _loadOrFetchBNut(SharedPreferences prefs) async {
    // 会话内已取 → 直接用（旧版 1 秒内存缓存是每次 API 主页请求的根源）
    if (_bNutCache != null) return _bNutCache;

    // 持久缓存未过期 → 还原
    final createdAt = prefs.getInt(_bNutCreatedAtKey);
    final cachedNut = prefs.getString(_bNutKey);
    final cachedB3 = prefs.getString(_buvid3Key);
    if (createdAt != null &&
        cachedNut != null &&
        cachedNut.isNotEmpty &&
        DateTime.now()
                .difference(DateTime.fromMillisecondsSinceEpoch(createdAt))
                .inDays <=
            1) {
      _bNutCache = BiliBNut(bNut: cachedNut, b3: cachedB3 ?? "");
      return _bNutCache;
    }

    // 主页 Set-Cookie 抓取（首个 firstWhere 加 orElse，缺头不再崩）
    try {
      final response = await _dio.get("https://www.bilibili.com/");
      final setCookie = response.headers["Set-Cookie"];
      String pick(String prefix) {
        final item = setCookie?.where((e) => e.startsWith(prefix)).firstOrNull;
        return item == null ? "" : item.split(";")[0].split("=")[1];
      }

      _bNutCache = BiliBNut(bNut: pick("b_nut"), b3: pick("buvid3"));
      return _bNutCache;
    } on BiliApiError {
      rethrow;
    } on DioException catch (e) {
      // b_nut 属可降级材料：失败不阻塞三件套，但记录类型化原因
      _bNutCache = null;
      throw BiliAuthError("b_nut 获取失败", cause: e);
    }
  }

  Future<bool> _restoreFromCache(
    SharedPreferences prefs,
    BiliBNut? bnut,
  ) async {
    final createAt = prefs.getInt(_cacheCreatedAtKey);
    final cacheVersion = prefs.getString(_cacheVersionKey);
    if (createAt == null || cacheVersion != _cacheVersionValue) return false;

    final isExpired = DateTime.now()
        .difference(DateTime.fromMillisecondsSinceEpoch(createAt))
        .inDays >
        1;
    if (isExpired) return false;

    final imgKey = prefs.getString(_signImgKey);
    final subKey = prefs.getString(_signSubKey);
    final b3 = prefs.getString(_spiB3);
    final b4 = prefs.getString(_spiB4);
    final ticketCache = prefs.getString(_ticketKey);
    if (subKey == null ||
        imgKey == null ||
        b3 == null ||
        b4 == null ||
        ticketCache == null ||
        ticketCache.isEmpty) {
      return false;
    }

    signData = SignData(imgKey: imgKey, subKey: subKey);
    spiData = SpiData(
      b3: bnut != null && bnut.b3.isNotEmpty ? bnut.b3 : b3,
      b4: b4,
    );
    ticket = ticketCache;
    bNut ??= bnut?.bNut;
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
      return SpiData.fromJson(response.data);
    } catch (e) {
      throw BiliAuthError("spi 指纹获取失败", cause: e);
    }
  }
}
