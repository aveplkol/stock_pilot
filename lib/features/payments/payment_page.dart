import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../database/app_database.dart';
import '../../providers.dart';
import '../customers/customers_page.dart' show customerLabel;

const _kBrandGreen = Color(0xFF123D32);
const _kBg = Color(0xFFF5F6F4);

class PaymentPage extends ConsumerStatefulWidget {
  const PaymentPage({super.key});
  @override
  ConsumerState<PaymentPage> createState() => _PaymentPageState();
}

class _PaymentPageState extends ConsumerState<PaymentPage> {
  String? _society, _block, _customerId;
  final _amountCtrl = TextEditingController();
  final _dateCtrl = TextEditingController();
  final _modeCtrl = TextEditingController(text: 'UPI');
  final _refCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  final _paymentsSectionKey = GlobalKey();
  bool _saving = false;
  List<Payment>? _recentPayments;
  double _outstanding = 0;

  @override
  void initState() {
    super.initState();
    _dateCtrl.text = _fmtDate(DateTime.now());
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _dateCtrl.dispose();
    _modeCtrl.dispose();
    _refCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  String _fmtDate(DateTime d) {
    const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${d.day} ${m[d.month - 1]} ${d.year}';
  }

  InputDecoration _dec(String hint) => InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: Colors.white,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _kBrandGreen, width: 1.5),
        ),
      );

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6, top: 4),
        child: Text(text,
            style: TextStyle(
                fontWeight: FontWeight.w600, color: Colors.grey.shade800)),
      );

  Widget _card({required Widget child}) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 10,
                offset: const Offset(0, 2)),
          ],
        ),
        child: child,
      );

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _dateCtrl.text = _fmtDate(picked));
  }

  /// Recomputes the current outstanding for the selected customer
  /// (sum of order totals − sum of payments). Called when a customer is
  /// selected and after a payment is recorded.
  Future<void> _refreshOutstanding() async {
    final customerId = _customerId;
    if (customerId == null) {
      if (mounted) setState(() => _outstanding = 0);
      return;
    }
    try {
      final ordersRepo = ref.read(ordersRepositoryProvider);
      final paymentsRepo = ref.read(paymentsRepositoryProvider);
      final orders = await ordersRepo.getOrdersForCustomer(customerId);
      final payments =
          await paymentsRepo.getRecentPaymentsForCustomer(customerId, limit: 100);
      final totalOrdered = orders.fold<double>(0, (s, o) => s + o.total);
      final totalPaid = payments.fold<double>(0, (s, p) => s + p.amount);
      if (!mounted) return;
      setState(() {
        _outstanding = (totalOrdered - totalPaid).clamp(0, double.infinity);
        // If the Recent Payments section is already open, refresh it too.
        if (_recentPayments != null) {
          _recentPayments = payments.take(10).toList();
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _viewRecentPayments() async {
    if (_customerId == null) return;
    try {
      final paymentsRepo = ref.read(paymentsRepositoryProvider);
      final payments =
          await paymentsRepo.getRecentPaymentsForCustomer(_customerId!, limit: 10);
      if (!mounted) return;
      setState(() => _recentPayments = payments);
      await _refreshOutstanding();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctx = _paymentsSectionKey.currentContext;
        if (ctx != null) {
          Scrollable.ensureVisible(
            ctx,
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeInOut,
            alignment: 0.05,
          );
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _recordPayment() async {
    if (!_formKey.currentState!.validate() || _customerId == null) return;
    setState(() => _saving = true);
    try {
      final amount = double.parse(_amountCtrl.text.trim());
      final mode = _modeCtrl.text.trim();
      final reference = _refCtrl.text.trim();
      final notes = _notesCtrl.text.trim();
      final parts = _dateCtrl.text.split(' ');
      const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      final paymentDate = DateTime(
          int.parse(parts[2]), months.indexOf(parts[1]) + 1, int.parse(parts[0]));

      await ref.read(paymentsRepositoryProvider).addPayment(
            customerId: _customerId!,
            amount: amount,
            paymentMode: mode,
            reference: reference.isEmpty ? null : reference,
            notes: notes.isEmpty ? null : notes,
            paymentDate: paymentDate,
          );
      if (!mounted) return;
      final syncError = await ref.read(syncServiceProvider).autoPush();
      if (!mounted) return;
      setState(() {
        _amountCtrl.clear();
        _refCtrl.clear();
        _notesCtrl.clear();
        _dateCtrl.text = _fmtDate(DateTime.now());
        _modeCtrl.text = 'UPI';
        _saving = false;
      });
      // Reflect the updated outstanding (and recent payments, if shown)
      // for the still-selected customer.
      await _refreshOutstanding();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(syncError ?? 'Payment recorded.'),
        backgroundColor: syncError != null ? Colors.red.shade700 : _kBrandGreen,
      ));
    } catch (e) {
      if (mounted) setState(() => _saving = false);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final custRepo = ref.watch(customersRepositoryProvider);
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        title: const Text('Record Payment'),
        backgroundColor: _kBrandGreen,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
            'Receive payment from customer and update their outstanding balance.',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: Colors.grey.shade600),
          ),
          const SizedBox(height: 20),
          _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Payment Details',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold, color: _kBrandGreen)),
                const SizedBox(height: 16),
                Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _label('Customer *'),
                      StreamBuilder<List<Society>>(
                        stream: ref
                            .watch(societiesRepositoryProvider)
                            .watchSocieties(),
                        builder: (_, snap) {
                          final names =
                              (snap.data ?? []).map((s) => s.name).toList();
                          return DropdownButtonFormField<String?>(
                            initialValue: _society,
                            isExpanded: true,
                            decoration: _dec('All Societies'),
                            items: [
                              const DropdownMenuItem(
                                  value: null, child: Text('All Societies')),
                              ...names.map((s) =>
                                  DropdownMenuItem(value: s, child: Text(s))),
                            ],
                            onChanged: (v) => setState(() {
                              _society = v;
                              _block = null;
                              _customerId = null;
                              _recentPayments = null;
                            }),
                          );
                        },
                      ),
                      const SizedBox(height: 12),
                      StreamBuilder<List<Customer>>(
                        stream: custRepo.watchCustomers(),
                        builder: (_, snap) {
                          final all =
                              (snap.data ?? []).where((c) => c.active).toList();
                          final inSoc = _society == null
                              ? all
                              : all.where((c) => c.society == _society).toList();
                          final blocks = {
                            for (final c in inSoc)
                              if ((c.address ?? '').trim().isNotEmpty)
                                c.address!.trim()
                          }.toList()
                            ..sort();
                          return DropdownButtonFormField<String?>(
                            initialValue: _block,
                            isExpanded: true,
                            decoration: _dec('All Blocks'),
                            items: [
                              const DropdownMenuItem(
                                  value: null, child: Text('All Blocks')),
                              ...blocks.map((s) =>
                                  DropdownMenuItem(value: s, child: Text(s))),
                            ],
                            onChanged: (v) => setState(() {
                              _block = v;
                              _customerId = null;
                              _recentPayments = null;
                            }),
                          );
                        },
                      ),
                      const SizedBox(height: 12),
                      StreamBuilder<List<Customer>>(
                        stream: custRepo.watchCustomers(),
                        builder: (_, snap) {
                          var custs =
                              (snap.data ?? []).where((c) => c.active).toList();
                          if (_society != null) {
                            custs = custs
                                .where((c) => c.society == _society)
                                .toList();
                          }
                          if (_block != null) {
                            custs = custs
                                .where((c) =>
                                    (c.address ?? '').trim() == _block)
                                .toList();
                          }
                          custs.sort((a, b) {
                            final na =
                                int.tryParse((a.flatNumber ?? '').trim());
                            final nb =
                                int.tryParse((b.flatNumber ?? '').trim());
                            if (na != null && nb != null) {
                              return na.compareTo(nb);
                            }
                            return (a.flatNumber ?? '')
                                .compareTo(b.flatNumber ?? '');
                          });
                          final validIds = custs.map((c) => c.id).toSet();
                          final selected = (_customerId != null &&
                                  validIds.contains(_customerId))
                              ? _customerId
                              : null;
                          return DropdownButtonFormField<String?>(
                            initialValue: selected,
                            isExpanded: true,
                            decoration: _dec('Choose customer'),
                            items: [
                              const DropdownMenuItem(
                                  value: null,
                                  child: Text('Choose customer')),
                              ...custs.map((c) => DropdownMenuItem(
                                  value: c.id,
                                  child: Text(customerLabel(c)))),
                            ],
                            onChanged: (v) {
                              setState(() {
                                _customerId = v;
                                _recentPayments = null;
                              });
                              _refreshOutstanding();
                            },
                            validator: (v) =>
                                v == null ? 'Select customer' : null,
                          );
                        },
                      ),
                      const SizedBox(height: 16),
                      // Outstanding + View Recent Payments banner
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEAF4EE),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.green.shade200),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.green.shade100,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.account_balance_wallet_outlined,
                                  color: _kBrandGreen, size: 22),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Current Outstanding',
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey.shade700)),
                                  const SizedBox(height: 2),
                                  Text('₹ ${_outstanding.toStringAsFixed(0)}',
                                      style: const TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.w800,
                                          color: _kBrandGreen)),
                                ],
                              ),
                            ),
                            TextButton(
                              onPressed: _customerId == null
                                  ? null
                                  : _viewRecentPayments,
                              child: const Text(
                                'View Recent Payments →',
                                style: TextStyle(
                                    color: _kBrandGreen,
                                    fontWeight: FontWeight.w700),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      _label('Payment Amount *'),
                      TextFormField(
                        controller: _amountCtrl,
                        keyboardType: TextInputType.number,
                        decoration: _dec('500').copyWith(prefixText: '₹ '),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return 'Required';
                          if (double.tryParse(v) == null) return 'Invalid';
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      _label('Payment Date *'),
                      TextFormField(
                        controller: _dateCtrl,
                        readOnly: true,
                        onTap: _pickDate,
                        decoration: _dec('').copyWith(
                            suffixIcon: const Icon(Icons.calendar_today,
                                color: _kBrandGreen, size: 18)),
                      ),
                      const SizedBox(height: 12),
                      _label('Payment Mode *'),
                      DropdownButtonFormField<String>(
                        initialValue: _modeCtrl.text,
                        decoration: _dec(''),
                        items: const [
                          DropdownMenuItem(value: 'UPI', child: Text('UPI')),
                          DropdownMenuItem(value: 'Cash', child: Text('Cash')),
                          DropdownMenuItem(
                              value: 'Cheque', child: Text('Cheque')),
                          DropdownMenuItem(
                              value: 'Bank Transfer',
                              child: Text('Bank Transfer')),
                        ],
                        onChanged: (v) => _modeCtrl.text = v ?? 'UPI',
                      ),
                      const SizedBox(height: 12),
                      _label('Payment Reference'),
                      TextFormField(
                        controller: _refCtrl,
                        decoration: _dec('e.g. UPI123456'),
                      ),
                      const SizedBox(height: 12),
                      _label('Notes (Optional)'),
                      TextFormField(
                        controller: _notesCtrl,
                        maxLines: 2,
                        decoration: _dec('Partial payment...'),
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: _kBrandGreen,
                            padding:
                                const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                          onPressed: _saving ? null : _recordPayment,
                          child: _saving
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white))
                              : const Text('Record Payment',
                                  style: TextStyle(
                                      fontWeight: FontWeight.w700)),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Recent Payments section (only after View Recent Payments)
          if (_recentPayments != null) ...[
            const SizedBox(height: 20),
            KeyedSubtree(
              key: _paymentsSectionKey,
              child: _card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.receipt_long_outlined,
                            color: _kBrandGreen, size: 20),
                        const SizedBox(width: 8),
                        Text('Recent Payments',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: _kBrandGreen)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (_recentPayments!.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text('No payments recorded yet.',
                            style: TextStyle(color: Colors.grey.shade600)),
                      )
                    else ...[
                      Container(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          border: Border(
                              bottom: BorderSide(
                                  color: Colors.grey.shade200)),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                                flex: 3,
                                child: Text('Date',
                                    style: _th())),
                            Expanded(
                                flex: 2,
                                child: Text('Amount', style: _th())),
                            Expanded(
                                flex: 2,
                                child: Text('Mode', style: _th())),
                            Expanded(
                                flex: 3,
                                child: Text('Reference', style: _th())),
                          ],
                        ),
                      ),
                      ..._recentPayments!.map((p) => Padding(
                            padding:
                                const EdgeInsets.symmetric(vertical: 10),
                            child: Row(
                              children: [
                                Expanded(
                                    flex: 3,
                                    child: Text(_fmtDate(p.paymentDate),
                                        style: const TextStyle(
                                            fontSize: 13))),
                                Expanded(
                                    flex: 2,
                                    child: Text(
                                        '₹ ${p.amount.toStringAsFixed(0)}',
                                        style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w700,
                                            color: _kBrandGreen))),
                                Expanded(
                                    flex: 2,
                                    child: Text(p.paymentMode,
                                        style: const TextStyle(
                                            fontSize: 13))),
                                Expanded(
                                    flex: 3,
                                    child: Text(p.reference ?? '—',
                                        style: TextStyle(
                                            fontSize: 13,
                                            color: Colors.grey.shade700))),
                              ],
                            ),
                          )),
                    ],
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 24),
        ]),
      ),
    );
  }

  TextStyle _th() => TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w700,
      color: Colors.grey.shade600);
}
