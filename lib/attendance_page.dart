import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';

class AttendancePage extends StatefulWidget {
  final String token;

  const AttendancePage({super.key, required this.token});

  @override
  State<AttendancePage> createState() => _AttendancePageState();
}

class _AttendancePageState extends State<AttendancePage> {
  DateTime _selectedDate = DateTime.now();
  bool _isLoading = false;
  bool _isSubmitting = false;
  List<Map<String, dynamic>> _students = [];
  List<Map<String, dynamic>> _filteredStudents = [];
  Map<String, Map<String, dynamic>> _attendance = {};
  final TimeOfDay _defaultTimeIn = const TimeOfDay(hour: 9, minute: 0);
  final TimeOfDay _defaultTimeOut = const TimeOfDay(hour: 10, minute: 30);
  String _errorMessage = '';
  final TextEditingController _searchController = TextEditingController();
  final _refreshKey = GlobalKey<RefreshIndicatorState>();
  String _baseUrl = 'https://taekwondo.pythonanywhere.com';

  @override
  void initState() {
    super.initState();
    _loadData();
    _searchController.addListener(_filterStudents);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _filterStudents() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _filteredStudents = List.from(_students);
      } else {
        _filteredStudents = _students
            .where((student) =>
            student['name'].toString().toLowerCase().contains(query))
            .toList();
      }
    });
  }

  // Загрузка данных о студентах и их посещаемости
  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final studentsResponse = await http.get(
        Uri.parse('$_baseUrl/api/students/'),
        headers: {
          'Authorization': 'Token ${widget.token}',
          'Content-Type': 'application/json',
        },
      );

      if (studentsResponse.statusCode != 200) {
        throw Exception('Не удалось загрузить список студентов: ${studentsResponse.body}');
      }
      final studentsData = json.decode(studentsResponse.body);
      final formattedDate = DateFormat('yyyy-MM-dd').format(_selectedDate);
      final attendanceResponse = await http.get(
        Uri.parse('$_baseUrl/api/daily-attendance/?date=$formattedDate'),
        headers: {
          'Authorization': 'Token ${widget.token}',
          'Content-Type': 'application/json',
        },
      );

      final List<Map<String, dynamic>> attendanceData = [];
      if (attendanceResponse.statusCode == 200) {
        final List<dynamic> attendanceList = json.decode(attendanceResponse.body);
        for (var item in attendanceList) {
          attendanceData.add(Map<String, dynamic>.from(item));
        }
      } else if (attendanceResponse.statusCode != 404) {
        throw Exception('Ошибка загрузки посещаемости: ${attendanceResponse.body}');
      }
      final List<Map<String, dynamic>> students = [];
      final Map<String, Map<String, dynamic>> attendance = {};

      for (var student in studentsData) {
        final studentId = student['id'].toString();
        students.add({
          'id': studentId,
          'name': '${student['full_name']}',
          'photo': student['photo'],
          'birth_date': student['birth_date'],
        });

        final existingAttendance = attendanceData.firstWhere(
              (a) => a['student'].toString() == studentId,
          orElse: () => {},
        );

        if (existingAttendance.isNotEmpty) {
          attendance[studentId] = {
            'present': true,
            'time_in': existingAttendance['time_in'],
            'time_out': existingAttendance['time_out'],
            'notes': existingAttendance['notes'] ?? '',
            'id': existingAttendance['id'],
          };
        } else {
          attendance[studentId] = {
            'present': false,
            'time_in': null,
            'time_out': null,
            'notes': '',
            'id': null,
          };
        }
      }

      setState(() {
        _students = students;
        _filteredStudents = List.from(students);
        _attendance = attendance;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = e.toString();
      });
      if (mounted) {
        _showSnackBar(e.toString(), isError: true);
      }
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w500,
          ),
        ),
        backgroundColor: isError ? Colors.red.shade700 : Colors.green.shade700,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        margin: EdgeInsets.only(
          bottom: MediaQuery.of(context).size.height * 0.1,
          left: 16,
          right: 16,
        ),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _saveAttendance() async {
    setState(() {
      _isSubmitting = true;
      _errorMessage = '';
    });

    try {
      final formattedDate = DateFormat('yyyy-MM-dd').format(_selectedDate);
      final List<Map<String, dynamic>> attendanceData = [];

      _attendance.forEach((studentId, data) {
        if (data['present'] == true) {
          attendanceData.add({
            'student_id': int.parse(studentId),
            'time_in': data['time_in'],
            'time_out': data['time_out'],
            'notes': data['notes'],
          });
        }
      });
      final response = await http.post(
        Uri.parse('$_baseUrl/api/daily-attendance/'),
        headers: {
          'Authorization': 'Token ${widget.token}',
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'date': formattedDate,
          'attendance_data': attendanceData,
        }),
      );

      if (response.statusCode != 200 && response.statusCode != 201) {
        throw Exception('Ошибка при сохранении данных: ${response.body}');
      }

      if (mounted) {
        _showSnackBar('Данные о посещаемости успешно сохранены');
      }
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
      });
      if (mounted) {
        _showSnackBar(e.toString(), isError: true);
      }
    } finally {
      setState(() {
        _isSubmitting = false;
      });
    }
  }

  // Устанавливает текущее время для времени прихода
  void _setCurrentTimeForTimeIn(String studentId) {
    final now = DateTime.now();
    final currentTime = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

    setState(() {
      _attendance[studentId]!['time_in'] = currentTime;
    });
  }

  // Устанавливает текущее время для времени ухода
  void _setCurrentTimeForTimeOut(String studentId) {
    final now = DateTime.now();
    final currentTime = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

    setState(() {
      _attendance[studentId]!['time_out'] = currentTime;
    });
  }

  Future<void> _selectTimeIn(String studentId) async {
    final choice = await showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: Colors.grey.shade900,
          title: const Text(
            'Время прихода',
            style: TextStyle(color: Colors.white),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.access_time, color: Color(0xFF00E5E5)),
                title: const Text(
                  'Текущее время',
                  style: TextStyle(color: Colors.white),
                ),
                onTap: () {
                  Navigator.of(context).pop('current');
                },
              ),
              ListTile(
                leading: const Icon(Icons.edit_calendar, color: Color(0xFF00E5E5)),
                title: const Text(
                  'Выбрать время',
                  style: TextStyle(color: Colors.white),
                ),
                onTap: () {
                  Navigator.of(context).pop('custom');
                },
              ),
            ],
          ),
        );
      },
    );

    if (choice == 'current') {
      _setCurrentTimeForTimeIn(studentId);
    } else if (choice == 'custom') {
      final TimeOfDay? picked = await showTimePicker(
        context: context,
        initialTime: _attendance[studentId]!['time_in'] != null
            ? TimeOfDay(
          hour: int.parse(_attendance[studentId]!['time_in'].split(':')[0]),
          minute: int.parse(_attendance[studentId]!['time_in'].split(':')[1]),
        )
            : _defaultTimeIn,
        builder: (context, child) {
          return Theme(
            data: Theme.of(context).copyWith(
              colorScheme: ColorScheme.dark(
                primary: const Color(0xFF00E5E5),
                onPrimary: Colors.white,
                surface: Colors.grey.shade900,
                onSurface: Colors.white,
              ),
              timePickerTheme: TimePickerThemeData(
                backgroundColor: Colors.grey.shade900,
                hourMinuteTextColor: Colors.white,
                dayPeriodTextColor: Colors.white,
                dialHandColor: const Color(0xFF00E5E5),
                dialBackgroundColor: Colors.grey.shade800,
                hourMinuteColor: Colors.grey.shade800,
                dayPeriodColor: Colors.grey.shade800,
                dialTextColor: Colors.white,
              ),
            ),
            child: child!,
          );
        },
      );

      if (picked != null) {
        setState(() {
          _attendance[studentId]!['time_in'] =
          '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
        });
      }
    }
  }

  Future<void> _selectTimeOut(String studentId) async {
    final choice = await showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: Colors.grey.shade900,
          title: const Text(
            'Время ухода',
            style: TextStyle(color: Colors.white),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.access_time, color: Color(0xFF00E5E5)),
                title: const Text(
                  'Текущее время',
                  style: TextStyle(color: Colors.white),
                ),
                onTap: () {
                  Navigator.of(context).pop('current');
                },
              ),
              ListTile(
                leading: const Icon(Icons.edit_calendar, color: Color(0xFF00E5E5)),
                title: const Text(
                  'Выбрать время',
                  style: TextStyle(color: Colors.white),
                ),
                onTap: () {
                  Navigator.of(context).pop('custom');
                },
              ),
            ],
          ),
        );
      },
    );

    if (choice == 'current') {
      _setCurrentTimeForTimeOut(studentId);
    } else if (choice == 'custom') {
      final TimeOfDay? picked = await showTimePicker(
        context: context,
        initialTime: _attendance[studentId]!['time_out'] != null
            ? TimeOfDay(
          hour: int.parse(_attendance[studentId]!['time_out'].split(':')[0]),
          minute: int.parse(_attendance[studentId]!['time_out'].split(':')[1]),
        )
            : _defaultTimeOut,
        builder: (context, child) {
          return Theme(
            data: Theme.of(context).copyWith(
              colorScheme: ColorScheme.dark(
                primary: const Color(0xFF00E5E5),
                onPrimary: Colors.white,
                surface: Colors.grey.shade900,
                onSurface: Colors.white,
              ),
              timePickerTheme: TimePickerThemeData(
                backgroundColor: Colors.grey.shade900,
                hourMinuteTextColor: Colors.white,
                dayPeriodTextColor: Colors.white,
                dialHandColor: const Color(0xFF00E5E5),
                dialBackgroundColor: Colors.grey.shade800,
                hourMinuteColor: Colors.grey.shade800,
                dayPeriodColor: Colors.grey.shade800,
                dialTextColor: Colors.white,
              ),
            ),
            child: child!,
          );
        },
      );

      if (picked != null) {
        setState(() {
          _attendance[studentId]!['time_out'] =
          '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
        });
      }
    }
  }

  void _addNote(String studentId) {
    final textController = TextEditingController(text: _attendance[studentId]!['notes']);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey.shade900,
        title: const Text(
          'Добавить примечание',
          style: TextStyle(color: Colors.white),
        ),
        content: TextField(
          controller: textController,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Введите примечание',
            hintStyle: TextStyle(color: Colors.grey.shade400),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.grey.shade700),
            ),
            focusedBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: Color(0xFF00E5E5)),
            ),
          ),
          maxLines: 3,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Отмена',
              style: TextStyle(color: Colors.grey),
            ),
          ),
          TextButton(
            onPressed: () {
              setState(() {
                _attendance[studentId]!['notes'] = textController.text;
              });
              Navigator.pop(context);
            },
            child: const Text(
              'Сохранить',
              style: TextStyle(color: Color(0xFF00E5E5)),
            ),
          ),
        ],
      ),
    );
  }

  String _getFormattedAge(String birthDate) {
    if (birthDate.isEmpty) return "";

    final birthDateObj = DateTime.parse(birthDate);
    final now = DateTime.now();
    int age = now.year - birthDateObj.year;

    if (now.month < birthDateObj.month ||
        (now.month == birthDateObj.month && now.day < birthDateObj.day)) {
      age--;
    }

    return "$age лет";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Посещаемость',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            letterSpacing: 1.0,
            color: Colors.white,
          ),
        ),
        backgroundColor: Colors.black,
        elevation: 0,
        iconTheme: const IconThemeData(color: Color(0xFF00E5E5)),
      ),
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
        child: _isLoading
            ? const Center(
          child: CircularProgressIndicator(
            color: Color(0xFF00E5E5),
          ),
        )
            : RefreshIndicator(
          key: _refreshKey,
          onRefresh: _loadData,
          color: const Color(0xFF00E5E5),
          backgroundColor: Colors.grey.shade900,
          displacement: 20,
          child: Column(
            children: [
              // Дата и поиск
              Container(
                padding: const EdgeInsets.all(16),
                margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                decoration: BoxDecoration(
                  color: Colors.grey.shade900,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.grey.shade800,
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        'Дата: ${_selectedDate.day}.${_selectedDate.month}.${_selectedDate.year}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.grey.shade800.withOpacity(0.6),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: IconButton(
                        icon: const Icon(Icons.calendar_today, color: Color(0xFF00E5E5)),
                        onPressed: () async {
                          final DateTime? picked = await showDatePicker(
                            context: context,
                            initialDate: _selectedDate,
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2030),
                            builder: (context, child) {
                              return Theme(
                                data: Theme.of(context).copyWith(
                                  colorScheme: ColorScheme.dark(
                                    primary: const Color(0xFF00E5E5),
                                    onPrimary: Colors.white,
                                    surface: Colors.grey.shade900,
                                    onSurface: Colors.white,
                                  ),
                                  dialogBackgroundColor: Colors.grey.shade900,
                                ),
                                child: child!,
                              );
                            },
                          );
                          if (picked != null && picked != _selectedDate) {
                            setState(() {
                              _selectedDate = picked;
                            });
                            _loadData();
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ),

              // Поиск
              Container(
                margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                decoration: BoxDecoration(
                  color: Colors.grey.shade900,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.grey.shade800,
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: TextField(
                  controller: _searchController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Поиск учеников...',
                    hintStyle: TextStyle(color: Colors.grey.shade500),
                    prefixIcon: Icon(Icons.search, color: Colors.grey.shade500),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                      icon: Icon(Icons.clear, color: Colors.grey.shade500),
                      onPressed: () {
                        _searchController.clear();
                      },
                    )
                        : null,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 15),
                  ),
                ),
              ),

              if (_errorMessage.isNotEmpty)
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.shade900.withOpacity(0.7),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Colors.red.shade800,
                      width: 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.error_outline,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorMessage,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Text(
                  'Отметьте присутствующих учеников и укажите время',
                  style: TextStyle(
                    color: Colors.grey.shade400,
                    fontSize: 14,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),

              const SizedBox(height: 8),
              Expanded(
                child: _filteredStudents.isEmpty
                    ? Center(
                  child: Text(
                    _students.isEmpty
                        ? 'Нет данных об учениках'
                        : 'Ничего не найдено',
                    style: TextStyle(
                      color: Colors.grey.shade400,
                      fontSize: 16,
                    ),
                  ),
                )
                    : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _filteredStudents.length,
                  itemBuilder: (context, index) {
                    final student = _filteredStudents[index];
                    final studentId = student['id'];
                    final attendanceData = _attendance[studentId]!;
                    final String? photoUrl = student['photo'];
                    final String birthDate = student['birth_date'] ?? '';

                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade900,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: attendanceData['present']
                              ? const Color(0xFF00E5E5).withOpacity(0.5)
                              : Colors.grey.shade800,
                          width: 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.2),
                            blurRadius: 6,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Theme(
                        data: Theme.of(context).copyWith(
                          dividerColor: Colors.transparent,
                          unselectedWidgetColor: Colors.grey.shade600,
                        ),
                        child: ExpansionTile(
                          initiallyExpanded: attendanceData['present'],
                          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          collapsedBackgroundColor: Colors.transparent,
                          backgroundColor: Colors.transparent,
                          leading: Container(
                            width: 50,
                            height: 50,
                            decoration: BoxDecoration(
                              color: Colors.grey.shade800,
                              borderRadius: BorderRadius.circular(25),
                              border: Border.all(
                                color: attendanceData['present']
                                    ? const Color(0xFF00E5E5)
                                    : Colors.grey.shade700,
                                width: 2,
                              ),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(25),
                              child: photoUrl != null && photoUrl.isNotEmpty
                                  ? CachedNetworkImage(
                                imageUrl: '$_baseUrl$photoUrl',
                                fit: BoxFit.cover,
                                width: 50,
                                height: 50,
                                placeholder: (context, url) => Center(
                                  child: CircularProgressIndicator(
                                    color: Colors.grey.shade600,
                                    strokeWidth: 2,
                                  ),
                                ),
                                errorWidget: (context, url, error) => const Center(
                                  child: Icon(
                                    Icons.person,
                                    color: Colors.white,
                                    size: 30,
                                  ),
                                ),
                              )
                                  : const Center(
                                child: Icon(
                                  Icons.person,
                                  color: Colors.white,
                                  size: 30,
                                ),
                              ),
                            ),
                          ),
                          title: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  student['name'],
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade800.withOpacity(0.6),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Checkbox(
                                  value: attendanceData['present'],
                                  activeColor: const Color(0xFF00E5E5),
                                  checkColor: Colors.black,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  onChanged: (bool? value) {
                                    setState(() {
                                      _attendance[studentId]!['present'] = value!;
                                      if (value && attendanceData['time_in'] == null) {
                                        _attendance[studentId]!['time_in'] =
                                        '${_defaultTimeIn.hour.toString().padLeft(2, '0')}:${_defaultTimeIn.minute.toString().padLeft(2, '0')}';
                                      }
                                      if (value && attendanceData['time_out'] == null) {
                                        _attendance[studentId]!['time_out'] =
                                        '${_defaultTimeOut.hour.toString().padLeft(2, '0')}:${_defaultTimeOut.minute.toString().padLeft(2, '0')}';
                                      }
                                    });
                                  },
                                ),
                              ),
                            ],
                          ),
                          subtitle: birthDate.isNotEmpty
                              ? Text(
                            _getFormattedAge(birthDate),
                            style: TextStyle(
                              color: Colors.grey.shade400,
                              fontSize: 12,
                            ),
                          )
                              : null,
                          trailing: attendanceData['present']
                              ? const Icon(Icons.keyboard_arrow_up, color: Color(0xFF00E5E5))
                              : const Icon(Icons.keyboard_arrow_down, color: Colors.grey),
                          expandedCrossAxisAlignment: CrossAxisAlignment.start,
                          childrenPadding: EdgeInsets.zero,
                          children: [
                            if (attendanceData['present'])
                              Divider(color: Colors.grey.shade800, thickness: 1, height: 1),
                            if (attendanceData['present'])
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade800.withOpacity(0.3),
                                  borderRadius: const BorderRadius.only(
                                    bottomLeft: Radius.circular(12),
                                    bottomRight: Radius.circular(12),
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                                            decoration: BoxDecoration(
                                              color: Colors.grey.shade900.withOpacity(0.7),
                                              borderRadius: BorderRadius.circular(8),
                                              border: Border.all(
                                                color: Colors.grey.shade800,
                                                width: 1,
                                              ),
                                            ),
                                            child: Row(
                                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                              children: [
                                                Text(
                                                  'Время прихода:',
                                                  style: TextStyle(
                                                    color: Colors.grey.shade300,
                                                    fontWeight: FontWeight.w500,
                                                    fontSize: 13,
                                                  ),
                                                ),
                                                TextButton.icon(
                                                  icon: const Icon(Icons.access_time, size: 16),
                                                  label: Text(
                                                    attendanceData['time_in'] ?? 'Выбрать',
                                                    style: const TextStyle(
                                                      fontSize: 13,
                                                      fontWeight: FontWeight.w500,
                                                    ),
                                                  ),
                                                  onPressed: () => _selectTimeIn(studentId),
                                                  style: TextButton.styleFrom(
                                                    foregroundColor: const Color(0xFF00E5E5),
                                                    padding: EdgeInsets.zero,
                                                    minimumSize: Size.zero,
                                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                                            decoration: BoxDecoration(
                                              color: Colors.grey.shade900.withOpacity(0.7),
                                              borderRadius: BorderRadius.circular(8),
                                              border: Border.all(
                                                color: Colors.grey.shade800,
                                                width: 1,
                                              ),
                                            ),
                                            child: Row(
                                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                              children: [
                                                Text(
                                                  'Время ухода:',
                                                  style: TextStyle(
                                                    color: Colors.grey.shade300,
                                                    fontWeight: FontWeight.w500,
                                                    fontSize: 13,
                                                  ),
                                                ),
                                                TextButton.icon(
                                                  icon: const Icon(Icons.access_time, size: 16),
                                                  label: Text(
                                                    attendanceData['time_out'] ?? 'Выбрать',
                                                    style: const TextStyle(
                                                      fontSize: 13,
                                                      fontWeight: FontWeight.w500,
                                                    ),
                                                  ),
                                                  onPressed: () => _selectTimeOut(studentId),
                                                  style: TextButton.styleFrom(
                                                    foregroundColor: const Color(0xFF00E5E5),
                                                    padding: EdgeInsets.zero,
                                                    minimumSize: Size.zero,
                                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                                            decoration: BoxDecoration(
                                              color: Colors.grey.shade900.withOpacity(0.7),
                                              borderRadius: BorderRadius.circular(8),
                                              border: Border.all(
                                                color: Colors.grey.shade800,
                                                width: 1,
                                              ),
                                            ),
                                            child: Row(
                                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                              children: [
                                                Text(
                                                  'Примечание:',
                                                  style: TextStyle(
                                                    color: Colors.grey.shade300,
                                                    fontWeight: FontWeight.w500,
                                                    fontSize: 13,
                                                  ),
                                                ),
                                                TextButton.icon(
                                                  icon: const Icon(Icons.note_add, size: 16),
                                                  label: Text(
                                                    attendanceData['notes'].isEmpty ? 'Добавить' : 'Изменить',
                                                    style: const TextStyle(
                                                      fontSize: 13,
                                                      fontWeight: FontWeight.w500,
                                                    ),
                                                  ),
                                                  onPressed: () => _addNote(studentId),
                                                  style: TextButton.styleFrom(
                                                    foregroundColor: const Color(0xFF00E5E5),
                                                    padding: EdgeInsets.zero,
                                                    minimumSize: Size.zero,
                                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),

                                    if (attendanceData['notes'].isNotEmpty)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 8),
                                        child: Container(
                                          width: double.infinity,
                                          padding: const EdgeInsets.all(12),
                                          decoration: BoxDecoration(
                                            color: Colors.grey.shade900.withOpacity(0.7),
                                            borderRadius: BorderRadius.circular(8),
                                            border: Border.all(
                                              color: Colors.grey.shade800,
                                              width: 1,
                                            ),
                                          ),
                                          child: Text(
                                            attendanceData['notes'],
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 13,
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.5),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 10,
                      offset: const Offset(0, -5),
                    ),
                  ],
                ),
                child: ElevatedButton(
                  onPressed: _isSubmitting ? null : _saveAttendance,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00E5E5),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 5,
                    shadowColor: const Color(0xFF00E5E5).withOpacity(0.5),
                    disabledBackgroundColor: Colors.grey.shade600,
                    disabledForegroundColor: Colors.black45,
                  ),
                  child: _isSubmitting
                      ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      color: Colors.black,
                      strokeWidth: 3,
                    ),
                  )
                      : const Text(
                    'Сохранить',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
