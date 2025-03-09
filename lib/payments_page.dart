import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

class PaymentsPage extends StatefulWidget {
  final String token;

  const PaymentsPage({super.key, required this.token});

  @override
  State<PaymentsPage> createState() => _PaymentsPageState();
}

class _PaymentsPageState extends State<PaymentsPage> {
  bool isLoading = true;
  List<dynamic> payments = [];
  List<dynamic> students = [];
  List<dynamic> filteredStudents = [];
  String errorMessage = '';
  FilterStatus filterStatus = FilterStatus.all;
  String searchQuery = '';
  bool isSearchVisible = false;
  final TextEditingController _searchController = TextEditingController();
  final NumberFormat _currencyFormat = NumberFormat('#,###', 'ru_RU');

  @override
  void initState() {
    super.initState();
    fetchData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> fetchData() async {
    setState(() {
      if (students.isEmpty) isLoading = true;
      errorMessage = '';
    });

    try {
      final studentsResponse = await http.get(
        Uri.parse('http://26.6.96.193:8000/api/students/'),
        headers: {
          'Authorization': 'Token ${widget.token}',
          'Content-Type': 'application/json',
        },
      );

      if (studentsResponse.statusCode != 200) {
        throw Exception('Ошибка загрузки учеников: ${studentsResponse.statusCode}');
      }

      final paymentsResponse = await http.get(
        Uri.parse('http://26.6.96.193:8000/api/payments/'),
        headers: {
          'Authorization': 'Token ${widget.token}',
          'Content-Type': 'application/json',
        },
      );

      if (paymentsResponse.statusCode != 200) {
        throw Exception('Ошибка загрузки платежей: ${paymentsResponse.statusCode}');
      }

      setState(() {
        students = jsonDecode(studentsResponse.body);
        payments = jsonDecode(paymentsResponse.body);
        applyFilters();
        isLoading = false;
      });
    } catch (e) {
      setState(() {
        errorMessage = 'Ошибка: $e';
        isLoading = false;
      });
    }
  }

  void applyFilters() {
    List<dynamic> result = List.from(students);

    // Фильтрация по статусу оплаты
    if (filterStatus != FilterStatus.all) {
      result = result.where((student) {
        Map<String, dynamic>? lastPayment = getLastPayment(student['id']);
        PaymentStatus status = getPaymentStatus(lastPayment);

        if (filterStatus == FilterStatus.paid) {
          return status == PaymentStatus.active;
        } else if (filterStatus == FilterStatus.expiring) {
          return status == PaymentStatus.expiringSoon;
        } else if (filterStatus == FilterStatus.expired) {
          return status == PaymentStatus.expired;
        } else if (filterStatus == FilterStatus.neverPaid) {
          return status == PaymentStatus.none;
        }

        return false;
      }).toList();
    }

    // Поиск по имени
    if (searchQuery.isNotEmpty) {
      result = result.where((student) =>
          student['full_name'].toString().toLowerCase().contains(searchQuery.toLowerCase())
      ).toList();
    }

    setState(() {
      filteredStudents = result;
    });
  }

  Map<String, dynamic>? getLastPayment(int studentId) {
    List<dynamic> studentPayments = payments
        .where((payment) => payment['student'] == studentId)
        .toList();

    if (studentPayments.isEmpty) {
      return null;
    }

    studentPayments.sort((a, b) =>
        DateTime.parse(b['period_end']).compareTo(DateTime.parse(a['period_end']))
    );

    return studentPayments.first;
  }

  PaymentStatus getPaymentStatus(Map<String, dynamic>? lastPayment) {
    if (lastPayment == null) {
      return PaymentStatus.none;
    }

    DateTime periodEnd = DateTime.parse(lastPayment['period_end']);
    DateTime now = DateTime.now();

    if (periodEnd.isAfter(now)) {
      if (periodEnd.difference(now).inDays < 7) {
        return PaymentStatus.expiringSoon;
      }
      return PaymentStatus.active;
    } else {
      return PaymentStatus.expired;
    }
  }

  List<dynamic> getFilteredStudents() {
    return filteredStudents;
  }

  String formatDate(String dateString) {
    try {
      final date = DateTime.parse(dateString);
      return DateFormat('dd.MM.yyyy').format(date);
    } catch (e) {
      return dateString;
    }
  }

  String formatCurrency(dynamic amount) {
    try {
      if (amount is String) {
        amount = double.parse(amount);
      }
      return '${_currencyFormat.format(amount)} UZS';
    } catch (e) {
      return '$amount UZS';
    }
  }

  String getNextPaymentDate(Map<String, dynamic>? lastPayment) {
    if (lastPayment == null) {
      return 'Не оплачено';
    }

    DateTime periodEnd = DateTime.parse(lastPayment['period_end']);
    DateTime nextPayment = periodEnd.add(const Duration(days: 1));
    return DateFormat('dd.MM.yyyy').format(nextPayment);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _buildAppBar(),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black,
              const Color(0xFF101010),
              const Color(0xFF151515),
            ],
          ),
        ),
        child: Column(
          children: [
            // Поле поиска, если видимо
            if (isSearchVisible) _buildSearchField(),
            // Фильтр
            _buildFilterTabs(),
            // Основной контент
            Expanded(
              child: RefreshIndicator(
                onRefresh: fetchData,
                color: const Color(0xFF00E5E5),
                backgroundColor: Colors.grey.shade900,
                child: _buildBody(),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          _showAddPaymentDialog();
        },
        backgroundColor: const Color(0xFF00E5E5),
        foregroundColor: Colors.black,
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Icon(Icons.add, size: 28),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      title: const Text(
        'ОПЛАТА УЧЕНИКОВ',
        style: TextStyle(
          fontWeight: FontWeight.bold,
          letterSpacing: 1.2,
          color: Colors.white,
        ),
      ),
      backgroundColor: Colors.black,
      elevation: 0,
      iconTheme: const IconThemeData(color: Color(0xFF00E5E5)),
      actions: [
        IconButton(
          icon: Icon(
            isSearchVisible ? Icons.close : Icons.search,
            color: const Color(0xFF00E5E5),
          ),
          onPressed: () {
            setState(() {
              isSearchVisible = !isSearchVisible;
              if (!isSearchVisible) {
                _searchController.clear();
                searchQuery = '';
                applyFilters();
              }
            });
          },
        ),
      ],
    );
  }

  Widget _buildSearchField() {
    return Container(
      margin: const EdgeInsets.only(top: 8, left: 12, right: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.grey.shade900,
        borderRadius: BorderRadius.circular(25),
        border: Border.all(color: Colors.grey.shade800),
      ),
      child: TextField(
        controller: _searchController,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          hintText: "Поиск ученика...",
          hintStyle: TextStyle(color: Colors.grey.shade500),
          border: InputBorder.none,
          prefixIcon: const Icon(Icons.search, color: Color(0xFF00E5E5)),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
            icon: const Icon(Icons.clear, color: Colors.grey),
            onPressed: () {
              setState(() {
                _searchController.clear();
                searchQuery = '';
                applyFilters();
              });
            },
          )
              : null,
        ),
        onChanged: (value) {
          setState(() {
            searchQuery = value;
            applyFilters();
          });
        },
      ),
    );
  }

  Widget _buildFilterTabs() {
    return Container(
      margin: const EdgeInsets.only(top: 12, left: 12, right: 12, bottom: 8),
      height: 50,
      decoration: BoxDecoration(
        color: Colors.grey.shade900,
        borderRadius: BorderRadius.circular(25),
        border: Border.all(color: Colors.grey.shade800),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _buildFilterTab(
              text: 'Все',
              selected: filterStatus == FilterStatus.all,
              onTap: () {
                setState(() {
                  filterStatus = FilterStatus.all;
                  applyFilters();
                });
              },
            ),
            _buildFilterTab(
              text: 'Оплачено',
              selected: filterStatus == FilterStatus.paid,
              color: const Color(0xFF00E5E5),
              onTap: () {
                setState(() {
                  filterStatus = FilterStatus.paid;
                  applyFilters();
                });
              },
            ),
            _buildFilterTab(
              text: 'Скоро истекает',
              selected: filterStatus == FilterStatus.expiring,
              color: Colors.orange,
              onTap: () {
                setState(() {
                  filterStatus = FilterStatus.expiring;
                  applyFilters();
                });
              },
            ),
            _buildFilterTab(
              text: 'Просрочено',
              selected: filterStatus == FilterStatus.expired,
              color: Colors.red,
              onTap: () {
                setState(() {
                  filterStatus = FilterStatus.expired;
                  applyFilters();
                });
              },
            ),
            _buildFilterTab(
              text: 'Не оплачено',
              selected: filterStatus == FilterStatus.neverPaid,
              color: Colors.grey,
              onTap: () {
                setState(() {
                  filterStatus = FilterStatus.neverPaid;
                  applyFilters();
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterTab({
    required String text,
    required bool selected,
    required VoidCallback onTap,
    Color? color,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(25),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? Colors.black : Colors.transparent,
            borderRadius: BorderRadius.circular(25),
            border: selected
                ? Border.all(color: color ?? const Color(0xFF00E5E5), width: 1)
                : null,
          ),
          child: Text(
            text,
            style: TextStyle(
              color: selected
                  ? (color ?? const Color(0xFF00E5E5))
                  : Colors.grey.shade400,
              fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              fontSize: 12,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (isLoading) {
      return const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF00E5E5)),
        ),
      );
    }

    if (errorMessage.isNotEmpty) {
      return Center(
        child: Container(
          padding: const EdgeInsets.all(20),
          margin: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.red.shade900.withOpacity(0.7),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.red.shade800),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline,
                color: Colors.white,
                size: 48,
              ),
              const SizedBox(height: 16),
              Text(
                errorMessage,
                style: const TextStyle(color: Colors.white, fontSize: 16),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: fetchData,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.red.shade900,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text('Повторить'),
              ),
            ],
          ),
        ),
      );
    }

    List<dynamic> filteredStudents = getFilteredStudents();

    if (filteredStudents.isEmpty) {
      String message = searchQuery.isNotEmpty
          ? 'Нет учеников, соответствующих поиску "$searchQuery"'
          : filterStatus == FilterStatus.all
          ? 'Нет учеников'
          : 'Нет учеников в этой категории';

      String subMessage = searchQuery.isNotEmpty
          ? 'Попробуйте изменить поисковый запрос'
          : filterStatus == FilterStatus.all
          ? 'Добавьте учеников и их оплаты'
          : 'Измените фильтр для просмотра других учеников';

      IconData iconData = searchQuery.isNotEmpty
          ? Icons.search_off
          : filterStatus == FilterStatus.neverPaid || filterStatus == FilterStatus.expired
          ? Icons.money_off
          : Icons.payment_outlined;

      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              iconData,
              size: 70,
              color: Colors.grey.shade600,
            ),
            const SizedBox(height: 16),
            Text(
              message,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade400,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Text(
                subMessage,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade500,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: filteredStudents.length,
      itemBuilder: (context, index) {
        final student = filteredStudents[index];
        final lastPayment = getLastPayment(student['id']);
        final paymentStatus = getPaymentStatus(lastPayment);

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: Colors.grey.shade800,
              width: 1,
            ),
          ),
          color: Colors.grey.shade900,
          child: InkWell(
            onTap: () {
              _showStudentPaymentDetails(student, lastPayment);
            },
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: _getStatusColor(paymentStatus),
                            width: 2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: _getStatusColor(paymentStatus).withOpacity(0.3),
                              blurRadius: 8,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                        child: CircleAvatar(
                          backgroundColor: Colors.black,
                          backgroundImage: student['photo'] != null
                              ? NetworkImage('http://26.6.96.193:8000/${student['photo']}')
                              : null,
                          child: student['photo'] == null
                              ? const Icon(
                            Icons.person,
                            color: Colors.white,
                          )
                              : null,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              student['full_name'],
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Icon(
                                  _getStatusIcon(paymentStatus),
                                  color: _getStatusColor(paymentStatus),
                                  size: 14,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  _getStatusText(paymentStatus),
                                  style: TextStyle(
                                    color: _getStatusColor(paymentStatus),
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),
                  const Divider(height: 1, color: Color(0xFF333333)),
                  const SizedBox(height: 16),

                  _buildPaymentInfoRow(
                    'Период оплаты:',
                    lastPayment != null
                        ? '${formatDate(lastPayment['period_start'])} - ${formatDate(lastPayment['period_end'])}'
                        : 'Нет данных',
                    showInfo: lastPayment != null,
                  ),
                  const SizedBox(height: 8),
                  _buildPaymentInfoRow(
                    'Следующая оплата:',
                    getNextPaymentDate(lastPayment),
                    textColor: _getNextPaymentColor(paymentStatus),
                    iconData: _getNextPaymentIcon(paymentStatus),
                    iconColor: _getNextPaymentColor(paymentStatus),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildPaymentInfoRow(
      String label,
      String value, {
        bool showInfo = true,
        IconData? iconData,
        Color? iconColor,
        Color? textColor,
      }) {
    return Row(
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.grey.shade400,
            fontSize: 13,
          ),
        ),
        const SizedBox(width: 8),
        if (iconData != null) Icon(iconData, color: iconColor, size: 14),
        if (iconData != null) const SizedBox(width: 4),
        Text(
          value,
          style: TextStyle(
            color: textColor ?? Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
        const Spacer(),
        if (showInfo)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: const Color(0xFF00E5E5),
                width: 1,
              ),
            ),
            child: const Text(
              'Подробнее',
              style: TextStyle(
                color: Color(0xFF00E5E5),
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
      ],
    );
  }

  Color _getStatusColor(PaymentStatus status) {
    switch (status) {
      case PaymentStatus.active:
        return const Color(0xFF00E5E5);
      case PaymentStatus.expiringSoon:
        return Colors.orange;
      case PaymentStatus.expired:
        return Colors.red;
      case PaymentStatus.none:
        return Colors.grey;
    }
  }

  IconData _getStatusIcon(PaymentStatus status) {
    switch (status) {
      case PaymentStatus.active:
        return Icons.check_circle;
      case PaymentStatus.expiringSoon:
        return Icons.warning;
      case PaymentStatus.expired:
        return Icons.error;
      case PaymentStatus.none:
        return Icons.money_off;
    }
  }

  String _getStatusText(PaymentStatus status) {
    switch (status) {
      case PaymentStatus.active:
        return 'Оплачено';
      case PaymentStatus.expiringSoon:
        return 'Скоро истекает';
      case PaymentStatus.expired:
        return 'Просрочено';
      case PaymentStatus.none:
        return 'Не оплачено';
    }
  }

  IconData _getNextPaymentIcon(PaymentStatus status) {
    switch (status) {
      case PaymentStatus.active:
        return Icons.event_available;
      case PaymentStatus.expiringSoon:
        return Icons.event_note;
      case PaymentStatus.expired:
      case PaymentStatus.none:
        return Icons.event_busy;
    }
  }

  Color _getNextPaymentColor(PaymentStatus status) {
    switch (status) {
      case PaymentStatus.active:
        return Colors.green;
      case PaymentStatus.expiringSoon:
        return Colors.orange;
      case PaymentStatus.expired:
        return Colors.red;
      case PaymentStatus.none:
        return Colors.grey;
    }
  }

  void _showStudentPaymentDetails(Map<String, dynamic> student, Map<String, dynamic>? lastPayment) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.7,
        decoration: BoxDecoration(
          color: Colors.grey.shade900,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 8, 16),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: Colors.grey.shade800, width: 1),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.payment,
                    color: Color(0xFF00E5E5),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'История оплат: ${student['full_name']}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 30,
                    backgroundColor: Colors.black,
                    backgroundImage: student['photo'] != null
                        ? NetworkImage('http://26.6.96.193:8000/${student['photo']}')
                        : null,
                    child: student['photo'] == null
                        ? const Icon(Icons.person, color: Colors.white, size: 30)
                        : null,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          student['full_name'],
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Дата рождения: ${formatDate(student['birth_date'])}',
                          style: TextStyle(
                            color: Colors.grey.shade400,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      _showAddPaymentDialog(student);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00E5E5),
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(25),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                    ),
                    child: const Text(
                      'Оплатить',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            Expanded(
              child: lastPayment == null
                  ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.payment_outlined,
                      size: 60,
                      color: Colors.grey.shade600,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Нет истории оплат',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey.shade400,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Добавьте первую оплату, нажав кнопку выше',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey.shade500,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              )
                  : ListView.builder(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                itemCount: payments
                    .where((payment) => payment['student'] == student['id'])
                    .length,
                itemBuilder: (context, index) {
                  final filteredPayments = payments
                      .where((payment) => payment['student'] == student['id'])
                      .toList();

                  filteredPayments.sort((a, b) =>
                      DateTime.parse(b['period_end']).compareTo(DateTime.parse(a['period_end']))
                  );

                  final payment = filteredPayments[index];
                  final periodEnd = DateTime.parse(payment['period_end']);
                  final isActive = periodEnd.isAfter(DateTime.now());

                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade800,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isActive
                            ? const Color(0xFF00E5E5)
                            : Colors.grey.shade700,
                        width: 1,
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Оплачено ${formatDate(payment['payment_date'])}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: isActive
                                      ? Colors.green.withOpacity(0.2)
                                      : Colors.red.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  isActive ? 'Активно' : 'Истекло',
                                  style: TextStyle(
                                    color: isActive
                                        ? Colors.green
                                        : Colors.red,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Период:',
                                      style: TextStyle(
                                        color: Colors.grey.shade400,
                                        fontSize: 12,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '${formatDate(payment['period_start'])} - ${formatDate(payment['period_end'])}',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Сумма:',
                                      style: TextStyle(
                                        color: Colors.grey.shade400,
                                        fontSize: 12,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      formatCurrency(payment['amount']),
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Способ оплаты:',
                                      style: TextStyle(
                                        color: Colors.grey.shade400,
                                        fontSize: 12,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      _getPaymentMethodText(payment['payment_method']),
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (payment['notes'] != null && payment['notes'].toString().isNotEmpty)
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Примечание:',
                                        style: TextStyle(
                                          color: Colors.grey.shade400,
                                          fontSize: 12,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        payment['notes'],
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 14,
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                )
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getPaymentMethodText(String method) {
    switch (method) {
      case 'cash':
        return 'Наличные';
      case 'card':
        return 'Банковская карта';
      case 'transfer':
        return 'Банковский перевод';
      case 'other':
        return 'Другое';
      default:
        return method;
    }
  }

  void _showAddPaymentDialog([Map<String, dynamic>? preSelectedStudent]) {
    final _formKey = GlobalKey<FormState>();
    Map<String, dynamic>? selectedStudent = preSelectedStudent;
    final _amountController = TextEditingController(text: '200000');
    DateTime _paymentDate = DateTime.now();
    DateTime _periodStart = DateTime.now();
    DateTime _periodEnd = DateTime.now().add(const Duration(days: 30));
    String _paymentMethod = 'cash';
    bool _isPaid = true;
    final _notesController = TextEditingController();
    bool _isSubmitting = false;
    String _errorMessage = '';
    final List<DropdownMenuItem<Map<String, dynamic>>> studentItems = students
        .map<DropdownMenuItem<Map<String, dynamic>>>((student) {
      return DropdownMenuItem<Map<String, dynamic>>(
        value: student,
        child: Text(
          student['full_name'],
          style: const TextStyle(color: Colors.white),
          overflow: TextOverflow.ellipsis,
        ),
      );
    }).toList();

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) {
          Future<void> selectDate(DateTime initialDate, Function(DateTime) onSelected) async {
            final DateTime? picked = await showDatePicker(
              context: context,
              initialDate: initialDate,
              firstDate: DateTime(2020),
              lastDate: DateTime(2030),
              builder: (context, child) {
                return Theme(
                  data: ThemeData.dark().copyWith(
                    colorScheme: const ColorScheme.dark(
                      primary: Color(0xFF00E5E5),
                      onPrimary: Colors.black,
                      surface: Color(0xFF212121),
                      onSurface: Colors.white,
                    ),
                    dialogBackgroundColor: const Color(0xFF212121),
                  ),
                  child: child!,
                );
              },
            );

            if (picked != null) {
              setState(() {
                onSelected(picked);
              });
            }
          }
          Future<void> submitPayment() async {
            if (_formKey.currentState!.validate() && selectedStudent != null) {
              setState(() {
                _isSubmitting = true;
                _errorMessage = '';
              });

              try {
                final response = await http.post(
                  Uri.parse('http://26.6.96.193:8000/api/payments/'),
                  headers: {
                    'Authorization': 'Token ${widget.token}',
                    'Content-Type': 'application/json',
                  },
                  body: jsonEncode({
                    'student': selectedStudent?['id'],
                    'amount': _amountController.text,
                    'payment_date': DateFormat('yyyy-MM-dd').format(_paymentDate),
                    'period_start': DateFormat('yyyy-MM-dd').format(_periodStart),
                    'period_end': DateFormat('yyyy-MM-dd').format(_periodEnd),
                    'payment_method': _paymentMethod,
                    'is_paid': _isPaid,
                    'notes': _notesController.text,
                  }),
                );

                if (response.statusCode == 201) {
                  ScaffoldMessenger.of(this.context).showSnackBar(
                    SnackBar(
                      content: const Text('Оплата успешно добавлена'),
                      backgroundColor: Colors.green.shade800,
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  );
                  fetchData();
                  Navigator.pop(dialogContext);
                } else {
                  setState(() {
                    _errorMessage = 'Ошибка при добавлении: ${response.statusCode}';
                    _isSubmitting = false;
                  });
                }
              } catch (e) {
                setState(() {
                  _errorMessage = 'Ошибка соединения с сервером: $e';
                  _isSubmitting = false;
                });
              }
            } else if (selectedStudent == null) {
              setState(() {
                _errorMessage = 'Пожалуйста, выберите ученика';
              });
            }
          }

          return AlertDialog(
            backgroundColor: Colors.grey.shade900,
            title: Text(
              selectedStudent != null
                  ? 'Добавление оплаты для ${selectedStudent?['full_name']}'
                  : 'Добавление оплаты',
              style: const TextStyle(color: Colors.white),
            ),
            content: SizedBox(
              width: double.maxFinite,
              child: Form(
                key: _formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (preSelectedStudent == null) ...[
                        const Text(
                          'Ученик:',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade800,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<Map<String, dynamic>>(
                              isExpanded: true,
                              value: selectedStudent,
                              hint: const Text(
                                'Выберите ученика',
                                style: TextStyle(color: Colors.grey),
                              ),
                              dropdownColor: Colors.grey.shade800,
                              items: studentItems,
                              onChanged: (value) {
                                setState(() {
                                  selectedStudent = value;
                                });
                              },
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      const Text(
                        'Сумма (UZS):',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _amountController,
                        keyboardType: TextInputType.number,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: Colors.grey.shade800,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide.none,
                          ),
                          prefixIcon: const Icon(
                            Icons.monetization_on,
                            color: Color(0xFF00E5E5),
                          ),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Введите сумму';
                          }
                          if (double.tryParse(value) == null) {
                            return 'Неверный формат числа';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Дата оплаты:',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      InkWell(
                        onTap: () => selectDate(_paymentDate, (date) => _paymentDate = date),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade800,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.calendar_today,
                                color: Color(0xFF00E5E5),
                                size: 20,
                              ),
                              const SizedBox(width: 10),
                              Text(
                                formatDate(_paymentDate.toIso8601String().split('T')[0]),
                                style: const TextStyle(color: Colors.white),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Начало периода:',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      InkWell(
                        onTap: () => selectDate(_periodStart, (date) => _periodStart = date),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade800,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.date_range,
                                color: Color(0xFF00E5E5),
                                size: 20,
                              ),
                              const SizedBox(width: 10),
                              Text(
                                formatDate(_periodStart.toIso8601String().split('T')[0]),
                                style: const TextStyle(color: Colors.white),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Конец периода:',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      InkWell(
                        onTap: () => selectDate(_periodEnd, (date) => _periodEnd = date),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade800,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.date_range,
                                color: Color(0xFF00E5E5),
                                size: 20,
                              ),
                              const SizedBox(width: 10),
                              Text(
                                formatDate(_periodEnd.toIso8601String().split('T')[0]),
                                style: const TextStyle(color: Colors.white),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Способ оплаты:',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade800,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            isExpanded: true,
                            value: _paymentMethod,
                            dropdownColor: Colors.grey.shade800,
                            items: const [
                              DropdownMenuItem(
                                value: 'cash',
                                child: Text(
                                  'Наличные',
                                  style: TextStyle(color: Colors.white),
                                ),
                              ),
                              DropdownMenuItem(
                                value: 'card',
                                child: Text(
                                  'Банковская карта',
                                  style: TextStyle(color: Colors.white),
                                ),
                              ),
                              DropdownMenuItem(
                                value: 'transfer',
                                child: Text(
                                  'Банковский перевод',
                                  style: TextStyle(color: Colors.white),
                                ),
                              ),
                              DropdownMenuItem(
                                value: 'other',
                                child: Text(
                                  'Другое',
                                  style: TextStyle(color: Colors.white),
                                ),
                              ),
                            ],
                            onChanged: (value) {
                              setState(() {
                                _paymentMethod = value!;
                              });
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Switch(
                            value: _isPaid,
                            onChanged: (value) {
                              setState(() {
                                _isPaid = value;
                              });
                            },
                            activeColor: const Color(0xFF00E5E5),
                            activeTrackColor: const Color(0xFF006B67),
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            'Оплачено',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Примечания:',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _notesController,
                        maxLines: 2,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: Colors.grey.shade800,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),

                      // Сообщение об ошибке
                      if (_errorMessage.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.red.shade900.withOpacity(0.7),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.error_outline,
                                color: Colors.white,
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _errorMessage,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text(
                  'Отмена',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
              ElevatedButton(
                onPressed: _isSubmitting ? null : submitPayment,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00E5E5),
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: _isSubmitting
                    ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.black),
                  ),
                )
                    : const Text('Сохранить'),
              ),
            ],
          );
        },
      ),
    );
  }
}

enum FilterStatus {
  all,
  paid,
  expiring,
  expired,
  neverPaid,
}

enum PaymentStatus {
  active,
  expiringSoon,
  expired,
  none,
}
