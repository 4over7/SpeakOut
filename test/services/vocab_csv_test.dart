import 'package:flutter_test/flutter_test.dart';
import 'package:speakout/services/vocab_service.dart';

/// `VocabService.splitCsvLine` 的行为测试。
///
/// 起因：词库导入原先直接 `line.split(',')` —— 用户从 Excel 导出的
/// `"深度学习, 机器学习",DL` 会被切成三段，第二列变成 ` 机器学习"`，
/// 导入进来的是一条永远匹配不上的垃圾词条，而 UI 报「导入成功 N 条」。
void main() {
  List<String> split(String s) => VocabService.splitCsvLine(s);

  test('普通行按逗号切', () {
    expect(split('wrong,correct'), ['wrong', 'correct']);
  });

  test('引号内的逗号不切', () {
    expect(split('"深度学习, 机器学习",DL'), ['深度学习, 机器学习', 'DL']);
  });

  test('两个连续引号是转义后的一个引号', () {
    expect(split('"他说""好""",ok'), ['他说"好"', 'ok']);
  });

  test('空字段保留位置 —— 否则列会左移，错误形式和正确形式对调', () {
    expect(split('a,,c'), ['a', '', 'c']);
    expect(split(',b'), ['', 'b']);
    expect(split('a,'), ['a', '']);
  });

  test('引号只包住部分字段也能处理', () {
    expect(split('plain,"quoted, here"'), ['plain', 'quoted, here']);
  });

  test('引号没闭合时不丢内容 —— 宁可整段进最后一列，也不要静默截断', () {
    expect(split('a,"unterminated, tail'), ['a', 'unterminated, tail']);
  });

  test('空行返回单个空字段（调用方按 length < 2 跳过）', () {
    expect(split(''), ['']);
  });
}
