/// B 站接口错误类型（S2.1）：SDK 对外只抛 BiliApiError 子类，
/// 不再泄漏 DioException / BotToast 弹窗，调用方按类型决定提示与降级
sealed class BiliApiError implements Exception {
  final String message;

  /// 原始异常（诊断用，UI 不要展示）
  final Object? cause;

  const BiliApiError(this.message, {this.cause});

  @override
  String toString() => "$runtimeType: $message";
}

/// 网络层失败（超时/断网/DNS 等）
class BiliNetworkError extends BiliApiError {
  const BiliNetworkError(super.message, {super.cause});
}

/// HTTP 状态非 2xx
class BiliHttpError extends BiliApiError {
  final int? statusCode;

  const BiliHttpError(super.message, {this.statusCode, super.cause});
}

/// B 站业务码非 0（[riskControl] = 命中风控 v_voucher，需稍后重试或换环境）
class BiliApiRejectError extends BiliApiError {
  final int code;
  final bool riskControl;

  const BiliApiRejectError(
    super.message, {
    required this.code,
    this.riskControl = false,
    super.cause,
  });
}

/// 鉴权材料（WBI 密钥/spi/ticket）获取失败或缺失
class BiliAuthError extends BiliApiError {
  const BiliAuthError(super.message, {super.cause});
}

/// 响应结构与预期不符（接口漂移的最先信号）
class BiliParseError extends BiliApiError {
  const BiliParseError(super.message, {super.cause});
}

/// 入参不合法（如 playurl 缺 cid）
class BiliInvalidIdError extends BiliApiError {
  const BiliInvalidIdError(super.message, {super.cause});
}
