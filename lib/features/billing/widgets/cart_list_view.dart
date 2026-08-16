import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart' show PointerScrollEvent;
import 'package:flutter/services.dart' show LogicalKeyboardKey, KeyDownEvent;
import '../../../services/billing_service.dart';
import '../../../core/utils/quantity_utils.dart';

class CartListView extends StatelessWidget {
  final List<CartItem> items;
  final Function(String, double) onQuantityChange;
  final Function(String) onRemove;
  final Function(String, double)? onDiscountChange;
  final FocusNode Function(String productId)? focusNodeForProduct;
  final VoidCallback? onQuantitySubmitted;

  const CartListView({
    super.key,
    required this.items,
    required this.onQuantityChange,
    required this.onRemove,
    this.onDiscountChange,
    this.focusNodeForProduct,
    this.onQuantitySubmitted,
  });

  // Shared flex ratios so the header row and every item row line up exactly.
  static const _flexHash = 1;
  static const _flexCode = 1;
  static const _flexName = 3;
  static const _flexQty = 3;
  static const _flexUnit = 1;
  static const _flexStock = 1;
  static const _flexPrice = 2;
  static const _flexDiscount = 2;
  static const _flexTax = 2;
  static const _flexTotal = 2;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.shopping_cart, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('Cart is empty', style: TextStyle(fontSize: 16)),
            Text('Add products from the left panel', style: TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _HeaderRow(
          flexHash: _flexHash,
          flexCode: _flexCode,
          flexName: _flexName,
          flexQty: _flexQty,
          flexUnit: _flexUnit,
          flexStock: _flexStock,
          flexPrice: _flexPrice,
          flexDiscount: _flexDiscount,
          flexTax: _flexTax,
          flexTotal: _flexTotal,
        ),
        const Divider(height: 1, thickness: 1),
        Expanded(
          child: ListView.separated(
            itemCount: items.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final item = items[index];
              return _CartRow(
                key: ValueKey(item.productId),
                rowNumber: index + 1,
                item: item,
                onQuantityChange: onQuantityChange,
                onRemove: onRemove,
                onDiscountChange: onDiscountChange,
                quantityFocusNode: focusNodeForProduct?.call(item.productId),
                onQuantitySubmitted: onQuantitySubmitted,
                flexHash: _flexHash,
                flexCode: _flexCode,
                flexName: _flexName,
                flexQty: _flexQty,
                flexUnit: _flexUnit,
                flexStock: _flexStock,
                flexPrice: _flexPrice,
                flexDiscount: _flexDiscount,
                flexTax: _flexTax,
                flexTotal: _flexTotal,
              );
            },
          ),
        ),
      ],
    );
  }
}

class _HeaderRow extends StatelessWidget {
  final int flexHash, flexCode, flexName, flexQty, flexUnit, flexStock, flexPrice, flexDiscount, flexTax, flexTotal;

  const _HeaderRow({
    required this.flexHash,
    required this.flexCode,
    required this.flexName,
    required this.flexQty,
    required this.flexUnit,
    required this.flexStock,
    required this.flexPrice,
    required this.flexDiscount,
    required this.flexTax,
    required this.flexTotal,
  });

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black54);
    Widget cell(String label, int flex, {TextAlign align = TextAlign.left}) => Expanded(
          flex: flex,
          child: Text(label, style: style, textAlign: align),
        );

    return Container(
      color: Colors.grey.shade100,
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
      child: Row(
        children: [
          cell('#', flexHash),
          cell('CODE', flexCode),
          cell('ITEM', flexName),
          cell('QTY', flexQty, align: TextAlign.center),
          cell('UNIT', flexUnit, align: TextAlign.center),
          cell('STOCK', flexStock, align: TextAlign.center),
          cell('PRICE/UNIT', flexPrice, align: TextAlign.right),
          cell('DISCOUNT ₹', flexDiscount, align: TextAlign.right),
          cell('TAX ₹', flexTax, align: TextAlign.right),
          cell('TOTAL ₹', flexTotal, align: TextAlign.right),
          const SizedBox(width: 30),
        ],
      ),
    );
  }
}

class _CartRow extends StatefulWidget {
  final int rowNumber;
  final CartItem item;
  final Function(String, double) onQuantityChange;
  final Function(String) onRemove;
  final Function(String, double)? onDiscountChange;
  final FocusNode? quantityFocusNode;
  final VoidCallback? onQuantitySubmitted;
  final int flexHash, flexCode, flexName, flexQty, flexUnit, flexStock, flexPrice, flexDiscount, flexTax, flexTotal;

  const _CartRow({
    super.key,
    required this.rowNumber,
    required this.item,
    required this.onQuantityChange,
    required this.onRemove,
    this.onDiscountChange,
    this.quantityFocusNode,
    this.onQuantitySubmitted,
    required this.flexHash,
    required this.flexCode,
    required this.flexName,
    required this.flexQty,
    required this.flexUnit,
    required this.flexStock,
    required this.flexPrice,
    required this.flexDiscount,
    required this.flexTax,
    required this.flexTotal,
  });

  @override
  State<_CartRow> createState() => _CartRowState();
}

class _CartRowState extends State<_CartRow> {
  late final TextEditingController _qtyController;
  late final TextEditingController _discountController;
  late final FocusNode _qtyFocusNode;
  final FocusNode _discountFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _qtyController = TextEditingController(text: formatQty(widget.item.quantity));
    _discountController = TextEditingController(
      text: widget.item.discountAmount == 0 ? '' : widget.item.discountAmount.toStringAsFixed(2),
    );
    _qtyFocusNode = widget.quantityFocusNode ?? FocusNode();
    _qtyFocusNode.addListener(_onQtyFocusChange);
    _discountFocusNode.addListener(_onDiscountFocusChange);
  }

  void _onQtyFocusChange() {
    if (_qtyFocusNode.hasFocus) {
      _qtyController.selection = TextSelection(baseOffset: 0, extentOffset: _qtyController.text.length);
    } else {
      _commitQtyIfChanged();
    }
  }

  void _onDiscountFocusChange() {
    if (_discountFocusNode.hasFocus) {
      _discountController.selection = TextSelection(baseOffset: 0, extentOffset: _discountController.text.length);
    } else {
      _commitDiscount();
    }
  }

  void _commitQtyIfChanged() {
    final parsed = parseQty(_qtyController.text);
    if (parsed != null && parsed > 0 && parsed != widget.item.quantity) {
      widget.onQuantityChange(widget.item.productId, parsed);
    } else {
      _qtyController.text = formatQty(widget.item.quantity);
    }
  }

  void _commitDiscount() {
    final parsed = double.tryParse(_discountController.text.trim());
    final value = parsed ?? 0;
    if (value != widget.item.discountAmount) {
      widget.onDiscountChange?.call(widget.item.productId, value);
    }
  }

  @override
  void didUpdateWidget(covariant _CartRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_qtyFocusNode.hasFocus && oldWidget.item.quantity != widget.item.quantity) {
      _qtyController.text = formatQty(widget.item.quantity);
    }
    if (!_discountFocusNode.hasFocus && oldWidget.item.discountAmount != widget.item.discountAmount) {
      _discountController.text =
          widget.item.discountAmount == 0 ? '' : widget.item.discountAmount.toStringAsFixed(2);
    }
  }

  @override
  void dispose() {
    _qtyFocusNode.removeListener(_onQtyFocusChange);
    if (widget.quantityFocusNode == null) _qtyFocusNode.dispose();
    _discountFocusNode.removeListener(_onDiscountFocusChange);
    _discountFocusNode.dispose();
    _qtyController.dispose();
    _discountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final product = item.product;
    final grossLine = product.retailPrice * item.quantity;
    // Manual + auto-applied-promotion discount together, same as
    // BillingService.processSale computes the line that actually gets
    // charged — without including promoDiscount here, this row would show
    // a tax/total higher than what checkout actually bills.
    final lineDiscount = (item.discountAmount + item.promoDiscount).clamp(0, grossLine);
    final taxableAmount = grossLine - lineDiscount;
    final taxAmount = (taxableAmount * product.taxRate) / 100;
    final lineTotal = taxableAmount + taxAmount;

    // Below-cost check uses the ex-tax price actually being charged per
    // unit (after any line discount) against the product's cost price —
    // tax isn't part of the shop's margin either way, so it's excluded
    // from both sides of the comparison.
    final perUnitAfterDiscount = item.quantity > 0 ? taxableAmount / item.quantity : product.retailPrice;
    final isBelowCost = product.costPrice > 0 && perUnitAfterDiscount < product.costPrice;

    // Live remaining stock "as you bill" — what will be left after this
    // line, so the cashier sees the impact immediately instead of finding
    // out at the next restock count.
    final remainingStock = product.stockQuantity - item.quantity;
    Color stockColor;
    if (remainingStock < 0) {
      stockColor = Colors.red;
    } else if (remainingStock <= product.reorderLevel) {
      stockColor = Colors.orange.shade800;
    } else {
      stockColor = Colors.grey.shade700;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 6.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(flex: widget.flexHash, child: Text('${widget.rowNumber}', style: const TextStyle(fontSize: 12))),
          Expanded(
            flex: widget.flexCode,
            child: Text(
              product.barcode.isEmpty ? '-' : product.barcode,
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            flex: widget.flexName,
            child: Text(
              product.displayName ?? product.name,
              style: const TextStyle(fontSize: 13),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            flex: widget.flexQty,
            child: Listener(
              onPointerSignal: (event) {
                if (event is PointerScrollEvent) {
                  final delta = event.scrollDelta.dy;
                  if (delta < 0) {
                    widget.onQuantityChange(item.productId, item.quantity + 1);
                  } else if (delta > 0 && item.quantity > 1) {
                    widget.onQuantityChange(item.productId, item.quantity - 1);
                  }
                }
              },
              // FittedBox is a hard safety net: even if this column ever
              // gets squeezed narrower than the controls inside it (which
              // is what caused the earlier overflow), this scales the
              // whole stepper down instead of overflowing the row.
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    InkWell(
                      onTap: () => widget.onQuantityChange(item.productId, item.quantity - 1),
                      child: const Icon(Icons.remove_circle, color: Colors.red, size: 16),
                    ),
                    const SizedBox(width: 1),
                    SizedBox(
                      width: 36,
                      height: 28,
                      child: Focus(
                        onKeyEvent: (node, event) {
                          if (event is! KeyDownEvent) return KeyEventResult.ignored;
                          if (event.logicalKey == LogicalKeyboardKey.enter ||
                              event.logicalKey == LogicalKeyboardKey.numpadEnter) {
                            _commitQtyIfChanged();
                            // Marking this handled stops the Enter press from
                            // also bubbling up to the screen-wide Pay shortcut.
                            widget.onQuantitySubmitted?.call();
                            return KeyEventResult.handled;
                          }
                          return KeyEventResult.ignored;
                        },
                        child: TextField(
                          controller: _qtyController,
                          focusNode: _qtyFocusNode,
                          textAlign: TextAlign.center,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                          decoration: const InputDecoration(
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(vertical: 4),
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 1),
                    InkWell(
                      onTap: () => widget.onQuantityChange(item.productId, item.quantity + 1),
                      child: const Icon(Icons.add_circle, color: Colors.green, size: 16),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            flex: widget.flexUnit,
            child: Text(product.unit, style: TextStyle(fontSize: 11, color: Colors.grey.shade600), textAlign: TextAlign.center),
          ),
          Expanded(
            flex: widget.flexStock,
            child: Text(
              formatQty(remainingStock),
              style: TextStyle(fontSize: 12, color: stockColor, fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
          ),
          Expanded(
            flex: widget.flexPrice,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (product.mrp > product.retailPrice)
                  Text(
                    '₹${product.mrp.toStringAsFixed(2)}',
                    style: TextStyle(fontSize: 9, color: Colors.grey.shade500, decoration: TextDecoration.lineThrough),
                  ),
                Text('₹${product.retailPrice.toStringAsFixed(2)}', style: const TextStyle(fontSize: 12)),
              ],
            ),
          ),
          Expanded(
            flex: widget.flexDiscount,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: 30,
                  child: TextField(
                    controller: _discountController,
                    focusNode: _discountFocusNode,
                    textAlign: TextAlign.right,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    style: const TextStyle(fontSize: 12),
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                      border: const OutlineInputBorder(),
                      hintText: '0.00',
                      hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 12),
                    ),
                    onSubmitted: (_) => _commitDiscount(),
                  ),
                ),
                if (item.promoDiscount > 0)
                  Tooltip(
                    message: item.promoLabel ?? 'Promotion applied',
                    child: Text(
                      'Promo -₹${item.promoDiscount.toStringAsFixed(2)}',
                      style: const TextStyle(fontSize: 9, color: Colors.green, fontWeight: FontWeight.w600),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            flex: widget.flexTax,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('₹${taxAmount.toStringAsFixed(2)}', style: const TextStyle(fontSize: 12)),
                if (product.taxRate > 0)
                  Text(
                    '${product.taxRate % 1 == 0 ? product.taxRate.toInt() : product.taxRate}%',
                    style: TextStyle(fontSize: 9, color: Colors.grey.shade500),
                  ),
              ],
            ),
          ),
          Expanded(
            flex: widget.flexTotal,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (isBelowCost)
                  Tooltip(
                    message: 'Selling below cost price (₹${product.costPrice.toStringAsFixed(2)}/unit)',
                    child: const Padding(
                      padding: EdgeInsets.only(right: 4),
                      child: Icon(Icons.warning_amber_rounded, color: Colors.red, size: 16),
                    ),
                  ),
                Text(
                  '₹${lineTotal.toStringAsFixed(2)}',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isBelowCost ? Colors.red : null,
                  ),
                  textAlign: TextAlign.right,
                ),
              ],
            ),
          ),
          SizedBox(
            width: 30,
            child: IconButton(
              icon: const Icon(Icons.delete_forever, color: Colors.red, size: 18),
              onPressed: () => widget.onRemove(item.productId),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ),
        ],
      ),
    );
  }
}