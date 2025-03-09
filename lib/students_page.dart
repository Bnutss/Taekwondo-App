import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'student_detail_page.dart';
import 'add_student_page.dart';

class StudentsPage extends StatefulWidget {
  final String token;

  const StudentsPage({super.key, required this.token});

  @override
  State<StudentsPage> createState() => _StudentsPageState();
}

class _StudentsPageState extends State<StudentsPage> {
  List<dynamic> students = [];
  List<dynamic> filteredStudents = [];
  bool isLoading = true;
  String errorMessage = '';
  String searchQuery = '';
  FilterStatus filterStatus = FilterStatus.all;
  bool isSearchVisible = false;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    fetchStudents();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _formatDate(String isoDate) {
    try {
      final DateTime date = DateTime.parse(isoDate);
      return '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';
    } catch (e) {
      return isoDate;
    }
  }

  Future<void> fetchStudents() async {
    try {
      final response = await http.get(
        Uri.parse('http://26.6.96.193:8000/api/students/'),
        headers: {
          'Authorization': 'Token ${widget.token}',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        setState(() {
          students = jsonDecode(response.body);
          applyFilters();
          isLoading = false;
        });
      } else {
        setState(() {
          errorMessage = 'Ошибка загрузки данных: ${response.statusCode}';
          isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        errorMessage = 'Ошибка соединения с сервером: $e';
        isLoading = false;
      });
    }
  }

  void applyFilters() {
    List<dynamic> result = List.from(students);
    if (filterStatus == FilterStatus.active) {
      result = result.where((student) => !student['is_inactive']).toList();
    } else if (filterStatus == FilterStatus.inactive) {
      result = result.where((student) => student['is_inactive']).toList();
    }
    if (searchQuery.isNotEmpty) {
      result = result.where((student) =>
          student['full_name'].toString().toLowerCase().contains(searchQuery.toLowerCase())
      ).toList();
    }

    setState(() {
      filteredStudents = result;
    });
  }

  Future<void> deleteStudent(int id) async {
    try {
      final response = await http.delete(
        Uri.parse('http://26.6.96.193:8000/api/students/$id/'),
        headers: {
          'Authorization': 'Token ${widget.token}',
        },
      );

      if (response.statusCode == 204) {
        setState(() {
          students.removeWhere((student) => student['id'] == id);
          applyFilters();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Ученик успешно удален'),
            backgroundColor: Colors.green.shade800,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка при удалении: ${response.statusCode}'),
            backgroundColor: Colors.red.shade800,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ошибка соединения: $e'),
          backgroundColor: Colors.red.shade800,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
    }
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
            // Фильтр по статусу
            isLoading ? Container() : _buildFilterTabs(),
            // Основной контент
            Expanded(
              child: RefreshIndicator(
                onRefresh: fetchStudents,
                color: const Color(0xFF00E5E5),
                backgroundColor: Colors.grey.shade900,
                child: _buildBody(),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => AddStudentPage(token: widget.token),
            ),
          );
          if (result == true) {
            fetchStudents();
          }
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

  AppBar _buildAppBar() {
    if (isSearchVisible) {
      return AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        title: TextField(
          controller: _searchController,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: "Поиск ученика...",
            hintStyle: TextStyle(color: Colors.grey.shade400),
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(vertical: 15),
          ),
          onChanged: (value) {
            setState(() {
              searchQuery = value;
              applyFilters();
            });
          },
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF00E5E5)),
          onPressed: () {
            setState(() {
              isSearchVisible = false;
              searchQuery = '';
              _searchController.clear();
              applyFilters();
            });
          },
        ),
      );
    } else {
      return AppBar(
        title: Row(
          children: [
            const Icon(
              Icons.people,
              color: Color(0xFF00E5E5),
              size: 24,
            ),
            const SizedBox(width: 8),
            const Text(
              'УЧЕНИКИ',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 8),
            if (!isLoading)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF00E5E5),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  students.length.toString(),
                  style: const TextStyle(
                    color: Colors.black,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search, color: Color(0xFF00E5E5)),
            onPressed: () {
              setState(() {
                isSearchVisible = true;
              });
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: Color(0xFF00E5E5)),
            onPressed: fetchStudents,
          ),
        ],
        backgroundColor: Colors.black,
        elevation: 0,
        iconTheme: const IconThemeData(color: Color(0xFF00E5E5)),
      );
    }
  }

  Widget _buildFilterTabs() {
    return Container(
      margin: const EdgeInsets.only(top: 12, left: 12, right: 12),
      decoration: BoxDecoration(
        color: Colors.grey.shade900,
        borderRadius: BorderRadius.circular(25),
        border: Border.all(color: Colors.grey.shade800),
      ),
      child: Row(
        children: [
          _buildFilterTab(
            text: 'Все',
            count: students.length,
            selected: filterStatus == FilterStatus.all,
            onTap: () {
              setState(() {
                filterStatus = FilterStatus.all;
                applyFilters();
              });
            },
          ),
          _buildFilterTab(
            text: 'Активные',
            count: students.where((student) => !student['is_inactive']).length,
            selected: filterStatus == FilterStatus.active,
            onTap: () {
              setState(() {
                filterStatus = FilterStatus.active;
                applyFilters();
              });
            },
            color: const Color(0xFF00E5E5),
          ),
          _buildFilterTab(
            text: 'Неактивные',
            count: students.where((student) => student['is_inactive']).length,
            selected: filterStatus == FilterStatus.inactive,
            onTap: () {
              setState(() {
                filterStatus = FilterStatus.inactive;
                applyFilters();
              });
            },
            color: Colors.red.shade400,
          ),
        ],
      ),
    );
  }

  Widget _buildFilterTab({
    required String text,
    required int count,
    required bool selected,
    required VoidCallback onTap,
    Color? color,
  }) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(25),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? Colors.black : Colors.transparent,
            borderRadius: BorderRadius.circular(25),
            border: selected
                ? Border.all(color: color ?? const Color(0xFF00E5E5), width: 1)
                : null,
          ),
          child: Column(
            children: [
              Text(
                text,
                style: TextStyle(
                  color: selected
                      ? (color ?? const Color(0xFF00E5E5))
                      : Colors.grey.shade400,
                  fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 2),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: selected
                      ? (color ?? const Color(0xFF00E5E5)).withOpacity(0.2)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  count.toString(),
                  style: TextStyle(
                    color: selected
                        ? (color ?? const Color(0xFF00E5E5))
                        : Colors.grey.shade400,
                    fontWeight: FontWeight.bold,
                    fontSize: 10,
                  ),
                ),
              ),
            ],
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
                onPressed: fetchStudents,
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

    if (filteredStudents.isEmpty) {
      if (searchQuery.isNotEmpty) {
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.search_off,
                size: 70,
                color: Colors.grey.shade600,
              ),
              const SizedBox(height: 16),
              Text(
                'Поиск не дал результатов',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey.shade400,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Попробуйте изменить запрос или фильтры',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade500,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        );
      } else if (filterStatus != FilterStatus.all) {
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                filterStatus == FilterStatus.active ? Icons.person : Icons.person_off,
                size: 70,
                color: filterStatus == FilterStatus.active
                    ? const Color(0xFF00E5E5).withOpacity(0.5)
                    : Colors.red.shade400.withOpacity(0.5),
              ),
              const SizedBox(height: 16),
              Text(
                filterStatus == FilterStatus.active
                    ? 'Нет активных учеников'
                    : 'Нет неактивных учеников',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey.shade400,
                ),
              ),
            ],
          ),
        );
      } else {
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.people_outline,
                size: 70,
                color: Colors.grey.shade600,
              ),
              const SizedBox(height: 16),
              Text(
                'Нет учеников',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey.shade400,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Добавьте нового ученика, нажав на кнопку +',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey.shade500,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        );
      }
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: filteredStudents.length,
      itemBuilder: (context, index) {
        final student = filteredStudents[index];
        return Dismissible(
          key: Key(student['id'].toString()),
          background: Container(
            margin: const EdgeInsets.symmetric(vertical: 6),
            decoration: BoxDecoration(
              color: Colors.red.shade900,
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 20),
            child: const Icon(
              Icons.delete,
              color: Colors.white,
              size: 28,
            ),
          ),
          direction: DismissDirection.endToStart,
          confirmDismiss: (direction) async {
            return await showDialog(
              context: context,
              builder: (BuildContext context) {
                return AlertDialog(
                  backgroundColor: Colors.grey.shade900,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  title: const Text(
                    "Подтверждение",
                    style: TextStyle(color: Colors.white),
                  ),
                  content: Text(
                    "Вы уверены, что хотите удалить ученика ${student['full_name']}?",
                    style: TextStyle(color: Colors.grey.shade300),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: const Text(
                        "Отмена",
                        style: TextStyle(color: Color(0xFF00E5E5)),
                      ),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      child: const Text(
                        "Удалить",
                        style: TextStyle(color: Colors.red),
                      ),
                    ),
                  ],
                );
              },
            );
          },
          onDismissed: (direction) {
            deleteStudent(student['id']);
          },
          child: Card(
            margin: const EdgeInsets.symmetric(vertical: 6),
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color: Colors.grey.shade800,
                width: 1,
              ),
            ),
            color: Colors.grey.shade900,
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 10,
              ),
              leading: Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: student['is_inactive']
                        ? Colors.red.shade800
                        : const Color(0xFF00E5E5),
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: student['is_inactive']
                          ? Colors.red.shade800.withOpacity(0.3)
                          : const Color(0xFF00E5E5).withOpacity(0.3),
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
                      ? Icon(
                    Icons.person,
                    color: student['is_inactive']
                        ? Colors.red.shade800
                        : const Color(0xFF00E5E5),
                  )
                      : null,
                ),
              ),
              title: Text(
                student['full_name'],
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 4),
                  Text(
                    'Дата рождения: ${_formatDate(student['birth_date'])}',
                    style: TextStyle(
                      color: Colors.grey.shade400,
                      fontSize: 14,
                    ),
                  ),
                  if (student['is_inactive'])
                    Container(
                      margin: const EdgeInsets.only(top: 6),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(4),
                        color: Colors.red.shade900.withOpacity(0.4),
                      ),
                      child: const Text(
                        'Неактивен',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                        ),
                      ),
                    ),
                ],
              ),
              trailing: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: Colors.black,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: const Color(0xFF00E5E5),
                    width: 1,
                  ),
                ),
                child: const Icon(
                  Icons.arrow_forward_ios,
                  color: Color(0xFF00E5E5),
                  size: 14,
                ),
              ),
              onTap: () async {
                final result = await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => StudentDetailPage(
                      token: widget.token,
                      studentId: student['id'],
                    ),
                  ),
                );
                if (result == true) {
                  fetchStudents();
                }
              },
            ),
          ),
        );
      },
    );
  }
}

enum FilterStatus {
  all,
  active,
  inactive,
}