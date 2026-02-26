import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

class AliyunTokenService {
  static const String _endpoint = "http://nls-meta.cn-shanghai.aliyuncs.com";
  
  /// Exchange AccessKey ID/Secret for a temporary NLS Token.
  /// Returns null if failed, logs error otherwise.
  static Future<String?> generateToken(String accessKeyId, String accessKeySecret) async {
    // 1. Params
    final params = {
      "AccessKeyId": accessKeyId,
      "Action": "CreateToken",
      "Format": "JSON",
      "RegionId": "cn-shanghai",
      "SignatureMethod": "HMAC-SHA1",
      "SignatureNonce": Uuid().v4(),
      "SignatureVersion": "1.0",
      "Timestamp": DateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'").format(DateTime.now().toUtc()),
      "Version": "2019-02-28",
    };

    // 2. Canonicalized Query String
    final sortedKeys = params.keys.toList()..sort();
    final canonicalizedQueryString = sortedKeys.map((key) {
      return "${_percentEncode(key)}=${_percentEncode(params[key]!)}";
    }).join("&");

    // 3. StringToSign
    final stringToSign = "GET&${_percentEncode("/")}&${_percentEncode(canonicalizedQueryString)}";

    // 4. Sign
    final key = "$accessKeySecret&";
    final hmacSha1 = Hmac(sha1, utf8.encode(key));
    final signature = base64Encode(hmacSha1.convert(utf8.encode(stringToSign)).bytes);

    // 5. Request
    final requestUrl = "$_endpoint/?$canonicalizedQueryString&Signature=${_percentEncode(signature)}";
    
    try {
      final response = await http.get(Uri.parse(requestUrl));
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        if (json['Token'] != null && json['Token']['Id'] != null) {
          return json['Token']['Id'];
        }
      }
      debugPrint("Aliyun Token Error: ${response.body}");
    } catch (e) {
      debugPrint("Aliyun Token Network Error: $e");
    }
    return null;
  }

  static String _percentEncode(String value) {
    return Uri.encodeComponent(value)
        .replaceAll("+", "%20")
        .replaceAll("*", "%2A")
        .replaceAll("%7E", "~");
  }
}
