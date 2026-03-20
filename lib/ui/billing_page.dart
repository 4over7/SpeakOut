import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/billing_model.dart';
import '../services/billing_service.dart';
import 'theme.dart';
import 'widgets/settings_widgets.dart';

class BillingPage extends StatefulWidget {
  const BillingPage({super.key});

  @override
  State<BillingPage> createState() => _BillingPageState();
}

class _BillingPageState extends State<BillingPage> {
  bool _loading = false;
  String _channel = 'alipay';

  @override
  void initState() {
    super.initState();
    BillingService().fetchStatus();
    BillingService().fetchPlans();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<BillingStatus?>(
      valueListenable: BillingService().statusNotifier,
      builder: (context, status, _) {
        return SingleChildScrollView(
          child: Column(
            children: [
              // 当前状态
              _buildCurrentStatus(status),
              const SizedBox(height: 16),
              // 套餐选择
              _buildPlanCards(status),
              const SizedBox(height: 24),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCurrentStatus(BillingStatus? status) {
    if (status == null) {
      return SettingsGroup(
        title: '当前方案',
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const SizedBox(width: 14, height: 14, child: ProgressCircle()),
                const SizedBox(width: 8),
                Text('加载中...', style: AppTheme.caption(context)),
              ],
            ),
          ),
        ],
      );
    }

    final planName = _planDisplayName(status.planId);
    final percent = status.usagePercent;
    final color = percent > 0.9
        ? MacosColors.systemRedColor
        : percent > 0.7
            ? MacosColors.systemOrangeColor
            : MacosColors.systemBlueColor;

    return SettingsGroup(
      title: '当前方案',
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(planName, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '剩余 ${status.formattedRemaining} / ${status.formattedLimit}',
                      style: AppTheme.body(context),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              // 进度条
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: percent,
                  minHeight: 8,
                  backgroundColor: MacosColors.systemGrayColor.withValues(alpha: 0.15),
                  valueColor: AlwaysStoppedAnimation(color),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '已用 ${(percent * 100).toStringAsFixed(0)}%',
                    style: AppTheme.caption(context).copyWith(color: MacosColors.systemGrayColor),
                  ),
                  Text(
                    '周期至 ${status.periodEnd}',
                    style: AppTheme.caption(context).copyWith(color: MacosColors.systemGrayColor),
                  ),
                ],
              ),
              if (status.isQuotaExceeded)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: MacosColors.systemRedColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: MacosColors.systemRedColor.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        const MacosIcon(CupertinoIcons.exclamationmark_triangle, size: 14, color: MacosColors.systemRedColor),
                        const SizedBox(width: 6),
                        Text('额度已用完，云端功能暂停。离线功能不受影响。',
                          style: TextStyle(fontSize: 12, color: MacosColors.systemRedColor)),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPlanCards(BillingStatus? status) {
    final plans = BillingService().plans;
    if (plans.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingsGroup(
          title: '套餐',
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Row(
                children: plans.map((plan) {
                  final isCurrentPlan = status?.planId == plan.id;
                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: _buildPlanCard(plan, isCurrentPlan),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
        // 支付方式选择
        const SizedBox(height: 12),
        SettingsGroup(
          title: '支付方式',
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  _buildChannelOption('alipay', '支付宝', CupertinoIcons.money_yen_circle),
                  const SizedBox(width: 16),
                  _buildChannelOption('stripe', 'Stripe (International)', CupertinoIcons.creditcard),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPlanCard(BillingPlan plan, bool isCurrent) {
    final borderColor = isCurrent ? MacosColors.systemBlueColor : MacosColors.systemGrayColor.withValues(alpha: 0.3);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor, width: isCurrent ? 2 : 1),
        color: isCurrent ? MacosColors.systemBlueColor.withValues(alpha: 0.06) : null,
      ),
      child: Column(
        children: [
          Text(plan.name, style: AppTheme.body(context).copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(plan.formattedDuration, style: AppTheme.caption(context)),
          const SizedBox(height: 8),
          Text(
            plan.formattedPriceCny,
            style: TextStyle(
              fontSize: plan.isFree ? 14 : 18,
              fontWeight: FontWeight.bold,
              color: plan.isFree ? MacosColors.systemGrayColor : MacosColors.systemBlueColor,
            ),
          ),
          const SizedBox(height: 8),
          if (!plan.isFree && !isCurrent)
            PushButton(
              controlSize: ControlSize.regular,
              onPressed: _loading ? null : () => _handlePurchase(plan),
              child: _loading
                  ? const SizedBox(width: 14, height: 14, child: ProgressCircle())
                  : const Text('购买'),
            )
          else if (isCurrent)
            Text('当前', style: TextStyle(fontSize: 12, color: MacosColors.systemGrayColor.withValues(alpha: 0.6)))
          else
            const SizedBox(height: 24), // placeholder for alignment
        ],
      ),
    );
  }

  Widget _buildChannelOption(String value, String label, IconData icon) {
    final selected = _channel == value;
    return GestureDetector(
      onTap: () => setState(() => _channel = value),
      child: Row(
        children: [
          MacosRadioButton<String>(
            groupValue: _channel,
            value: value,
            onChanged: (v) { if (v != null) setState(() => _channel = v); },
          ),
          const SizedBox(width: 6),
          MacosIcon(icon, size: 16, color: selected ? MacosColors.systemBlueColor : MacosColors.systemGrayColor),
          const SizedBox(width: 4),
          Text(label, style: AppTheme.body(context).copyWith(
            color: selected ? null : MacosColors.systemGrayColor,
          )),
        ],
      ),
    );
  }

  Future<void> _handlePurchase(BillingPlan plan) async {
    setState(() => _loading = true);

    final order = await BillingService().createOrder(plan.id, _channel);
    if (order == null) {
      setState(() => _loading = false);
      if (mounted) {
        _showError('创建订单失败，请重试');
      }
      return;
    }

    setState(() => _loading = false);

    if (_channel == 'alipay' && order.qrCode != null) {
      if (mounted) _showAlipayQrDialog(order);
    } else if (_channel == 'stripe' && order.checkoutUrl != null) {
      launchUrl(Uri.parse(order.checkoutUrl!));
      if (mounted) _showWaitingDialog(order);
    }
  }

  void _showAlipayQrDialog(BillingOrder order) {
    StreamSubscription? pollSub;
    showMacosAlertDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setDialogState) {
          // Start polling
          pollSub ??= BillingService().pollOrderStatus(order.orderId).listen((o) {
            if (o.isPaid && ctx.mounted) {
              Navigator.of(ctx).pop();
              _showSuccess('支付成功！额度已更新。');
            }
          });

          return MacosAlertDialog(
            appIcon: const MacosIcon(CupertinoIcons.qrcode, size: 48),
            title: const Text('支付宝扫码支付'),
            message: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: QrImageView(
                    data: order.qrCode!,
                    size: 200,
                    backgroundColor: Colors.white,
                  ),
                ),
                const SizedBox(height: 12),
                Text('打开支付宝扫描二维码完成支付', style: AppTheme.caption(context)),
                const SizedBox(height: 4),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(width: 10, height: 10, child: ProgressCircle()),
                    const SizedBox(width: 6),
                    Text('等待支付...', style: AppTheme.caption(context).copyWith(color: MacosColors.systemGrayColor)),
                  ],
                ),
              ],
            ),
            primaryButton: PushButton(
              controlSize: ControlSize.large,
              secondary: true,
              onPressed: () {
                pollSub?.cancel();
                Navigator.of(ctx).pop();
              },
              child: const Text('取消'),
            ),
          );
        });
      },
    ).then((_) => pollSub?.cancel());
  }

  void _showWaitingDialog(BillingOrder order) {
    StreamSubscription? pollSub;
    showMacosAlertDialog(
      context: context,
      builder: (ctx) {
        pollSub ??= BillingService().pollOrderStatus(order.orderId).listen((o) {
          if (o.isPaid && ctx.mounted) {
            Navigator.of(ctx).pop();
            _showSuccess('Payment successful! Quota updated.');
          }
        });

        return MacosAlertDialog(
          appIcon: const MacosIcon(CupertinoIcons.creditcard, size: 48),
          title: const Text('Waiting for payment...'),
          message: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Complete payment in your browser.', style: AppTheme.caption(context)),
              const SizedBox(height: 12),
              const ProgressCircle(),
            ],
          ),
          primaryButton: PushButton(
            controlSize: ControlSize.large,
            secondary: true,
            onPressed: () {
              pollSub?.cancel();
              Navigator.of(ctx).pop();
            },
            child: const Text('Cancel'),
          ),
        );
      },
    ).then((_) => pollSub?.cancel());
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating, duration: const Duration(seconds: 3)),
    );
  }

  void _showSuccess(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        backgroundColor: MacosColors.systemGreenColor,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  String _planDisplayName(String planId) {
    switch (planId) {
      case 'free': return '免费体验';
      case 'basic': return '基础版';
      case 'pro': return '专业版';
      default: return planId;
    }
  }
}
