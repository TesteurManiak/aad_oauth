import 'dart:async';
import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'model/config.dart';
import 'request/authorization_request.dart';

class RequestCode {
  final Config _config;
  final AuthorizationRequest _authorizationRequest;
  final String _redirectUriHost;
  late NavigationDelegate _navigationDelegate;
  late WebViewCookieManager _cookieManager;
  String? _code;

  RequestCode(Config config)
      : _config = config,
        _authorizationRequest = AuthorizationRequest(config),
        _redirectUriHost = Uri.parse(config.redirectUri).host {
    _navigationDelegate = NavigationDelegate(
      onNavigationRequest: _onNavigationRequest,
    );
    _cookieManager = WebViewCookieManager();
  }

  Future<String?> requestCode() async {
    _code = null;

    final urlParams = _constructUrlParams();
    final launchUri = Uri.parse('${_authorizationRequest.url}?$urlParams');
    final controller = WebViewController();
    await controller.setNavigationDelegate(_navigationDelegate);
    await controller.setJavaScriptMode(JavaScriptMode.unrestricted);

    await controller.setBackgroundColor(Colors.transparent);
    await controller.setUserAgent(_config.userAgent);
    await controller.loadRequest(launchUri);

    await controller.setOnConsoleMessage((message) {
      log('Console: ${message.message}', name: 'aad_oauth');
    });

    await controller.setNavigationDelegate(
      NavigationDelegate(
        onPageFinished: (url) {
          log('Accessing URL: $url', name: 'aad_oauth');
          controller.hideSignupElements();
          _config.onPageFinished?.call(url);
        },
      ),
    );

    final webView = WebViewWidget(controller: controller);

    if (_config.navigatorKey.currentState == null) {
      throw Exception(
        'Could not push new route using provided navigatorKey, Because '
        'NavigatorState returned from provided navigatorKey is null. Please Make sure '
        'provided navigatorKey is passed to WidgetApp. This can also happen if at the time of this method call '
        'WidgetApp is not part of the flutter widget tree',
      );
    }

    await _config.navigatorKey.currentState!.push(
      MaterialPageRoute(
        builder: (context) => Scaffold(
          appBar: _config.appBar,
          body: PopScope(
            canPop: false,
            onPopInvoked: (bool didPop) async {
              if (didPop) return;
              if (await controller.canGoBack()) {
                await controller.goBack();
                return;
              }
              final NavigatorState navigator = Navigator.of(context);
              navigator.pop();
            },
            child: SafeArea(
              child: Stack(
                children: [_config.loader, webView],
              ),
            ),
          ),
        ),
      ),
    );
    return _code;
  }

  Future<NavigationDecision> _onNavigationRequest(
      NavigationRequest request) async {
    try {
      var uri = Uri.parse(request.url);

      if (uri.queryParameters['error'] != null) {
        _config.navigatorKey.currentState!.pop();
      }

      var checkHost = uri.host == _redirectUriHost;

      if (uri.queryParameters['code'] != null && checkHost) {
        _code = uri.queryParameters['code'];
        _config.navigatorKey.currentState!.pop();
      }
    } catch (_) {}
    return NavigationDecision.navigate;
  }

  Future<void> clearCookies() async {
    await _cookieManager.clearCookies();
  }

  String _constructUrlParams() => _mapToQueryParams(
      _authorizationRequest.parameters, _config.customParameters);

  String _mapToQueryParams(
      Map<String, String> params, Map<String, String> customParams) {
    final queryParams = <String>[];

    params.forEach((String key, String value) =>
        queryParams.add('$key=${Uri.encodeQueryComponent(value)}'));

    customParams.forEach((String key, String value) =>
        queryParams.add('$key=${Uri.encodeQueryComponent(value)}'));
    return queryParams.join('&');
  }
}

extension on WebViewController {
  Future<void> hideSignupElements() async {
    final javascript = '''
      console.log(document.documentElement.outerHTML);
      var signupElement = document.getElementById("signup");
      if (signupElement) {
        signupElement.style.display = "none";
      }

    document.addEventListener("DOMContentLoaded", function() {
      console.log("DOMContentLoaded hideSignupElements");
      var signupElement = document.getElementById("signup");
      console.log("listener signupElement", signupElement);
      if (signupElement) {
        signupElement.style.display = "none";
      }
    });
    ''';

    await runJavaScript(javascript);
  }
}
